import XCTest
@testable import WorkFollow

final class DocumentEditorStateTests: XCTestCase {
    func testEscapeRoutesFromInputMethodThroughEditorLayersToHost() {
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: true, slash: false, selectionToolbar: false, findBar: false), .inputMethod)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: true, selectionToolbar: false, findBar: true), .slash)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: false, selectionToolbar: true, findBar: true), .selectionToolbar)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: false, selectionToolbar: false, findBar: true), .findBar)
        XCTAssertEqual(DocumentEditorEscapeRoute.resolve(composing: false, slash: false, selectionToolbar: false, findBar: false), .host)
    }

    func testSelectionIsRetainedForSameTaskAndResetWhenTaskChanges() {
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        var state = DocumentEditorState(documentID: firstTaskID)
        state.updateSelection(NSRange(location: 8, length: 3))

        state.bind(to: firstTaskID)
        XCTAssertEqual(state.selectedRange, NSRange(location: 8, length: 3))

        state.bind(to: secondTaskID)
        XCTAssertEqual(state.documentID, secondTaskID)
        XCTAssertEqual(state.selectedRange, NSRange(location: 0, length: 0))
    }
}
