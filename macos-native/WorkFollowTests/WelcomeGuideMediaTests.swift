import AppKit
import ImageIO
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class WelcomeGuideMediaTests: XCTestCase {
    func testMediaResourceNamesAreUniquePerAction() {
        let names = WelcomeGuide.Action.allCases.map(WelcomeGuide.mediaResourceName(for:))
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(WelcomeGuide.mediaResourceName(for: .quickAdd), "guide-quick-add")
        XCTAssertEqual(WelcomeGuide.mediaResourceName(for: .commandPalette), "guide-command-palette")
    }

    func testFeatureGuideItemsHaveAnAnimatedDemo() throws {
        let actions = Set(WelcomeGuide.items.map(\.action))
        XCTAssertEqual(actions.count, WelcomeGuide.items.count,
                       "每条引导都需要独立动作，否则会共用同一张演示")
        for action in actions {
            let url = try XCTUnwrap(WelcomeGuide.mediaURL(for: action),
                                    "Missing " + WelcomeGuide.mediaResourceName(for: action) + ".gif")
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let name = WelcomeGuide.mediaResourceName(for: action)
            XCTAssertGreaterThanOrEqual(CGImageSourceGetCount(source), 20, name + " 帧数太少，读不清操作")
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            XCTAssertGreaterThanOrEqual(width, 900, name + " 宽度不足")
            XCTAssertGreaterThanOrEqual(height, 500, name + " 高度不足")
        }
    }

    func testMediaViewKeepsGIFPlaying() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Reduce Motion intentionally freezes the demo on its first frame.")
        let host = NSHostingView(rootView: WelcomeGuideMediaView(action: .quickAdd)
            .frame(width: 640, height: 400))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 640, height: 400)
        defer {
            window.contentView = nil
            window.close()
        }
        let imageView = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSImageView }.first)
        XCTAssertTrue(imageView.animates)
        XCTAssertNotNil(imageView.image)

        let early = try snapshot(host)
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        let late = try snapshot(host)
        XCTAssertNotEqual(early, late, "GIF frames should advance without user interaction")
    }

    /// 引导任务详情：卡片在正文之后、开始使用之前，打开就播放。
    func testGuideTaskInspectorShowsAutoPlayingDemo() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Reduce Motion intentionally freezes the demo on its first frame.")
        let fixture = InspectorFixture()
        defer { fixture.close() }
        fixture.environment.taskWorkspace.installWelcomeGuide()
        fixture.settle(0.4)

        let quickAdd = try XCTUnwrap(fixture.environment.taskWorkspace.allTasks.first {
            $0.guideAction == WelcomeGuide.Action.quickAdd.rawValue
        })
        fixture.environment.navigation.destination = .allTasks
        fixture.environment.taskWorkspace.activeList = WelcomeGuide.listName
        fixture.environment.taskWorkspace.select(quickAdd.id)
        fixture.settle(0.8)

        let image = try XCTUnwrap(fixture.animatingImage())
        XCTAssertTrue(image.animates)
        let frame = image.convert(image.bounds, to: fixture.host)
        XCTAssertGreaterThan(frame.width, 500, "演示图应铺满详情栏")
        XCTAssertGreaterThan(frame.minX, 600, "演示图应在右侧详情栏内")

        let early = try fixture.snapshot(image)
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        let late = try fixture.snapshot(image)
        XCTAssertNotEqual(early, late, "进入引导任务后 GIF 应自动播放")
    }

    func testOrdinaryTaskHasNoDemoCard() throws {
        let fixture = InspectorFixture()
        defer { fixture.close() }
        let id = try XCTUnwrap(fixture.environment.taskWorkspace.createTask(title: "普通任务", in: .today).taskID)
        fixture.environment.navigation.destination = .today
        fixture.environment.taskWorkspace.select(id)
        fixture.settle(0.6)
        XCTAssertNil(fixture.animatingImage())
    }

    private func descendants(of view: NSView) -> [NSView] {
        var result: [NSView] = []
        func walk(_ view: NSView) {
            result.append(view)
            view.subviews.forEach(walk)
        }
        walk(view)
        return result
    }

    private func snapshot(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor
    private final class InspectorFixture {
        let directory: URL
        let environment: AppEnvironment
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("guide-media-test-" + UUID().uuidString)
            environment = AppEnvironment(clock: { now }, calendar: calendar, directory: directory)
            host = NSHostingView(rootView: AnyView(
                RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
                    .environmentObject(environment)))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
            settle(0.3)
        }

        func settle(_ duration: TimeInterval = 0.2) {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(duration))
            host.layoutSubtreeIfNeeded()
        }

        func animatingImage() -> NSImageView? {
            descendants(of: host).compactMap { $0 as? NSImageView }
                .first { $0.animates && $0.window != nil }
        }

        func descendants(of view: NSView) -> [NSView] {
            var result: [NSView] = []
            func walk(_ view: NSView) {
                result.append(view)
                view.subviews.forEach(walk)
            }
            walk(view)
            return result
        }

        func snapshot(_ view: NSView) throws -> Data {
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }

        func close() {
            window.childWindows?.forEach { $0.orderOut(nil) }
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
