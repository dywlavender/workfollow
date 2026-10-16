import Combine
import XCTest
@testable import WorkFollow

@MainActor
final class TaskListArchiveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_123_200)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func task(_ title: String, list: String = "工作", parent: UUID? = nil) -> Task {
        var value = Task(id: UUID(), title: title, list: TaskList(name: list), priority: .high,
            schedule: TaskSchedule(dueAt: now.addingTimeInterval(3600), hasTime: true),
            parentID: parent, childOrder: 0, createdAt: now, updatedAt: now)
        value.reminderAt = now.addingTimeInterval(1800)
        return value
    }

    func testArchivePreservesHierarchyMetadataAndRestoresWithOneUndo() throws {
        var parent = task("归档项目")
        parent.sectionID = "delivery"
        let child = task("交付检查", parent: parent.id)
        let inbox = task("当前任务", list: TaskList.inbox.name)
        let reference = UUID()
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false,
            initialTasks: [parent, child, inbox], initialLists: ["工作"],
            initialListMeta: [TaskListMeta(name: "工作", colorIndex: 3, isPinned: true,
                icon: "💼", folderName: "项目", referenceID: reference)],
            initialListFolders: [TaskListFolder(name: "项目")],
            initialListSections: [TaskListSection(id: "delivery", listName: "工作", title: "交付")])
        let original = workspace.allTasks
        let meta = try XCTUnwrap(workspace.listMeta(for: "工作"))
        workspace.activeList = "工作"
        workspace.select(parent.id)
        workspace.setBulkSelected(child.id, true)
        var archiveEvents: [Set<String>] = []
        var reminderCounts: [Int] = []
        var taskEdits = 0
        let archives = workspace.listArchiveChanges.sink { names in
            archiveEvents.append(names)
            reminderCounts.append(ReminderSignature.values(workspace.tasksInActiveLists,
                calendar: self.calendar, now: self.now).count)
        }
        let changes = workspace.taskChanges.sink { _ in taskEdits += 1 }
        XCTAssertTrue(workspace.setListArchived("工作", true))
        XCTAssertEqual(workspace.allTasks, original, "归档不能改任务、父子关系或提醒设置")
        XCTAssertNil(workspace.selectedTaskID)
        XCTAssertTrue(workspace.bulkSelection.isEmpty)
        XCTAssertEqual(workspace.availableListNames, [TaskList.inbox.name])
        XCTAssertEqual(workspace.listNames, ["工作"], "保存元数据时仍须包含归档清单")
        XCTAssertEqual(workspace.archivedListNames, ["工作"])
        XCTAssertEqual(workspace.count(for: NativeDestination.allTasks), 1)
        XCTAssertEqual(workspace.count(for: NativeDestination.today), 1)
        XCTAssertEqual(workspace.tasksInActiveLists.map(\.id), [inbox.id])
        let archived = try XCTUnwrap(workspace.listMeta(for: "工作"))
        var expected = meta; expected.archivedAt = now
        XCTAssertEqual(archived, expected)
        let direct = workspace.groups(for: .allTasks, query: TaskListQuery(list: "工作"), viewMode: .kanban)
        XCTAssertEqual(direct.first?.sectionID, parent.sectionID)
        XCTAssertEqual(direct.first?.tasks.map(\.id), [parent.id])
        XCTAssertEqual(workspace.kanbanNodes(for: parent).map { $0.task.id }, [parent.id, child.id])
        XCTAssertFalse(workspace.setListArchived("工作", true), "重复归档不新增撤销步")
        workspace.undo()
        XCTAssertEqual(workspace.listMeta(for: "工作"), meta)
        XCTAssertEqual(workspace.count(for: NativeDestination.allTasks), 3)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertTrue(workspace.isListArchived("工作"))
        XCTAssertTrue(workspace.setListArchived("工作", false))
        XCTAssertEqual(workspace.listMeta(for: "工作"), meta)
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertEqual(archiveEvents, [Set(["工作"]), [], Set(["工作"]), []])
        XCTAssertEqual(reminderCounts, [1, 3, 1, 3], "归档/恢复/撤销/重做都重排提醒资格")
        XCTAssertEqual(taskEdits, 0, "清单归档不伪造任务编辑事件")
        withExtendedLifetime((archives, changes)) {}
    }

    func testEmptyArchivedListSurvivesDatabaseReloadAndLegacyMetadataStillDecodes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("list-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [], initialLists: ["空归档"],
            initialListMeta: [TaskListMeta(name: "空归档", referenceID: UUID())])
        XCTAssertTrue(workspace.setListArchived("空归档", true))
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: workspace.allTasks, notes: [],
            taskLists: workspace.listNames, taskListMeta: workspace.listMetas))
        let loaded = try XCTUnwrap(try NativePreviewRepository(directory: directory).load())
        let reopened = TaskWorkspaceModel(seedDemoData: false, initialTasks: loaded.tasks,
            initialLists: loaded.taskLists ?? [], initialListMeta: loaded.taskListMeta)
        XCTAssertEqual(reopened.archivedListNames, ["空归档"])
        XCTAssertEqual(reopened.listMetas, workspace.listMetas)
        XCTAssertTrue(reopened.activeListNames.isEmpty)
        XCTAssertTrue(reopened.setListArchived("空归档", false))
        XCTAssertEqual(reopened.orderedListNames, ["空归档"])
        let legacy = try JSONDecoder().decode(TaskListMeta.self, from: Data(#"{"name":"旧清单"}"#.utf8))
        XCTAssertFalse(legacy.isArchived)
    }

    func testArchiveStateSurvivesMigrationExportAndReplaceIncludingEmptyLists() throws {
        let snapshot = NativeWorkspaceSnapshot(tasks: [task("归档任务")], notes: [],
            taskLists: ["工作", "空归档"], taskListMeta: [
                TaskListMeta(name: "工作", colorIndex: 3, icon: "💼", folderName: "项目", archivedAt: now),
                TaskListMeta(name: "空归档", sortOrder: 1, archivedAt: now)])
        let exported = try MigrationSnapshot.exportJSON(from: snapshot, attachmentDirectory: nil, now: now)
        let bundle = try MigrationSnapshot.parse(exported)
        let imported = MigrationSnapshot.replaced(bundle, attachmentNames: [], now: now).snapshot
        XCTAssertEqual(Set(imported.taskListMeta?.filter(\.isArchived).map(\.name) ?? []), ["工作", "空归档"])
        XCTAssertEqual(imported.taskListMeta?.first { $0.name == "工作" }?.archivedAt, now)
        XCTAssertEqual(imported.taskListMeta?.first { $0.name == "工作" }?.folderName, "项目")
        XCTAssertEqual(imported.tasks.first?.title, "归档任务")
    }

    func testArchivedListIsNotACreationOrMoveTargetAndGlobalCaptureUsesInbox() throws {
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [task("旧项目")], initialLists: ["工作"])
        XCTAssertTrue(workspace.setListArchived("工作", true))
        workspace.activeList = "工作"
        let created = try XCTUnwrap(GlobalQuickAddComposer(workspace: workspace).submit(text: "新事项"))
        XCTAssertEqual(workspace.task(for: created)?.list, .inbox)
        XCTAssertEqual(workspace.moveToList(created, TaskList(name: "工作")), .failure(.invalidList))
        XCTAssertEqual(workspace.createDraft(title: "误入归档", list: "工作", schedule: TaskSchedule(),
            priority: .none, tags: [], reminder: nil, repeatFrequency: .never), .failure(.invalidList))
        XCTAssertFalse(workspace.saveList("工作"), "归档清单仍占用原名称")
        XCTAssertFalse(workspace.setListArchived(TaskList.inbox.name, true))
    }

    func testSavedFiltersAndClosedSmartListsExcludeArchivedTasksButDirectListKeepsThem() throws {
        var completed = task("已完成项目")
        completed.status = .completed; completed.completedAt = now
        var abandoned = task("已放弃项目")
        abandoned.abandonedAt = now
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-filter-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let filters = FilterStore(directory: directory)
        let filter = SavedFilter(name: "工作项目", listNames: ["工作"])
        XCTAssertTrue(filters.add(filter))
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [task("当前项目"), completed, abandoned], initialLists: ["工作"])
        workspace.attachFilterStore(filters); workspace.openFilter(filter.id)
        XCTAssertTrue(workspace.setListArchived("工作", true))
        for scope in [TaskListScope.allTasks, .today, .completed, .abandoned] {
            XCTAssertTrue(workspace.groups(for: scope, viewMode: .kanban).isEmpty)
        }
        XCTAssertEqual(workspace.groups(for: .allTasks, query: TaskListQuery(list: "工作"),
            grouping: .none, viewMode: .kanban).flatMap(\.tasks).count, 3)
        XCTAssertTrue(workspace.setListArchived("工作", false))
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .none, viewMode: .kanban).flatMap(\.tasks).count, 3)
    }
}
