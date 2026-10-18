import AppKit
import XCTest
@testable import WorkFollow

/// TI2-05a：检查项整项操作。
///
/// 滴答证据：`TTTaskDetailCheckItemCell` 的 `deleteButton`（行尾删除）与
/// `deleteChecklistItemCell:viaBackspace:viaClick:`。本地先做两项：
/// 空项行首退格删掉这一项；活动项行尾 × 删除整项（含换行）。
@MainActor
final class DocumentChecklistItemTests: XCTestCase {

    func testBackspaceOnEmptyChecklistItemDeletesTheItem() throws {
        let view = try makeView(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .checklist(false), runs: []),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ])
        let emptyLocation = ("第一项\n" as NSString).length
        view.setSelectedRange(NSRange(location: emptyLocation, length: 0))

        view.deleteBackward(nil)

        let document = decoded(view)
        XCTAssertEqual(document.blocks.map(\.kind), [.checklist(false), .paragraph])
        XCTAssertEqual(document.blocks.map { $0.runs.map(\.text).joined() }, ["第一项", "正文"])
    }

    func testBackspaceInsideANonEmptyChecklistItemDoesNotDeleteIt() throws {
        let view = try makeView(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "不该被删")])
        ])
        view.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertFalse(view.deleteEmptyChecklistItemOnBackspace())
        XCTAssertEqual(view.string, "不该被删")
    }

    func testDeleteChecklistItemRemovesLineAndKeepsSiblings() throws {
        let view = try makeView(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "第二项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ])
        let source = view.string as NSString
        let second = source.paragraphRange(for: NSRange(location: source.range(of: "第二项").location, length: 0))

        XCTAssertTrue(view.deleteChecklistItem(at: second))

        let document = decoded(view)
        XCTAssertEqual(document.blocks.map(\.kind), [.checklist(false), .paragraph])
        XCTAssertEqual(document.blocks.first?.runs.first?.text, "第一项")
        XCTAssertEqual(document.blocks.last?.runs.first?.text, "正文")
    }

    func testDeleteLastChecklistLineEatsThePrecedingNewline() throws {
        let view = try makeView(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "末项")])
        ])
        let source = view.string as NSString
        let last = source.paragraphRange(for: NSRange(location: source.range(of: "末项").location, length: 0))

        XCTAssertTrue(view.deleteChecklistItem(at: last))

        XCTAssertEqual(view.string, "正文")
        XCTAssertEqual(decoded(view).blocks.map(\.kind), [.paragraph])
    }

    func testDeleteHitRectSitsAtTheTrailingEdge() throws {
        let view = try makeView(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "检查项")])
        ])
        let rect = view.checklistDeleteHitRect(centerY: 20)
        XCTAssertGreaterThan(rect.minX, view.bounds.midX, "删除按钮在行尾，不在行首")
        XCTAssertLessThanOrEqual(rect.maxX, view.bounds.maxX)
        XCTAssertEqual(rect.width, 18, accuracy: 0.5)
    }

    // MARK: - Helpers

    private func makeView(blocks: [DocumentBlock]) throws -> NativeTextView {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { window.close() }
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: blocks)))
        view.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        window.makeFirstResponder(view)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return view
    }

    private func decoded(_ view: NativeTextView) -> NativeDocument {
        DocumentTextCodec.decode(view.attributedString(),
                                 preserving: NativeDocument(plainText: view.string),
                                 trailing: view.pendingTrailingBlock)
    }
}
