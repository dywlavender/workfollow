import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class TaskRelationUndoBoundaryTests: XCTestCase {
    @MainActor private final class Fixture {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let handle = DocumentEditorHandle()
        let editor = NativeTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 100), textContainer: nil)
        let source: UUID
        let coordinator: DocumentEditorCoordinator

        init(document: NativeDocument = .empty, sourceNoteID: UUID? = nil) throws {
            source = try XCTUnwrap(workspace.createTask(title: "来源", in: .inbox).taskID)
            _ = workspace.setDocument(source, document)
            if let sourceNoteID { workspace.setSourceNote(source, sourceNoteID) }
            workspace.select(source)
            editor.documentIdentity = source
            editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            editor.setSelectedRange(NSRange(location: editor.attributedString().length, length: 0))
            coordinator = DocumentEditorCoordinator(documentID: source, document: document,
                onDocumentChange: { [workspace, source] in _ = workspace.setDocument(source, $0) },
                onEscape: { .keepInspector }, onEditingChanged: { _ in })
            editor.delegate = coordinator
            handle.textView = editor
        }

        func apply(_ note: Note) -> Bool {
            TaskRelationSelection.apply(.note(note), sourceTaskID: source,
                workspace: workspace, notes: [note], handle: handle)
        }
        var task: Task { workspace.task(for: source)! }
    }

    private func note(_ title: String) -> Note {
        Note(id: UUID(), title: title, document: .empty, folder: "资料", updatedAt: Date())
    }
    private func settleTyping() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    }

    func testReferenceUndoRedoRestoresSelectedTextAndPreviousSourceInOneCommit() throws {
        let original = NativeDocument(plainText: "前文 被替换 后文")
        let previous = UUID()
        let fixture = try Fixture(document: original, sourceNoteID: previous)
        let selection = (fixture.editor.string as NSString).range(of: "被替换")
        fixture.editor.setSelectedRange(selection)
        let target = note("新笔记")
        let revision = fixture.workspace.revision
        XCTAssertTrue(fixture.apply(target))
        XCTAssertEqual(fixture.workspace.revision, revision + 1)
        XCTAssertEqual(fixture.task.sourceNoteID, target.id)
        let inserted = fixture.task.document
        XCTAssertNotEqual(inserted, original)
        fixture.editor.undo(nil)
        XCTAssertEqual(fixture.workspace.revision, revision + 2)
        XCTAssertEqual(fixture.task.document, original)
        XCTAssertEqual(fixture.task.sourceNoteID, previous)
        XCTAssertEqual(fixture.editor.selectedRange(), selection)
        fixture.editor.redo(nil)
        XCTAssertEqual(fixture.workspace.revision, revision + 3)
        XCTAssertEqual(fixture.task.document, inserted)
        XCTAssertEqual(fixture.task.sourceNoteID, target.id)
    }

    func testLaterTypingUndoThenReferenceUndoAndRedoDoNotMerge() throws {
        let fixture = try Fixture()
        let target = note("笔记")
        fixture.editor.insertText("前文 ", replacementRange: fixture.editor.selectedRange())
        settleTyping()
        let before = fixture.task.document
        XCTAssertTrue(fixture.apply(target))
        let linked = fixture.task.document
        settleTyping()
        fixture.editor.insertText(" 后续输入", replacementRange: fixture.editor.selectedRange())
        settleTyping()
        let afterTyping = fixture.task.document
        fixture.editor.undo(nil)
        XCTAssertEqual(fixture.task.document, linked)
        XCTAssertEqual(fixture.task.sourceNoteID, target.id)
        fixture.editor.undo(nil)
        XCTAssertEqual(fixture.task.document, before)
        XCTAssertNil(fixture.task.sourceNoteID)
        fixture.editor.undo(nil)
        XCTAssertTrue(fixture.task.document.isEmpty)
        XCTAssertNil(fixture.task.sourceNoteID)
        fixture.editor.redo(nil)
        XCTAssertEqual(fixture.task.document, before)
        fixture.editor.redo(nil)
        XCTAssertEqual(fixture.task.document, linked)
        XCTAssertEqual(fixture.task.sourceNoteID, target.id)
        fixture.editor.redo(nil)
        XCTAssertEqual(fixture.task.document, afterTyping)
        XCTAssertEqual(fixture.task.sourceNoteID, target.id)
    }

    func testConsecutiveReferencesAndBusinessUndoKeepSourceInSync() throws {
        let fixture = try Fixture(document: NativeDocument(plainText: "正文 "))
        let original = fixture.task.document
        let a = note("A"), b = note("B")
        _ = fixture.workspace.setPriority(fixture.source, .high)
        XCTAssertTrue(fixture.apply(a))
        XCTAssertEqual(fixture.editor.undoManager?.groupingLevel, 0, "Reference A must close its command group")
        let afterA = fixture.task.document
        XCTAssertTrue(fixture.apply(b))
        XCTAssertEqual(fixture.editor.undoManager?.groupingLevel, 0, "Reference B must close its command group")
        let afterB = fixture.task.document
        fixture.editor.undo(nil)
        XCTAssertEqual(fixture.task.document, afterA)
        XCTAssertEqual(fixture.task.sourceNoteID, a.id)
        fixture.workspace.undo()
        XCTAssertEqual(fixture.task.priority, .none)
        XCTAssertEqual(fixture.task.document, afterA)
        XCTAssertEqual(fixture.task.sourceNoteID, a.id)
        fixture.editor.undo(nil)
        XCTAssertEqual(fixture.task.document, original)
        XCTAssertNil(fixture.task.sourceNoteID)
        fixture.editor.redo(nil)
        XCTAssertEqual(fixture.task.document, afterA)
        XCTAssertEqual(fixture.task.sourceNoteID, a.id)
        fixture.editor.redo(nil)
        XCTAssertEqual(fixture.task.document, afterB)
        XCTAssertEqual(fixture.task.sourceNoteID, b.id)
    }

    func testTaskReferencePreservesSourceAndRejectedInsertionCannotChangeIt() throws {
        let previous = UUID()
        let fixture = try Fixture(sourceNoteID: previous)
        let targetID = try XCTUnwrap(fixture.workspace.createTask(title: "目标", in: .inbox).taskID)
        let target = try XCTUnwrap(fixture.workspace.task(for: targetID))
        XCTAssertTrue(TaskRelationSelection.apply(.task(target), sourceTaskID: fixture.source,
            workspace: fixture.workspace, notes: [], handle: fixture.handle))
        XCTAssertEqual(fixture.task.sourceNoteID, previous)
        XCTAssertNil(fixture.task.parentID)
        fixture.editor.undo(nil)
        XCTAssertTrue(fixture.task.document.isEmpty)
        XCTAssertEqual(fixture.task.sourceNoteID, previous)
        fixture.editor.redo(nil)
        let before = fixture.task
        fixture.editor.isEditable = false
        XCTAssertFalse(fixture.apply(note("拒绝")))
        XCTAssertEqual(fixture.task, before)
    }

    func testDeletionAfterReferenceHasItsOwnUndoAndKeepsSourceUntilReferenceUndo() throws {
        let fixture = try Fixture()
        let target = note("笔记")
        XCTAssertTrue(fixture.apply(target))
        let linked = fixture.task.document
        fixture.editor.deleteBackward(nil)
        settleTyping()
        XCTAssertNotEqual(fixture.task.document, linked)
        XCTAssertEqual(fixture.task.sourceNoteID, target.id)
        fixture.editor.undo(nil)
        XCTAssertEqual(fixture.task.document, linked)
        XCTAssertEqual(fixture.task.sourceNoteID, target.id)
        fixture.editor.undo(nil)
        XCTAssertTrue(fixture.task.document.isEmpty)
        XCTAssertNil(fixture.task.sourceNoteID)
    }
}
