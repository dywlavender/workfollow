import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class NativeTextViewTests: XCTestCase {
    func testUndoManagersAreDocumentScoped() {
        let first = NativeTextView(frame: .zero, textContainer: nil)
        let second = NativeTextView(frame: .zero, textContainer: nil)
        XCTAssertNotNil(first.undoManager)
        XCTAssertFalse(first.undoManager === second.undoManager)
        let manager = first.undoManager!
        manager.beginUndoGrouping()
        first.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
        manager.endUndoGrouping()
        XCTAssertEqual(first.string, "正文")
        XCTAssertTrue(manager.canUndo)
        let undoItem = NSMenuItem(title: "Undo", action: #selector(NativeTextView.undo(_:)), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: #selector(NativeTextView.redo(_:)), keyEquivalent: "Z")
        XCTAssertTrue(first.validateUserInterfaceItem(undoItem))
        XCTAssertFalse(second.undoManager!.canUndo)
        first.undo(nil)
        XCTAssertEqual(first.string, "")
        XCTAssertTrue(first.validateUserInterfaceItem(redoItem))
        first.redo(nil)
        XCTAssertEqual(first.string, "正文")
    }

    func testFindBarEscapeDoesNotDismissInspector() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let editor = NativeTextView(frame: scroll.bounds, textContainer: nil)
        scroll.documentView = editor
        var inspectorEscapes = 0
        editor.onEscape = { inspectorEscapes += 1; return .keepInspector }
        XCTAssertTrue(editor.usesFindBar)
        scroll.isFindBarVisible = true
        editor.cancelOperation(nil)
        XCTAssertFalse(scroll.isFindBarVisible)
        XCTAssertEqual(inspectorEscapes, 0)
        editor.cancelOperation(nil)
        XCTAssertEqual(inspectorEscapes, 1)
    }

    func testCompositionIsNotPublishedUntilCommitted() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var changes: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(
            documentID: UUID(), document: .empty,
            onDocumentChange: { changes.append($0) },
            onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertTrue(changes.isEmpty)
        coordinator.flushPendingComposition(in: editor)
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(changes.last?.plainText, "中文")
    }
}
