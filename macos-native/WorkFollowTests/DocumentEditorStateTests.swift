import XCTest
@testable import WorkFollow

final class DocumentEditorStateTests: XCTestCase {
    func testSelectionIsRetainedForSameTaskAndResetWhenTaskChanges() {
        let firstTaskID = UUID()
        let secondTaskID = UUID()
        var state = DocumentEditorState(taskID: firstTaskID)
        state.updateSelection(NSRange(location: 8, length: 3))

        state.bind(to: firstTaskID)
        XCTAssertEqual(state.selectedRange, NSRange(location: 8, length: 3))

        state.bind(to: secondTaskID)
        XCTAssertEqual(state.taskID, secondTaskID)
        XCTAssertEqual(state.selectedRange, NSRange(location: 0, length: 0))
    }
}
