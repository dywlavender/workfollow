import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class RailTooltipTests: XCTestCase {
    private struct Fixture {
        let window: NSWindow
        let host: NSView
        let state: RailTooltipState
        let navigation: AppNavigation
        let directory: URL
    }

    private func fixture(dark: Bool = false) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail-tooltip-" + UUID().uuidString)
        let environment = AppEnvironment(directory: directory)
        environment.focusStore.notifier = nil
        let state = RailTooltipState()
        let navigation = environment.navigation
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            IconRailView(workspace: environment.taskWorkspace, navigation: navigation,
                         onNavigate: environment.navigate, onOpenQuickOpen: {},
                         sync: environment.systemReminders, tooltips: state)
            NavigationColumnView(workspace: environment.taskWorkspace, navigation: navigation,
                                 filterStore: environment.filterStore)
                .frame(width: WFMetrics.navigationWidth)
            TaskListView(workspace: environment.taskWorkspace, navigation: navigation,
                         navigationVisible: true)
        }
        .environmentObject(environment)
        .frame(width: 1000, height: 720)
        .preferredColorScheme(dark ? .dark : .light))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1000, height: 720)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        InspectorPanelTestSupport.settle(window)
        addTeardownBlock {
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        return Fixture(window: window, host: host, state: state, navigation: navigation, directory: directory)
    }

    func testEveryRailIconShowsAnInwardTooltipWithoutChangingFocusOrBlockingClicks() throws {
        let expected = ["任务", "笔记", "日历", "四象限", "倒数纪念日", "专注", "会议纪要", "Apple 同步", "快速打开（⌘K）", "设置（⌘,）"]
        for dark in [false, true] {
            let fixture = try fixture(dark: dark)
            let targets = railTargets(in: fixture.host)
            XCTAssertEqual(targets.count, expected.count)
            let responder = fixture.window.firstResponder
            let event = try trackingEvent(.mouseEntered, window: fixture.window)
            for (target, title) in zip(targets, expected) {
                target.mouseEntered(with: event)
                InspectorPanelTestSupport.settle(fixture.window)
                let active = try XCTUnwrap(fixture.state.active)
                XCTAssertEqual(active.title, title)
                XCTAssertEqual(active.frame.width, RailMetrics.hitSize, accuracy: 1)
                XCTAssertTrue(fixture.window.firstResponder === responder)
                XCTAssertTrue(InspectorPanelTestSupport.visibleWindows(below: fixture.window).isEmpty)
                // The label extends over the neighboring sidebar but cannot own its clicks.
                let point = CGPoint(x: active.frame.maxX + 20, y: active.frame.midY)
                let hit = try XCTUnwrap(fixture.host.hitTest(point))
                XCTAssertFalse(hit is RowHoverView)
                if title == "四象限", let path = ProcessInfo.processInfo.environment["WORKFOLLOW_RAIL_CAPTURE_DIRECTORY"] {
                    try capture(fixture.host, path: path, name: dark ? "dark" : "light")
                }
                target.mouseExited(with: try trackingEvent(.mouseExited, window: fixture.window))
                XCTAssertNil(fixture.state.active)
            }
        }
    }

    func testMovingBetweenIconsAndClickingNavigationNeverLeavesAStaleLabel() throws {
        let fixture = try fixture()
        let targets = railTargets(in: fixture.host)
        let first = try XCTUnwrap(targets.first)
        let matrix = try XCTUnwrap(targets.dropFirst(3).first)
        first.mouseEntered(with: try trackingEvent(.mouseEntered, window: fixture.window))
        matrix.mouseEntered(with: try trackingEvent(.mouseEntered, window: fixture.window))
        first.mouseExited(with: try trackingEvent(.mouseExited, window: fixture.window))
        XCTAssertEqual(fixture.state.active?.title, "四象限")
        let rect = matrix.convert(matrix.bounds, to: fixture.host)
        try InspectorPanelTestSupport.click(rect, in: fixture.host, window: fixture.window)
        XCTAssertEqual(fixture.navigation.destination, .matrix)
        XCTAssertNil(fixture.state.active)
    }

    private func railTargets(in host: NSView) -> [RowHoverView] {
        descendants(host).compactMap { $0 as? RowHoverView }.filter {
            let frame = $0.convert($0.bounds, to: host)
            return $0.onHover != nil && frame.minX >= 0 && frame.maxX <= RailMetrics.width + 1
                && abs(frame.width - RailMetrics.hitSize) < 1
        }.sorted { $0.convert($0.bounds, to: host).midY < $1.convert($1.bounds, to: host).midY }
    }

    private func trackingEvent(_ type: NSEvent.EventType, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func capture(_ host: NSView, path: String, name: String) throws {
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rect = CGRect(x: 0, y: 0, width: 280, height: 720)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: rect))
        host.cacheDisplay(in: rect, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
    }
}
