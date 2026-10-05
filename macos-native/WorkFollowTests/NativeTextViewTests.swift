import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class NativeTextViewTests: XCTestCase {
    func testCleanDocumentSwitchSkipsDecodeButExternalStorageChangesStillFlush() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let original = NativeDocument(plainText: "原正文")
        var outgoing: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: original,
            onDocumentChange: { outgoing.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
        coordinator.didLoadDocument(in: editor)
        coordinator.flushPendingComposition(in: editor)
        XCTAssertEqual(coordinator.decodeCount, 0)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "未提交正文")))
        coordinator.update(editor, documentID: UUID(), document: NativeDocument(plainText: "新正文"),
            onDocumentChange: { _ in XCTFail("Outgoing text must not commit to the new task") },
            onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertEqual(outgoing.last?.plainText, "未提交正文")
        XCTAssertEqual(coordinator.decodeCount, 1)
        coordinator.flushPendingComposition(in: editor)
        XCTAssertEqual(coordinator.decodeCount, 1)
    }

    func testCleanFlushStillCommitsPendingEmptyHeading() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var changes: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { changes.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        coordinator.didLoadDocument(in: editor)
        editor.seedTrailingParagraphKind(.heading(1))
        coordinator.flushPendingComposition(in: editor)
        XCTAssertEqual(changes.last?.blocks.last?.kind, .heading(1))
        XCTAssertEqual(coordinator.decodeCount, 1)
    }

    func testRebindFlushesCompositionToOldDocumentOnly() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var oldChanges: [NativeDocument] = []
        var newChanges: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { oldChanges.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let newID = UUID()
        coordinator.update(editor, documentID: newID, document: NativeDocument(plainText: "新文档"),
            onDocumentChange: { newChanges.append($0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertEqual(oldChanges.last?.plainText, "中文")
        XCTAssertTrue(newChanges.isEmpty)
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "新文档")
        XCTAssertEqual(editor.documentIdentity, newID)
        XCTAssertFalse(editor.undoManager!.canUndo)
    }

    func testRebindRemovesActualSlashWindowAndObservers() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let editor = NativeTextView(frame: scroll.bounds, textContainer: nil)
        scroll.documentView = editor
        window.contentView = scroll
        window.orderFront(nil)
        defer { window.close() }
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        let panel = editor.slashPanel
        XCTAssertNotNil(panel)
        XCTAssertFalse(editor.slashObservers.isEmpty)
        XCTAssertTrue(panel?.parent === window)
        coordinator.update(editor, documentID: UUID(), document: NativeDocument(plainText: "second"),
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertNil(editor.slashPanel)
        XCTAssertNil(editor.slashSession)
        XCTAssertTrue(editor.slashObservers.isEmpty)
        XCTAssertNil(panel?.parent)
        XCTAssertFalse(panel?.isVisible ?? true)
        XCTAssertFalse(editor.undoManager!.canUndo)
    }

    func testDetachClosesSelectionToolbarAndDisconnectsCallbacks() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = NativeTextView(frame: window.contentLayoutRect, textContainer: nil)
        window.contentView = editor
        window.orderFront(nil)
        defer { window.close() }
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.profile = NoteDocumentProfile.make(host: NoteEditorHostActions(createTaskFromSelection: { _ in }))
        editor.onEscape = { .keepInspector }
        editor.onEditingChanged = { _ in }
        editor.onSelectionChanged = {}
        editor.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        editor.refreshSelectionToolbar()
        let panel = editor.selectionPanel
        XCTAssertNotNil(panel)
        XCTAssertTrue(panel?.parent === window)
        coordinator.detach(editor)
        XCTAssertNil(editor.selectionPanel)
        XCTAssertNil(panel?.parent)
        XCTAssertFalse(panel?.isVisible ?? true)
        XCTAssertNil(editor.delegate)
        XCTAssertNil(editor.onEscape)
        XCTAssertNil(editor.onEditingChanged)
        XCTAssertNil(editor.onSelectionChanged)
        XCTAssertTrue(editor.profile.selectionActions.isEmpty)
        XCTAssertFalse(editor.undoManager!.canUndo)
    }

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
