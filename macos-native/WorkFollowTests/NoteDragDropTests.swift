import XCTest
@testable import WorkFollow

@MainActor
final class NoteDragDropTests: XCTestCase {
    func testFolderRowEdgePromotesSubtreeToSiblingAndMiddleNestsItAgain() throws {
        let notes = NotesWorkspaceModel()
        let parent = try XCTUnwrap(notes.addFolder("工作", parentID: nil))
        let peer = try XCTUnwrap(notes.addFolder("归档", parentID: nil))
        let child = try XCTUnwrap(notes.addFolder("周报", parentID: parent))
        let grandchild = try XCTUnwrap(notes.addFolder("历史", parentID: child))
        let note = notes.create(folder: "周报", title: "本周记录")

        let edge = try XCTUnwrap(NoteDirectoryDropDelegate.folderPlacement(rowID: peer, y: 2))
        XCTAssertTrue(notes.moveFolder(id: child, to: edge))
        XCTAssertEqual(notes.folderNodes.filter { $0.depth == 0 }.map(\.id), [parent, child, peer])
        XCTAssertEqual(notes.folderNodes.first { $0.id == grandchild }?.parentID, child)
        XCTAssertEqual(notes.notes.first { $0.id == note }?.folderID, child)

        let middle = try XCTUnwrap(NoteDirectoryDropDelegate.folderPlacement(rowID: parent, y: 15))
        XCTAssertTrue(notes.moveFolder(id: child, to: middle))
        XCTAssertEqual(notes.folderPath(named: "历史"), ["工作", "周报", "历史"])
    }

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
