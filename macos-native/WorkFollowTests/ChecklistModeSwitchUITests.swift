import XCTest
@testable import WorkFollow

/// P2：切到清单前的影响面与确认口径。
@MainActor
final class ChecklistModeSwitchUITests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPlainParagraphsSwitchWithoutConfirmation() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "列表")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "编号")])
        ])
        let impact = TaskActions.checklistConversionImpact(in: document)
        XCTAssertEqual(impact.affectedBlocks, 0)
        XCTAssertFalse(impact.requiresConfirmation)
    }

    func testStructuredBlocksRequireConfirmation() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引用")]),
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "code")]),
            DocumentBlock(kind: .divider, runs: [])
        ])
        let impact = TaskActions.checklistConversionImpact(in: document)
        XCTAssertEqual(impact.affectedBlocks, 4)
        XCTAssertEqual(impact.richTextBlocks, 0)
        XCTAssertTrue(impact.requiresConfirmation)
    }

    func testRichRunsAreCountedButPreserved() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "重点", marks: [.bold])]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "普通")])
        ])
        let impact = TaskActions.checklistConversionImpact(in: document)
        XCTAssertEqual(impact.richTextBlocks, 1)
        XCTAssertFalse(impact.requiresConfirmation)

        let converted = TaskActions.document(document, convertingTo: .checklist)
        XCTAssertEqual(converted.blocks[0].kind, .checklist(false))
        XCTAssertEqual(converted.blocks[0].runs[0].marks, [.bold])
    }

    func testConversionKeepsStructuresAndUndoesAsOneStep() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.now })
        let id = try XCTUnwrap(actions.create(title: "切模式").taskID)
        actions.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ]))
        store.clearUndo()

        actions.setKind(id, .checklist)
        XCTAssertEqual(store.task(id)?.document.blocks.map(\.kind),
                       [.heading(2), .checklist(false)])

        actions.undo()
        XCTAssertEqual(store.task(id)?.kind, .text)
        XCTAssertEqual(store.task(id)?.document.blocks.map(\.kind), [.heading(2), .paragraph])
    }
}
