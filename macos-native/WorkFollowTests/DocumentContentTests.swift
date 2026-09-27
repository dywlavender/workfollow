import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentContentTests: XCTestCase {
    func testBlockPresentationDoesNotBecomeInlineFormatting() {
        for kind in [DocumentBlockKind.heading(1), .heading(3), .code] {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            let original = NativeDocument(blocks: [DocumentBlock(kind: kind, runs: [DocumentRun(text: "正文")])])
            editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
            editor.setSelectedRange(NSRange(location: 0, length: 2))
            editor.applyFormat(.init(title: "正文", block: .paragraph, mark: nil))
            let converted = DocumentTextCodec.decode(editor.attributedString(), preserving: original)
            XCTAssertEqual(converted.blocks[0].kind, .paragraph)
            XCTAssertEqual(converted.blocks[0].runs[0].marks, [])
        }
        let explicit = NativeDocument(blocks: [DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "手动粗体", marks: [.bold])])])
        let decoded = DocumentTextCodec.decode(DocumentTextCodec.render(explicit), preserving: explicit)
        XCTAssertEqual(decoded.blocks[0].runs[0].marks, [.bold])
    }

    func testCaretFormatsComposeAndToggleWithoutChangingExistingText() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        editor.applyFormat(.init(title: "粗体", block: nil, mark: .bold))
        editor.applyFormat(.init(title: "下划线", block: nil, mark: .underline))
        editor.insertText("甲", replacementRange: editor.selectedRange())
        editor.applyFormat(.init(title: "粗体", block: nil, mark: .bold))
        editor.insertText("乙", replacementRange: editor.selectedRange())
        let runs = DocumentTextCodec.decode(editor.attributedString(), preserving: .empty).blocks[0].runs
        XCTAssertEqual(runs.map(\.text), ["甲", "乙"])
        XCTAssertEqual(runs[0].marks, [.bold, .underline])
        XCTAssertEqual(runs[1].marks, [.underline])
    }

    func testEditorFormattingAdditionsPersistAndUndo() throws {
        let editor = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: nil)
        editor.insertText("验收", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        editor.applyFormat(.init(title: "三级标题", block: .heading(3), mark: nil))
        editor.applyFormat(.init(title: "行内代码", block: nil, mark: .code))
        var document = DocumentTextCodec.decode(editor.attributedString(), preserving: .empty)
        XCTAssertEqual(document.blocks[0].kind, .heading(3))
        XCTAssertTrue(document.blocks[0].runs[0].marks.contains(.code))
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        editor.undoManager?.beginUndoGrouping()
        editor.insertDocumentDivider()
        editor.undoManager?.endUndoGrouping()
        document = DocumentTextCodec.decode(editor.attributedString(), preserving: document)
        XCTAssertEqual(document.blocks[1].kind, .divider)
        XCTAssertEqual(document.blocks.last?.kind, .paragraph)
        let restored = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(DocumentTextCodec.decode(DocumentTextCodec.render(restored), preserving: restored).blocks[1].kind, .divider)
        editor.undo(nil)
        XCTAssertEqual(editor.string, "验收")
        editor.redo(nil)
        XCTAssertTrue(editor.string.contains("\u{FFFC}"))
        editor.insertDocumentTime(Date(timeIntervalSince1970: 0))
        XCTAssertTrue(editor.string.contains("1970年1月1日"))
        XCTAssertEqual(DocumentTextCodec.decode(editor.attributedString(), preserving: document).blocks.last?.kind, .paragraph)
    }

    func testLegacyRunWithoutAttachmentDecodes() throws {
        let data = Data("{\"text\":\"old text\",\"marks\":[]}".utf8)
        let run = try JSONDecoder().decode(DocumentRun.self, from: data)
        XCTAssertEqual(run.text, "old text")
        XCTAssertNil(run.attachment)
    }

    func testAttachmentSurvivesTextKitAndJSONRoundTrip() throws {
        let attachment = NativeAttachment(id: UUID(), name: "资料.pdf", storedName: "example.pdf")
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "正文 "), DocumentRun(text: "\u{FFFC}", attachment: attachment)
        ])])
        let rendered = DocumentTextCodec.render(document)
        XCTAssertNotNil(rendered.attribute(.attachment, at: 3, effectiveRange: nil))
        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.blocks.first?.runs.last?.attachment, attachment)
        let restored = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(restored, decoded)
    }

    func testChecklistStatusRoundTrip() {
        for checked in [false, true] {
            let document = NativeDocument(blocks: [DocumentBlock(kind: .checklist(checked), runs: [DocumentRun(text: "item")])])
            let rendered = DocumentTextCodec.render(document)
            XCTAssertEqual(DocumentTextCodec.decode(rendered, preserving: document).blocks.first?.kind, .checklist(checked))
            let style = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(style?.textLists.count, 1)
        }
    }

    func testConsecutiveOrderedBlocksShareOneNativeList() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第二项")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第三项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "分组结束")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "新列表")])
        ])
        let rendered = DocumentTextCodec.render(document)
        let first = try XCTUnwrap((rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first)
        let second = (rendered.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first
        let third = (rendered.attribute(.paragraphStyle, at: 8, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first
        let afterGap = (rendered.attribute(.paragraphStyle, at: 17, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first

        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertTrue(first === third)
        XCTAssertFalse(first === afterGap)
        XCTAssertEqual(rendered.itemNumber(in: first, at: 0), 1)
        XCTAssertEqual(rendered.itemNumber(in: first, at: 4), 2)
        XCTAssertEqual(rendered.itemNumber(in: first, at: 8), 3)
        XCTAssertEqual(rendered.itemNumber(in: try XCTUnwrap(afterGap), at: 17), 1)
    }

    func testLinkEditingPreservesTextAndOtherMarks() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "网站", marks: [.bold])])])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setDocumentLink("https://example.com", range: NSRange(location: 0, length: 2))
        var updated = DocumentTextCodec.decode(editor.attributedString(), preserving: document)
        XCTAssertEqual(updated.plainText, "网站")
        XCTAssertTrue(updated.blocks[0].runs[0].marks.contains(.link("https://example.com")))
        XCTAssertTrue(updated.blocks[0].runs[0].marks.contains(.bold))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.removeDocumentLink(nil)
        updated = DocumentTextCodec.decode(editor.attributedString(), preserving: document)
        XCTAssertFalse(updated.blocks[0].runs[0].marks.contains(.link("https://example.com")))
        XCTAssertTrue(updated.blocks[0].runs[0].marks.contains(.bold))
    }

    func testAttachmentInsertionCanUndoAndDoesNotLeakToTyping() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.undoManager?.beginUndoGrouping()
        editor.insertAttachments([NativeAttachment(id: UUID(), name: "test.txt", storedName: "test.txt")])
        editor.undoManager?.endUndoGrouping()
        XCTAssertTrue(editor.string.contains("\u{FFFC}"))
        XCTAssertNil(editor.typingAttributes[.attachment])
        editor.undo(nil)
        XCTAssertEqual(editor.string, "")
        editor.redo(nil)
        XCTAssertTrue(editor.string.contains("\u{FFFC}"))
    }

    func testFormattingPreservesEmbeddedFileReference() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let file = NativeAttachment(id: UUID(), name: "test.txt", storedName: "test.txt")
        editor.insertAttachments([file])
        editor.setSelectedRange(NSRange(location: 0, length: 1))
        editor.applyFormat(DocumentFormatCommand(title: "高亮", block: nil, mark: .highlight))
        let result = DocumentTextCodec.decode(editor.attributedString(), preserving: .empty)
        XCTAssertEqual(result.blocks[0].runs[0].attachment, file)
        XCTAssertTrue(result.blocks[0].runs[0].marks.contains(.highlight))
    }
}
