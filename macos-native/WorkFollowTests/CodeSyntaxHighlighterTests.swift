import AppKit
import XCTest
@testable import WorkFollow

/// 代码块语法着色（第二批）：配色取自滴答 `ticktick.light/dark.css`。
@MainActor
final class CodeSyntaxHighlighterTests: XCTestCase {

    private let light = NSAppearance(named: .aqua)!
    private let dark = NSAppearance(named: .darkAqua)!

    // MARK: - 分词

    func testTokenizesSwiftCommentStringNumberKeyword() {
        let source = "// 说明\nlet count = 42\nprint(\"hi\")"
        let tokens = CodeSyntaxHighlighter.tokenize(source, language: .swift)
        XCTAssertEqual(tokens.count, (source as NSString).length)

        func token(at needle: String) -> CodeSyntaxHighlighter.Token? {
            let range = (source as NSString).range(of: needle)
            guard range.location != NSNotFound else { return nil }
            return tokens[range.location]
        }
        XCTAssertEqual(token(at: "// 说明"), .comment)
        XCTAssertEqual(token(at: "let"), .keyword)
        XCTAssertEqual(token(at: "42"), .number)
        XCTAssertEqual(token(at: "\"hi\""), .string)
        XCTAssertEqual(token(at: "print"), .function, "标识符后紧跟 ( 视为函数调用")
        XCTAssertEqual(token(at: "count"), .plain)
    }

    func testUnterminatedStringStopsAtLineEnd() {
        let source = "let a = \"未闭合\nlet b = 1"
        let tokens = CodeSyntaxHighlighter.tokenize(source, language: .swift)
        let secondLine = (source as NSString).range(of: "let b")
        XCTAssertEqual(tokens[secondLine.location], .keyword,
                       "上一行的未闭合引号不能把下一行吃掉")
    }

    func testPythonUsesHashCommentsAndDetectsIndentationStyle() {
        let source = "# 注释\ndef run():\n    print(1)"
        let tokens = CodeSyntaxHighlighter.tokenize(source, language: .python)
        XCTAssertEqual(tokens[0], .comment)
        XCTAssertEqual(tokens[(source as NSString).range(of: "def").location], .keyword)
        XCTAssertEqual(CodeSyntaxHighlighter.Language.detect(in: source), .python)
    }

    func testGenericLanguageOnlyHighlightsUnambiguousTokens() {
        let source = "foo bar 12 \"x\" // note"
        let tokens = CodeSyntaxHighlighter.tokenize(source, language: .generic)
        XCTAssertEqual(tokens[(source as NSString).range(of: "foo").location], .plain,
                       "认不出语言时不猜关键字")
        XCTAssertEqual(tokens[(source as NSString).range(of: "12").location], .number)
        XCTAssertEqual(tokens[(source as NSString).range(of: "\"x\"").location], .string)
    }

    func testJSONHasNoLineComments() {
        let source = "{\n  \"url\": \"https://example.com\"\n}"
        let tokens = CodeSyntaxHighlighter.tokenize(source, language: .json)
        // `//` 在 JSON 里是字符串内容，不能当成注释
        let slash = (source as NSString).range(of: "//").location
        XCTAssertNotEqual(tokens[slash], .comment)
        XCTAssertEqual(CodeSyntaxHighlighter.Language.detect(in: source), .json)
    }

    func testNumberScanHandlesHexAndDecimals() {
        let source = "0xFF 3.14 1_000"
        let tokens = CodeSyntaxHighlighter.tokenize(source, language: .swift)
        for needle in ["0xFF", "3.14", "1_000"] {
            let location = (source as NSString).range(of: needle).location
            XCTAssertEqual(tokens[location], .number, "\(needle) 应识别为数字")
        }
    }

    // MARK: - 配色

