import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentExternalClipboardCodecTests: XCTestCase {
    func testMarkdownKeepsEveryParagraphIncludingEmptyAndTrailingLines() throws {
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromMarkdown:
            "# 标题\n\n- **要点**\n1. 编号\n- [x] 完成\n> 引用\n"))
        XCTAssertEqual(value.document.blocks.map(\.kind), [.heading(1), .paragraph, .bullet,
            .ordered, .checklist(true), .quote, .paragraph])
        XCTAssertEqual(value.document.plainText, "标题\n\n要点\n编号\n完成\n引用\n")
        XCTAssertEqual(value.document.blocks[2].runs.first?.marks, [.bold])
        XCTAssertTrue(value.startsAtParagraphBoundary)
        XCTAssertTrue(value.endsAtParagraphBoundary)
    }

    func testMarkdownFencesKeepCodeLiteralAndDoNotDropBlankLines() throws {
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromMarkdown:
            "```swift\n# **原文**\n\n```\n\n尾段\n"))
        XCTAssertEqual(value.document.blocks.map(\.kind), [.code, .code, .paragraph, .paragraph, .paragraph])
        XCTAssertEqual(value.document.blocks[0].plainText, "# **原文**")
        XCTAssertTrue(value.document.blocks[0].runs.allSatisfy { $0.marks.isEmpty })
        XCTAssertEqual(value.document.blocks[1].plainText, "")
        XCTAssertEqual(value.document.blocks.last?.plainText, "")
    }

    func testInlineOnlyMarkdownKeepsDestinationTypeAndPlainTextFallsThrough() throws {
        XCTAssertNil(DocumentExternalClipboardCodec.fragment(fromMarkdown: "普通文字\n另一行"))
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromMarkdown: "**加粗**"))
        XCTAssertFalse(value.startsAtParagraphBoundary)
        XCTAssertFalse(value.endsAtParagraphBoundary)
        let destination = DocumentTextCodec.render(NativeDocument(blocks: [block(.quote, "引用")]))
        let insertion = try XCTUnwrap(DocumentClipboardCodec.attributedContent(for: value,
            replacing: NSRange(location: 1, length: 0), in: destination))
        XCTAssertEqual(insertion.string, "加粗")
        let decoded = DocumentTextCodec.decode(insertion, preserving: .empty)
        XCTAssertEqual(decoded.blocks.first?.kind, .quote)
        XCTAssertEqual(decoded.blocks.first?.runs.first?.marks, [.bold])
    }

    func testCodeDestinationDoesNotConvertExternalFormattingMarkers() {
        XCTAssertNil(DocumentExternalClipboardCodec.fragment(fromMarkdown: "# 标题\n**文字**", destinationKind: .code))
        XCTAssertNil(DocumentExternalClipboardCodec.fragment(fromHTML: "<h1>标题</h1>", destinationKind: .code))
        XCTAssertNil(DocumentExternalClipboardCodec.fragment(from: NSAttributedString(string: "# 标题"), destinationKind: .code))
    }

    func testRichImportUsesExplicitParagraphSemanticsInsteadOfFontSize() throws {
        let large = NSAttributedString(string: "大号文字", attributes: [.font: NSFont.systemFont(ofSize: 36)])
        XCTAssertNil(DocumentExternalClipboardCodec.fragment(from: large))
        let bold = NSAttributedString(string: "加粗", attributes: [.font: NSFont.boldSystemFont(ofSize: 36)])
        let inline = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(from: bold))
        XCTAssertEqual(inline.document.blocks.first?.kind, .paragraph)
        XCTAssertFalse(inline.startsAtParagraphBoundary)

        let value = NSMutableAttributedString(string: "标题\n第一项\n第二项")
        let heading = NSMutableParagraphStyle(); heading.headerLevel = 2
        value.addAttribute(.paragraphStyle, value: heading, range: NSRange(location: 0, length: 3))
        let list = NSTextList(markerFormat: .decimal, options: 0)
        let ordered = NSMutableParagraphStyle(); ordered.textLists = [list]
        value.addAttribute(.paragraphStyle, value: ordered, range: NSRange(location: 3, length: value.length - 3))
        let result = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(from: value))
        XCTAssertEqual(result.document.blocks.map(\.kind), [.heading(2), .ordered, .ordered])
    }

    func testSemanticHTMLRoundTripPreservesListsChecksQuotesCodeAndEmptyParagraph() throws {
        let document = NativeDocument(blocks: [block(.heading(2), "标题"), block(.ordered, "第一项"),
            block(.ordered, "第二项"), block(.bullet, "要点"), block(.checklist(false), "待做"),
            block(.checklist(true), "已做"), block(.quote, "引用"), block(.code, "a < b && b > 0"),
            block(.paragraph, ""), block(.paragraph, "链接", [.bold, .link("https://example.test/?a=1&b=2")])])
        let fragment = full(document)
        let html = DocumentExternalClipboardCodec.html(for: fragment)
        XCTAssertTrue(html.contains("<h2>")); XCTAssertTrue(html.contains("<ol>"))
        XCTAssertTrue(html.contains("<blockquote>")); XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("checked=\"checked\""))
        let read = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromHTML: html))
        XCTAssertEqual(read.document.blocks.map(\.kind), document.blocks.map(\.kind))
        XCTAssertEqual(read.document.plainText, document.plainText)
        XCTAssertEqual(read.document.blocks.last?.runs.first?.marks, [.bold, .link("https://example.test/?a=1&b=2")])
    }

    func testExternalHTMLInlineStyleDoesNotInventHeadingAndRetainsSemanticStructure() throws {
        let inline = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromHTML:
            "<span style='font-size:36px;font-weight:700'>加粗</span>"))
        XCTAssertEqual(inline.document.blocks.first?.kind, .paragraph)
        XCTAssertEqual(inline.document.blocks.first?.runs.first?.marks, [.bold])
        XCTAssertFalse(inline.startsAtParagraphBoundary)
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromHTML:
            "<h3>小标题</h3><ul><li>甲</li><li>乙</li></ul>"))
        XCTAssertEqual(value.document.blocks.map(\.kind), [.heading(3), .bullet, .bullet])
    }

    func testRTFExportKeepsListsWithoutGuessingMissingHeadingMetadata() throws {
        let fragment = full(NativeDocument(blocks: [block(.heading(2), "标题"),
            block(.ordered, "第一项"), block(.ordered, "第二项")]))
        let publicValue = DocumentExternalClipboardCodec.publicAttributedString(for: fragment)
        let first = try XCTUnwrap(publicValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let second = try XCTUnwrap(publicValue.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(first.headerLevel, 2)
        XCTAssertEqual(second.textLists.last?.markerFormat, .decimal)
        let data = try publicValue.data(from: NSRange(location: 0, length: publicValue.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let rich = try XCTUnwrap(NSAttributedString(rtf: data, documentAttributes: nil))
        let read = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(from: rich))
        // Cocoa on the current macOS retains NSTextList but drops headerLevel
        // during RTF serialization. Only preserve a heading if the reader
        // actually reports one; font size/weight must not invent that metadata.
        let reportedLevel = (rich.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0
        let expectedHeading: DocumentBlockKind = reportedLevel > 0 ? .heading(min(6, reportedLevel)) : .paragraph
        XCTAssertEqual(read.document.blocks.map(\.kind), [expectedHeading, .ordered, .ordered])
        XCTAssertEqual(read.document.plainText, "标题\n第一项\n第二项")
    }

    func testClipboardPublishesSemanticPublicFlavorsAndMarkdown() throws {
        let fragment = full(NativeDocument(blocks: [block(.heading(1), "计划"),
            block(.ordered, "一"), block(.ordered, "二"), block(.checklist(false), "待做")]))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WorkFollow.ExternalClipboardTests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(DocumentClipboardCodec.write(fragment, to: pasteboard))
        XCTAssertTrue(try XCTUnwrap(pasteboard.string(forType: .html)).contains("<ol>"))
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
        XCTAssertEqual(pasteboard.string(forType: .string), "# 计划\n1. 一\n2. 二\n- [ ] 待做")
        let read = try XCTUnwrap(DocumentExternalClipboardCodec.read(from: pasteboard))
        XCTAssertEqual(read.document.blocks.map(\.kind), fragment.document.blocks.map(\.kind))
    }

    func testHTMLImportsNestedListsStartAndItemValueWithoutEmptyParentDuplicates() throws {
        let html = "<ol start='4'><li>父项<ul><li>子项</li></ul></li><li value='8'>后项</li></ol>"
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromHTML: html))
        XCTAssertEqual(value.document.plainText, "父项\n子项\n后项")
        XCTAssertEqual(value.document.blocks.map(\.kind), [.ordered, .bullet, .ordered])
        XCTAssertEqual(value.document.blocks.map(\.indentLevel), [0, 1, 0])
        XCTAssertEqual(value.document.blocks.map(\.listStart), [4, nil, 8])
        XCTAssertEqual(DocumentListStructure.ordinal(at: 2, in: value.document.blocks), 8)
    }

    func testNestedHTMLExportRoundTripKeepsParentCountersAndCheckStates() throws {
        let blocks = [list(.ordered, "父项", 0, 4), list(.ordered, "子项", 1, 7),
            list(.bullet, "孙项", 2), list(.ordered, "下一子项", 1),
            list(.ordered, "下一父项", 0), list(.checklist(false), "待做", 1),
            list(.checklist(true), "已做", 1), list(.ordered, "重新编号", 0, 9)]
        let html = DocumentExternalClipboardCodec.html(for: full(NativeDocument(blocks: blocks)))
        XCTAssertTrue(html.contains("<ol start=\"4\""))
        XCTAssertTrue(html.contains("<ol start=\"7\""))
        XCTAssertTrue(html.contains("value=\"9\""))
        let read = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromHTML: html))
        XCTAssertEqual(read.document.blocks.map(\.kind), blocks.map(\.kind))
        XCTAssertEqual(read.document.blocks.map(\.indentLevel), blocks.map(\.indentLevel))
        XCTAssertEqual(read.document.blocks.map(\.listStart), blocks.map(\.listStart))
        XCTAssertEqual(read.document.plainText, blocks.map(\.plainText).joined(separator: "\n"))
        XCTAssertEqual(DocumentListStructure.ordinal(at: 3, in: read.document.blocks), 8)
        XCTAssertEqual(DocumentListStructure.ordinal(at: 4, in: read.document.blocks), 5)
    }

    func testCopiedHTMLSubtreeKeepsItsExplicitDepthWithoutInventingParents() throws {
        let block = list(.ordered, "子树", 2, 5)
        let html = DocumentExternalClipboardCodec.html(for: full(NativeDocument(blocks: [block])))
        let read = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromHTML: html))
        XCTAssertEqual(read.document.blocks.count, 1)
        XCTAssertEqual(read.document.blocks.first?.indentLevel, 2)
        XCTAssertEqual(read.document.blocks.first?.listStart, 5)
    }

    func testMarkdownImportsTwoSpaceAndTabNestingAndNonOneStart() throws {
        let markdown = "4. 父项\n  7. 子项\n\t  - 孙项\n  8. 下一子项\n5. 下一父项\n"
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(fromMarkdown: markdown))
        XCTAssertEqual(value.document.blocks.map(\.indentLevel), [0, 1, 2, 1, 0, 0])
        XCTAssertEqual(value.document.blocks.map(\.listStart), [4, 7, nil, nil, nil, nil])
        XCTAssertEqual(DocumentListStructure.ordinal(at: 3, in: value.document.blocks), 8)
        XCTAssertEqual(DocumentListStructure.ordinal(at: 4, in: value.document.blocks), 5)
        XCTAssertEqual(value.document.blocks.last?.kind, .paragraph)
        XCTAssertNil(DocumentExternalClipboardCodec.fragment(fromMarkdown: markdown, destinationKind: .code))
    }

    func testNestedRTFListChainAndStartingNumberRoundTrip() throws {
        let blocks = [list(.ordered, "父项", 0, 4), list(.ordered, "子项", 1, 7),
                      list(.ordered, "下一父项", 0)]
        let rich = DocumentExternalClipboardCodec.publicAttributedString(for: full(NativeDocument(blocks: blocks)))
        let first = try XCTUnwrap(rich.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let child = try XCTUnwrap(rich.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(first.textLists.count, 1)
        XCTAssertEqual(first.textLists.first?.startingItemNumber, 4)
        XCTAssertEqual(child.textLists.count, 2)
        XCTAssertEqual(child.textLists.last?.startingItemNumber, 7)
        let data = try XCTUnwrap(DocumentRTFStructureCodec.data(from: rich))
        let decoded = try XCTUnwrap(DocumentRTFStructureCodec.attributedString(from: data))
        let read = try XCTUnwrap(DocumentExternalClipboardCodec.fragment(from: decoded))
        XCTAssertEqual(read.document.blocks.map(\.indentLevel), [0, 1, 0])
        XCTAssertEqual(read.document.blocks.map(\.listStart), [4, 7, nil])
        XCTAssertEqual(read.document.plainText, "父项\n子项\n下一父项")
        XCTAssertEqual(DocumentListStructure.ordinal(at: 2, in: read.document.blocks), 5)
    }

    func testRTFOnlyClipboardUsesHeadingCompatibilityReader() throws {
        let rich = DocumentExternalClipboardCodec.publicAttributedString(for:
            full(NativeDocument(blocks: [block(.heading(2), "RTF标题"), block(.paragraph, "正文")])))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WorkFollow.RTFHeadingClipboardTests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(try XCTUnwrap(DocumentRTFStructureCodec.data(from: rich)), forType: .rtf))
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.read(from: pasteboard))
        XCTAssertEqual(value.document.blocks.map(\.kind), [.heading(2), .paragraph])
    }

    func testStyledHtmlDoesNotHideAnExplicitRTFHeading() throws {
        let rich = DocumentExternalClipboardCodec.publicAttributedString(for:
            full(NativeDocument(blocks: [block(.heading(2), "标题"), block(.paragraph, "正文")])))
        let board = NSPasteboard(name: .init("editor-mixed-heading-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("<p><strong>标题</strong></p><p>正文</p>", forType: .html)
        board.setData(try XCTUnwrap(DocumentRTFStructureCodec.data(from: rich)), forType: .rtf)
        let value = try XCTUnwrap(DocumentExternalClipboardCodec.read(from: board))
        XCTAssertEqual(value.document.blocks.map(\.kind), [.heading(2), .paragraph])
        XCTAssertTrue(value.document.blocks[0].runs[0].marks.contains(.bold))
    }

    private func block(_ kind: DocumentBlockKind, _ text: String, _ marks: Set<DocumentMark> = []) -> DocumentBlock {
        DocumentBlock(kind: kind, runs: [DocumentRun(text: text, marks: marks)])
    }

    private func full(_ document: NativeDocument) -> DocumentClipboardCodec.Fragment {
        .init(document: document, startsAtParagraphBoundary: true, endsAtParagraphBoundary: true)
    }

    private func list(_ kind: DocumentBlockKind, _ text: String, _ depth: Int,
                      _ start: Int? = nil) -> DocumentBlock {
        DocumentBlock(kind: kind, runs: [DocumentRun(text: text)], indentLevel: depth, listStart: start)
    }
}
