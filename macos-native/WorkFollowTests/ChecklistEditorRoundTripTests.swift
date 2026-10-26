import AppKit
import XCTest
@testable import WorkFollow

/// P1：编辑器按行重建文档时，检查项元数据跟随块身份保留；新行不继承。
@MainActor
final class ChecklistEditorRoundTripTests: XCTestCase {
    private let completed = Date(timeIntervalSince1970: 1_700_000_000)
    private let reminder = Date(timeIntervalSince1970: 1_700_003_600)

    private var meta: ChecklistItemMeta {
        ChecklistItemMeta(completedAt: completed, reminderAt: reminder)
    }

    func testReplacingPlainTextKeepsMetadataOnTheEditedLine() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")], checklist: meta),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第二项")])
        ])

        let typed = document.replacingPlainText("第一项改\n第二项")

        XCTAssertEqual(typed.blocks[0].id, document.blocks[0].id)
        XCTAssertEqual(typed.blocks[0].checklist, meta)
        XCTAssertEqual(typed.blocks[1].id, document.blocks[1].id)
        XCTAssertNil(typed.blocks[1].checklist)
    }

    func testAppendingANewLineDoesNotInheritMetadata() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")], checklist: meta)
        ])

        let typed = document.replacingPlainText("第一项\n新项")

        XCTAssertEqual(typed.blocks[0].checklist, meta)
        XCTAssertNil(typed.blocks[1].checklist)
        XCTAssertNotEqual(typed.blocks[1].id, document.blocks[0].id)
    }

    func testSplittingALineKeepsMetadataOnTheFirstHalfOnly() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")], checklist: meta)
        ])

        let typed = document.replacingPlainText("第一\n项")

        XCTAssertEqual(typed.blocks[0].id, document.blocks[0].id)
        XCTAssertEqual(typed.blocks[0].checklist, meta)
        XCTAssertNil(typed.blocks[1].checklist)
        XCTAssertNotEqual(typed.blocks[1].id, document.blocks[0].id)
    }

    func testDocumentTextCodecDecodeKeepsMetadataThroughAnAttributedEdit() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")], checklist: meta),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第二项")])
        ])
        let rendered = NSMutableAttributedString(attributedString: DocumentTextCodec.render(document))
        let range = (rendered.string as NSString).range(of: "第一项")
        rendered.replaceCharacters(in: range, with: "第一项改")

        let decoded = DocumentTextCodec.decode(rendered, preserving: document)

        XCTAssertEqual(decoded.blocks[0].checklist, meta)
        XCTAssertEqual(decoded.blocks[0].runs.map(\.text).joined(), "第一项改")
        XCTAssertNil(decoded.blocks[1].checklist)
    }
}
