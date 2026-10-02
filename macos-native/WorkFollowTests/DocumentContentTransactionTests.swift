import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentContentTransactionTests: XCTestCase {
    func testOrdinaryTypingUndoRedoPublishesReplayedDocument() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var documents: [NativeDocument] = []
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { documents.append($0) },
            onEscape: { .keepInspector }, onEditingChanged: { _ in })
        defer { withExtendedLifetime(coordinator) {} }
        editor.delegate = coordinator
        editor.insertText("普通输入", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(documents.last?.plainText, "普通输入")
        editor.undo(nil)
        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(documents.last?.plainText, "")
        editor.redo(nil)
        XCTAssertEqual(editor.string, "普通输入")
        XCTAssertEqual(documents.last?.plainText, "普通输入")
    }

    func testReplacementRestoresTextAndSelectionAcrossUndoRedo() throws {
        let original = NativeDocument(plainText: "before old after")
        let (editor, coordinator) = makeEditor(document: original)
        defer { withExtendedLifetime(coordinator) {} }
        let manager = try XCTUnwrap(editor.undoManager)
        let replacedRange = NSRange(location: 7, length: 3)
        let insertedSelection = NSRange(location: 10, length: 0)
        editor.setSelectedRange(replacedRange)

        XCTAssertTrue(editor.replaceDocumentContent(NSAttributedString(string: "new"),
            range: replacedRange, selection: insertedSelection,
            commit: { _ in }, inverseCommit: { _ in }))
        XCTAssertEqual(editor.string, "before new after")
        XCTAssertEqual(editor.selectedRange(), insertedSelection)
        XCTAssertTrue(manager.canUndo)

        editor.undo(nil)
        XCTAssertEqual(editor.string, "before old after")
        XCTAssertEqual(editor.selectedRange(), replacedRange)
        XCTAssertTrue(manager.canRedo)

        editor.redo(nil)
        XCTAssertEqual(editor.string, "before new after")
        XCTAssertEqual(editor.selectedRange(), insertedSelection)
    }

    func testReferenceCallbacksReceiveCompleteDecodedDocumentOnForwardUndoAndRedo() throws {
        let original = NativeDocument(plainText: "left old right")
        let (editor, coordinator) = makeEditor(document: original)
        defer { withExtendedLifetime(coordinator) {} }
        let manager = try XCTUnwrap(editor.undoManager)
        let replacedRange = NSRange(location: 5, length: 3)
        editor.setSelectedRange(replacedRange)

        let handle = DocumentEditorHandle()
        handle.textView = editor
        var forwardDocuments: [NativeDocument] = []
        var inverseDocuments: [NativeDocument] = []
        let target = "https://example.com/guide"

        XCTAssertTrue(handle.insertReference(EditorReference(title: "Guide", target: target),
            commit: { forwardDocuments.append($0) },
            undoCommit: { inverseDocuments.append($0) }))
        XCTAssertEqual(editor.string, "left Guide right")
        XCTAssertEqual(forwardDocuments.map(\.plainText), ["left Guide right"])
        let insertedDocument = try XCTUnwrap(forwardDocuments.first)
        XCTAssertTrue(insertedDocument.blocks.flatMap(\.runs).contains {
            $0.text.contains("Guide") && $0.marks.contains(.link(target))
        })
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 10, length: 0))

        editor.undo(nil)
        XCTAssertEqual(editor.string, "left old right")
        XCTAssertEqual(editor.selectedRange(), replacedRange)
        XCTAssertEqual(inverseDocuments.map(\.plainText), ["left old right"])

        editor.redo(nil)
        XCTAssertEqual(editor.string, "left Guide right")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertEqual(forwardDocuments.map(\.plainText), ["left Guide right", "left Guide right"])
        XCTAssertTrue(manager.canUndo)
    }

    func testRejectedReferenceDoesNotCommitOrRegisterUndo() throws {
        let original = NativeDocument(plainText: "left old right")
        let (editor, coordinator) = makeEditor(document: original)
        defer { withExtendedLifetime(coordinator) {} }
        let manager = try XCTUnwrap(editor.undoManager)
        let selection = NSRange(location: 5, length: 3)
        editor.setSelectedRange(selection)
        editor.isEditable = false

        let handle = DocumentEditorHandle()
        handle.textView = editor
        var forwardDocuments: [NativeDocument] = []
        var inverseDocuments: [NativeDocument] = []

        XCTAssertFalse(handle.insertReference(EditorReference(title: "Guide", target: "https://example.com/guide"),
            commit: { forwardDocuments.append($0) },
            undoCommit: { inverseDocuments.append($0) }))
        XCTAssertEqual(editor.string, original.plainText)
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertTrue(forwardDocuments.isEmpty)
        XCTAssertTrue(inverseDocuments.isEmpty)
        XCTAssertFalse(manager.canUndo)
    }

    func testDocumentResetDiscardsPreviousDocumentUndo() throws {
        let original = NativeDocument(plainText: "before old after")
        let (editor, coordinator) = makeEditor(document: original)
        let manager = try XCTUnwrap(editor.undoManager)
        let replacedRange = NSRange(location: 7, length: 3)
        editor.setSelectedRange(replacedRange)
        var inverseDocuments: [NativeDocument] = []

        XCTAssertTrue(editor.replaceDocumentContent(NSAttributedString(string: "new"),
            range: replacedRange, selection: NSRange(location: 10, length: 0),
            commit: { _ in }, inverseCommit: { inverseDocuments.append($0) }))
        XCTAssertEqual(editor.string, "before new after")
        XCTAssertTrue(manager.canUndo)

        let newDocumentID = UUID()
        let newDocument = NativeDocument(plainText: "new document")
        coordinator.update(editor, documentID: newDocumentID, document: newDocument,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })

        XCTAssertEqual(editor.documentIdentity, newDocumentID)
        XCTAssertEqual(editor.string, newDocument.plainText)
        XCTAssertFalse(manager.canUndo)
        editor.undo(nil)
        XCTAssertEqual(editor.string, newDocument.plainText)
        XCTAssertTrue(inverseDocuments.isEmpty)
    }

    private func makeEditor(document: NativeDocument) -> (NativeTextView, DocumentEditorCoordinator) {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: document,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        return (editor, coordinator)
    }
}
