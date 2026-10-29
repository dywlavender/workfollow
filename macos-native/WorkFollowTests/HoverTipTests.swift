import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class HoverTipTests: XCTestCase {
    override func setUp() async throws {
        HoverTipCenter.shared.hide()
    }

    override func tearDown() async throws {
        HoverTipCenter.shared.hide()
    }

    func testHoverShowsLabelImmediatelyAndMovesBetweenTargets() throws {
        let host = NSHostingView(rootView: VStack(spacing: 10) {
            Color.clear.frame(width: 120, height: 32).hoverTip("任务类型")
            Color.clear.frame(width: 120, height: 32).hoverTip("优先级")
        }.padding(20))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 220, height: 160)
        addTeardownBlock { window.close() }
        InspectorPanelTestSupport.settle(window)

        let targets = descendants(host).compactMap { $0 as? HoverTipTrackingView }
        XCTAssertEqual(targets.count, 2)
        let event = try trackingEvent(.mouseEntered, window: window)

        targets[0].mouseEntered(with: event)
        XCTAssertEqual(HoverTipCenter.shared.activeTitle, "任务类型")
        XCTAssertTrue(HoverTipCenter.shared.isShowing)
        let anchor = window.convertToScreen(targets[0].convert(targets[0].bounds, to: nil))
        let frame = try XCTUnwrap(HoverTipCenter.shared.currentFrame)
        XCTAssertEqual(frame.midX, anchor.midX, accuracy: 1)
        XCTAssertEqual(frame.maxY, anchor.minY - HoverTipMetrics.gap, accuracy: 1)
        XCTAssertEqual(frame.height, HoverTipMetrics.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(frame.width, HoverTipMetrics.width(for: "任务类型") - 1)

        targets[1].mouseEntered(with: event)
        XCTAssertEqual(HoverTipCenter.shared.activeTitle, "优先级")
        targets[0].mouseExited(with: try trackingEvent(.mouseExited, window: window))
        XCTAssertEqual(HoverTipCenter.shared.activeTitle, "优先级",
                       "离开旧目标不能收掉新目标的提示")

        targets[1].mouseExited(with: try trackingEvent(.mouseExited, window: window))
        XCTAssertNil(HoverTipCenter.shared.activeTitle)
        XCTAssertFalse(HoverTipCenter.shared.isShowing)
    }

    func testAppKitIconButtonUsesTheSameImmediateTip() throws {
        let action = {}
        let host = NSHostingView(rootView: AppKitIconButton(
            symbol: "flag", pointSize: 13, tint: .secondaryLabelColor,
            accessibilityLabel: "优先级：中", action: action)
            .frame(width: 34, height: 34))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 120, height: 100)
        addTeardownBlock { window.close() }
        InspectorPanelTestSupport.settle(window)

        let button = try XCTUnwrap(descendants(host).compactMap { $0 as? HoverButton }.first)
        XCTAssertNil(button.toolTip, "系统延迟 tooltip 应关闭，避免与即时提示重复")
        button.mouseEntered(with: try trackingEvent(.mouseEntered, window: window))
        XCTAssertEqual(HoverTipCenter.shared.activeTitle, "优先级：中")
        button.mouseExited(with: try trackingEvent(.mouseExited, window: window))
        XCTAssertNil(HoverTipCenter.shared.activeTitle)
    }

    func testPlacementFlipsLeftAndAboveAtScreenEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 80, height: HoverTipMetrics.height)

        let below = HoverTipMetrics.origin(
            anchor: CGRect(x: 100, y: 400, width: 30, height: 30),
            size: size, in: screen, placement: .automatic)
        XCTAssertEqual(below.x, 100 + 15 - size.width / 2)
        XCTAssertEqual(below.y, 400 - HoverTipMetrics.gap - size.height)

        let above = HoverTipMetrics.origin(
            anchor: CGRect(x: 450, y: 0, width: 30, height: 30),
            size: size, in: screen, placement: .automatic)
        XCTAssertEqual(above.y, 30 + HoverTipMetrics.gap)
        XCTAssertEqual(above.x, 450 + 15 - size.width / 2)

        let right = HoverTipMetrics.origin(
            anchor: CGRect(x: 100, y: 400, width: 30, height: 30),
            size: size, in: screen, placement: .right)
        XCTAssertEqual(right.x, 136)
        XCTAssertEqual(right.y, 400 + 15 - HoverTipMetrics.height / 2)

        let left = HoverTipMetrics.origin(
            anchor: CGRect(x: 940, y: 400, width: 30, height: 30),
            size: size, in: screen, placement: .right)
        XCTAssertEqual(left.x, 940 - HoverTipMetrics.gap - size.width)
    }

    private func trackingEvent(_ type: NSEvent.EventType, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
