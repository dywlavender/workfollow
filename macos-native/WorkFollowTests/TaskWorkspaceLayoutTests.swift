import XCTest
@testable import WorkFollow

final class TaskWorkspaceLayoutTests: XCTestCase {
    func testOrdinaryListRetainsItsWidthBeforeAndAfterOpeningOrClosingATask() {
        for selected in [false, true, false] {
            let layout = TaskWorkspaceLayout(availableWidth: 1006, preferredListWidth: 390,
                wideView: false, hasSelection: selected, hasBulkSelection: false)
            XCTAssertTrue(layout.showsInspector)
            XCTAssertEqual(layout.listWidth, 390)
        }
    }

    func testBoardKeepsFullWidthUntilATaskNeedsTheInspector() {
        let empty = TaskWorkspaceLayout(availableWidth: 1006, preferredListWidth: 390,
            wideView: true, hasSelection: false, hasBulkSelection: false)
        XCTAssertFalse(empty.showsInspector)
        XCTAssertEqual(empty.listWidth, 1006)
        let selected = TaskWorkspaceLayout(availableWidth: 1006, preferredListWidth: 390,
            wideView: true, hasSelection: true, hasBulkSelection: false)
        XCTAssertTrue(selected.showsInspector)
        XCTAssertEqual(selected.listWidth, 685)
    }
}
