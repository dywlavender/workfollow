import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIConversationInputTests: XCTestCase {
    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.isEditable, !textView.isFieldEditor {
            return textView
        }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    func testChatPlaceholderYieldsToCompositionAndReturnsAfterSend() throws {
        let model = AIConversationModel()
        var placeholders: [String] = []
        let host = NSHostingView(rootView: AIConversationView(model: model,
            generate: { _, _, _, _, _ in "" })
            .onPreferenceChange(LivePlaceholderTitles.self) { placeholders = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 700)
        defer { window.close() }

        try InspectorPanelTestSupport.waitUntil("空输入框应先显示占位") {
            placeholders.contains("ai.chat.placeholder")
        }
        let editor = try XCTUnwrap(textView(in: host))
        window.makeFirstResponder(editor)
        editor.setMarkedText("xing", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(model.input, "", "组合阶段模型里还没有字")
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(placeholders.contains("ai.chat.placeholder"),
                       "拼音组合阶段占位就该让位")

        editor.unmarkText()
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(model.input, "xing", "上屏后组合串要落到模型")
        XCTAssertFalse(placeholders.contains("ai.chat.placeholder"))

        // 发送后输入框被程序化清空：占位也要回来。
        model.input = ""
        try InspectorPanelTestSupport.waitUntil("清空输入框后占位应恢复") {
            placeholders.contains("ai.chat.placeholder")
        }
    }
}
