import XCTest
@testable import WorkFollow

/// Markdown 的**输入期与渲染期解析**契约（2026-10-16 输入期口径修订，对齐滴答
/// 8.0.80；2026-10-17 升级为渲染期解析——历史字面/粘贴中段/编辑揭示的闭合都会
/// 渲染，见 `testReparse*` 与"整串全转"用例）。
///
/// 规格来源与 `MarkdownSyntaxTests` 同一批探针；这里锁的是编辑路径的契约：
/// 完成标记的空格落下即成块、标记串从正文移除（标记由装饰层重画）、
/// 接着输入的字落在新块里、一次撤销回到标记敲下之前。
/// 分割线（整行 `---` / `***` / `___`）换成分割线附件、光标跳下一行；
/// 围栏代码块（整行 3+ 个反引号）成代码段、空代码行回车退回正文。
/// 重解析（`reparseInlineMarkdown`）：加性、幂等、保光标；代码段与工具条 marks 不受影响。
final class MarkdownInputTriggerTests: XCTestCase {

    @MainActor
    private func makeView() -> NativeTextView {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.profile = DocumentProfile(taskSlash: true)
        return view
    }

    /// 模拟真实打字顺序：逐字符 insertText。
    @MainActor
    private func type(_ text: String, into view: NativeTextView) {
        for character in text {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }
    }

    @MainActor
    private func decodedKind(_ view: NativeTextView) -> DocumentBlockKind? {
        let document = DocumentTextCodec.decode(view.attributedString(),
                                                preserving: NativeDocument(plainText: view.string),
                                                trailing: view.pendingTrailingBlock)
        return document.blocks.first?.kind
    }

    // MARK: - 空行上完成标记

    @MainActor
    func testTypedBlockPrefixesConvertAndConsumeTheMarker() throws {
        let expectations: [(String, DocumentBlockKind)] = [
            ("# ", .heading(1)), ("## ", .heading(2)), ("### ", .heading(3)),
            ("#### ", .heading(4)), ("##### ", .heading(5)), ("###### ", .heading(6)),
            ("* ", .bullet), ("- ", .bullet), ("+ ", .bullet),
            ("1. ", .ordered), ("12. ", .ordered),
            ("- [ ] ", .checklist(false)), ("- [x] ", .checklist(true)), ("* [ ] ", .checklist(false)),
            ("* [x] ", .checklist(true)), ("+ [ ] ", .checklist(false)),
            ("> ", .quote)
        ]
        for (prefix, kind) in expectations {
            let view = makeView()
            type(prefix, into: view)
            XCTAssertEqual(view.string, "", "\(prefix) 的标记串应从正文里移除（滴答同款符号隐藏）")
            XCTAssertEqual(view.pendingTrailingBlock, kind, "\(prefix) 应建立待定段落类型")
            XCTAssertEqual(view.displayedTrailingBlock, kind, "\(prefix) 应常驻显示标记")
            XCTAssertEqual(decodedKind(view), kind, "\(prefix) 解码后应是 \(kind)")
        }
    }

