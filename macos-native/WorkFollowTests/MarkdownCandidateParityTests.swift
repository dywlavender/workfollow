import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class MarkdownCandidateParityTests: XCTestCase {
    /// User-verified reference sequence: # opens suggestions; a following
    /// space consumes the trigger and behaves exactly like selecting H1.
    func testHashCandidateBecomesHeadingWhenSpaceIsTyped() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.profile.tagCandidates = { ["工作", "学习"] }
        let window = InspectorPanelTestSupport.ownerWindow(for: view, width: 600, height: 200)
        defer { view.dismissTagCompletion(); window.close() }
        window.makeFirstResponder(view)
        view.insertText("#", replacementRange: view.selectedRange())
        XCTAssertEqual(view.tagSession?.candidates, ["工作", "学习"])
        view.insertText(" ", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "")
        XCTAssertNil(view.tagSession)
        XCTAssertEqual(view.typingAttributes[DocumentTextCodec.blockKey] as? String, "h1")
        let typedFont = try XCTUnwrap(view.typingAttributes[.font] as? NSFont)

        let menuView = NativeTextView(frame: view.frame, textContainer: nil)
        menuView.applyFormat(try XCTUnwrap(EditorCommandCatalog.format("format.heading1")))
        let menuFont = try XCTUnwrap(menuView.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(typedFont.fontDescriptor, menuFont.fontDescriptor)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))

        view.insertText("一级标题", replacementRange: view.selectedRange())
        let document = DocumentTextCodec.decode(view.attributedString(), preserving: .empty)
        XCTAssertEqual(document.plainText, "一级标题")
        XCTAssertEqual(document.blocks.first?.kind, .heading(1))
        XCTAssertEqual(view.selectedRange().location, ("一级标题" as NSString).length)
    }

    func testHeadingCandidateConversionUndoReturnsToBeforeTheTriggeringSpace() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.allowsUndo = true
        view.profile.tagCandidates = { ["工作"] }
        let window = InspectorPanelTestSupport.ownerWindow(for: view, width: 600, height: 200)
        defer { view.dismissTagCompletion(); window.close() }
        window.makeFirstResponder(view)
        view.insertText("#", replacementRange: view.selectedRange())
        view.breakUndoCoalescing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        view.insertText(" ", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "")
        view.undo(nil)
        XCTAssertEqual(view.string, "#")
        XCTAssertNotEqual(view.typingAttributes[DocumentTextCodec.blockKey] as? String, "h1")
    }

    func testCandidateViewportKeepsItemsAfterTheSixthAvailable() throws {
        let candidates = (1...10).map { "标签\($0)" }
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.profile.tagCandidates = { candidates }
        var inserted: String?
        view.profile.onTagInserted = { inserted = $0 }
        let window = InspectorPanelTestSupport.ownerWindow(for: view, width: 600, height: 200)
        defer { view.dismissTagCompletion(); window.close() }
        window.makeFirstResponder(view)
        view.insertText("#", replacementRange: view.selectedRange())
        XCTAssertEqual(view.tagSession?.candidates, candidates)
        let panel = try XCTUnwrap(view.tagPanel)
        XCTAssertLessThanOrEqual(panel.frame.height, 6 * 28 + 8)
        XCTAssertGreaterThan(panel.frame.height, 0)
        XCTAssertTrue(EditorPopupGeometry.bounds(in: window).contains(panel.frame))
        view.moveTagCompletion(8)
        XCTAssertEqual(view.tagSession?.selectedIndex, 8)
        view.commitTagCompletion()
        XCTAssertEqual(inserted, "标签9")
        XCTAssertEqual(view.string, "#标签9 ")
    }
}
