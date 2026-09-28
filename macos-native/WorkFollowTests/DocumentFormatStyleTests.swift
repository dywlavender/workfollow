import XCTest
@testable import WorkFollow

/// 工具条激活态所依赖的"读选区样式"。
///
/// 这几条用例守的是两件事：**段落类型**读得对（标题/引用/列表与正文分得开），以及
/// **行内标记**按"选区里每个 run 都有才算激活"的口径读（与原版 `isActive` 一致，
/// 也与"再点一次会取消"的判断同源——否则会出现按钮亮着却取消不掉的错位）。
final class DocumentFormatStyleTests: XCTestCase {

    func testReadsBlockKindOfAHeading() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题", marks: [])])
        ])
        let style = DocumentTextCodec.style(of: DocumentTextCodec.render(document))

        XCTAssertTrue(style.isBlock(.heading(1)))
        XCTAssertFalse(style.isBlock(.heading(2)))
        XCTAssertFalse(style.isBlock(.paragraph))
    }

    func testReadsQuoteAndListAsTheirOwnKinds() {
        let quote = NativeDocument(blocks: [
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引用", marks: [])])
        ])
        XCTAssertTrue(DocumentTextCodec.style(of: DocumentTextCodec.render(quote)).isBlock(.quote))

        let bullet = NativeDocument(blocks: [
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "一条", marks: [])])
        ])
        XCTAssertTrue(DocumentTextCodec.style(of: DocumentTextCodec.render(bullet)).isBlock(.bullet))
    }

    func testMarksActivateOnlyWhenSomeRunCarriesThem() {
        let bold = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "加粗", marks: [.bold])])
        ])
        XCTAssertTrue(DocumentTextCodec.style(of: DocumentTextCodec.render(bold)).has(.bold))
        XCTAssertFalse(DocumentTextCodec.style(of: DocumentTextCodec.render(bold)).has(.italic))
    }

    func testMixedSelectionIsNotActive() {
        // 一半粗一半不粗：原版 `isActive` 不会认为整段是粗体，工具条也不该亮。
        let mixed = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "粗", marks: [.bold]),
                DocumentRun(text: "不粗", marks: [])
            ])
        ])
        XCTAssertFalse(DocumentTextCodec.style(of: DocumentTextCodec.render(mixed)).has(.bold))
    }

    func testPlainTextHasNoMarksAndIsParagraph() {
        let style = DocumentTextCodec.style(of: DocumentTextCodec.render(NativeDocument(plainText: "普通一段")))
        XCTAssertTrue(style.marks.isEmpty)
        XCTAssertTrue(style.isBlock(.paragraph))
    }

    // MARK: - 标题字阶：22 / 19 / 16，半粗

    /// 原版 `WorkFollowMacTypography.documentH1/H2/H3` = 22 / 19 / 16，正文 14；
    /// 字重是 `semibold`（`document_styles.dart:114`），不是粗体。
    func testHeadingLevelsRenderAtTheirOwnSizeAndSemiboldWeight() throws {
        let expectations: [(DocumentBlockKind, CGFloat)] = [
            (.paragraph, 14), (.heading(1), 22), (.heading(2), 19), (.heading(3), 16)
        ]
        for (kind, size) in expectations {
            let rendered = DocumentTextCodec.render(NativeDocument(blocks: [
                DocumentBlock(kind: kind, runs: [DocumentRun(text: "字号", marks: [])])
            ]))
            let font = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.pointSize, size, "\(kind) 的字号应为 \(size)")

            let isHeading: Bool = { if case .heading = kind { return true }; return false }()
            if isHeading {
                XCTAssertEqual(font.fontName,
                               NSFont.systemFont(ofSize: size, weight: .semibold).fontName,
                               "\(kind) 应是半粗字面")
            }
        }
    }

    /// 用户报的问题：空行上选完标题，**当场**就该按该级别重排，且接着输入的字也
    /// 必须是该级别字号——原版 Quill 的 `formatText` 直接改 Delta，并把行格式留在
    /// 输入位置上；而不是等整篇重新渲染（切走再切回来）才换字号。
    @MainActor
    func testApplyingHeadingToAnEmptyLineAppliesAndContinuesAtThatSize() throws {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.profile = DocumentProfile(taskSlash: true)
        // 中间的空行在文档里就是那一个换行字符（下标 6）。
        let document = NativeDocument(plainText: "前面的段落\n\n后面的段落")
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.setSelectedRange(NSRange(location: 6, length: 0))

        let command = try XCTUnwrap(DocumentFormatCommand.commands.first { $0.block == .heading(1) })
        view.applyFormat(command)

        let token = try XCTUnwrap(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 6,
                                                             effectiveRange: nil) as? String)
        XCTAssertEqual(token, "h1", "空行设标题后，文档里那一行当场就该是 h1")
        let font = try XCTUnwrap(view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 22, "空行那一行当场就该按 22pt 重排")
        let typing = try XCTUnwrap(view.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(typing.pointSize, 22, "接着输入的字也必须继承标题字号")

        view.insertText("标题内容", replacementRange: view.selectedRange())
        let typed = try XCTUnwrap(view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(typed.pointSize, 22, "实际敲进去的字是 22pt")
    }

    /// 文末那个"一个字符都没有"的空段落：级别只存在于输入属性里，模型必须能收到它，
    /// 否则"在文末空行上选标题、不输入就切走"会丢掉这一级。
    @MainActor
    func testHeadingOnATrailingEmptyParagraphSurvivesIntoTheModel() throws {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.profile = DocumentProfile(taskSlash: true)
        let document = NativeDocument(plainText: "正文\n")
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.setSelectedRange(NSRange(location: 3, length: 0))

        let command = try XCTUnwrap(DocumentFormatCommand.commands.first { $0.block == .heading(2) })
        view.applyFormat(command)

        XCTAssertEqual(view.pendingTrailingBlock, .heading(2), "文末空段落的级别要被记为待定")
        let saved = DocumentTextCodec.decode(view.attributedString(), preserving: document,
                                             trailing: view.pendingTrailingBlock)
        XCTAssertEqual(saved.blocks.map(\.kind), [.paragraph, .heading(2)])

        // 再渲染一次（等于切走再回来）：文末空段落仍是二级标题
        let reloaded = DocumentTextCodec.decode(DocumentTextCodec.render(saved), preserving: saved,
                                                trailing: view.pendingTrailingBlock)
        XCTAssertEqual(reloaded.blocks.map(\.kind), [.paragraph, .heading(2)])
    }

    /// 绑定文档时把文末级别带回输入属性，切走再回来接着输入才不会退回正文。
    @MainActor
    func testDocumentRebindSeedsTheTrailingBlockKindForTyping() {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        view.delegate = coordinator
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
            DocumentBlock(kind: .heading(2), runs: [])
        ])

        coordinator.update(view, documentID: UUID(), document: document,
                           onDocumentChange: { _ in }, onEscape: { .keepInspector },
                           onEditingChanged: { _ in })

        XCTAssertEqual(view.pendingTrailingBlock, .heading(2))
        XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, 19)
    }

    /// Markdown 快捷输入：敲完前缀（光标紧跟其后）自动成块，触发串从正文里移除，
    /// 随后输入的内容落在新块里——与真实打字顺序一致。
    @MainActor
    func testMarkdownTriggersConvertTypedPrefixes() throws {
        let cases: [(String, DocumentBlockKind, String)] = [
            ("# ", .heading(1), "标题"),
            ("## ", .heading(2), "标题"),
            ("- ", .bullet, "项目"),
            ("1. ", .ordered, "事项"),
            ("[] ", .checklist(false), "待办"),
            ("> ", .quote, "引用")
        ]
        for (prefix, kind, rest) in cases {
            let view = NativeTextView(frame: .zero, textContainer: nil)
            view.profile = DocumentProfile(taskSlash: true)
            view.insertText(prefix, replacementRange: NSRange(location: 0, length: 0))
            // 剩余为空 → 整篇变空段落，级别记为待定（模型层由 decode(trailing:) 接收）
            XCTAssertEqual(view.pendingTrailingBlock, kind, "\(prefix) 应把级别记为待定")
            XCTAssertEqual(view.string, "", "\(prefix) 的触发串应被移除")
            view.insertText(rest, replacementRange: view.selectedRange())
            let after = DocumentTextCodec.decode(view.attributedString(),
                                                 preserving: NativeDocument(plainText: view.string))
            XCTAssertEqual(after.blocks.map(\.kind), [kind], "\(prefix) 之后输入的内容应留在 \(kind)")
            XCTAssertEqual(after.plainText, rest)
        }
        // 非触发：`#` 后没有空格不成块
        let plain = NativeTextView(frame: .zero, textContainer: nil)
        plain.profile = DocumentProfile(taskSlash: true)
        plain.insertText("#没有空格", replacementRange: NSRange(location: 0, length: 0))
        let kept = DocumentTextCodec.decode(plain.attributedString(),
                                            preserving: NativeDocument(plainText: plain.string))
        XCTAssertEqual(kept.blocks.map(\.kind), [.paragraph])
    }

    /// `---` 整行 + 回车 → 分割线。
    @MainActor
    func testMarkdownDividerTriggerOnNewline() {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.profile = DocumentProfile(taskSlash: true)
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "---")))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        let decoded = DocumentTextCodec.decode(view.attributedString(),
                                               preserving: NativeDocument(plainText: view.string))
        XCTAssertTrue(decoded.blocks.contains { $0.kind == .divider })
        XCTAssertFalse(view.string.contains("---"))
    }

    /// 已勾选检查项的置灰与删除线是**展示层**：渲染时写入，解码时不成为用户标记。
    @MainActor
    func testCheckedChecklistGreysAndStrikesWithoutPollutingMarks() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成", marks: [])])
        ])
        let rendered = DocumentTextCodec.render(document)
        XCTAssertEqual((rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor),
                       NSColor.secondaryLabelColor)
        XCTAssertNotEqual(rendered.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int, 0)

        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.blocks[0].runs[0].marks, [], "删除线不应写进用户标记")
        XCTAssertEqual(decoded.blocks[0].kind, .checklist(true))
    }

    /// "输入的字号"这条链：空段落上设标题走的是 `typingAttributes` 分支，之后真正
    /// 敲进去的字必须继承该级别字号（三级标题各不相同）。
    @MainActor
    func testTypingAfterApplyingAHeadingUsesThatLevelsSize() throws {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.profile = DocumentProfile(taskSlash: true)
        for (level, size) in [(1, CGFloat(22)), (2, CGFloat(19)), (3, CGFloat(16))] {
            view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "")))
            view.setSelectedRange(NSRange(location: 0, length: 0))
            let command = try XCTUnwrap(DocumentFormatCommand.commands.first { $0.block == .heading(level) })
            view.applyFormat(command)

            let typing = try XCTUnwrap(view.typingAttributes[.font] as? NSFont)
            XCTAssertEqual(typing.pointSize, size, "设 \(level) 级标题后，待输入字号应为 \(size)")

            view.insertText("标题正文", replacementRange: view.selectedRange())
            let typed = try XCTUnwrap(view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(typed.pointSize, size, "\(level) 级标题下实际输入的字号")
        }
    }
}
