import AppKit
import XCTest
@testable import WorkFollow

/// Characterizes the outstanding gap, not the desired product contract.
/// Replace these assertions with atomic undo/redo assertions when migrating.
@MainActor
final class TaskRelationUndoBoundaryTests: XCTestCase {
    func testCurrentBusinessUndoRestoresSourceButKeepsInsertedReference() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "来源", in: .inbox).taskID)
        let previousNote = UUID()
        workspace.setSourceNote(source, previousNote)
        workspace.select(source)
        let note = Note(id: UUID(), title: "新笔记", document: .empty, folder: "资料", updatedAt: Date())
        let handle = DocumentEditorHandle()
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.documentIdentity = source
        let coordinator = DocumentEditorCoordinator(documentID: source, document: .empty,
            onDocumentChange: { _ = workspace.setDocument(source, $0) },
            onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        handle.textView = editor

        XCTAssertTrue(TaskRelationSelection.apply(.note(note), sourceTaskID: source,
            workspace: workspace, notes: [note], handle: handle))
        let inserted = try XCTUnwrap(workspace.task(for: source)?.document)
        XCTAssertFalse(inserted.isEmpty)
        XCTAssertEqual(workspace.task(for: source)?.sourceNoteID, note.id)

        workspace.undo()
        XCTAssertEqual(workspace.task(for: source)?.sourceNoteID, previousNote)
        XCTAssertEqual(workspace.task(for: source)?.document, inserted,
            "Known gap: business undo does not remove the document reference")
    }

    func testSnapshotAtomicCommitAloneDoesNotSurviveLaterDocumentRebase() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let id = try XCTUnwrap(actions.create(title: "来源", list: TaskList(name: "收集箱")).taskID)
        store.clearUndo()
        var linked = try XCTUnwrap(store.task(id))
        linked.sourceNoteID = UUID()
        linked.document = NativeDocument(plainText: "笔记引用")
        store.commit([linked])
        var typed = linked
        typed.document = NativeDocument(plainText: "笔记引用 后续输入")
        store.commit([typed], undoPolicy: .skip)

        store.undo()
        XCTAssertNil(store.task(id)?.sourceNoteID)
        XCTAssertEqual(store.task(id)?.document, typed.document,
            "Known gap: text rebase replaces the pre-relation document snapshot")
    }
}
