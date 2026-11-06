import AppKit
import XCTest
@testable import WorkFollow

/// AI 回复正文的块级排版：间距、代码底色、列表悬挂缩进、表头。
///
/// 回归背景：块与块之间原来只靠一个裸 `\n` 连接，段落/标题/代码块挤成一
/// 面字墙（对齐 ChatGPT / Claude 的消息排版口径后收口）。
final class AIMessageRichTextLayoutTests: XCTestCase {
    private func paragraphStyle(_ rendered: NSAttributedString, of needle: String) throws -> NSParagraphStyle {
        let range = (rendered.string as NSString).range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound, "正文里应能找到 \(needle)")
        return try XCTUnwrap(rendered.attributes(at: range.location, effectiveRange: nil)[.paragraphStyle]
            as? NSParagraphStyle)
    }

    /// 段落之间要有真实间距（首段 paragraphSpacing 8、末段之前不留顶部空）。
    func testParagraphSpacing() throws {
        let rendered = AIMessageRichText.render("第一段正文。\n\n第二段正文。")
        let first = try paragraphStyle(rendered, of: "第一段")
        XCTAssertEqual(first.paragraphSpacing, 8, accuracy: 0.5)
        XCTAssertEqual(first.paragraphSpacingBefore, 0, "消息顶部不应多出空隙")
        XCTAssertEqual(first.lineSpacing, 6)
        let second = try paragraphStyle(rendered, of: "第二段")
        XCTAssertEqual(second.paragraphSpacing, 8, accuracy: 0.5)
    }

    /// 标题前留白要大于后留白，和正文拉开层级。
    func testHeadingSpacing() throws {
        let rendered = AIMessageRichText.render("第一段正文。\n\n## 标题\n\n后续正文。")
        let heading = try paragraphStyle(rendered, of: "标题")
        XCTAssertEqual(heading.paragraphSpacingBefore, 12, accuracy: 0.5)
        XCTAssertEqual(heading.paragraphSpacing, 8, accuracy: 0.5)
        // h3 与正文拉开一档字号，不再与 14pt 正文同号。
        let h3 = AIMessageRichText.render("### 小标题")
        let h3Range = (h3.string as NSString).range(of: "小标题")
        XCTAssertNotEqual(h3Range.location, NSNotFound)
        let font = try XCTUnwrap(h3.attributes(at: h3Range.location,
                                              effectiveRange: nil)[.font] as? NSFont)
        XCTAssertEqual(font.pointSize, 15)
    }

    /// 代码块要有底色衬出来，块内行距贴紧（不再每行都垫 6pt 段距）。
    func testCodeBlockFillAndTightLines() throws {
        // 前面垫一段正文：代码块在消息首位时顶部不留空（before=0）。
        let rendered = AIMessageRichText.render("说明正文。\n\n```swift\nlet a = 1\nlet b = 2\n```")
        let first = try paragraphStyle(rendered, of: "let a = 1")
        XCTAssertEqual(first.paragraphSpacingBefore, 2, accuracy: 0.5)
        let second = try paragraphStyle(rendered, of: "let b = 2")
        XCTAssertEqual(second.paragraphSpacingBefore, 0, "代码块内部行不应再垫段距")
        XCTAssertEqual(second.paragraphSpacing, 10, accuracy: 0.5)
        let fill = rendered.attribute(.backgroundColor, at: (rendered.string as NSString)
            .range(of: "let a = 1").location, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(fill, "代码块应有底色")
    }

    /// 列表要悬挂缩进：marker 在外、正文对齐到 tab 位，续行归并进上一项。
    func testListHangingIndent() throws {
        let rendered = AIMessageRichText.render("- 项一\n- 项二\n  续行内容")
        XCTAssertTrue(rendered.string.contains("•\t项一"), "marker 与正文之间应是制表符")
        let item = try paragraphStyle(rendered, of: "项一")
        XCTAssertEqual(item.firstLineHeadIndent, 0)
        XCTAssertEqual(item.headIndent, 14)
        XCTAssertTrue(rendered.string.contains("续行内容"), "缩进续行应保留")
    }

    /// 表格首行当表头：半粗 + 底色。
    func testTableHeaderEmphasis() throws {
        let rendered = AIMessageRichText.render("| 名称 | 数量 |\n|---|---|\n| 甲 | 2 |")
        let headerRange = (rendered.string as NSString).range(of: "名称")
        XCTAssertNotEqual(headerRange.location, NSNotFound)
        let font = try XCTUnwrap(rendered.attributes(at: headerRange.location,
                                                    effectiveRange: nil)[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "表头应半粗")
        XCTAssertNotNil(rendered.attributes(at: headerRange.location,
                                           effectiveRange: nil)[.backgroundColor], "表头应有底色")
    }

    /// 空正文与纯空白不崩、不产出内容。
    func testEmptyAndBlankAreSafe() {
        XCTAssertEqual(AIMessageRichText.render("").length, 0)
        XCTAssertEqual(AIMessageRichText.render("   \n\n  ").length, 0)
    }
}
