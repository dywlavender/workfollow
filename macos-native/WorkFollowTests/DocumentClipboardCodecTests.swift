import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentClipboardCodecTests: XCTestCase {
    func testPrivateFlavorKeepsStructureMarksAttachmentsAndFreshBlockIdentity() throws {
        let file = NativeAttachment(id: UUID(), name: "报告.pdf", storedName: "report.pdf")
        let image = NativeAttachment(id: UUID(), name: "图片.png", storedName: "data:image/png;base64,AAAA")
        let diagram = NativeDiagram(xml: NativeDiagram.emptyXML, previewPNG: Data([1, 2, 3]))
        let document = NativeDocument(blocks: [
            block(.heading(2), "标题", [.bold]), block(.bullet, "要点"), block(.ordered, "第一项"),
            block(.ordered, "第二项"), block(.quote, "引用"), block(.checklist(false), "未完成"),
            block(.checklist(true), "已完成"),
            block(.paragraph, "多种样式", [.italic, .underline, .strikethrough, .highlight, .code, .link("https://example.test")]),
            // The private clipboard must not go through the persistence adapter
            // that normalizes code runs and discards their inline marks.
            block(.code, "let value = 1", [.bold, .underline]),
            block(.divider, "\u{FFFC}"),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: file),
                DocumentRun(text: "\u{FFFC}", attachment: image), DocumentRun(text: "\u{FFFC}", diagram: diagram)])
        ])
        let original = DocumentClipboardCodec.Fragment(document: document,
            startsAtParagraphBoundary: true, endsAtParagraphBoundary: true)
        let data = try DocumentClipboardCodec.encodedData(for: original)
        let first = try XCTUnwrap(DocumentClipboardCodec.decode(data))
        let second = try XCTUnwrap(DocumentClipboardCodec.decode(data))
        XCTAssertEqual(first.document.blocks.map(\.kind), document.blocks.map(\.kind))
        XCTAssertEqual(first.document.blocks.map(\.runs), document.blocks.map(\.runs))
        XCTAssertTrue(Set(first.document.blocks.map(\.id)).isDisjoint(with: document.blocks.map(\.id)))
        XCTAssertTrue(Set(first.document.blocks.map(\.id)).isDisjoint(with: second.document.blocks.map(\.id)))
        XCTAssertEqual(first.document.blocks.last?.runs.first?.attachment, file)
        XCTAssertEqual(first.document.blocks.last?.runs.last?.diagram, diagram)
    }

    func testSelectingWholeHeadingVersusWordKeepsBoundaryMeaning() throws {
        let original = NativeDocument(blocks: [block(.heading(1), "标题内容", [.bold]), block(.paragraph, "下一段")])
        let source = DocumentTextCodec.render(original)
        let full = try XCTUnwrap(DocumentClipboardCodec.fragment(from: source, range: NSRange(location: 0, length: 4)))
        XCTAssertTrue(full.startsAtParagraphBoundary)
        XCTAssertTrue(full.endsAtParagraphBoundary, "The newline itself need not be selected")
        XCTAssertEqual(DocumentClipboardCodec.markdown(full), "# **标题内容**")

        let part = try XCTUnwrap(DocumentClipboardCodec.fragment(from: source, range: NSRange(location: 1, length: 2)))
        XCTAssertFalse(part.startsAtParagraphBoundary)
        XCTAssertFalse(part.endsAtParagraphBoundary)
        XCTAssertEqual(DocumentClipboardCodec.markdown(part), "**题内**")
        let destination = DocumentTextCodec.render(NativeDocument(blocks: [block(.quote, "前后")]))
        let value = try XCTUnwrap(DocumentClipboardCodec.attributedContent(for: part,
            replacing: NSRange(location: 1, length: 0), in: destination))
        let pasted = DocumentTextCodec.decode(value, preserving: .empty)
        XCTAssertEqual(value.string, "题内")
        XCTAssertEqual(pasted.blocks.first?.kind, .quote)
        XCTAssertEqual(pasted.blocks.first?.runs.first?.marks, [.bold])
    }

    func testWholeBlocksSplitDestinationWithoutChangingPrefixOrSuffixStyle() throws {
        let fragment = DocumentClipboardCodec.Fragment(document: NativeDocument(blocks: [
            block(.heading(2), "标题"), block(.checklist(false), "行动")
        ]), startsAtParagraphBoundary: true, endsAtParagraphBoundary: true)
        let destinationDocument = NativeDocument(blocks: [block(.quote, "前文后文")])
        let destination = NSMutableAttributedString(attributedString: DocumentTextCodec.render(destinationDocument))
        let range = NSRange(location: 2, length: 0)
        let value = try XCTUnwrap(DocumentClipboardCodec.attributedContent(for: fragment,
            replacing: range, in: destination))
        destination.replaceCharacters(in: range, with: value)
        let result = DocumentTextCodec.decode(destination, preserving: destinationDocument)
        XCTAssertEqual(result.plainText, "前文\n标题\n行动\n后文")
        XCTAssertEqual(result.blocks.map(\.kind), [.quote, .heading(2), .checklist(false), .quote])
    }

    func testWholeBlockAtStartOfExistingParagraphStillSeparatesFollowingText() throws {
        let fragment = DocumentClipboardCodec.Fragment(document: NativeDocument(blocks: [block(.heading(1), "标题")]),
            startsAtParagraphBoundary: true, endsAtParagraphBoundary: true)
        let destinationDocument = NativeDocument(blocks: [block(.paragraph, "前段"), block(.quote, "后段")])
        let destination = NSMutableAttributedString(attributedString: DocumentTextCodec.render(destinationDocument))
        let range = NSRange(location: 3, length: 0)
        let value = try XCTUnwrap(DocumentClipboardCodec.attributedContent(for: fragment,
            replacing: range, in: destination))
        destination.replaceCharacters(in: range, with: value)
        let result = DocumentTextCodec.decode(destination, preserving: destinationDocument)
        XCTAssertEqual(result.plainText, "前段\n标题\n后段")
        XCTAssertEqual(result.blocks.map(\.kind), [.paragraph, .heading(1), .quote])
    }

    func testPartialMultiParagraphSelectionMergesEdgesButKeepsMiddleBlock() throws {
        let source = DocumentTextCodec.render(NativeDocument(blocks: [
            block(.heading(1), "甲乙"), block(.checklist(true), "完成"), block(.ordered, "丙丁")
        ]))
        let fragment = try XCTUnwrap(DocumentClipboardCodec.fragment(from: source,
            range: NSRange(location: 1, length: source.length - 2)))
        let destinationDocument = NativeDocument(blocks: [block(.quote, "左右")])
        let destination = NSMutableAttributedString(attributedString: DocumentTextCodec.render(destinationDocument))
        let range = NSRange(location: 1, length: 0)
        let value = try XCTUnwrap(DocumentClipboardCodec.attributedContent(for: fragment,
            replacing: range, in: destination))
        destination.replaceCharacters(in: range, with: value)
        let result = DocumentTextCodec.decode(destination, preserving: destinationDocument)
        XCTAssertEqual(result.plainText, "左乙\n完成\n丙右")
        XCTAssertEqual(result.blocks.map(\.kind), [.quote, .checklist(true), .quote])
    }

    func testFullSelectionIncludingTrailingNewlinePreservesEmptyFinalParagraph() throws {
        let document = NativeDocument(blocks: [block(.ordered, "第一项"), block(.ordered, "第二项"),
                                               block(.paragraph, "")])
        let source = DocumentTextCodec.render(document)
        let fragment = try XCTUnwrap(DocumentClipboardCodec.fragment(from: source,
            range: NSRange(location: 0, length: source.length)))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WorkFollow.ClipboardTests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(DocumentClipboardCodec.write(fragment, to: pasteboard))
        let read = try XCTUnwrap(DocumentClipboardCodec.read(from: pasteboard))
        XCTAssertEqual(read.document.plainText, "第一项\n第二项\n")
        XCTAssertEqual(read.document.blocks.map(\.kind), [.ordered, .ordered, .paragraph])
        XCTAssertEqual(pasteboard.string(forType: .string), "1. 第一项\n2. 第二项\n")
    }

    func testMarkdownCarriesTaskStructureLinksAndCodeWithoutBlockIdentity() throws {
        let document = NativeDocument(blocks: [block(.heading(2), "计划"), block(.ordered, "一"),
            block(.ordered, "二"), block(.checklist(false), "待做"), block(.checklist(true), "做完"),
            block(.quote, "引用"), block(.paragraph, "网页", [.link("https://example.test/a(b)")]),
            block(.code, "print(`value`)"), block(.divider, "\u{FFFC}")])
        let fragment = DocumentClipboardCodec.Fragment(document: document,
            startsAtParagraphBoundary: true, endsAtParagraphBoundary: true)
        let value = DocumentClipboardCodec.markdown(fragment)
        XCTAssertTrue(value.contains("## 计划\n1. 一\n2. 二\n- [ ] 待做\n- [x] 做完\n> 引用"))
        XCTAssertTrue(value.contains("[网页](<https://example.test/a(b)>)"))
        XCTAssertTrue(value.contains("```\nprint(`value`)\n```"))
        XCTAssertTrue(value.hasSuffix("---"))
        for id in document.blocks.map(\.id) { XCTAssertFalse(value.contains(id.uuidString)) }
    }

    func testUnsupportedPrivateVersionFallsBackWithoutReturningPartialDocument() throws {
        let fragment = DocumentClipboardCodec.Fragment(document: NativeDocument(plainText: "正文"),
            startsAtParagraphBoundary: true, endsAtParagraphBoundary: true)
        let data = try DocumentClipboardCodec.encodedData(for: fragment)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 2
        XCTAssertNil(DocumentClipboardCodec.decode(try JSONSerialization.data(withJSONObject: object)))
    }

    private func block(_ kind: DocumentBlockKind, _ text: String,
                       _ marks: Set<DocumentMark> = []) -> DocumentBlock {
        DocumentBlock(kind: kind, runs: [DocumentRun(text: text, marks: marks)])
    }
}
