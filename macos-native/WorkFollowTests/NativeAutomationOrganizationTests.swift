import XCTest
@testable import WorkFollow

@MainActor
final class NativeAutomationOrganizationTests: XCTestCase {
    private func service(tasks: TaskWorkspaceModel? = nil) -> NativeAutomationService {
        let workspace = tasks ?? TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        return NativeAutomationService(tasks: workspace, notes: NotesWorkspaceModel(taskWorkspace: workspace),
            directory: FileManager.default.temporaryDirectory)
    }
    private func execute(_ service: NativeAutomationService, _ operation: String, _ args: [String: String] = [:]) throws -> AutomationValue {
        try service.execute(AutomationRequest(operation: operation, arguments: args))
    }
    private func field(_ value: AutomationValue, _ name: String) throws -> String { try XCTUnwrap(value[name]?.string) }
    private func edit(_ value: AutomationValue, _ fields: [String: String]) throws -> [String: String] {
        try ["id": field(value, "id"), "version": field(value, "version")].merging(fields) { _, new in new }
    }

    func testOrganizationArgumentsAndSectionIdentifiers() throws {
        let created = try AutomationInvocation.parse(["list", "create", "--name", "项目 A", "--group", "工作"]) { _ in "" }
        XCTAssertEqual(created.request?.operation, "list.create")
        let move = try AutomationInvocation.parse(["list", "move", "--name", "项目 A", "--clear-group"]) { _ in "" }
        XCTAssertEqual(move.request?.arguments["clear-group"], "true")
        let section = try AutomationInvocation.parse(["section", "get", "--id", "imported-section-1"]) { _ in "" }
        XCTAssertEqual(section.request?.arguments["id"], "imported-section-1")
        XCTAssertThrowsError(try AutomationInvocation.parse(["list", "rename", "--name", "项目 A"]) { _ in "" })
        XCTAssertThrowsError(try AutomationInvocation.parse(["list", "move", "--name", "项目 A"]) { _ in "" })
        XCTAssertThrowsError(try AutomationInvocation.parse(["list", "move", "--name", "项目 A", "--group", "工作", "--clear-group"]) { _ in "" })
        XCTAssertThrowsError(try AutomationInvocation.parse(["task", "update", "--id", UUID().uuidString, "--version", "1", "--section", "a", "--clear-section"]) { _ in "" })
    }

    func testListAndSidebarGroupLifecycleUsesExistingOrganization() throws {
        let service = service()
        _ = try execute(service, "group.create", ["name": "工作"])
        let list = try execute(service, "list.create", ["name": "项目 A", "group": "工作"])
        XCTAssertEqual(list["group"], .string("工作"))
        XCTAssertNil(service.tasks.activeList, "CLI 新建清单不切换当前页面清单")
        service.tasks.undo()
        XCTAssertFalse(service.tasks.allListNames.contains("项目 A"), "新建清单和归入分组是一条撤销记录")
        _ = try execute(service, "list.create", ["name": "项目 A", "group": "工作"])
        _ = try execute(service, "list.rename", ["name": "项目 A", "to": "项目 B"])
        XCTAssertEqual(service.tasks.folderName(forList: "项目 B"), "工作")
        _ = try execute(service, "list.archive", ["name": "项目 B"])
        let archived = try execute(service, "list.list", ["group": "工作", "archived": "true"])
        XCTAssertEqual(archived["total"], .number(1))
        XCTAssertFalse(service.tasks.availableListNames.contains("项目 B"))
        XCTAssertThrowsError(try execute(service, "task.add", ["title": "归档期间", "list": "项目 B"]))
        _ = try execute(service, "group.rename", ["name": "工作", "to": "公司"])
        XCTAssertEqual(service.tasks.folderName(forList: "项目 B"), "公司", "归档清单也更新分组归属")
        _ = try execute(service, "list.unarchive", ["name": "项目 B"])
        _ = try execute(service, "list.move", ["name": "项目 B", "clear-group": "true"])
        XCTAssertNil(service.tasks.folderName(forList: "项目 B"))
        _ = try execute(service, "list.move", ["name": "项目 B", "group": "公司"])
        _ = try execute(service, "group.dissolve", ["name": "公司"])
        XCTAssertTrue(service.tasks.allListNames.contains("项目 B"))
        XCTAssertNil(service.tasks.folderName(forList: "项目 B"))
        XCTAssertTrue(service.tasks.listFolders.isEmpty)
    }

