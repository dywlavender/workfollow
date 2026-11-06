import XCTest
@testable import WorkFollow

@MainActor
final class AssistantMemoryTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-memory-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testRememberUpdateForgetPersistAcrossNewStoreInstances() throws {
        let root = try directory(), store = AssistantMemoryStore(directory: root)
        let first = try store.add("  虚构偏好：上午不安排会议  ")
        XCTAssertEqual(try store.add(first.content).id, first.id)
        XCTAssertEqual(AssistantMemoryStore(directory: root).entries, [first])
        let updated = try store.update(first.id, version: first.version, content: "虚构偏好：下午不安排会议")
        XCTAssertThrowsError(try store.update(first.id, version: first.version, content: "旧版本不能覆盖"))
        let reopened = AssistantMemoryStore(directory: root)
        XCTAssertEqual(reopened.entries, [updated])
        try reopened.forget(updated.id, version: updated.version)
        XCTAssertTrue(AssistantMemoryStore(directory: root).entries.isEmpty)
    }

    func testFailedSaveDoesNotPublishAnUnsavedPreference() throws {
        let root = try directory()
        let saved = try AssistantMemoryStore(directory: root).add("虚构的已保存偏好")
        let failing = AssistantMemoryStore(directory: root, write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertThrowsError(try failing.add("不能保存的偏好"))
        XCTAssertThrowsError(try failing.forget(saved.id, version: saved.version))
        XCTAssertEqual(failing.entries, [saved])
        XCTAssertEqual(AssistantMemoryStore(directory: root).entries, [saved])
    }

    func testMemoryCLIUsesSharedStoreAndDoesNotChangeTasksOrBusinessUndo() throws {
        let root = try directory(), memories = AssistantMemoryStore(directory: root.appendingPathComponent("modules"))
        let tasks = TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        let service = NativeAutomationService(tasks: tasks, notes: NotesWorkspaceModel(taskWorkspace: tasks),
            directory: root, memories: memories)
        func command(_ tokens: [String]) throws -> AutomationValue {
            let invocation = try AutomationInvocation.parse(tokens) { _ in "" }
            return try service.execute(XCTUnwrap(invocation.request))
        }
        let saved = try command(["memory", "add", "--content", "虚构偏好：提前十分钟提醒"])
        XCTAssertEqual(memories.entries.count, 1)
        XCTAssertNil(tasks.automationUndoID)
        XCTAssertTrue(tasks.allTasks.isEmpty)
        let id = try XCTUnwrap(saved["id"]?.string), revision = try XCTUnwrap(saved["version"]?.string)
        let updated = try command(["memory", "update", "--id", id, "--version", revision, "--content", "虚构偏好：提前二十分钟提醒"])
        XCTAssertEqual(memories.entries.first?.content, "虚构偏好：提前二十分钟提醒")
        XCTAssertThrowsError(try command(["memory", "delete", "--id", id, "--version", revision]))
        try command(["memory", "delete", "--id", id, "--version", try XCTUnwrap(updated["version"]?.string)])
        XCTAssertTrue(memories.entries.isEmpty)
        XCTAssertEqual(try command(["memory", "list"]), .array([]))
        XCTAssertNil(tasks.automationUndoID)
    }

    func testEveryConversationSurfaceGetsFreshPreferencesFromTheSameWorkspace() async throws {
        let root = try directory(), script = root.appendingPathComponent("backend.py")
        try #"""
        import json,pathlib,sys
        log=pathlib.Path(__file__).parent/'requests.jsonl'
        for line in sys.stdin:
            request=json.loads(line)
            if request.get('method')=='cancel': continue
            with log.open('a') as output: output.write(json.dumps(request)+'\n')
            print(json.dumps({'id':request['id'],'result':{'text':'虚构回复'}}),flush=True)
        """#.write(to: script, atomically: true, encoding: .utf8)
        let backend = AIBackendBridge(root: root, launch: { _ in
            (URL(fileURLWithPath: "/usr/bin/python3"), ["-u", script.path])
        })
        defer { backend.shutdown() }
        let environment = AppEnvironment(directory: root)
        let initial = try environment.assistantMemories.add("虚构偏好：上午不安排会议")
        var client = environment.conversationClient(); client.backend = backend
        func send(_ scene: AIConversationModel.Scene) async throws {
            _ = try await client.send(id: UUID(), scene: scene, context: "", message: "读取我的偏好", updates: { _ in })
        }
        for scene in [AIConversationModel.Scene.chat, .note, .selection] { try await send(scene) }
        let updated = try environment.assistantMemories.update(initial.id, version: initial.version, content: "虚构偏好：下午不安排会议")
        try await send(.chat)
        try environment.assistantMemories.forget(updated.id, version: updated.version)
        try await send(.chat)
        let lines = try String(contentsOf: root.appendingPathComponent("requests.jsonl"), encoding: .utf8).split(separator: "\n")
        let params = try lines.map { line -> [String: Any] in
            let request = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(request["params"] as? [String: Any])
        }
        XCTAssertEqual(params.count, 5)
        for entry in params.prefix(3) {
            XCTAssertEqual((entry["memories"] as? [[String: String]])?.first?["content"], initial.content)
        }
        XCTAssertEqual((params[3]["memories"] as? [[String: String]])?.first?["content"], updated.content)
        XCTAssertTrue(try XCTUnwrap(params[4]["memories"] as? [[String: String]]).isEmpty)
    }
}
