import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class MainWindowChromeContractTests: XCTestCase {
    func testConfigureSetsChromeAndPreservesWindowCapabilitiesAndDelegate() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        let delegate = WindowDelegateSpy()
        window.delegate = delegate
        window.isMovableByWindowBackground = true

        MainWindowChromeConfiguration.configure(window)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.delegate === delegate)
    }

    func testTrafficLightFramesRetainNativeSizesFitRailAndKeepTop() {
        let sizes = Array(repeating: CGSize(width: 14, height: 14), count: 3)
        let top: CGFloat = 19

        // 这个字面值是**故意写死**的：它把「栏宽」钉成一条设计决定，改了就要来改这里。
        // 2026-10-03 由 52 调到 62，对齐滴答清单实测的栏宽（见 `RailMetrics` 的注释）。
        // 本用例其余断言都从 `RailMetrics.width` 推导，所以只有这一行会因改宽度而失败。
        XCTAssertEqual(RailMetrics.width, 62)
        let frames = MainWindowChromeGeometry.trafficLightFrames(
            sizes: sizes, railWidth: RailMetrics.width, top: top
        )

        XCTAssertEqual(frames.map(\.size), sizes)
        XCTAssertEqual(frames.map(\.minY), Array(repeating: top, count: sizes.count))
        XCTAssertEqual(frames.count, sizes.count)
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, RailMetrics.width)
        }
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(left.maxX, right.minX)
        }
    }

    func testRailInsetAddsEightPointsAndIsZeroWithoutButtons() {
        let frames = [
            CGRect(x: 3, y: 12, width: 14, height: 14),
            CGRect(x: 20, y: 24, width: 14, height: 14)
        ]

        XCTAssertEqual(MainWindowChromeGeometry.railInset(buttonFrames: frames), 46)
        XCTAssertEqual(MainWindowChromeGeometry.railInset(buttonFrames: []), 0)
    }

    func testAttachedChromePositionsActualSystemButtonsInsideRailAfterResize() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        var inset: CGFloat = 0
        window.contentView = NSHostingView(rootView: Color.clear.background(
            MainWindowChromeConfiguration(railInset: Binding(get: { inset }, set: { inset = $0 }))))
        defer { window.orderOut(nil) }
        window.orderFront(nil)
        for width in [CGFloat(800), 1100, 620] {
            window.setContentSize(CGSize(width: width, height: 600))
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let content = try XCTUnwrap(window.contentView)
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try XCTUnwrap(window.standardWindowButton(type))
                let frame = content.convert(button.bounds, from: button)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, RailMetrics.width)
                let bottom = content.isFlipped ? frame.maxY : content.bounds.height - frame.minY
                XCTAssertGreaterThanOrEqual(inset, bottom + 8)
            }
        }
    }

    func testRootShellIgnoresTopSafeArea() throws {
        let source = try sourceFile("Features/Shell/RootShellView.swift")
        let rootShell = try section(
            in: source,
            from: "struct RootShellView: View",
            to: "/// Reusable production shell"
        )

        XCTAssertTrue(rootShell.contains(".ignoresSafeArea(.container, edges: .top)"))
    }

    func testIconRailUsesInsetOnlyForTopPaddingAndKeepsWidth() throws {
        let source = try sourceFile("Features/Sidebar/SidebarViews.swift")
        let iconRail = try section(
            in: source,
            from: "struct IconRailView: View",
            to: "struct NavigationColumnView:"
        )

        XCTAssertTrue(iconRail.contains(".padding(.top, max(RailMetrics.topPadding, mainWindowRailInset))"))
        XCTAssertTrue(iconRail.contains(".padding(.bottom, RailMetrics.topPadding)"))
        XCTAssertFalse(iconRail.contains(".padding(.vertical, mainWindowRailInset)"))
        XCTAssertFalse(iconRail.contains(".padding(.bottom, mainWindowRailInset)"))
        XCTAssertTrue(iconRail.contains(".frame(width: RailMetrics.width)"))
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WorkFollow", isDirectory: true)
    }

    private func sourceFile(_ path: String) throws -> String {
        try String(contentsOf: sourceRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        let startRange = try XCTUnwrap(source.range(of: start), "Missing source section: \(start)")
        let endRange = try XCTUnwrap(
            source.range(of: end, range: startRange.upperBound..<source.endIndex),
            "Missing end marker: \(end)"
        )
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private final class WindowDelegateSpy: NSObject, NSWindowDelegate {}
}
