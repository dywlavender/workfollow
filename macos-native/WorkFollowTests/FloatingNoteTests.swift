import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class FloatingNoteTests: XCTestCase {
    func testCreateCanReturnIDWithoutChangingSelection() throws {
        let model = NotesWorkspaceModel()
        let first = model.create()
        XCTAssertEqual(model.selectedID, first)

        let floating = model.create(folder: "工作", select: false)
        XCTAssertEqual(model.selectedID, first)
        XCTAssertNotEqual(first, floating)
        XCTAssertEqual(model.notes.first(where: { $0.id == floating })?.folder, "工作")
    }

    func testDiscardEmptyNoteOnlyRemovesUntouchedNote() throws {
        let model = NotesWorkspaceModel()

        let empty = model.create(select: false)
        XCTAssertTrue(model.discardEmptyNote(empty))
        XCTAssertFalse(model.notes.contains { $0.id == empty })

        let titled = model.create(select: false)
        model.edit(titled) { $0.title = "标题" }
        XCTAssertFalse(model.discardEmptyNote(titled))
        XCTAssertTrue(model.notes.contains { $0.id == titled })

        let body = model.create(select: false)
        model.edit(body) { $0.document = NativeDocument(plainText: "正文") }
        XCTAssertFalse(model.discardEmptyNote(body))

        let deleted = model.create(select: false)
        model.delete(deleted)
        XCTAssertFalse(model.discardEmptyNote(deleted))

        XCTAssertFalse(model.discardEmptyNote(UUID()))
    }

    func testEditorPopupLevelFollowsFloatingOwnerOnly() {
        let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.borderless], backing: .buffered, defer: false)

        EditorPopupWindowLevel.apply(to: panel, owner: owner)
        XCTAssertEqual(panel.level, .normal)

        owner.level = .floating
        EditorPopupWindowLevel.apply(to: panel, owner: owner)
        XCTAssertEqual(panel.level.rawValue, owner.level.rawValue + 1)
    }
}
