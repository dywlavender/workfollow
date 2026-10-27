import Combine
import XCTest
@testable import WorkFollow

@MainActor
final class NativeAutomationTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-automation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func request(_ operation: String, _ args: [String: String] = [:]) -> AutomationRequest {
        AutomationRequest(operation: operation, arguments: args)
    }
    private func service(_ root: URL) -> NativeAutomationService {
        let tasks = TaskWorkspaceModel(initialTasks: [])
        return NativeAutomationService(tasks: tasks, notes: NotesWorkspaceModel(taskWorkspace: tasks), directory: root)
    }
    private func fields(_ value: AutomationValue) throws -> [String: String] {
        ["id": try XCTUnwrap(value["id"]?.string), "version": try XCTUnwrap(value["version"]?.string)]
    }

    func testArgumentsHandleMultilineContentWithoutShellInterpretation() throws {
        let body = "第一行\n引号 \"\"，以及 $() 和 `文字` 保持原样。"
        let call = try AutomationInvocation.parse(["note", "create", "--title", "测试", "--content-file", "-", "--json"]) { path in
            XCTAssertEqual(path, "-"); return body
        }
        XCTAssertTrue(call.json)
        XCTAssertEqual(call.request?.arguments["content"], body)
        XCTAssertThrowsError(try AutomationInvocation.parse(["task", "add", "--title", "x", "--unknown", "x"]) { _ in "" })
        XCTAssertThrowsError(try AutomationInvocation.parse(["note", "append", "--id", UUID().uuidString, "--content", "x"]) { _ in "" })
        XCTAssertThrowsError(try AutomationInvocation.parse(["note", "create", "--content", "x", "--content-file", "a"]) { _ in "" })
    }

    func testTaskCreationScheduleAndMetadataQueriesStayInCurrentWorkspace() throws {
        let service = service(try directory())
        let value = try service.execute(request("task.add", ["title": "提交周报", "priority": "high", "date": "2026-10-27", "due": "2026-10-28", "content": "检查数据\n发送邮件"]))
        let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(value["id"]?.string)))
        let task = try XCTUnwrap(service.tasks.task(for: id))
        XCTAssertEqual(task.priority, .high)
        XCTAssertNotEqual(task.schedule.dueAt, task.schedule.deadlineAt)
        XCTAssertEqual(task.document.plainText, "检查数据\n发送邮件")
        XCTAssertNil(service.tasks.selectedTaskID)
        let listed = try service.execute(request("task.list", ["query": "检查数据", "completed": "false", "limit": "1"]))
        guard case let .array(items)? = listed["items"] else { return XCTFail("Missing items") }
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0]["content"])
        XCTAssertEqual(items[0]["url"]?.string, "workfollow://task/" + id.uuidString)
        XCTAssertThrowsError(try service.execute(request("task.list", ["limit": "0"])))
    }

    func testTaskUpdateIsUndoableAndStaleVersionDoesNotOverwriteNewerEdits() throws {
        let service = service(try directory())
        let created = try service.execute(request("task.add", ["title": "旧标题", "content": "旧正文"]))
        var args = try fields(created)
        args["title"] = "新标题"; args["priority"] = "high"; args["content"] = "新正文"
        let updated = try service.execute(request("task.update", args))
        XCTAssertEqual(updated["title"]?.string, "新标题")
        XCTAssertEqual(updated["content"]?.string, "新正文")
        XCTAssertThrowsError(try service.execute(request("task.update", args))) { error in
            XCTAssertEqual((error as? AutomationFailure)?.code, "version_conflict")
        }
        service.tasks.undo()
        let old = try service.execute(request("task.get", ["id": try XCTUnwrap(created["id"]?.string)]))
        XCTAssertEqual(old["title"]?.string, "旧标题")
        XCTAssertEqual(old["content"]?.string, "旧正文")
        XCTAssertEqual(old["priority"]?.string, "none")
    }

    func testTaskCompleteAndReopenUseDomainActions() throws {
        let service = service(try directory())
        let created = try service.execute(request("task.add", ["title": "确认交付"]))
        let completed = try service.execute(request("task.complete", fields(created)))
        XCTAssertEqual(completed["completed"], .bool(true))
        let reopened = try service.execute(request("task.reopen", fields(completed)))
        XCTAssertEqual(reopened["completed"], .bool(false))
    }

    func testNoteCreateAppendAndReplaceKeepSelectionAndExistingFormatting() throws {
        let service = service(try directory())
        let selected = service.notes.create()
        let created = try service.execute(request("note.create", ["title": "纪要", "content": "原文"]))
        let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(created["id"]?.string)))
        service.notes.edit(id) { $0.document = NativeDocument(blocks: [DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "原文")])]) }
        let before = try service.execute(request("note.get", ["id": id.uuidString]))
        var append = try fields(before); append["content"] = "补充第一行\n补充第二行"
        let appended = try service.execute(request("note.append", append))
        XCTAssertEqual(appended["content"]?.string, "原文\n补充第一行\n补充第二行")
        XCTAssertEqual(service.notes.notes.first { $0.id == id }?.document.blocks.first?.kind, .heading(2))
        XCTAssertEqual(service.notes.selectedID, selected)
        XCTAssertThrowsError(try service.execute(request("note.append", append)))
        var replace = try fields(appended); replace["title"] = "新版纪要"; replace["content"] = "完整替换"
        let replaced = try service.execute(request("note.update", replace))
        XCTAssertEqual(replaced["content"]?.string, "完整替换")
        XCTAssertEqual(replaced["title"]?.string, "新版纪要")
    }

    func testBridgeAcknowledgesWritesAfterSQLitePersistence() async throws {
        let root = try directory(), service = service(root), channel = AutomationChannel(workspaceDirectory: root)
        let repository = NativePreviewRepository(directory: root)
        try repository.save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        let persistence = PersistenceCoordinator(repository: repository)
        let tasks = service.tasks.taskChanges.sink { persistence.schedule(changes: $0) }
        defer { tasks.cancel() }
        let bridge = NativeAutomationBridge(channel: channel, service: service, canProcess: { true },
                                            flush: { persistence.flush(completion: $0) })
        let input = request("note.create", ["title": "已保存", "content": "持久化正文"])
        try channel.submit(input)
        await bridge.processPending()
        let response = try XCTUnwrap(channel.response(for: input.id))
        XCTAssertTrue(response.ok)
        XCTAssertTrue(try channel.pending().isEmpty)
        let saved = try XCTUnwrap(repository.load())
        XCTAssertEqual(saved.tasks.first(where: { $0.kind == .note })?.title, "已保存")
        XCTAssertEqual(saved.tasks.first(where: { $0.kind == .note })?.document.plainText, "持久化正文")
    }

    func testBridgeReportsSaveFailureAndDoesNotRunExpiredRequests() async throws {
        let root = try directory(), service = service(root), channel = AutomationChannel(workspaceDirectory: root)
        let bridge = NativeAutomationBridge(channel: channel, service: service, canProcess: { true },
                                            flush: { $0(CocoaError(.fileWriteUnknown)) })
        let input = request("task.add", ["title": "保存失败"])
        try channel.submit(input)
        await bridge.processPending()
        XCTAssertEqual(try channel.response(for: input.id)?.error?.code, "save_failed")
        var expired = request("task.add", ["title": "不应创建"])
        expired.expiresAt = Date().addingTimeInterval(-1)
        try channel.submit(expired)
        await bridge.processPending()
        XCTAssertEqual(try channel.response(for: expired.id)?.error?.code, "expired")
        XCTAssertFalse(service.tasks.allTasks.contains { $0.title == "不应创建" })
    }

    func testAutomationLaunchSuppressesInitialWindow() {
        let policy = WidgetMainWindowLaunchPolicy(arguments: ["WorkFollow", AutomationChannel.launchArgument])
        XCTAssertTrue(policy.startedForAutomation)
        XCTAssertFalse(policy.startedForWidget)
        XCTAssertTrue(policy.suppressInitialMainWindow)
    }
}
