import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentEditorPlaceholderTests: XCTestCase {
    private let bodyPlaceholder = "写下你的想法、会议记录或下一步行动…"

    private func editor(in view: NSView) -> NativeTextView? {
        if let editor = view as? NativeTextView { return editor }
        return view.subviews.lazy.compactMap { self.editor(in: $0) }.first
    }

    /// 实时空状态是排到下一轮 runloop 发布的，断言前先把它跑完。
    private func drainMainQueue() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    func testPlaceholderFollowsLiveTextEvenWhenModelIsStillEmpty() {
        let document = NativeDocument.empty
        let handle = DocumentEditorHandle()
        XCTAssertTrue(DocumentEditorPlaceholder.isVisible(for: document, handle: handle))

        handle.syncLiveTextIsEmpty(false)
        drainMainQueue()
        XCTAssertFalse(DocumentEditorPlaceholder.isVisible(for: document, handle: handle),
                       "组合串已经在编辑区里，占位文案不能继续压在它下面")
        XCTAssertTrue(DocumentEditorPlaceholder.isVisible(for: document),
                      "不传句柄时退回模型口径")

        handle.syncLiveTextIsEmpty(true)
        drainMainQueue()
        XCTAssertTrue(DocumentEditorPlaceholder.isVisible(for: document, handle: handle))
    }

    func testNoteBodyPlaceholderYieldsToIMEMarkedTextBeforeCommit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-placeholder-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        environment.navigation.destination = .notes
        let notes = environment.notesWorkspace
        notes.create()

        var titles: [String] = []
        let host = NSHostingView(rootView: NotesWorkspaceView(notes: notes,
            navigation: environment.navigation, tasks: environment.taskWorkspace)
            .environmentObject(environment)
            .onPreferenceChange(DocumentEditorPlaceholderTitles.self) { titles = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1000, height: 680)
        defer { window.close() }

        try InspectorPanelTestSupport.waitUntil("空笔记应先显示正文占位") {
            titles.contains(bodyPlaceholder)
        }
        let editor = try XCTUnwrap(editor(in: host))
        window.makeFirstResponder(editor)
        editor.setMarkedText("xing", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertTrue(notes.notes.first?.document.isEmpty ?? false,
                      "组合阶段模型里还没有提交任何字")
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(titles.contains(bodyPlaceholder),
                       "拼音组合阶段占位文案就应让位，而不是等上屏提交")

        editor.unmarkText()
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(titles.contains(bodyPlaceholder))

        editor.selectAll(nil)
        editor.deleteBackward(nil)
        try InspectorPanelTestSupport.waitUntil("删空正文后占位文案应恢复") {
            titles.contains(bodyPlaceholder)
        }
    }
}
