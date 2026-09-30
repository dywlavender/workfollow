import XCTest
@testable import WorkFollow

final class FocusOverviewLayoutContractTests: XCTestCase {
    func testOverviewPointSizesAreFixedRatherThanWindowScaled() {
        XCTAssertEqual(FocusLayoutMetrics.overviewHorizontalPadding, 24)
        XCTAssertEqual(FocusLayoutMetrics.overviewVerticalPadding, 24)
        XCTAssertEqual(FocusLayoutMetrics.overviewTitleFontSize, 18)
        XCTAssertEqual(FocusLayoutMetrics.overviewCardGap, 12)
        XCTAssertEqual(FocusLayoutMetrics.overviewCardHeight, 76)
        XCTAssertEqual(FocusLayoutMetrics.overviewCardRadius, 10)
        XCTAssertEqual(FocusLayoutMetrics.recordHeaderTop, 26)
        XCTAssertEqual(FocusLayoutMetrics.recordRowHeight, 48)
    }

    func testPaneSplitPreservesOverviewMinimumAtDesktopWidths() {
        for windowWidth: CGFloat in [1_280, 1_440, 1_600] {
            let workspaceWidth = windowWidth - WFMetrics.railWidth - WFMetrics.divider
            let focusWidth = FocusLayoutMetrics.focusPaneWidth(availableWidth: workspaceWidth)
            let overviewWidth = workspaceWidth - focusWidth - FocusLayoutMetrics.dividerWidth

            XCTAssertGreaterThanOrEqual(overviewWidth, FocusLayoutMetrics.overviewPaneMinWidth)
        }
    }

    func testWorkspaceMinimumFitsBothPaneMinimumsAndDivider() {
        XCTAssertEqual(FocusLayoutMetrics.minimumWorkspaceWidth, 1_051)
        let focusWidth = FocusLayoutMetrics.focusPaneWidth(
            availableWidth: FocusLayoutMetrics.minimumWorkspaceWidth
        )
        let overviewWidth = FocusLayoutMetrics.minimumWorkspaceWidth
            - focusWidth - FocusLayoutMetrics.dividerWidth

        XCTAssertEqual(focusWidth, FocusLayoutMetrics.focusPaneMinWidth)
        XCTAssertEqual(overviewWidth, FocusLayoutMetrics.overviewPaneMinWidth)
    }

    func testOverviewTypographyAndRecordRowContract() {
        XCTAssertEqual(FocusLayoutMetrics.overviewLabelFontSize, 12)
        XCTAssertEqual(FocusLayoutMetrics.overviewValueFontSize, 24)
        XCTAssertEqual(FocusLayoutMetrics.overviewUnitFontSize, 12)
        XCTAssertEqual(FocusLayoutMetrics.overviewGoalFontSize, 12)
        XCTAssertEqual(FocusLayoutMetrics.overviewGoalProgressHeight, 3)
        XCTAssertEqual(FocusLayoutMetrics.recordHeaderFontSize, 17)
        XCTAssertEqual(FocusLayoutMetrics.recordHeaderIconSize, 16)
        XCTAssertEqual(FocusLayoutMetrics.recordHeaderButtonSize, 28)
        XCTAssertEqual(FocusLayoutMetrics.recordTimeFontSize, 13)
        XCTAssertEqual(FocusLayoutMetrics.recordTitleFontSize, 14)
        XCTAssertEqual(FocusLayoutMetrics.recordMinutesFontSize, 13)
        XCTAssertEqual(FocusLayoutMetrics.recordStatusDotSize, 5)
    }
}
