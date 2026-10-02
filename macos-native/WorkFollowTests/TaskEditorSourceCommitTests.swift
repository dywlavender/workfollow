import XCTest
@testable import WorkFollow

final class TaskEditorSourceCommitTests: XCTestCase {
    func testEditorReferenceCommitRebasesDocumentAndSourceThroughBusinessUndo() throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        var now = createdAt
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { now })
        let taskID = try XCTUnwrap(actions.create(title: "目标", list: .inbox).taskID)
        let otherID = try XCTUnwrap(actions.create(title: "另一任务", list: .inbox).taskID)
        let previousSource = UUID()
        _ = actions.setSourceNote(taskID, previousSource)
        store.clearUndo()

        let otherBefore = try XCTUnwrap(store.task(otherID))
        now = Date(timeIntervalSince1970: 1_800_000_100)
        XCTAssertEqual(actions.setPriority(taskID, .high), .success(taskID))
        let beforeEditorCommit = try XCTUnwrap(store.task(taskID))
        XCTAssertTrue(store.canUndo)

        let nextSource = UUID()
        let document = NativeDocument(plainText: "编辑器提交的正文")
        now = Date(timeIntervalSince1970: 1_800_000_200)
        XCTAssertEqual(actions.commitEditorReference(taskID, document: document, sourceNoteID: nextSource),
                       .success(taskID))

        var expectedCommitted = beforeEditorCommit
        expectedCommitted.document = document
        expectedCommitted.sourceNoteID = nextSource
        expectedCommitted.updatedAt = now
        XCTAssertEqual(store.task(taskID), expectedCommitted)
        XCTAssertEqual(store.task(otherID), otherBefore)
        XCTAssertTrue(store.canUndo, "The editor commit must not add a business undo entry")

        actions.undo()
        var expectedUndone = expectedCommitted
        expectedUndone.priority = .none
        XCTAssertEqual(store.task(taskID), expectedUndone)
        XCTAssertEqual(store.task(otherID), otherBefore)
        XCTAssertFalse(store.canUndo)
    }

    func testEditorReferenceCommitCanClearSourceAndRebaseNilThroughBusinessUndo() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let taskID = try XCTUnwrap(actions.create(title: "目标", list: .inbox).taskID)
        let previousSource = UUID()
        _ = actions.setSourceNote(taskID, previousSource)
        store.clearUndo()

        XCTAssertEqual(actions.setPriority(taskID, .high), .success(taskID))
        let document = NativeDocument(plainText: "脱离来源后的正文")
        XCTAssertEqual(actions.commitEditorReference(taskID, document: document, sourceNoteID: nil),
                       .success(taskID))
        XCTAssertTrue(store.canUndo)

        actions.undo()
        let restored = try XCTUnwrap(store.task(taskID))
        XCTAssertEqual(restored.priority, .none)
        XCTAssertEqual(restored.document, document)
        XCTAssertNil(restored.sourceNoteID)
        XCTAssertFalse(store.canUndo)
    }

    func testOrdinarySetSourceNoteStillUsesBusinessUndo() throws {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store)
        let taskID = try XCTUnwrap(actions.create(title: "目标", list: .inbox).taskID)
        store.clearUndo()
        let sourceID = UUID()

        XCTAssertEqual(actions.setSourceNote(taskID, sourceID), .success(taskID))
        XCTAssertTrue(store.canUndo)
        actions.undo()

        XCTAssertNil(store.task(taskID)?.sourceNoteID)
        XCTAssertFalse(store.canUndo)
    }
}
