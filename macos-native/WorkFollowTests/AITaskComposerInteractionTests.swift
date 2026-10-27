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
        try """
        #!/bin/sh
        cat <<'RESULT'
        {"tasks":[{"title":"核对成本","quote":"核对成本。","due":"2026-10-30"},{"title":"发送报价","quote":"发送报价。"}]}
        RESULT

        """.write(to: script, atomically: true, encoding: .utf8)
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
}
