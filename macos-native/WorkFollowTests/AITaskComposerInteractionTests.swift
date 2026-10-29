import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AITaskComposerInteractionTests: XCTestCase {
    private struct SheetHost: View {
        let request: AITaskRequest
        let session: AITaskDraftSession
        @State private var presented = false
        var body: some View {
            Text("原页面").frame(width: 760, height: 680)
                .sheet(isPresented: $presented) { AITaskComposerView(request: request, session: session) }
                .onAppear { presented = true }
        }
    }

    private func environment() throws -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-composer-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try NativePreviewRepository(directory: root).save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        let script = root.appendingPathComponent("fixture-pi")
        try #"""
        #!/usr/bin/python3
        import json, sys, pathlib, time
        root = pathlib.Path(__file__).parent
        for line in sys.stdin:
            request = json.loads(line)
            if request.get('type') != 'prompt': continue
            if (root / 'hold').exists():
                print(json.dumps({'type':'message_start','message':{'role':'assistant'}}),flush=True)
                print(json.dumps({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':'{"tasks":[{"title":"核对成本"'}}),flush=True)
                while not (root / 'release').exists(): time.sleep(0.02)
            text = '{"tasks":[{"title":"核对成本","quote":"核对成本。","due":"2026-10-30"},{"title":"发送报价","quote":"发送报价。"}]}'
            print(json.dumps({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':text}]}}),flush=True)
            print('{"type":"agent_settled"}',flush=True)
        """#.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let environment = AppEnvironment(directory: root)
        environment.meetingStore.configuration.executable = script.path
        return environment
    }

    private func present(_ request: AITaskRequest, session: AITaskDraftSession,
                         environment: AppEnvironment, dark: Bool = false) async throws -> (NSWindow, NSWindow) {
        let host = NSHostingView(rootView: SheetHost(request: request, session: session)
            .environmentObject(environment).preferredColorScheme(dark ? .dark : .light))
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        for _ in 0..<250 {
            if let sheet = window.attachedSheet, case .ready = session.phase {
                InspectorPanelTestSupport.settle(sheet)
                return (window, sheet)
            }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        window.close()
        throw NSError(domain: "AITaskComposerInteractionTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "AI result sheet did not become ready"])
    }

    private func screenshot(_ window: NSWindow, name: String) throws {
        let view = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/wf-native-ai-tasks-20261026-\(name).png"))
    }

    func testOneCreateActionSavesNoteTasksAndClosesPreview() async throws {
        let environment = try environment()
        let noteID = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(noteID) { $0.title = "报价跟进"; $0.document = NativeDocument(plainText: "核对成本。发送报价。") }
        let note = try XCTUnwrap(environment.notesWorkspace.notes.first { $0.id == noteID })
        let session = AITaskDraftSession()
        let (window, sheet) = try await present(environment.aiTaskRequest(for: note), session: session, environment: environment)
        defer { window.close() }
        XCTAssertEqual(session.selectedCount, 2)
        XCTAssertEqual(environment.taskWorkspace.allTasks.filter { !$0.isNoteTask }.count, 0, "生成期间不写任务")
        try screenshot(sheet, name: "extract-light")
        let create = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: sheet.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        sheet.makeKey()
        NSApp.sendEvent(create)
        try InspectorPanelTestSupport.waitUntil("创建后关闭预览") { window.attachedSheet == nil }
        XCTAssertEqual(environment.taskWorkspace.allTasks.filter { $0.sourceNoteID == noteID }.count, 2)
        XCTAssertEqual(environment.notesWorkspace.selectedID, noteID)
        environment.taskWorkspace.undo()
        XCTAssertTrue(environment.taskWorkspace.allTasks.filter { $0.sourceNoteID == noteID }.isEmpty)
        XCTAssertEqual(environment.notesWorkspace.notes.count, 1)
    }

    func testBreakdownPreviewSupportsDarkModeAndEscapeWithoutMutation() async throws {
        let environment = try environment()
        let parentID = try XCTUnwrap(environment.taskWorkspace.createTask(title: "准备客户报价", in: .inbox).taskID)
        environment.taskWorkspace.select(parentID)
        let parent = try XCTUnwrap(environment.taskWorkspace.task(for: parentID))
        let session = AITaskDraftSession()
        let (window, sheet) = try await present(environment.aiTaskRequest(for: parent), session: session, environment: environment, dark: true)
        defer { window.close() }
        XCTAssertEqual(session.selectedCount, 2)
        try screenshot(sheet, name: "breakdown-dark")
        try InspectorPanelTestSupport.sendEscape(to: sheet)
        try InspectorPanelTestSupport.waitUntil("Escape 关闭预览") { window.attachedSheet == nil }
        XCTAssertEqual(environment.taskWorkspace.task(for: parentID), parent)
        XCTAssertEqual(environment.taskWorkspace.allTasks.count, 1)
        XCTAssertEqual(environment.taskWorkspace.selectedTaskID, parentID)
    }

    func testInspectorMoreActionOpensTheSharedPreview() throws {
        let environment = try environment()
        let parentID = try XCTUnwrap(environment.taskWorkspace.createTask(title: "准备客户报价", in: .inbox).taskID)
        environment.taskWorkspace.select(parentID)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: environment.taskWorkspace, environment: environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        XCTAssertEqual(environment.taskWorkspace.selectedTaskID, parentID)
        try screenshot(window, name: "inspector-before-menu")
        try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
        try screenshot(window, name: "inspector-after-menu")
        let menu = try InspectorPanelTestSupport.actionPanel(in: window)
        try InspectorPanelTestSupport.clickButton(containing: "拆分子任务…", in: menu)
        try InspectorPanelTestSupport.waitUntil("入口打开预览面板", timeout: 2) { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        XCTAssertEqual(environment.taskWorkspace.allTasks.count, 1)
        XCTAssertFalse(menu.isVisible, "入口菜单关闭后显示一个预览面板")
        try InspectorPanelTestSupport.sendEscape(to: sheet)
        XCTAssertEqual(environment.taskWorkspace.selectedTaskID, parentID)
    }

    func testStreamIsVisibleBeforeCompletionAndEscapeDoesNotCreateTasks() async throws {
        let environment = try environment()
        let root = URL(fileURLWithPath: environment.meetingStore.configuration.executable).deletingLastPathComponent()
        try "hold".write(to: root.appendingPathComponent("hold"), atomically: true, encoding: .utf8)
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) { $0.title = "虚构笔记"; $0.document = NativeDocument(plainText: "核对成本。") }
        let note = try XCTUnwrap(environment.notesWorkspace.selected)
        let session = AITaskDraftSession()
        let host = NSHostingView(rootView: SheetHost(request: try environment.aiTaskRequest(for: note), session: session).environmentObject(environment))
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        for _ in 0..<250 {
            if session.preview == "核对成本", window.attachedSheet != nil { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.preview, "核对成本")
        XCTAssertTrue(session.drafts.isEmpty)
        XCTAssertTrue(environment.taskWorkspace.allTasks.filter { !$0.isNoteTask }.isEmpty)
        let sheet = try XCTUnwrap(window.attachedSheet)
        try screenshot(sheet, name: "streaming")
        try InspectorPanelTestSupport.sendEscape(to: sheet)
        for _ in 0..<100 {
            if window.attachedSheet == nil { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(window.attachedSheet)
        XCTAssertTrue(environment.taskWorkspace.allTasks.filter { !$0.isNoteTask }.isEmpty)
    }
}
