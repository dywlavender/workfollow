import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// AI 回复正文必须是**一个**可选文本视图：跨段落/标题/代码块的鼠标拖选要连续。
///
/// 回归背景：原来逐块 `Text` 渲染，`.textSelection(.enabled)` 每块各有一份选区，
/// 鼠标从第一段往下拖到段落末尾就断——用户反馈「跨行内容不能多选中」。
@MainActor
final class AIMessageSelectionTests: XCTestCase {
    private func textViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        func walk(_ node: NSView) {
            if let text = node as? NSTextView { found.append(text) }
            node.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    private func host(_ text: String) -> (NSWindow, NSHostingView<AIMessageContent>) {
        let view = AIMessageContent(text: text)
        let host = NSHostingView(rootView: view)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 700, height: 600)
        return (window, host)
    }

    /// 整条回复只有一个文本视图——这是跨块连续选中的前提。
    func testWholeMessageRendersOneSelectableTextView() throws {
        let body = """
        结论分三块。

        ## 一、现状

        第一段正文，这一行属于第二个段落。

        ## 二、原因

        - 列表项甲
        - 列表项乙

        ```swift
        let broken = true
        ```
        """
        let (window, host) = host(body)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let views = textViews(in: host).filter { $0.isSelectable && !$0.isFieldEditor }
        XCTAssertEqual(views.count, 1, "整条 AI 回复应只有一个可选文本视图，否则选区会在块边界断开")
        let text = try XCTUnwrap(views.first)
        XCTAssertFalse(text.isEditable, "正文只读")
        XCTAssertTrue(text.isSelectable, "正文必须可选中")
    }

    /// 选区可以一次覆盖标题 + 段落 + 列表 + 代码块，且复制出来是连续正文。
    func testSelectionSpansHeadingParagraphAndCodeBlock() throws {
        let body = """
        ## 标题一

        第一段正文。

        ```swift
        let code = 1
        ```

        第二段正文。
        """
        let (window, host) = host(body)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let text = try XCTUnwrap(textViews(in: host).first { $0.isSelectable && !$0.isEditable })
        let full = text.string as NSString
        let heading = full.range(of: "标题一")
        let tail = full.range(of: "第二段正文。")
        XCTAssertNotEqual(heading.location, NSNotFound)
        XCTAssertNotEqual(tail.location, NSNotFound)
        XCTAssertLessThan(heading.location, tail.location)

        // 一次选区覆盖从标题到文末：跨越了段落、代码块与空行。
        let span = NSRange(location: heading.location,
                           length: tail.location + tail.length - heading.location)
        text.setSelectedRange(span)
        XCTAssertEqual(text.selectedRange(), span)
        let selected = full.substring(with: text.selectedRange())
        XCTAssertTrue(selected.contains("标题一"))
        XCTAssertTrue(selected.contains("第一段正文。"))
        XCTAssertTrue(selected.contains("let code = 1"), "代码块也要落在同一选区里")
        XCTAssertTrue(selected.contains("第二段正文。"))
    }

    /// 只读正文要随内容长高，而不是被裁成固定高度。
    func testContentHeightGrowsWithText() throws {
        let short = AIMessageRichText.render("一行。")
        let long = AIMessageRichText.render(
            Array(repeating: "这是一段比较长的正文，用来把高度撑开。", count: 30)
                .joined(separator: "\n\n"))
        XCTAssertGreaterThan(long.length, short.length)

        let (window, host) = host(
            Array(repeating: "这是一段比较长的正文，用来把高度撑开。", count: 30)
                .joined(separator: "\n\n"))
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let text = try XCTUnwrap(textViews(in: host).first { $0.isSelectable && !$0.isEditable })
        XCTAssertGreaterThan(text.frame.height, 100, "多段正文应长高，不能塌成一行")
    }

    /// 行内标记要落成真实属性：`**加粗**` 变粗体而不是留字面星号。
    func testInlineMarkdownBecomesRealAttributes() {
        let rendered = AIMessageRichText.render("普通 **加粗** 和 `代码`")
        let plain = rendered.string
        XCTAssertFalse(plain.contains("**"), "标记符号不应留在正文里")
        XCTAssertFalse(plain.contains("`"))

        let boldRange = (plain as NSString).range(of: "加粗")
        let codeRange = (plain as NSString).range(of: "代码")
        let boldFont = rendered.attributes(at: boldRange.location, effectiveRange: nil)[.font] as? NSFont
        let codeFont = rendered.attributes(at: codeRange.location, effectiveRange: nil)[.font] as? NSFont
        XCTAssertNotNil(boldFont)
        XCTAssertNotNil(codeFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont!).contains(.boldFontMask),
                      "**加粗** 应渲染为粗体")
        XCTAssertTrue(codeFont!.isFixedPitch, "`代码` 应渲染为等宽字体")
    }

    /// 空正文不应崩，也不该留下多余的可选视图。
    func testEmptyMessageIsSafe() {
        let (window, host) = host("")
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)
        let views = textViews(in: host).filter { $0.isSelectable && !$0.isEditable }
        XCTAssertLessThanOrEqual(views.count, 1)
        XCTAssertEqual(views.first?.string ?? "", "")
    }
}

/// 真实对话界面里的 AI 消息：整条回复必须只产生一个可选文本视图，
/// 且用户消息仍是普通 `Text`（那本来就能跨行选中）。
@MainActor
final class AIConversationSelectionIntegrationTests: XCTestCase {
    private func textViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        func walk(_ node: NSView) {
            if let text = node as? NSTextView, !text.isFieldEditor { found.append(text) }
            node.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    func testAssistantReplySelectableAcrossBlocksInsideConversation() throws {
        let reply = """
        结论分三块。

        ## 一、现状

        第一段正文。

        ```swift
        let code = 1
        ```
        """
        let record = AIConversationRecord(messages: [
            .init(role: .user, text: "问一句"),
            .init(role: .assistant, text: reply)
        ])
        let model = AIConversationModel(record: record)
        let host = NSHostingView(rootView: AIConversationView(model: model,
            generate: { _, _, _, _, _ in "" }))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 700)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        // 输入框是唯一可编辑的那个；其余可选文本视图都来自消息正文。
        let selectable = textViews(in: host).filter { $0.isSelectable && !$0.isEditable }
        let assistant = try XCTUnwrap(selectable.first { ($0.string).contains("第一段正文") },
                                      "AI 回复要落在一个可选文本视图里")
        XCTAssertTrue(assistant.string.contains("一、现状"), "标题与正文同属一个文本视图")
        XCTAssertTrue(assistant.string.contains("let code = 1"), "代码块同属一个文本视图")

        let ns = assistant.string as NSString
        let from = ns.range(of: "一、现状")
        let to = ns.range(of: "let code = 1")
        let span = NSRange(location: from.location, length: to.location + to.length - from.location)
        assistant.setSelectedRange(span)
        let selected = ns.substring(with: assistant.selectedRange())
        XCTAssertTrue(selected.contains("第一段正文。"), "拖选能从标题一路覆盖到段落")
        XCTAssertTrue(selected.contains("let code = 1"), "并继续覆盖到代码块")

        // 不再按块炸开：AI 正文不应产生多个可选文本视图。
        let assistantViews = selectable.filter { ($0.string).contains("结论分三块") || ($0.string).contains("第一段正文") }
        XCTAssertEqual(assistantViews.count, 1, "一条 AI 回复只应有一个可选文本视图")
    }
}
