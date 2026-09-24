import XCTest
@testable import WorkFollow

final class TaskInspectorPresentationTests: XCTestCase {
    func testEscapeDismissesPopoverBeforeEndingTitleEditing() {
        var state = TaskInspectorPresentationState(editingTarget: .title, activePopover: .schedule)

        XCTAssertEqual(state.handleEscape(isNarrow: true), .dismissPopover)
        XCTAssertEqual(state.editingTarget, .title)
        XCTAssertNil(state.activePopover)
        XCTAssertEqual(state.handleEscape(isNarrow: true), .endEditing)
        XCTAssertEqual(state.handleEscape(isNarrow: true), .returnToList)
    }

    func testEscapeEndsTitleEditingWithoutClosingWideInspector() {
        var state = TaskInspectorPresentationState(editingTarget: .title)

        XCTAssertEqual(state.handleEscape(isNarrow: false), .endEditing)
        XCTAssertEqual(state.handleEscape(isNarrow: false), .keepInspector)
    }

    func testEscapeReturnsFromNarrowInspectorButKeepsWideSelection() {
        var state = TaskInspectorPresentationState()

        XCTAssertEqual(state.handleEscape(isNarrow: true), .returnToList)
        XCTAssertEqual(state.handleEscape(isNarrow: false), .keepInspector)
    }

    func testBodyEditingAlsoConsumesEscapeBeforeNarrowNavigation() {
        var state = TaskInspectorPresentationState(editingTarget: .body)

        XCTAssertEqual(state.handleEscape(isNarrow: true), .endEditing)
        XCTAssertEqual(state.handleEscape(isNarrow: true), .returnToList)
    }

    func testBodyEscapeDismissesPopoverBeforeEndingEditing() {
        var state = TaskInspectorPresentationState(editingTarget: .body,
                                                  activePopover: .deadline)

        XCTAssertEqual(state.handleEscape(isNarrow: true), .dismissPopover)
        XCTAssertEqual(state.editingTarget, .body)
        XCTAssertEqual(state.handleEscape(isNarrow: true), .endEditing)
        XCTAssertEqual(state.handleEscape(isNarrow: true), .returnToList)
    }

    func testTitleDraftResetsForANewTaskButKeepsTheActiveDraftForTheSameTask() {
        var state = TaskInspectorPresentationState()
        let firstTaskID = UUID()
        let secondTaskID = UUID()

        state.synchronizeTitle(taskID: firstTaskID, title: "First")
        state.titleDraft = "First draft"
        state.synchronizeTitle(taskID: firstTaskID, title: "Updated First")
        XCTAssertEqual(state.titleDraft, "First draft")

        state.synchronizeTitle(taskID: secondTaskID, title: "Second")
        XCTAssertEqual(state.titleDraft, "Second")
        state.synchronizeTitle(taskID: nil, title: "")
        XCTAssertEqual(state.titleDraft, "")
    }
}
