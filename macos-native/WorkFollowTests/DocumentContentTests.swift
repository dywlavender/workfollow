import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentContentTests: XCTestCase {
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
