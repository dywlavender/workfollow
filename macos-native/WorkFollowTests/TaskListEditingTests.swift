import Combine
import XCTest
@testable import WorkFollow

@MainActor
final class TaskListEditingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func task(_ title: String, closed: Bool = false, parent: UUID? = nil) -> Task {
        Task(id: UUID(), title: title, document: NativeDocument(plainText: "保留正文"),
            reminderAt: now, list: TaskList(name: "工作"), priority: .high,
            schedule: TaskSchedule(dueAt: now), status: closed ? .completed : .active,
            parentID: parent, childOrder: 0, createdAt: now, updatedAt: now,
            completedAt: closed ? now : nil)
    }
    private func workspace(_ tasks: [Task] = []) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, seedDemoData: false, initialTasks: tasks,
            initialLists: ["工作"], initialListMeta: [TaskListMeta(name: "工作", colorIndex: 3, icon: "💼")])
    }

    func testEditorSaveRenamesAndAppliesAllPropertiesWithOneUndo() throws {
        let original = task("评审")
        let model = workspace([original]), before = model.listMetas
        var draft = TaskListEditingDraft(meta: model.listMeta(for: "工作"))
        draft.name = "项目"; draft.folderName = "公司"; draft.colorIndex = 8
        draft.showsInSmartLists = false; draft.remindersEnabled = false; draft.isDefault = true
        XCTAssertTrue(model.saveListDetails(draft, replacing: "工作"))
        XCTAssertEqual(model.task(for: original.id)?.list.name, "项目")
        XCTAssertEqual(model.listMeta(for: "项目")?.folderName, "公司")
        XCTAssertEqual(model.listMeta(for: "项目")?.colorIndex, 8)
        XCTAssertEqual(model.defaultListName, "项目")
        XCTAssertFalse(model.tasksForLocalReminders.contains { $0.id == original.id })
        model.undo()
        XCTAssertEqual(model.listMetas, before)
        XCTAssertEqual(model.task(for: original.id)?.list.name, "工作")
        XCTAssertTrue(model.listFolders.isEmpty)
        XCTAssertFalse(model.canUndo)
    }

    func testInvalidEditorDraftDoesNotPartlyCreateFolderOrChangeTasks() {
        let model = workspace([task("评审")]), before = model.allTasks
        var draft = TaskListEditingDraft(); draft.name = "工作"; draft.folderName = "不应创建"
        XCTAssertFalse(model.saveListDetails(draft))
        XCTAssertEqual(model.allTasks, before)
        XCTAssertTrue(model.listFolders.isEmpty)
        XCTAssertFalse(model.canUndo)
    }

    func testTaskDerivedListsSupportManagementBeforeTheyHaveMetadata() {
        let original = task("快速添加到清单")
        let model = TaskWorkspaceModel(seedDemoData: false, initialTasks: [original])
        XCTAssertNil(model.listMeta(for: "工作"))
        XCTAssertTrue(model.copyList("工作", to: "副本", scope: .allPreservingStatus))
        XCTAssertTrue(model.setDefaultList("工作"))
        XCTAssertEqual(model.defaultListName, "工作")
        let other = TaskWorkspaceModel(seedDemoData: false, initialTasks: [original])
        XCTAssertTrue(other.deleteList("工作"))
        XCTAssertNotNil(other.task(for: original.id)?.deletedAt)
    }

    func testHiddenAndMutedAreIndependentAndUndoRepublishesSettings() {
        let original = task("评审")
        let current = workspace([original])
        var changes = 0
        let subscription = current.listSettingsChanges.sink { changes += 1 }
        var draft = TaskListEditingDraft(meta: current.listMeta(for: "工作"))
        draft.showsInSmartLists = false
        XCTAssertTrue(current.saveListDetails(draft, replacing: "工作"))
        XCTAssertEqual(current.count(for: NativeDestination.today), 0)
        XCTAssertEqual(current.count(for: NativeDestination.allTasks), 1)
        XCTAssertEqual(current.groups(for: .allTasks, query: TaskListQuery(list: "工作")).flatMap(\.tasks).count, 1)
        XCTAssertEqual(current.tasksForLocalReminders.map(\.id), [original.id])
        XCTAssertTrue(current.tasksForSmartWidgets.isEmpty)
        draft.remindersEnabled = false
        XCTAssertTrue(current.saveListDetails(draft, replacing: "工作"))
        XCTAssertTrue(current.tasksForLocalReminders.isEmpty)
        XCTAssertEqual(current.mutedListNames, ["工作"])
        XCTAssertNotNil(current.task(for: original.id)?.reminderAt, "清单静音不清除任务上保存的提醒")
        current.undo()
        XCTAssertEqual(current.tasksForLocalReminders.map(\.id), [original.id])
        XCTAssertEqual(changes, 3)
        withExtendedLifetime(subscription) {}
    }

    func testCopyScopesPreserveStructureAndDoNotShareSeriesIdentity() throws {
        var parent = task("周期评审")
        parent.sectionID = "phase"; parent.recurrence = .weekly
        parent.series = TaskSeries(task: parent, calendar: .current, now: now)
        parent.occurrenceKey = parent.series?.initialKey
        let child = task("检查项", closed: true, parent: parent.id), closed = task("已交付", closed: true)
        for scope in TaskListCopyScope.allCases {
            let model = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
                initialTasks: [parent, child, closed], initialLists: ["工作"],
                initialListSections: [TaskListSection(id: "phase", listName: "工作", title: "交付")])
            let before = model.allTasks
            XCTAssertTrue(model.copyList("工作", to: "副本", scope: scope))
            let copies = model.allTasks.filter { $0.list.name == "副本" }
            XCTAssertEqual(copies.count, scope == .incomplete ? 1 : 3)
            let copiedParent = try XCTUnwrap(copies.first { $0.title == parent.title })
            XCTAssertNotEqual(copiedParent.id, parent.id)
            XCTAssertNotEqual(copiedParent.series?.id, parent.series?.id)
            XCTAssertEqual(copiedParent.series?.template.list.name, "副本")
            XCTAssertNotEqual(copiedParent.sectionID, parent.sectionID)
            XCTAssertEqual(copiedParent.document, parent.document)
            if scope != .incomplete {
                XCTAssertEqual(copies.first { $0.title == child.title }?.parentID, copiedParent.id)
                XCTAssertEqual(copies.filter(\.isClosed).count, scope == .allResettingStatus ? 0 : 2)
            }
            XCTAssertEqual(model.allTasks.filter { $0.list.name == "工作" }, before)
            model.undo()
            XCTAssertEqual(model.allTasks, before)
            XCTAssertFalse(model.allListNames.contains("副本"))
        }
    }

    func testDeletingListUsesTrashAndRestoresWithOneUndo() {
        let parent = task("评审"), child = task("检查", parent: parent.id)
        let model = workspace([parent, child]), before = model.listMetas, tasksBefore = model.allTasks
        XCTAssertTrue(model.deleteList("工作"))
        XCTAssertFalse(model.allListNames.contains("工作"))
        XCTAssertEqual(model.allTasks.filter { $0.deletedAt != nil }.count, 2)
        XCTAssertTrue(model.groups(for: .allTasks).isEmpty)
        model.undo()
        XCTAssertEqual(model.listMetas, before)
        XCTAssertEqual(model.allTasks, tasksBefore)
    }

    func testDefaultListIsUsedByGlobalCaptureAndCannotBeArchivedOrDeleted() throws {
        let model = workspace()
        XCTAssertTrue(model.setDefaultList("工作"))
        XCTAssertFalse(model.setListArchived("工作", true))
        XCTAssertFalse(model.deleteList("工作"))
        let id = try XCTUnwrap(GlobalQuickAddComposer(workspace: model).submit(text: "全局捕获"))
        XCTAssertEqual(model.task(for: id)?.list.name, "工作")
        let inbox = try XCTUnwrap(model.submitCapture(QuickCaptureSession(text: "收集箱内添加")).first)
        XCTAssertEqual(model.task(for: inbox)?.list, .inbox, "页面明确的收集箱落点不受全局默认值影响")
        XCTAssertTrue(model.setDefaultList(nil))
        XCTAssertEqual(model.defaultListName, TaskList.inbox.name)
    }

    func testSettingsSurviveSQLiteAndMigrationRoundTrip() throws {
        let model = workspace([task("评审")])
        var draft = TaskListEditingDraft(meta: model.listMeta(for: "工作"))
        draft.showsInSmartLists = false; draft.remindersEnabled = false; draft.isDefault = true
        XCTAssertTrue(model.saveListDetails(draft, replacing: "工作"))
        let snapshot = NativeWorkspaceSnapshot(tasks: model.allTasks, notes: [], taskLists: model.listNames, taskListMeta: model.listMetas)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("list-settings-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(snapshot)
        XCTAssertEqual(try repository.load()?.taskListMeta, snapshot.taskListMeta)
        let bundle = try MigrationSnapshot.parse(MigrationSnapshot.exportJSON(from: snapshot, attachmentDirectory: nil, now: now))
        let restored = MigrationSnapshot.replaced(bundle, attachmentNames: [], now: now).snapshot
        let meta = try XCTUnwrap(restored.taskListMeta?.first { $0.name == "工作" })
        XCTAssertTrue(meta.hidesFromSmartLists); XCTAssertTrue(meta.remindersMuted); XCTAssertTrue(meta.isDefault)
        let legacy = try JSONDecoder().decode(TaskListMeta.self, from: Data(#"{"name":"旧清单"}"#.utf8))
        XCTAssertFalse(legacy.hidesFromSmartLists); XCTAssertFalse(legacy.remindersMuted); XCTAssertFalse(legacy.isDefault)
    }

    func testFolderEditingAndIconPersistAndUndoTogether() throws {
        let model = workspace()
        XCTAssertTrue(model.saveListFolderDetails("公司", replacing: nil, icon: "💼"))
        XCTAssertTrue(model.setListFolder("工作", "公司"))
        XCTAssertTrue(model.saveListFolderDetails("项目", replacing: "公司", icon: "🚀"))
        XCTAssertEqual(model.folderName(forList: "工作"), "项目")
        XCTAssertEqual(model.listFolders.first?.icon, "🚀")
        let snapshot = NativeWorkspaceSnapshot(tasks: [], notes: [], taskLists: model.listNames,
            taskListMeta: model.listMetas, taskListFolders: model.listFolders)
        let bundle = try MigrationSnapshot.parse(MigrationSnapshot.exportJSON(from: snapshot, attachmentDirectory: nil, now: now))
        XCTAssertEqual(MigrationSnapshot.replaced(bundle, attachmentNames: [], now: now).snapshot.taskListFolders?.first?.icon, "🚀")
        model.undo()
        XCTAssertEqual(model.folderName(forList: "工作"), "公司")
        XCTAssertEqual(model.listFolders.first?.icon, "💼")
    }

    func testArchivedTasksRejectEditsAndBatchDeletion() {
        let source = task("归档内容")
        let archived = workspace([source])
        XCTAssertTrue(archived.setListArchived("工作", true))
        XCTAssertNil(archived.setTitle(source.id, "不应改动").taskID)
        archived.setBulkSelected(source.id, true)
        archived.applyBulk(.delete)
        XCTAssertNil(archived.task(for: source.id)?.deletedAt)
        XCTAssertEqual(archived.task(for: source.id)?.title, source.title)
    }

    func testKanbanAndFolderPreferencesPersistAndCopiedScopesKeepDisplayChoices() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("list-display-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = TaskViewPreferenceStore(directory: directory)
        let options = TaskKanbanOptions(size: .large, showsInput: false, showsChecklist: false)
        preferences.setKanbanOptions(options, for: "list:工作")
        preferences.setViewMode(.kanban, for: "list:工作")
        preferences.setCollapsedGroups(["section:old"], for: "list:工作")
        preferences.copyScope(from: "list:工作", to: "list:副本")
        XCTAssertEqual(preferences.kanbanOptions(for: "list:副本"), options)
        XCTAssertTrue(preferences.collapsedGroups(for: "list:副本").isEmpty, "副本不能引用原清单分组身份")
        XCTAssertEqual(preferences.kanbanOptions(for: "list:其他"), TaskKanbanOptions())
        preferences.setCollapsedCollectionFolders(["项目"])
        preferences.setArchivedListsCollapsed(false)
        let saved = expectation(description: "preferences persisted")
        preferences.flush { error in XCTAssertNil(error); saved.fulfill() }
        wait(for: [saved], timeout: 3)
        let reopened = TaskViewPreferenceStore(directory: directory)
        XCTAssertEqual(reopened.kanbanOptions(for: "list:工作"), options)
        XCTAssertEqual(reopened.collapsedCollectionFolders, ["项目"])
        XCTAssertFalse(reopened.archivedListsCollapsed)
    }
}
