import XCTest
@testable import WorkFollow

final class TaskInspectorActionPanelTests: XCTestCase {
    func testOpeningAnActionReplacesThePreviousPanel() {
        var state = TaskInspectorActionPresentationState()
        XCTAssertNil(state.panel)
        state.open(.more)
        XCTAssertEqual(state.panel, .more)
        state.open(.tags)
        XCTAssertEqual(state.panel, .tags)
        state.open(.relation)
        XCTAssertEqual(state.panel, .relation)
        state.open(.parent)
        XCTAssertEqual(state.panel, .parent)
    }

    func testSubmenuEscapeAndPanelReplacementAreHierarchical() {
        var state = TaskInspectorActionPresentationState()
        state.open(.more)
        state.openSubmenu(.focus)
        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(state.panel, .more)
        XCTAssertNil(state.submenu)
        XCTAssertTrue(state.handleEscape())
        XCTAssertNil(state.panel)
        state.open(.more)
        state.openSubmenu(.focus)
        state.open(.tags)
        XCTAssertEqual(state.panel, .tags)
        XCTAssertNil(state.submenu)
        state.open(.more)
        state.openSubmenu(.focus)
        state.open(.parent)
        XCTAssertEqual(state.panel, .parent)
        XCTAssertNil(state.submenu)
        XCTAssertTrue(state.handleEscape())
        XCTAssertNil(state.panel)
        state.dismiss()
        XCTAssertNil(state.panel)
        XCTAssertNil(state.submenu)
    }

    func testPanelCompletionAndOutsideDismissalUseTheSameState() {
        var state = TaskInspectorActionPresentationState()
        state.open(.tags)
        state.dismiss(.tags)
        XCTAssertNil(state.panel)
        state.open(.relation)
        state.dismiss()
        XCTAssertNil(state.panel)
        state.open(.more)
        state.dismiss(.more)
        state.open(.tags)
        XCTAssertEqual(state.panel, .tags, "More action can transition to the existing Tag Picker")
    }
}