    func testTaskPlacementValidatesOwnershipAndIsOneUndoStep() throws {
        let service = service()
        _ = try execute(service, "list.create", ["name": "工作"])
        _ = try execute(service, "list.create", ["name": "个人"])
        let first = try execute(service, "section.create", ["list": "工作", "title": "计划"])
        let second = try execute(service, "section.create", ["list": "个人", "title": "安排"])
        let firstID = try field(first, "id"), secondID = try field(second, "id")
        XCTAssertThrowsError(try execute(service, "task.add", ["title": "无效归属", "list": "工作", "section": secondID]))
        XCTAssertTrue(service.tasks.allTasks.isEmpty)
        let created = try execute(service, "task.add", ["title": "准备材料", "list": "工作", "section": firstID,
            "date": "2026-10-27", "priority": "high", "content": "正文保留"])
        XCTAssertEqual(created["sectionID"], .string(firstID))
        XCTAssertEqual(created["sectionTitle"], .string("计划"))
        service.tasks.undo()
        XCTAssertTrue(service.tasks.allTasks.isEmpty, "新建和放入分组一起撤销")
        service.tasks.redo()
        let task = try execute(service, "task.get", ["id": field(created, "id")])
        let moved = try execute(service, "task.update", edit(task, ["list": "个人", "section": secondID, "title": "新标题"]))
        XCTAssertEqual(moved["list"], .string("个人"))
        XCTAssertEqual(moved["sectionID"], .string(secondID))
        XCTAssertEqual(moved["content"], .string("正文保留"))
        XCTAssertEqual(try execute(service, "task.list", ["section": secondID])["total"], .number(1))
        service.tasks.undo()
        let original = try execute(service, "task.get", ["id": field(created, "id")])
        XCTAssertEqual(original["list"], .string("工作"))
        XCTAssertEqual(original["title"], .string("准备材料"))
        XCTAssertEqual(original["sectionID"], .string(firstID))
        let cleared = try execute(service, "task.update", edit(original, ["clear-section": "true"]))
        XCTAssertEqual(cleared["sectionID"], .null)
        XCTAssertNotEqual(cleared["version"], original["version"], "只改分组也必须使旧版本失效")
        XCTAssertThrowsError(try execute(service, "task.update", edit(original, ["title": "旧版本写入"])))
        let assigned = try execute(service, "task.update", edit(cleared, ["section": firstID]))
        let taskID = try XCTUnwrap(UUID(uuidString: field(assigned, "id")))
        _ = service.tasks.saveTiming(taskID, schedule: TaskSchedule(dueAt: Date()), reminder: nil, frequency: .daily)
        let repeated = try execute(service, "task.get", ["id": taskID.uuidString])
        let plainMove = try execute(service, "task.update", edit(repeated, ["list": "个人"]))
        XCTAssertEqual(plainMove["sectionID"], .null, "换清单不携带原清单分组")
        XCTAssertEqual(service.tasks.task(for: taskID)?.series?.template.list.name, "个人")
        XCTAssertNil(service.tasks.task(for: taskID)?.series?.template.sectionID)
    }

