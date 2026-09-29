import XCTest
@testable import WorkFollow

final class FocusTimerLayoutContractTests: XCTestCase {
    func testHeaderAndTimerCoreDimensionsMatchTheLayoutContract() {
        XCTAssertEqual(FocusLayoutMetrics.topPadding, 20)
        XCTAssertEqual(FocusLayoutMetrics.horizontalPadding, 24)
        XCTAssertEqual(FocusLayoutMetrics.titleFontSize, 18)
        XCTAssertEqual(FocusLayoutMetrics.segmentWidth, 150)
        XCTAssertEqual(FocusLayoutMetrics.segmentHeight, 30)
        XCTAssertEqual(FocusLayoutMetrics.headerIconSize, 16)
        XCTAssertEqual(FocusLayoutMetrics.headerButtonSize, 28)
        XCTAssertEqual(FocusLayoutMetrics.headerButtonSpacing, 9)

        XCTAssertEqual(FocusLayoutMetrics.ringSize, 236)
        XCTAssertEqual(FocusLayoutMetrics.ringLineWidth, 2.5)
        XCTAssertEqual(FocusLayoutMetrics.progressRingLineWidth, 3)
        XCTAssertEqual(FocusLayoutMetrics.timerFontSize, 42)
        XCTAssertEqual(FocusLayoutMetrics.primaryButtonWidth, 120)
        XCTAssertEqual(FocusLayoutMetrics.primaryButtonHeight, 42)
    }

    func testTimerCoreDimensionsStayFixedAtDesktopWindowHeights() {
        for windowHeight: CGFloat in [820, 900, 1_000] {
            XCTAssertEqual(FocusLayoutMetrics.ringSize, 236)
            XCTAssertEqual(FocusLayoutMetrics.ringLineWidth, 2.5)
            XCTAssertEqual(FocusLayoutMetrics.timerFontSize, 42)
            XCTAssertEqual(FocusLayoutMetrics.primaryButtonWidth, 120)
            XCTAssertEqual(FocusLayoutMetrics.primaryButtonHeight, 42)
            XCTAssertEqual(FocusLayoutMetrics.footerTop(paneHeight: windowHeight), windowHeight - 180)
        }
    }

    func testSelectorAndRingPositionsStayFixedWithOrWithoutPresetChips() {
        let selectorYWithoutPresets = FocusLayoutMetrics.topPadding
            + FocusLayoutMetrics.headerHeight
            + FocusLayoutMetrics.selectorTopPadding(hasPresetChips: false)
        let selectorYWithPresets = FocusLayoutMetrics.topPadding
            + FocusLayoutMetrics.headerHeight
            + FocusLayoutMetrics.presetChipsRowTop
            + FocusLayoutMetrics.presetChipsRowHeight
            + FocusLayoutMetrics.selectorTopPadding(hasPresetChips: true)

        XCTAssertEqual(selectorYWithoutPresets, 185)
        XCTAssertEqual(selectorYWithPresets, 185)
        XCTAssertEqual(FocusLayoutMetrics.ringTop, 319)
    }
}