    /// 整串写入（AX 写入、粘贴一行的前缀）同样算"完成标记"——滴答的解析是
    /// 渲染期的，写进去的标记行也成块；这里对齐同一结果。
    @MainActor
    func testWholePrefixInsertionAlsoConverts() throws {
        let view = makeView()
        view.insertText("# ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.string, "")
        XCTAssertEqual(view.pendingTrailingBlock, .heading(1))
    }

    // MARK: - 行上已有文字

    @MainActor
    func testTypedPrefixOnALineWithTextKeepsTheText() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "abc")])
        ])))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        type("# ", into: view)

        XCTAssertEqual(view.string, "abc", "标记移除后正文保留")
        let token = view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(token, "h1")
        let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 18, "标题字号当场生效")
        XCTAssertEqual(font?.fontName,
                       NSFont.systemFont(ofSize: 18, weight: .bold).fontName,
                       "字重也是标题的粗体，不是旧字体的特征合并")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0), "光标留在段首")
    }

    @MainActor
    func testTypingContinuesInsideTheNewBlock() throws {
        let view = makeView()
        type("# ", into: view)
        type("标题", into: view)

        XCTAssertEqual(view.string, "标题")
        let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 18, "接着输入的字继承 h1 字号")
        XCTAssertEqual(decodedKind(view), .heading(1))
    }

    /// 文档**中间**的空行：与文末空段走的是不同分支（文末靠待定级别、
    /// 中间那行是"只含换行的段落"）。转换后上下两行不受影响，
    /// 接着输入的字也落在新块里。
    @MainActor
    func testTypedPrefixOnAnEmptyMiddleLine() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "上")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "下")])
        ])))
        // 光标落在中间那行的行首（"上\n" 之后）。
        view.setSelectedRange(NSRange(location: 2, length: 0))
        type("# ", into: view)

        XCTAssertEqual(view.string, "上\n\n下", "标记移除后其余内容不受影响")
        let middle = view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 2, effectiveRange: nil) as? String
        XCTAssertEqual(middle, "h1", "中间空行成为一级标题")
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0, effectiveRange: nil) as? String,
                       "paragraph", "上一行不受影响")
        XCTAssertNil(view.pendingTrailingBlock, "光标不在文末空段，待定级别不该被误设")

        type("标", into: view)
        XCTAssertEqual(view.string, "上\n标\n下")
        let font = view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 18, "接着输入的字继承标题字号")
    }

    // MARK: - 分割线（整行敲完）

    /// 文末敲 `---`：行文本换成分割线附件，补一个空段落供继续输入。
    @MainActor
    func testTypedDividerOnTheLastLineBecomesALine() throws {
        let view = makeView()
        type("---", into: view)

        XCTAssertEqual(view.string, "\u{FFFC}\n", "分割线附件 + 新空段落")
        let decoded = DocumentTextCodec.decode(view.attributedString(),
                                               preserving: NativeDocument(plainText: view.string),
                                               trailing: view.pendingTrailingBlock)
        XCTAssertEqual(decoded.blocks.map(\.kind), [.divider, .paragraph])
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 0), "光标落在空段落里")

        type("下", into: view)
        XCTAssertEqual(view.string, "\u{FFFC}\n下", "接着输入的字落在分割线之后")
    }

    /// 文档中间敲 `---`：只替换行内容、不加行，光标落到下一行行首。
    @MainActor
    func testTypedDividerOnAMiddleLineKeepsNeighbours() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "上")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "下")])
        ])))
        view.setSelectedRange(NSRange(location: 2, length: 0))
        type("---", into: view)

        XCTAssertEqual(view.string, "上\n\u{FFFC}\n下", "只替换行内容，上下两行不动")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: 0), "光标落到下一行行首")
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 2, effectiveRange: nil) as? String,
                       "divider")
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0, effectiveRange: nil) as? String,
                       "paragraph", "上一行不受影响")

        type("补", into: view)
        XCTAssertEqual(view.string, "上\n\u{FFFC}\n补下", "继续输入进入下一行")
    }

    /// `***` / `___` 也是滴答的分割线写法。
    @MainActor
    func testAsteriskAndUnderscoreDividersAlsoConvert() throws {
        for line in ["***", "___"] {
            let view = makeView()
            type(line, into: view)
            XCTAssertEqual(view.string, "\u{FFFC}\n", "\(line) 应成为分割线")
        }
    }

    /// 一次撤销回到第三个符号敲下之前（同分割线一起回退）。
    @MainActor
    func testUndoRevertsTheTypedDividerInOneStep() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "--")])
        ])))
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.insertText("-", replacementRange: view.selectedRange())

        XCTAssertEqual(view.string, "\u{FFFC}\n")
        view.undo(nil)
        XCTAssertEqual(view.string, "--", "一次撤销回到第三个 - 敲下之前")
    }

    // MARK: - 不该触发的输入

    @MainActor
    func testNonMarkerPrefixesStayLiteral() throws {
        for prefix in ["#", "##", "####### ", "[] ", "1.x ", "** ", "--"] {
            let view = makeView()
            type(prefix, into: view)
            XCTAssertEqual(view.string, prefix, "\(prefix) 应原样保留在文本里")
            XCTAssertNil(view.pendingTrailingBlock, "\(prefix) 不应触发段落类型")
            XCTAssertEqual(decodedKind(view), .paragraph, "\(prefix) 应保持普通文本")
        }
    }

    /// 分割线是**整行**判定：`abc---` 尾随、`-*-` 混合、`--` 不满三个都不成线。
    /// （`---abc` 敲到第三个 `-` 时就已成线，只能以整串写入的形态覆盖。）
    @MainActor
    func testNonLineDividersStayLiteral() throws {
        for line in ["--", "abc---", "-*-"] {
            let view = makeView()
            type(line, into: view)
            XCTAssertEqual(view.string, line, "\(line) 不是独立分割线，保持字面")
            XCTAssertEqual(decodedKind(view), .paragraph)
        }
        let pasted = makeView()
        pasted.insertText("---abc", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(pasted.string, "---abc", "后面还有文字不是独立分割线")
    }

    // MARK: - 围栏代码块（整行敲完，2026-10-16 第二轮口径）

    /// 围栏代码块：整行 3+ 个反引号敲完即转（用户确认）——行文本移除、
    /// 段落转为代码、接着输入的字落在代码段里（等宽字体）。
    @MainActor
    func testTypedFenceStartsACodeBlock() throws {
        let view = makeView()
        type("```", into: view)

        XCTAssertEqual(view.string, "", "围栏行文本应从正文移除")
        XCTAssertEqual(view.pendingTrailingBlock, .code, "围栏应建立待定段落类型")
        XCTAssertEqual(view.displayedTrailingBlock, .code, "围栏应常驻显示代码段")
        XCTAssertEqual(decodedKind(view), .code)

        type("let x = 1", into: view)
        XCTAssertEqual(view.string, "let x = 1")
        let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch == true, "接着输入的字是等宽代码字体")
    }

    /// 文档**中间**的空行：围栏成块只影响该行，上下两行不受影响；
    /// 接着输入的字落在代码段里。
    @MainActor
    func testTypedFenceOnAnEmptyMiddleLine() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "上")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "下")])
        ])))
        // 光标落在中间那行的行首（"上\n" 之后）。
        view.setSelectedRange(NSRange(location: 2, length: 0))
        type("```", into: view)

        XCTAssertEqual(view.string, "上\n\n下", "围栏行文本移除后其余内容不受影响")
        let middle = view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 2, effectiveRange: nil) as? String
        XCTAssertEqual(middle, "code", "中间空行成为代码段")
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0, effectiveRange: nil) as? String,
                       "paragraph", "上一行不受影响")
        XCTAssertNil(view.pendingTrailingBlock, "光标不在文末空段，待定级别不该被误设")

        type("let x", into: view)
        XCTAssertEqual(view.string, "上\nlet x\n下")
        let font = view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch == true, "接着输入的字是等宽代码字体")
    }

    /// 代码段回车延续、空代码行回车退回正文（与标题/列表"空块退出"同款）。
    @MainActor
    func testCodeBlockContinuesAndEmptyLineExits() throws {
        let view = makeView()
        type("```", into: view)
        type("甲", into: view)
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        type("乙", into: view)
        XCTAssertEqual(view.string, "甲\n乙")

        func token(at location: Int) -> String? {
            view.textStorage?.attribute(DocumentTextCodec.blockKey, at: location, effectiveRange: nil) as? String
        }
        XCTAssertEqual(token(at: 0), "code")
        XCTAssertEqual(token(at: 2), "code", "有内容行回车延续代码段")

        // 有内容行回车先进空代码行，再按一次回车退出（换行不落下）。
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        XCTAssertEqual(view.string, "甲\n乙\n")
        XCTAssertEqual(view.pendingTrailingBlock, .paragraph, "退出后是正文待定级别")
        type("丙", into: view)
        XCTAssertEqual(view.string, "甲\n乙\n丙")
        XCTAssertEqual(token(at: 4), "paragraph", "空代码行回车后输入的是正文")
        let font = view.textStorage?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        XCTAssertNotEqual(font?.isFixedPitch, true, "正文不是等宽字体")
    }

    /// 围栏守卫：两反引号、行内有文字、整串带语言标记都保持字面；
    /// 代码段里的反引号是代码内容，不二次触发。
    @MainActor
    func testFenceGuardsStayLiteral() throws {
        for literal in ["``", "甲```"] {
            let view = makeView()
            type(literal, into: view)
            XCTAssertEqual(view.string, literal, "\(literal) 应保持字面")
            XCTAssertEqual(decodedKind(view), .paragraph)
        }

        // 逐键输入 "```" 在第三个反引号即成块（触发时机使然，无法预知后续字符），
        // 整串写入带语言标记的围栏则保持字面。
        let tagged = makeView()
        tagged.insertText("```swift", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(tagged.string, "```swift", "整串带语言标记的围栏保持字面")

        let code = makeView()
        type("```", into: code)
        type("```", into: code)
        XCTAssertEqual(code.string, "```", "代码段里的反引号保持字面")
        XCTAssertEqual(decodedKind(code), .code)
    }

    /// 一次撤销回到第三个反引号敲下之前。
    @MainActor
    func testUndoRevertsTheTypedFenceInOneStep() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "``")])
        ])))
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.insertText("`", replacementRange: view.selectedRange())

        XCTAssertEqual(view.string, "")
        XCTAssertEqual(view.pendingTrailingBlock, .code)

        view.undo(nil)
        XCTAssertEqual(view.string, "``", "一次撤销回到第三个反引号敲下之前")
        XCTAssertEqual(decodedKind(view), .paragraph, "段落类型也随转换一起回退")
    }

    /// 代码段落里的行内文本保持字面：码里不做格式转换。
    @MainActor
    func testCodeParagraphKeepsTypedPrefixLiteral() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "abc")])
        ])))
        view.typingAttributes = DocumentTextCodec.attributes(kind: .code, marks: [])
        view.setSelectedRange(NSRange(location: 0, length: 0))
        type("# ", into: view)

        XCTAssertEqual(view.string, "# abc", "代码段落里的字面文本不转换")
        let token = view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 3, effectiveRange: nil) as? String
        XCTAssertEqual(token, "code", "段落类型仍是代码")
        XCTAssertNil(view.pendingTrailingBlock)
    }

    // MARK: - 撤销

    /// 触发与敲下的空格同属一次输入：一次撤销回到空格敲下之前。
    ///
    /// 单元测试里几次 keystroke 落在同一个 runloop 事件里，会被 groupsByEvent
    /// 并成一个撤销分组；这里把标记文本先用 storage 落进去（代表上一次事件敲的
    /// "#"），只把完成标记的空格作为一次输入——分组里就是"空格 + 转换"。
    @MainActor
    func testUndoRevertsTheTriggeredConversionInOneStep() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "#")])
        ])))
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertText(" ", replacementRange: view.selectedRange())

        XCTAssertEqual(view.string, "", "触发后标记串被移除")
        XCTAssertEqual(view.pendingTrailingBlock, .heading(1))

        view.undo(nil)
        XCTAssertEqual(view.string, "#", "一次撤销回到空格敲下之前")
        XCTAssertEqual(decodedKind(view), .paragraph, "段落类型也随转换一起回退")
    }

    // MARK: - 行内标记（闭合即转，2026-10-16 口径）

    /// 7 种行内标记：闭合标记的最后字符落下即转换——开闭符号从正文移除、
    /// 内容按**设值**语义应用标记（只加不减）、光标落内容末尾（用户逐条确认）。
    @MainActor
    func testTypedInlineMarkersConvertAndConsumeTheSymbols() throws {
        let expectations: [(String, String, MarkdownSyntax.InlineMark)] = [
            ("**粗**", "粗", .bold),
            ("*斜*", "斜", .italic),
            ("~~删~~", "删", .strikethrough),
            ("~下划~", "下划", .underline),
            ("::亮::", "亮", .highlight),
            ("`码`", "码", .code),
            ("[字](https://x.com)", "字", .link(url: "https://x.com"))
        ]
        for (source, content, mark) in expectations {
            let view = makeView()
            type(source, into: view)
            XCTAssertEqual(view.string, content, "\(source) 的标记符号应从正文移除")
            XCTAssertEqual(view.selectedRange(),
                           NSRange(location: (content as NSString).length, length: 0),
                           "\(source) 转换后光标应落在内容末尾")
            XCTAssertTrue(inlineMarkPresent(mark, in: view, at: 0),
                          "\(source) 应对内容应用 \(mark)")
            XCTAssertEqual(decodedKind(view), .paragraph, "行内转换不改变段落类型")
        }
    }

    /// 双写标记的中间态不得被单字符标记抢先：`~~删~` 不先转下划线、
    /// `**粗*` 不先转斜体，等第二个字符完成才转（防抢跑守卫）。
    @MainActor
    func testDoubleCharacterMarkersDoNotFireEarly() throws {
        let strike = makeView()
        type("~~删~", into: strike)
        XCTAssertEqual(strike.string, "~~删~", "删除线中间态保持字面，不能先转下划线")
        type("~", into: strike)
        XCTAssertEqual(strike.string, "删")
        XCTAssertTrue(inlineMarkPresent(.strikethrough, in: strike, at: 0))

        let bold = makeView()
        type("**粗*", into: bold)
        XCTAssertEqual(bold.string, "**粗*", "粗体中间态保持字面，不能先转斜体")
        type("*", into: bold)
        XCTAssertEqual(bold.string, "粗")
        XCTAssertTrue(inlineMarkPresent(.bold, in: bold, at: 0))
    }

    /// 行上已有文字与行中文中插入：只转换本次闭合的片段，前后文原样保留。
    @MainActor
    func testTypedInlineKeepsSurroundingText() throws {
        let line = makeView()
        line.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "abc")])
        ])))
        line.setSelectedRange(NSRange(location: 3, length: 0))
        type(" **粗**", into: line)
        XCTAssertEqual(line.string, "abc 粗")
        XCTAssertTrue(inlineMarkPresent(.bold, in: line, at: 4))
        XCTAssertFalse(inlineMarkPresent(.bold, in: line, at: 0), "前面的文字不受影响")
        XCTAssertEqual(decodedKind(line), .paragraph)

        let middle = makeView()
        middle.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "ab")])
        ])))
        middle.setSelectedRange(NSRange(location: 1, length: 0))
        type("**粗**", into: middle)
        XCTAssertEqual(middle.string, "a粗b", "光标后已有内容时只转换闭合片段")
        XCTAssertTrue(inlineMarkPresent(.bold, in: middle, at: 1))
    }

    /// 引用段落照常触发；代码段落的行内文本保持字面（沿用块级的段落 guard）。
    @MainActor
    func testTypedInlineInQuoteAndCodeParagraphs() throws {
        let quote = makeView()
        quote.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引")])
        ])))
        quote.setSelectedRange(NSRange(location: 1, length: 0))
        type("**粗**", into: quote)
        XCTAssertEqual(quote.string, "引粗")
        XCTAssertTrue(inlineMarkPresent(.bold, in: quote, at: 1), "引用段落照常触发行内转换")

        let code = makeView()
        code.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "abc")])
        ])))
        code.typingAttributes = DocumentTextCodec.attributes(kind: .code, marks: [])
        code.setSelectedRange(NSRange(location: 0, length: 0))
        type("**粗**", into: code)
        XCTAssertEqual(code.string, "**粗**abc", "代码段落里的字面文本不转换")
    }

    /// 空 URL、未闭合标记、空内容保持字面；`)` 落下不吞 `[文字]()`。
    @MainActor
    func testEmptyURLAndUnclosedInlineStayLiteral() throws {
        let emptyURL = makeView()
        type("[文字]()", into: emptyURL)
        XCTAssertEqual(emptyURL.string, "[文字]()", "空 URL 不构成链接，保持字面")
        XCTAssertNil(emptyURL.textStorage?.attribute(.link, at: 0, effectiveRange: nil))

        for literal in ["**未闭合", "*未闭合", "`未闭合", "~未闭合", "::未闭合", "~~~~", "::::"] {
            let view = makeView()
            type(literal, into: view)
            XCTAssertEqual(view.string, literal, "\(literal) 应保持字面")
        }

        // 空内容的行内标记不转换。`****` 在**整行**位置会先撞分割线口径（`***`），
        // 所以放在行中间测。
        let emptyContent = makeView()
        emptyContent.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "ab")])
        ])))
        emptyContent.setSelectedRange(NSRange(location: 1, length: 0))
        type("****", into: emptyContent)
        XCTAssertEqual(emptyContent.string, "a****b", "空内容的行内标记保持字面")
    }

    /// 转换后继续输入的字符继承该行内标记（同块级"接着输入的字落在新块里"）。
    @MainActor
    func testTypingContinuesWithTheInlineMark() throws {
        let view = makeView()
        type("**粗**", into: view)
        type("体", into: view)
        XCTAssertEqual(view.string, "粗体")
        XCTAssertTrue(inlineMarkPresent(.bold, in: view, at: 1), "接着输入的字继承粗体")
    }

    /// 触发与闭合字符同属一次输入：一次撤销回到字面标记。
    @MainActor
    func testUndoRevertsTheTypedInlineInOneStep() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "**粗*")])
        ])))
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertText("*", replacementRange: view.selectedRange())

        XCTAssertEqual(view.string, "粗")
        XCTAssertTrue(inlineMarkPresent(.bold, in: view, at: 0))

        view.undo(nil)
        XCTAssertEqual(view.string, "**粗*", "一次撤销回到闭合字符敲下之前")
        XCTAssertFalse(inlineMarkPresent(.bold, in: view, at: 2))
    }

    /// 整串写入（粘贴/AX）：渲染期解析（2026-10-17 口径）——写入文本里**所有**
    /// 闭合标记都转换，不再只认"以标记字符结尾"的最近一处。
    @MainActor
    func testWholeInlineInsertionConvertsEveryClosedSpan() throws {
        let pasted = makeView()
        pasted.insertText("**粗**", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(pasted.string, "粗")
        XCTAssertTrue(inlineMarkPresent(.bold, in: pasted, at: 0))

        let sentence = makeView()
        sentence.insertText("前 **粗** 后", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(sentence.string, "前 粗 后", "中段闭合的标记也转换（渲染期口径）")
        XCTAssertTrue(inlineMarkPresent(.bold, in: sentence, at: 2))
        XCTAssertFalse(inlineMarkPresent(.bold, in: sentence, at: 0), "前后文不受影响")
    }

    // MARK: - 渲染期重解析（2026-10-17 口径）

    /// 历史字面：文档里已有的 `**粗**` 在重解析时渲染成粗体（加载期走同一路径）。
    @MainActor
    func testReparseRendersHistoricalLiterals() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "前 **粗** 后")])
        ])))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(view.string, "前 **粗** 后")

        XCTAssertTrue(view.reparseInlineMarkdown())
        XCTAssertEqual(view.string, "前 粗 后")
        XCTAssertTrue(inlineMarkPresent(.bold, in: view, at: 2))
        XCTAssertFalse(inlineMarkPresent(.bold, in: view, at: 0))
        XCTAssertFalse(view.reparseInlineMarkdown(), "幂等：没有新的闭合片段")
    }

    /// 代码段不参与渲染期解析；没有标记字符时不做任何改动、工具条 marks 不丢失。
    @MainActor
    func testReparseSkipsCodeBlockAndKeepsToolbarMarks() throws {
        let code = makeView()
        code.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "**x**")])
        ])))
        XCTAssertFalse(code.reparseInlineMarkdown())
        XCTAssertEqual(code.string, "**x**", "代码段里的字面保持原样")

        let bold = makeView()
        bold.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "abc", marks: [.bold])])
        ])))
        XCTAssertFalse(bold.reparseInlineMarkdown(), "没有标记字符时不做任何改动")
        XCTAssertTrue(inlineMarkPresent(.bold, in: bold, at: 0), "工具条 marks 保留")
    }

    /// 一段里多个闭合片段一次转换（历史字面批量渲染）。
    @MainActor
    func testReparseConvertsMultipleSpansInOnePass() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph,
                          runs: [DocumentRun(text: "**甲** 与 `乙` 和 [丙](https://x.com)")])
        ])))
        XCTAssertTrue(view.reparseInlineMarkdown())
        XCTAssertEqual(view.string, "甲 与 乙 和 丙")
        XCTAssertTrue(inlineMarkPresent(.bold, in: view, at: 0))
        XCTAssertTrue(inlineMarkPresent(.code, in: view, at: 4))
        XCTAssertTrue(inlineMarkPresent(.link(url: "https://x.com"), in: view, at: 8))
    }

    /// 重解析不把光标移到片段末尾：按删除量校正，保持用户位置。
    @MainActor
    func testReparsePreservesCaret() throws {
        let view = makeView()
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "a**b**c")])
        ])))
        view.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertTrue(view.reparseInlineMarkdown())
        XCTAssertEqual(view.string, "abc")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
    }

    /// 粘贴（⌘V 走 `NSAttributedString` 分支）与整串字符串写入：与逐键同口径触发。
    @MainActor
    func testPastedContentTriggersLikeTyping() throws {
        // 行内：富文本路径（模拟真实粘贴）
        let pastedInline = makeView()
        pastedInline.insertText(NSAttributedString(string: "**粗**"),
                                replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(pastedInline.string, "粗", "粘贴的富文本应以纯文本参与输入期转换")
        XCTAssertTrue(inlineMarkPresent(.bold, in: pastedInline, at: 0))

        // 围栏：整串字符串路径
        let typedFence = makeView()
        typedFence.insertText("```", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(typedFence.string, "", "整串写入的整行围栏应成代码块")
        XCTAssertEqual(decodedKind(typedFence), .code)

        // 围栏：富文本粘贴路径
        let pastedFence = makeView()
        pastedFence.insertText(NSAttributedString(string: "```"),
                               replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(pastedFence.string, "", "粘贴的整行围栏应成代码块")
        XCTAssertEqual(decodedKind(pastedFence), .code)

        // 粘贴带语言标记的围栏仍保持字面（整串写入的字面口径不变）。
        let tagged = makeView()
        tagged.insertText(NSAttributedString(string: "```swift"),
                          replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(tagged.string, "```swift", "带语言标记的整串围栏保持字面")
    }

    /// 行内标记按解析规格落进富文本属性，供断言用。
    @MainActor
    private func inlineMarkPresent(_ mark: MarkdownSyntax.InlineMark,
                                   in view: NativeTextView, at location: Int) -> Bool {
        guard let storage = view.textStorage, location < storage.length else { return false }
        let attrs = storage.attributes(at: location, effectiveRange: nil)
        switch mark {
        case .bold:
            guard let font = attrs[.font] as? NSFont else { return false }
            return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        case .italic:
            guard let font = attrs[.font] as? NSFont else { return false }
            return NSFontManager.shared.traits(of: font).contains(.italicFontMask)
        case .underline:
            return (attrs[.underlineStyle] as? Int).map { $0 != 0 } ?? false
        case .strikethrough:
            return (attrs[.strikethroughStyle] as? Int).map { $0 != 0 } ?? false
        case .highlight:
            return attrs[.backgroundColor] != nil
        case .code:
            return attrs[DocumentTextCodec.inlineCodeKey] as? Bool == true
        case .link(let url):
            return (attrs[.link] as? String) == url
        }
    }
}
