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
