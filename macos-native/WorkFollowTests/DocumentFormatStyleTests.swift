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
        for kind in [DocumentBlockKind.bullet, .ordered, .quote] {
            let structured = try style(kind)
            XCTAssertEqual(structured.headIndent - plain.headIndent, 16)
            XCTAssertEqual(structured.firstLineHeadIndent, structured.headIndent)
            XCTAssertEqual(structured.paragraphSpacing, 2)
            XCTAssertTrue(structured.textLists.isEmpty)
        }
        let checklist = try style(.checklist(false))
        XCTAssertEqual(checklist.headIndent - plain.headIndent, 24, "17pt 勾选框 + 文字间距")
        XCTAssertEqual(checklist.paragraphSpacing, 19, "清单节距 37pt（滴答截图实测）")
        XCTAssertTrue(checklist.textLists.isEmpty)
        XCTAssertEqual(plain.paragraphSpacing, 10, "正文换段留 10pt 段距（ima 实测 5+5）")
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
            XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, 16)
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

    // MARK: - 标题字阶：18 / 16 / 14，粗体

    /// 滴答实测（2026-10-16，截图 1px = 1pt）：标题三级 18 / 16 / 14，正文 14；
    /// 滴答的三级到六级标题是同一字号，所以这里一并锁住 H4 / H6。
    /// 字重是 **bold**：标题笔画宽/字高比实测 0.20（Bold 0.20、Medium 0.158）。
    func testHeadingLevelsRenderAtTheirOwnSizeAndBoldWeight() throws {
        let expectations: [(DocumentBlockKind, CGFloat)] = [
            (.paragraph, 14), (.heading(1), 18), (.heading(2), 16),
            (.heading(3), 14), (.heading(4), 14), (.heading(6), 14)
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
                               NSFont.systemFont(ofSize: size, weight: .bold).fontName,
                               "\(kind) 应是粗体字面")
            }
        }
    }

    // MARK: - 段落度量：滴答实测的间距

    /// 行盒由「字体默认行高 + lineSpacing」合成，恒等于目标值，不受字体版本影响；
    /// 段落基线间距再叠加段间距与相邻两段上伸部差（字号不同时 CoreText 会把下一段的
    /// ascent 计入），用 ±1pt 容差对齐滴答截图量得的 35 / 32 / 29–30，列表与引用 20。
    func testParagraphLineBoxesAndPitchesMatchMeasuredTickTickSpacing() throws {
        func metrics(_ kind: DocumentBlockKind) throws -> (lineBox: CGFloat, spacing: CGFloat, ascent: CGFloat) {
            let attrs = DocumentTextCodec.attributes(kind: kind, marks: [])
            let style = try XCTUnwrap(attrs[.paragraphStyle] as? NSParagraphStyle)
            let font = try XCTUnwrap(attrs[.font] as? NSFont)
            let natural = font.ascender - font.descender + font.leading
            return (natural + style.lineSpacing, style.paragraphSpacing, font.ascender)
        }
        func pitch(_ from: DocumentBlockKind, _ to: DocumentBlockKind) throws -> CGFloat {
            let a = try metrics(from), b = try metrics(to)
            return a.lineBox + a.spacing + (b.ascent - a.ascent)
        }
        func lineBox(_ kind: DocumentBlockKind) throws -> CGFloat { try metrics(kind).lineBox }

        XCTAssertEqual(try lineBox(.heading(1)), 1.6 * 18, accuracy: 0.01, "一级标题行盒 28.8")
        XCTAssertEqual(try lineBox(.heading(2)), 1.6 * 16, accuracy: 0.01, "二级标题行盒 25.6")
        XCTAssertEqual(try lineBox(.heading(3)), 1.6 * 14, accuracy: 0.01, "三级标题行盒 22.4")
        XCTAssertEqual(try lineBox(.heading(6)), 1.6 * 14, accuracy: 0.01, "六级标题与三级同盒")
        XCTAssertEqual(try lineBox(.paragraph), 21, accuracy: 0.01, "正文行盒 1.5 倍字号")
        XCTAssertEqual(try pitch(.paragraph, .paragraph), 31, accuracy: 1,
                       "正文换段 31pt；自动折行/软换行仍 21pt（ima 段距 10）")
        for kind in [DocumentBlockKind.bullet, .ordered, .quote] {
            XCTAssertEqual(try lineBox(kind), 18, accuracy: 0.01, "\(kind) 行盒 18，配 2pt 段间距得 20")
        }
        XCTAssertEqual(try lineBox(.checklist(false)), 18, accuracy: 0.01, "清单行盒 18")
        XCTAssertEqual(try pitch(.checklist(false), .checklist(false)), 37, accuracy: 1,
                       "清单节距约 37（滴答截图实测）")

        XCTAssertEqual(try pitch(.heading(1), .heading(2)), 35, accuracy: 1, "滴答 35")
        XCTAssertEqual(try pitch(.heading(2), .heading(3)), 32, accuracy: 1, "滴答 32")
        // 滴答同一对（14pt 标题之间）两次量得 29（H3→H4）与 30（H4→H5），
        // 差 1px 是墨迹下边缘抗锯齿的取整噪声，按 30 对齐。
        XCTAssertEqual(try pitch(.heading(3), .heading(4)), 30, accuracy: 1, "滴答 29–30")
        XCTAssertEqual(try pitch(.bullet, .ordered), 20, accuracy: 1, "滴答列表 20")
        XCTAssertEqual(try pitch(.quote, .bullet), 20, accuracy: 1, "滴答引用 20")
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
        XCTAssertEqual(font.pointSize, 18, "空行那一行当场就该按 18pt 重排")
        let typing = try XCTUnwrap(view.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(typing.pointSize, 18, "接着输入的字也必须继承标题字号")

        view.insertText("标题内容", replacementRange: view.selectedRange())
        let typed = try XCTUnwrap(view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(typed.pointSize, 18, "实际敲进去的字是 18pt")
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
        XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, 16)
    }

    // 键入 `# `/`- [ ] ` 等前缀的行为已按 2026-10-16 口径修订为**输入期转换**
    // （对齐滴答 8.0.80）：用例见 `MarkdownInputTriggerTests`。

    /// 已勾选检查项只置灰（与已完成任务同档），不再加删除线；解码时也不产生用户标记。
    @MainActor
    func testCheckedChecklistGreysWithoutStrikeOrPollutingMarks() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成", marks: [])])
        ])
        let rendered = DocumentTextCodec.render(document)
        XCTAssertEqual((rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor),
                       NSColor(WFColors.taskCompletedTitle))
        XCTAssertNil(rendered.attribute(.strikethroughStyle, at: 0, effectiveRange: nil),
                     "勾选后只变灰，不划删除线")

        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.blocks[0].runs[0].marks, [], "无删除线可写进用户标记")
        XCTAssertEqual(decoded.blocks[0].kind, .checklist(true))
    }

    /// "输入的字号"这条链：空段落上设标题走的是 `typingAttributes` 分支，之后真正
    /// 敲进去的字必须继承该级别字号（18 / 16 / 14 各不相同）。
    @MainActor
    func testTypingAfterApplyingAHeadingUsesThatLevelsSize() throws {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.profile = DocumentProfile(taskSlash: true)
        for (level, size) in [(1, CGFloat(18)), (2, CGFloat(16)), (3, CGFloat(14))] {
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

    /// 代码块必须和正文区分开：等宽 13pt、左右 12pt 内边距（负 tailIndent 收窄
    /// 折行）、行间无段距，由视图层的圆角卡片背景成块。
    @MainActor
    func testCodeBlockUsesInsetCardTypography() throws {
        let attributes = DocumentTextCodec.attributes(kind: .code, marks: [])
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertTrue(font.isFixedPitch)
        XCTAssertEqual(font.pointSize, 13)
        let style = try XCTUnwrap(attributes[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(style.firstLineHeadIndent,
                       DocumentEditorGeometry.decorationLane + DocumentEditorGeometry.codeBlockTextInset)
        XCTAssertEqual(style.headIndent, style.firstLineHeadIndent)
        XCTAssertEqual(style.tailIndent, -DocumentEditorGeometry.codeBlockTextInset)
        XCTAssertEqual(style.paragraphSpacing, 0)
        XCTAssertGreaterThan(style.lineSpacing, 0, "13pt 等宽字要有舒展的行盒")
    }
}
