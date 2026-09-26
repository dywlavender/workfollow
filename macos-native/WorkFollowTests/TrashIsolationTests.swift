import XCTest
@testable import WorkFollow

final class TrashIsolationTests: XCTestCase {
    func testTaskAndNoteTrashesAreIndependentAndTaskTrashIsNewestFirst() async {
        await MainActor.run {
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let taskWorkspace = TaskWorkspaceModel(clock: { now }, seedDemoData: false)
            let notesWorkspace = NotesWorkspaceModel(clock: { now })

            let keptTask = taskWorkspace.createTask(title: "keep task", in: .inbox).taskID!
            let older = taskWorkspace.createTask(title: "older removal", in: .inbox).taskID!
            _ = taskWorkspace.delete(older)
            now = now.addingTimeInterval(60)
            let newer = taskWorkspace.createTask(title: "newer removal", in: .inbox).taskID!
            _ = taskWorkspace.delete(newer)

            notesWorkspace.create()
            let noteID = notesWorkspace.selectedID!
            notesWorkspace.delete(noteID)

            XCTAssertEqual(taskWorkspace.deletedTasks.map(\.id), [newer, older])
            XCTAssertEqual(notesWorkspace.rows(trash: true, query: "", folder: nil, favorites: false).map(\.id), [noteID])

            taskWorkspace.restoreDeleted(newer)
            XCTAssertEqual(taskWorkspace.deletedTasks.map(\.id), [older])
            taskWorkspace.permanentlyDelete(older)
            XCTAssertTrue(taskWorkspace.deletedTasks.isEmpty)
            XCTAssertNotNil(taskWorkspace.task(for: keptTask))
            XCTAssertEqual(notesWorkspace.rows(trash: true, query: "", folder: nil, favorites: false).map(\.id), [noteID])

            notesWorkspace.emptyTrash()
            XCTAssertTrue(notesWorkspace.rows(trash: true, query: "", folder: nil, favorites: false).isEmpty)
            XCTAssertNotNil(taskWorkspace.task(for: keptTask))
            XCTAssertNotNil(taskWorkspace.task(for: newer))
        }
    }
}
