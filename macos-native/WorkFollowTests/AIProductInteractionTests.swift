import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIProductInteractionTests: XCTestCase {
    private func wait(_ label: String, _ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await _Concurrency.Task.sleep(for: .milliseconds(15)) }
        XCTFail("AI product window did not settle: " + label)
    }
    func testNativeOperationReceiptUndoAndReferencePickerInFullShell() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-product-window-" + UUID().uuidString)
        let environment = AppEnvironment(directory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        environment.focusStore.notifier = nil
        let noteID = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(noteID) { $0.title = "虚构引用笔记" }
        environment.navigation.destination = .aiChat
        let model = environment.aiChat.current
        model.input = "虚构问题"; model.send { _, _, _, _, _ in "# 核对结果\n\n| 项目 | 结果 |\n| --- | --- |\n| 资料 | 已核对 |\n\n```text\n虚构代码块\n```" }
        try await wait("response") { !model.isRunning }
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        let channel = AutomationChannel(workspaceDirectory: root)
        var request = AutomationRequest(operation: "task.add", arguments: ["title": "回执窗口验收", "date": "2026-11-02T09:00:00+08:00", "reminder-offsets": "0"])
        request.conversationID = model.record.id
        try channel.submit(request)
        try await wait("native receipt") { model.record.messages.last?.actions?.isEmpty == false }
        let receipt = try XCTUnwrap(model.record.messages.last?.actions?.first)
        let undoID = "ai.action.undo.\(receipt.id)"
        try await wait("undo button") { anchors[undoID]?.window === window }
        let undo = try XCTUnwrap(anchors[undoID])
        try InspectorPanelTestSupport.click(undo.bounds, in: undo, window: window)
        try await wait("undone") { model.record.messages.last?.actions?.first?.undone == true }
        XCTAssertFalse(environment.taskWorkspace.allTasks.contains { $0.title == "回执窗口验收" })
        let reference = try XCTUnwrap(anchors["ai.chat.reference"])
        try InspectorPanelTestSupport.click(reference.bounds, in: reference, window: window)
        let referenceID = "ai.reference.\(noteID)"
        try await wait("reference popover") { anchors[referenceID]?.window != nil }
        let choice = try XCTUnwrap(anchors[referenceID]), popover = try XCTUnwrap(choice.window)
        try InspectorPanelTestSupport.click(choice.bounds, in: choice, window: popover)
        try await wait("reference chosen") { model.record.references?.contains { $0.id == noteID } == true }
    }
    func testTranscriptEditorSavesEditedText() async throws {
        var saved = ""
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: MeetingTranscriptEditor(line: .init(speaker: "甲", text: "虚构原句", offset: 0)) { text, _, _ in saved = text }
            .environment(\.workflowActionObservation, { anchors[$0] = $1 }))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 550, height: 360)
        defer { window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextView }.first)
        editor.string = "虚构校正句子"; editor.didChangeText()
        try await wait("save control") { anchors["meeting.correction.save"]?.window === window }
        let button = try XCTUnwrap(anchors["meeting.correction.save"])
        try InspectorPanelTestSupport.click(button.bounds, in: button, window: window)
        XCTAssertEqual(saved, "虚构校正句子")
    }
}
