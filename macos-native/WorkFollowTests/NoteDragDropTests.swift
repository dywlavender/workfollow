import XCTest
@testable import WorkFollow

@MainActor
final class NoteDragDropTests: XCTestCase {
    private func makeModel() -> (NotesWorkspaceModel, Note) {
        let note = Note(id: UUID(), title: "会议记录", document: .empty, folder: "未归档",
                        updatedAt: Date(timeIntervalSince1970: 10))
        return (NotesWorkspaceModel(initialNotes: [note], folders: ["会议"]), note)
    }

    func testPayloadRoundTripsAndRejectsOtherDomains() throws {
        let id = UUID()
        XCTAssertEqual(NoteDragPayload.decode(NoteDragPayload.encode(id)), id)
        XCTAssertNil(NoteDragPayload.decode(id.uuidString), "任务拖拽负载不能当笔记收")
        XCTAssertNil(NoteDragPayload.decode(SidebarDragPayload.encode(.list("工作"))))
        XCTAssertNil(NoteDragPayload.decode(nil))
        XCTAssertNil(NoteDragPayload.decode(NoteDragPayload.prefix))
    }

    func testOnlyFolderRowsAreDropTargets() {
        XCTAssertEqual(NoteFolderDrop.target(folder: "会议", trash: false), "会议")
        XCTAssertEqual(NoteFolderDrop.target(folder: "未归档", trash: false), "未归档")
        XCTAssertNil(NoteFolderDrop.target(folder: nil, trash: false), "全部笔记/收藏不是归属")
        XCTAssertNil(NoteFolderDrop.target(folder: "会议", trash: true), "垃圾桶不是归属")
    }

    func testDropMovesNoteIntoFolderAndKeepsStableFolderID() throws {
        let (model, note) = makeModel()
        let folderID = try XCTUnwrap(model.folderID(named: "会议"))
        XCTAssertTrue(NoteFolderDrop.move(payload: NoteDragPayload.encode(note.id), to: "会议", notes: model))
        XCTAssertEqual(model.notes.first?.folder, "会议")
        XCTAssertEqual(model.notes.first?.folderID, folderID)

        XCTAssertTrue(NoteFolderDrop.move(payload: NoteDragPayload.encode(note.id), to: "未归档", notes: model))
        XCTAssertEqual(model.notes.first?.folder, "未归档")
        XCTAssertNil(model.notes.first?.folderID)
    }

    func testDropRejectsTaskPayloadAndTrashedNote() {
        let (model, note) = makeModel()
        XCTAssertFalse(NoteFolderDrop.move(payload: note.id.uuidString, to: "会议", notes: model))
        XCTAssertEqual(model.notes.first?.folder, "未归档")

        model.delete(note.id)
        XCTAssertFalse(NoteFolderDrop.move(payload: NoteDragPayload.encode(note.id), to: "会议", notes: model),
                       "垃圾桶里的笔记不能被拖走")
        XCTAssertEqual(model.notes.first?.folder, "未归档")

        model.restore(note.id)
        XCTAssertFalse(NoteFolderDrop.move(payload: NoteDragPayload.encode(UUID()), to: "会议", notes: model))
    }
}
