import XCTest
@testable import WorkFollow

/// 工具条激活态所依赖的"读选区样式"。
///
/// 这几条用例守的是两件事：**段落类型**读得对（标题/引用/列表与正文分得开），以及
/// **行内标记**按"选区里每个 run 都有才算激活"的口径读（与原版 `isActive` 一致，
/// 也与"再点一次会取消"的判断同源——否则会出现按钮亮着却取消不掉的错位）。
final class DocumentFormatStyleTests: XCTestCase {
    func testStructuredParagraphsUseCompactGeometryWithoutMovingPlainText() throws {
        func style(_ kind: DocumentBlockKind) throws -> NSParagraphStyle {
            try XCTUnwrap(DocumentTextCodec.attributes(kind: kind, marks: [])[.paragraphStyle] as? NSParagraphStyle)
        }
        let plain = try style(.paragraph)
        XCTAssertEqual(plain.headIndent, DocumentEditorGeometry.decorationLane)
        XCTAssertEqual(try style(.heading(1)).headIndent, plain.headIndent)
        for kind in [DocumentBlockKind.bullet, .ordered, .checklist(false), .quote] {
            let structured = try style(kind)
            XCTAssertEqual(structured.headIndent - plain.headIndent, 16)
            XCTAssertEqual(structured.firstLineHeadIndent, structured.headIndent)
            XCTAssertEqual(structured.paragraphSpacing, 2)
            XCTAssertTrue(structured.textLists.isEmpty)
        }
        XCTAssertEqual(plain.paragraphSpacing, 8)
    }

    @MainActor
    func testListFormattingOnlyChangesSelectedParagraphs() throws {
        for kind in [DocumentBlockKind.bullet, .ordered, .checklist(false)] {
            for selectedCount in [1, 2] {
                let view = NativeTextView(frame: .zero, textContainer: nil)
                let document = NativeDocument(blocks: ["甲", "乙", "丙", "丁"].map {
                    DocumentBlock(kind: kind, runs: [DocumentRun(text: $0)])
                })
                view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
                let selection = NSRange(location: 2, length: selectedCount == 1 ? 0 : 3)
                view.setSelectedRange(selection)
                let command = try XCTUnwrap(DocumentFormatCommand.commands.first { $0.block == kind })
                view.applyFormat(command)
                let decoded = DocumentTextCodec.decode(view.attributedString(), preserving: document)
                XCTAssertEqual(decoded.blocks.map(\.kind),
                               [kind, .paragraph, selectedCount == 2 ? .paragraph : kind, kind])
                XCTAssertEqual(view.selectedRange(), selection)
                XCTAssertEqual(view.string, "甲\n乙\n丙\n丁")
            }
        }
    }

    @MainActor
    func testSettingEmptyParagraphFormatSupportsUndoAndRedo() throws {
        for text in ["", "正文\n"] {
            for kind in [DocumentBlockKind.heading(1), .bullet, .ordered, .checklist(false), .quote] {
                let view = NativeTextView(frame: .zero, textContainer: nil)
                let document = NativeDocument(plainText: text)
                view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
                view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
                view.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
                view.undoManager?.removeAllActions()
                let command = try XCTUnwrap(DocumentFormatCommand.commands.first { $0.block == kind })
                view.applyFormat(command)
                XCTAssertEqual(view.pendingTrailingBlock, kind)
                XCTAssertTrue(view.undoManager?.canUndo == true)
                view.undo(nil)
                XCTAssertEqual(DocumentTextCodec.decode(view.attributedString(), preserving: document,
                                                        trailing: view.pendingTrailingBlock).blocks.last?.kind,
                               .paragraph)
                XCTAssertEqual(view.string, text)
                view.redo(nil)
                XCTAssertEqual(view.pendingTrailingBlock, kind)
                view.insertText("继续输入", replacementRange: view.selectedRange())
                let saved = DocumentTextCodec.decode(view.attributedString(), preserving: document,
                                                     trailing: view.pendingTrailingBlock)
                XCTAssertEqual(saved.blocks.last?.kind, kind)
            }
        }
    }

    @MainActor
    func testExitingEmptyBlockSupportsUndoAndRedo() throws {
        for trailing in [false, true] {
            let view = NativeTextView(frame: .zero, textContainer: nil)
            view.isEditable = true
            let blocks = [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "前文")]),
                          DocumentBlock(kind: .heading(2), runs: [])]
                + (trailing ? [] : [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "后文")])])
            let document = NativeDocument(blocks: blocks)
            view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            view.setSelectedRange(NSRange(location: 3, length: 0))
            view.typingAttributes = DocumentTextCodec.attributes(kind: .heading(2), marks: [])
            view.pendingTrailingBlock = trailing ? .heading(2) : nil
            view.undoManager?.removeAllActions()

            XCTAssertTrue(view.exitEmptyBlockOnNewline())
            func kinds() -> [DocumentBlockKind] {
                DocumentTextCodec.decode(view.attributedString(), preserving: document,
                                         trailing: view.pendingTrailingBlock).blocks.map(\.kind)
            }
            XCTAssertEqual(kinds()[1], .paragraph)
            XCTAssertTrue(view.undoManager?.canUndo == true)
            view.undo(nil)
            XCTAssertEqual(kinds()[1], .heading(2))
            XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, 19)
            view.redo(nil)
            XCTAssertEqual(kinds()[1], .paragraph)
            XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
        }
    }

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
    /// Markdown 符号触发已按产品要求移除：段落格式只通过"/"菜单与工具条修改，
    /// 输入 `# `/`- `/`---` 等前缀必须保持普通文本。
    func testTypedMarkdownPrefixesStayPlain() {
        for prefix in ["# ", "## ", "- ", "1. ", "[] ", "> ", "---"] {
            let view = NativeTextView(frame: .zero, textContainer: nil)
            view.profile = DocumentProfile(taskSlash: true)
            view.insertText(prefix, replacementRange: NSRange(location: 0, length: 0))
            XCTAssertNil(view.pendingTrailingBlock, "\(prefix) 不应触发任何段落类型")
            let decoded = DocumentTextCodec.decode(view.attributedString(),
                                                   preserving: NativeDocument(plainText: view.string))
            XCTAssertEqual(decoded.blocks.map(\.kind), [.paragraph],
                           "\(prefix) 应保持普通文本，不做格式转换")
            XCTAssertTrue(view.string.contains(prefix), "\(prefix) 应原样保留在文本里")
        }
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
