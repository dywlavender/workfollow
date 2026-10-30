import AppKit
import XCTest
@testable import WorkFollow

final class AIPaneWindowExpansionTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 0, width: 2560, height: 1440)

    func testExpandsToTheRightWhenThereIsRoom() throws {
        let base = NSRect(x: 100, y: 100, width: 1128, height: 820)
        let frame = try XCTUnwrap(AIPaneWindowExpansionGeometry.expandedFrame(
            base: base, extraWidth: 440, visible: visible))
        XCTAssertEqual(frame.width, 1568)
        XCTAssertEqual(frame.minX, 100)
    }

    func testShiftsLeftWhenRightEdgeHitsScreen() throws {
        let base = NSRect(x: 2000, y: 100, width: 500, height: 820)
        let frame = try XCTUnwrap(AIPaneWindowExpansionGeometry.expandedFrame(
            base: base, extraWidth: 440, visible: visible))
        XCTAssertEqual(frame.width, 940)
        XCTAssertEqual(frame.minX, 1620)
        XCTAssertEqual(frame.maxX, visible.maxX)
    }

    func testClampsToVisibleOriginWhenLeftEdgeIsTight() throws {
        let base = NSRect(x: 100, y: 100, width: 2000, height: 820)
        let frame = try XCTUnwrap(AIPaneWindowExpansionGeometry.expandedFrame(
            base: base, extraWidth: 500, visible: visible))
        XCTAssertEqual(frame.width, 2500)
        XCTAssertEqual(frame.minX, visible.minX + 60)
        XCTAssertEqual(frame.maxX, visible.maxX)
    }

    func testFailsWhenScreenCannotFit() {
        let base = NSRect(x: 0, y: 0, width: 2400, height: 820)
        XCTAssertNil(AIPaneWindowExpansionGeometry.expandedFrame(
            base: base, extraWidth: 440, visible: visible))
    }

    @MainActor
    func testWindowExpandsRightAndCollapseRestoresFrame() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: visible.minX + 80, y: visible.minY + 80,
                                width: 600, height: 500),
            styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let base = window.frame
        let expansion = AIPaneWindowExpansion()

        XCTAssertTrue(expansion.expand(window, by: 300))
        XCTAssertTrue(expansion.isExpanded)
        XCTAssertEqual(window.frame.width, base.width + 300, accuracy: 1)
        XCTAssertEqual(window.frame.minX, base.minX, accuracy: 1)

        expansion.collapse()
        XCTAssertFalse(expansion.isExpanded)
        XCTAssertEqual(window.frame.width, base.width, accuracy: 1)
        XCTAssertEqual(window.frame.minX, base.minX, accuracy: 1)
    }

    @MainActor
    func testWindowShiftsLeftAtScreenEdgeAndCollapseRestoresOrigin() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: visible.maxX - 600, y: visible.minY + 80,
                                width: 600, height: 500),
            styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let base = window.frame
        let expansion = AIPaneWindowExpansion()

        XCTAssertTrue(expansion.expand(window, by: 300))
        XCTAssertLessThan(window.frame.minX, base.minX)
        XCTAssertEqual(window.frame.maxX, visible.maxX, accuracy: 1)

        expansion.collapse()
        XCTAssertEqual(window.frame.minX, base.minX, accuracy: 1)
        XCTAssertEqual(window.frame.width, base.width, accuracy: 1)
    }
}
