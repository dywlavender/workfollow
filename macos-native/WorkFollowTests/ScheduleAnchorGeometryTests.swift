import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class ScheduleAnchorGeometryTests: XCTestCase {
    func testOrdinaryAnchorPlacesPanelBelowWithLeadingEdgesAligned() {
        let bounds = CGRect(x: 100, y: 200, width: 600, height: 500)
        let anchor = CGRect(x: 240, y: 480, width: 80, height: 32)

        let frame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: anchor, size: CGSize(width: 220, height: 180), bounds: bounds
        )

        XCTAssertEqual(frame, CGRect(x: 240, y: 294, width: 220, height: 180))
        XCTAssertEqual(anchor.minY - frame.maxY, 6)
    }

    func testBottomAnchorFlipsPanelAbove() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = CGRect(x: 300, y: 24, width: 100, height: 32)

        let frame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: anchor, size: CGSize(width: 220, height: 180), bounds: bounds
        )

        XCTAssertEqual(frame, CGRect(x: 300, y: 62, width: 220, height: 180))
        XCTAssertEqual(frame.minY - anchor.maxY, 6)
    }

    func testPanelClampsHorizontallyAtRightEdgeWithoutChangingVerticalPlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = CGRect(x: 740, y: 200, width: 60, height: 32)

        let frame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: anchor, size: CGSize(width: 200, height: 100), bounds: bounds
        )

        XCTAssertEqual(frame, CGRect(x: 592, y: 94, width: 200, height: 100))
        XCTAssertEqual(anchor.minY - frame.maxY, 6)
    }

    func testOverheightPanelIsLimitedToSafeBounds() {
        let bounds = CGRect(x: 20, y: 30, width: 500, height: 400)
        let anchor = CGRect(x: 190, y: 200, width: 100, height: 30)
        let safeBounds = bounds.insetBy(dx: 8, dy: 8)

        let frame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: anchor, size: CGSize(width: 160, height: 600), bounds: bounds
        )

        XCTAssertEqual(frame, CGRect(x: 190, y: safeBounds.minY, width: 160, height: safeBounds.height))
        XCTAssertTrue(safeBounds.contains(frame))
    }

    func testWhenNeitherSideFitsPanelUsesSideWithMoreSpaceThenClamps() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = CGRect(x: 300, y: 280, width: 100, height: 32)

        let frame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: anchor, size: CGSize(width: 220, height: 360), bounds: bounds
        )

        XCTAssertEqual(frame, CGRect(x: 300, y: 232, width: 220, height: 360))
        XCTAssertTrue(bounds.insetBy(dx: 8, dy: 8).contains(frame))
    }

    func testDifferentHostWidthsPreservePlacementForSameButtonAnchor() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let narrowHostAnchor = CGRect(x: 260, y: 300, width: 40, height: 32)
        let wideHostAnchor = CGRect(x: 260, y: 300, width: 420, height: 32)
        let size = CGSize(width: 220, height: 180)

        let narrowHostFrame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: narrowHostAnchor, size: size, bounds: bounds
        )
        let wideHostFrame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: wideHostAnchor, size: size, bounds: bounds
        )

        XCTAssertEqual(narrowHostFrame, wideHostFrame)
        XCTAssertEqual(narrowHostFrame.minX, narrowHostAnchor.minX)
    }

    func testPanelFollowsButtonWhenAnchorMoves() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = CGRect(x: 240, y: 400, width: 80, height: 32)
        let size = CGSize(width: 220, height: 180)
        let originalFrame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: anchor, size: size, bounds: bounds
        )
        let movedAnchor = anchor.offsetBy(dx: 45, dy: 35)

        let movedFrame = AnchoredPropertyPanelGeometry.scheduleFrame(
            anchor: movedAnchor, size: size, bounds: bounds
        )

        XCTAssertEqual(movedFrame, originalFrame.offsetBy(dx: 45, dy: 35))
    }
}
