import XCTest
@testable import WorkFollow

final class FocusLayoutMetricsTests: XCTestCase {
    func testFocusPaneWidthUsesMinimumBelowIdealRange() {
        XCTAssertEqual(FocusLayoutMetrics.focusPaneWidth(availableWidth: 1_000), 430)
    }

    func testFocusPaneWidthUsesProportionalWidthWithinRange() {
        XCTAssertEqual(FocusLayoutMetrics.focusPaneWidth(availableWidth: 1_757), 676.445, accuracy: 0.01)
    }

    func testFocusPaneWidthMatchesObservedReferenceWindowSplit() {
        XCTAssertEqual(FocusLayoutMetrics.focusPaneWidth(availableWidth: 1_450), 558.25, accuracy: 0.01)
    }

    func testCompletedFocusPaneMatchesObservedReferenceWindowSplit() {
        XCTAssertEqual(FocusLayoutMetrics.focusPaneWidth(availableWidth: 1_450, isCompleted: true), 567, accuracy: 0.01)
    }

    func testFocusPaneWidthUsesMaximumAboveIdealRange() {
        XCTAssertEqual(FocusLayoutMetrics.focusPaneWidth(availableWidth: 2_000), 680)
    }

    func testFocusLayoutBaselineMatchesReferenceContract() {
        XCTAssertEqual(FocusLayoutMetrics.focusPaneMinWidth, 430)
        XCTAssertEqual(FocusLayoutMetrics.focusPaneIdealWidth, 650)
        XCTAssertEqual(FocusLayoutMetrics.focusPaneMaxWidth, 680)
        XCTAssertEqual(FocusLayoutMetrics.overviewPaneMinWidth, 620)
        XCTAssertEqual(FocusLayoutMetrics.dividerWidth, 1)
    }
}