    func testColorsFollowTickTickTheme() throws {
        func components(_ color: NSColor?) throws -> (CGFloat, CGFloat, CGFloat) {
            let rgb = try XCTUnwrap(color?.usingColorSpace(.sRGB))
            return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        }
        // 关键字 #FF871D（浅）/ #C4742E（深）
        let keywordLight = try components(CodeSyntaxHighlighter.color(for: .keyword, appearance: light))
        XCTAssertEqual(keywordLight.0, 0xFF / 255.0, accuracy: 0.01)
        XCTAssertEqual(keywordLight.1, 0x87 / 255.0, accuracy: 0.01)
        XCTAssertEqual(keywordLight.2, 0x1D / 255.0, accuracy: 0.01)
        let keywordDark = try components(CodeSyntaxHighlighter.color(for: .keyword, appearance: dark))
        XCTAssertEqual(keywordDark.0, 0xC4 / 255.0, accuracy: 0.01)
        // 字符串 #14C257（浅）/ #319A59（深）
        let stringDark = try components(CodeSyntaxHighlighter.color(for: .string, appearance: dark))
        XCTAssertEqual(stringDark.0, 0x31 / 255.0, accuracy: 0.01)
        // plain 不着色
        XCTAssertNil(CodeSyntaxHighlighter.color(for: .plain, appearance: light))
    }

    func testApplyWritesColorsAndRestoresPlainBase() throws {
        let storage = NSMutableAttributedString(string: "let a = 1 // 说明")
        storage.addAttribute(.foregroundColor, value: NSColor.systemPink,
                             range: NSRange(location: 0, length: storage.length))
        CodeSyntaxHighlighter.apply(to: storage, range: NSRange(location: 0, length: storage.length),
                                    language: .swift, baseColor: .labelColor, appearance: light)
        let keyword = try XCTUnwrap(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(keyword, NSColor.systemPink, "关键字要换成主题色")
        let space = try XCTUnwrap(storage.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(space.usingColorSpace(.sRGB), NSColor.labelColor.usingColorSpace(.sRGB),
                       "plain token 写回基色，不留上一轮强调色")
    }

    // MARK: - 渲染接入

    func testRenderColorsCodeBlockWithoutTouchingStorage() throws {
        // 代码块是"一段一行"：两行 = 两个 code block。
        let firstLine = "// 注释"
        let secondLine = "let a = 1"
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .code, runs: [DocumentRun(text: firstLine)]),
            DocumentBlock(kind: .code, runs: [DocumentRun(text: secondLine)])
        ])
        let rendered = DocumentTextCodec.render(document)
        let commentColor = try XCTUnwrap(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let keywordOffset = (rendered.string as NSString).range(of: "let").location
        let keywordColor = try XCTUnwrap(rendered.attribute(.foregroundColor, at: keywordOffset,
                                                            effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(commentColor.usingColorSpace(.sRGB), keywordColor.usingColorSpace(.sRGB))

        // 解码不把颜色当标记：还是同一段文字、同一个 code 类型、没有任何 mark
        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.blocks.first?.kind, .code)
        XCTAssertEqual(decoded.blocks.map(\.plainText), [firstLine, secondLine])
        XCTAssertEqual(decoded.blocks.first?.runs.first?.marks, [])
    }

    func testPlainParagraphIsNotColored() {
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "// 不是代码")])])
        let rendered = DocumentTextCodec.render(document)
        let color = rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color?.usingColorSpace(.sRGB), NSColor.labelColor.usingColorSpace(.sRGB))
    }

    // MARK: - 编辑期重排

    func testTypingInCodeBlockAppliesHighlighting() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { window.close() }

        view.textStorage?.setAttributedString(DocumentTextCodec.render(
            NativeDocument(blocks: [DocumentBlock(kind: .code, runs: [DocumentRun(text: "let a = 1")])])))
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 9, length: 0))
        view.insertText(" // 尾注", replacementRange: view.selectedRange())

        let commentRange = (view.string as NSString).range(of: "// 尾注")
        XCTAssertNotEqual(commentRange.location, NSNotFound)
        let comment = try XCTUnwrap(view.textStorage?.attribute(.foregroundColor, at: commentRange.location,
                                                                effectiveRange: nil) as? NSColor)
        let keyword = try XCTUnwrap(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(comment.usingColorSpace(.sRGB), keyword.usingColorSpace(.sRGB),
                          "新输入的注释要立刻着色")
    }
}