    func testMovingAndRemovingSectionCarriesChildrenAndRecurringTemplate() throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        var parent = Task(id: UUID(), title: "每日评审", recurrence: .daily, list: TaskList(name: "工作"), priority: .high,
            schedule: TaskSchedule(dueAt: old), childOrder: 0, createdAt: old, updatedAt: old)
        parent.sectionID = "review"
        parent.series = TaskSeries(task: parent, calendar: .current, now: old)
        let child = Task(id: UUID(), title: "核对附件", list: TaskList(name: "工作"), priority: .none,
            schedule: TaskSchedule(), parentID: parent.id, childOrder: 0, createdAt: old, updatedAt: old)
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [parent, child], initialLists: ["工作", "个人"],
            initialListSections: [TaskListSection(id: "review", listName: "工作", title: "评审")])
        let service = service(tasks: workspace)
        let before = try execute(service, "task.get", ["id": parent.id.uuidString])
        _ = try execute(service, "section.rename", ["id": "review", "title": "待评审"])
        let moved = try execute(service, "section.move", ["id": "review", "list": "个人"])
        XCTAssertEqual(moved["title"], .string("待评审"))
        XCTAssertEqual(workspace.task(for: child.id)?.list.name, "个人")
        XCTAssertEqual(workspace.task(for: parent.id)?.series?.template.list.name, "个人")
        XCTAssertEqual(workspace.task(for: parent.id)?.series?.template.sectionID, "review")
        XCTAssertThrowsError(try execute(service, "task.update", edit(before, ["title": "过时标题"])))
        workspace.undo()
        XCTAssertEqual(workspace.task(for: child.id)?.list.name, "工作")
        XCTAssertEqual(workspace.task(for: parent.id)?.series?.template.list.name, "工作")
        XCTAssertEqual(workspace.listSections.first?.listName, "工作")
        _ = try execute(service, "section.delete", ["id": "review"])
        XCTAssertNil(workspace.task(for: parent.id)?.sectionID)
        XCTAssertNil(workspace.task(for: parent.id)?.series?.template.sectionID)
        XCTAssertEqual(workspace.allTasks.count, 2)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: parent.id)?.sectionID, "review")
    }

    func testDeletingListKeepsTasksAndClearsSectionsAndRecurringMembership() throws {
        let service = service()
        _ = try execute(service, "list.create", ["name": "工作"])
        let section = try execute(service, "section.create", ["list": "工作", "title": "计划"])
        let value = try execute(service, "task.add", ["title": "交付", "list": "工作", "section": field(section, "id")])
        let id = try XCTUnwrap(UUID(uuidString: field(value, "id")))
        _ = service.tasks.saveTiming(id, schedule: TaskSchedule(dueAt: Date()), reminder: nil, frequency: .daily)
        _ = try execute(service, "note.create", ["title": "保留笔记"])
        _ = try execute(service, "list.delete", ["name": "工作"])
        let task = try XCTUnwrap(service.tasks.task(for: id))
        XCTAssertEqual(task.list, .inbox)
        XCTAssertNil(task.deletedAt)
        XCTAssertNil(task.sectionID)
        XCTAssertEqual(task.series?.template.list, .inbox)
        XCTAssertNil(task.series?.template.sectionID)
        XCTAssertTrue(service.tasks.listSections.isEmpty)
        XCTAssertEqual(service.notes.notes.count, 1)
        service.tasks.undo()
        XCTAssertEqual(service.tasks.task(for: id)?.list.name, "工作")
        XCTAssertEqual(service.tasks.task(for: id)?.sectionID, try field(section, "id"))
        XCTAssertEqual(service.tasks.listSections.count, 1)
    }

    func testDuplicateNamesAndReservedListsAreRejectedBeforeMutation() throws {
        let service = service()
        for name in ["A", "B"] {
            _ = try execute(service, "list.create", ["name": name])
            _ = try execute(service, "group.create", ["name": name])
        }
        XCTAssertThrowsError(try execute(service, "list.rename", ["name": "A", "to": "B"]))
        XCTAssertThrowsError(try execute(service, "group.rename", ["name": "A", "to": "B"]))
        for name in [TaskList.inbox.name, TaskList.notes.name] {
            XCTAssertThrowsError(try execute(service, "list.create", ["name": name]))
            XCTAssertThrowsError(try execute(service, "list.delete", ["name": name]))
        }
        let section = try execute(service, "section.create", ["list": "A", "title": "计划"])
        _ = try execute(service, "section.create", ["list": "B", "title": "计划"])
        XCTAssertThrowsError(try execute(service, "section.move", ["id": field(section, "id"), "list": "B"]))
        XCTAssertEqual(try execute(service, "section.get", ["id": field(section, "id")])["list"], .string("A"))
    }
}
