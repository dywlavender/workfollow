import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class ScheduleContainerRenderTests: XCTestCase {
    private final class Probe: ObservableObject {
        @Published var revision = 0
        var frames: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        var page: TaskDatePopoverV2.Page { [.main, .time, .reminder, .recurrence][revision] }
    }
    private struct Harness: View {
        @ObservedObject var probe: Probe
        let workspace: TaskWorkspaceModel
        let task: Task
        var body: some View {
            TaskDatePopoverV2(task: task, workspace: workspace, initialPage: probe.page) {}
                .id(probe.revision)
                .coordinateSpace(name: "schedule-render")
                .onPreferenceChange(ScheduleFramesKey.self) { probe.frames = $0 }
        }
    }

    func testRealPopoverFrameAndCalendarStayFixedAcrossExpandedPages() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 20, minute: 30))!
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
        let id = workspace.createTask(title: "固定容器验收", in: .inbox).taskID!
        let task = workspace.task(for: id)!
        let probe = Probe()
        let controller = NSHostingController(rootView: Harness(probe: probe, workspace: workspace, task: task))
        let owner = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 1000),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 1000))
        owner.contentView = anchor
        owner.makeKeyAndOrderFront(nil)
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = controller
        popover.show(relativeTo: NSRect(x: 400, y: 900, width: 30, height: 20), of: anchor, preferredEdge: .minY)
        defer { popover.close(); owner.contentView = nil; owner.close() }
        func settle() {
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        settle()
        let window = try XCTUnwrap(controller.view.window)
        let baseline = window.frame
        let calendarFrame = try XCTUnwrap(probe.frames[.calendarSection]).frame
        let viewport = try XCTUnwrap(probe.frames[.propertyViewport]).frame
        let footerFrame = try XCTUnwrap(probe.frames[.mainFooter]).frame
        for index in 1...3 {
            probe.revision = index
            settle()
            XCTAssertEqual(window.frame.origin.x, baseline.origin.x, accuracy: 0.5)
            XCTAssertEqual(window.frame.origin.y, baseline.origin.y, accuracy: 0.5)
            XCTAssertEqual(window.frame.width, baseline.width, accuracy: 0.5)
            XCTAssertEqual(window.frame.height, baseline.height, accuracy: 0.5)
            XCTAssertEqual(probe.frames[.calendarSection]?.frame, calendarFrame)
            XCTAssertEqual(probe.frames[.propertyViewport]?.frame, viewport)
            XCTAssertEqual(probe.frames[.mainFooter]?.frame, footerFrame)
            XCTAssertEqual(probe.frames[.panel]?.frame.width, 260)
            XCTAssertEqual(probe.frames[.panel]?.frame.height, SchedulePopoverLayoutV2.height(availableHeight: NSScreen.main?.visibleFrame.height ?? 900))
            for section in [ScheduleExpandedSection.time, .reminder, .repeat] {
                XCTAssertNotNil(probe.frames[.row(section)])
                XCTAssertNil(probe.frames[.expandedContent(section)])
                XCTAssertNil(probe.frames[.editorFooter(section)])
            }
            let children = try XCTUnwrap(window.childWindows)
            XCTAssertEqual(children.count, 1, "切换属性应卸载旧 childWindow")
            let child = try XCTUnwrap(children.first as? NSPanel)
            XCTAssertTrue(child.parent === window)
            XCTAssertEqual(child.title, "日期属性")
            let childHost = try XCTUnwrap(child.contentView as? NSHostingView<AnyView>)
            childHost.layoutSubtreeIfNeeded()
            XCTAssertEqual(child.frame.width, ScheduleMetrics.optionPanelWidth, accuracy: 0.5)
            let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            XCTAssertEqual(child.frame.height, min(childHost.fittingSize.height, screen.height - 16), accuracy: 0.5)
        }
        let child = try XCTUnwrap(window.childWindows?.first)
        popover.close()
        settle()
        XCTAssertNil(child.parent)
        XCTAssertFalse(child.isVisible)
        XCTAssertEqual(workspace.task(for: id), task)
    }

    func testHeightIsResolvedFromAvailableSpaceNotExpansion() {
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 900), 506)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 550), 506)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 500), 468)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 450), 440)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 900, repeating: true), 536)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 900, period: true), 560)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 900, repeating: true, period: true), 590)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 550, repeating: true), 518)
    }

    func testSelectingRepeatGrowsPanelAndKeepsCalendarTopAndFooterVisible() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
        let id = workspace.createTask(title: "重复高度", in: .inbox).taskID!
        let task = workspace.task(for: id)!
        var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        let root = TaskDatePopoverV2(task: task, workspace: workspace, initialPage: .recurrence) {}
            .environment(\.colorScheme, .light)
            .background(WFColors.content)
            .coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { values = $0 }
        let controller = NSHostingController(rootView: root)
        let owner = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 1000),
            styleMask: [.borderless], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 1000))
        owner.contentView = anchor
        owner.orderFront(nil)
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = controller
        popover.show(relativeTo: NSRect(x: 400, y: 900, width: 30, height: 20), of: anchor, preferredEdge: .minY)
        defer { popover.close(); owner.contentView = nil; owner.close() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)); controller.view.layoutSubtreeIfNeeded() }
        settle()
        let window = try XCTUnwrap(controller.view.window)
        let baseline = window.frame
        let calendarFrame = try XCTUnwrap(values[.calendarSection]).frame
        let child = try XCTUnwrap(window.childWindows?.first)
        let childHost = try XCTUnwrap(child.contentView as? NSHostingView<AnyView>)
        var childValues: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        let originalRoot = childHost.rootView
        childHost.rootView = AnyView(originalRoot.coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { childValues = $0 })
        settle()
        let daily = try XCTUnwrap(childValues[.option("每天")]).frame
        let point = CGPoint(x: daily.midX, y: childHost.bounds.height - daily.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: child.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            child.sendEvent(event)
        }
        settle()
        XCTAssertEqual(values[.row(.repeat)]?.label, "每天")
        XCTAssertNotNil(values[.row(.repeatEnd)])
        XCTAssertEqual(window.frame.maxY, baseline.maxY, accuracy: 0.5)
        XCTAssertEqual(values[.calendarSection]?.frame, calendarFrame)
        XCTAssertEqual(window.frame.height, baseline.height + 30, accuracy: 0.5)
        XCTAssertLessThanOrEqual(try XCTUnwrap(values[.mainFooter]).frame.maxY,
            try XCTUnwrap(values[.panel]).frame.maxY - ScheduleMetrics.horizontalPadding + 0.5)
        XCTAssertEqual(workspace.task(for: id), task)

        func press(_ frame: CGRect, in window: NSWindow) throws {
            let host = window === controller.view.window ? controller.view : try XCTUnwrap(window.contentView)
            let local = CGPoint(x: frame.midX, y: host.isFlipped ? frame.midY : host.bounds.height - frame.midY)
            let point = host.convert(local, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1)))
            }
            settle()
        }
        func childFrames() throws -> (NSWindow, [ScheduleRenderAnchor: ScheduleRenderValue]) {
            let child = try XCTUnwrap(window.childWindows?.first)
            let host = try XCTUnwrap(child.contentView as? NSHostingView<AnyView>)
            var frames: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
            let root = host.rootView
            host.rootView = AnyView(root.coordinateSpace(name: "schedule-render")
                .onPreferenceChange(ScheduleFramesKey.self) { frames = $0 })
            settle()
            return (child, frames)
        }
        func snapshot(_ target: NSWindow, name: String) throws {
            let host = try XCTUnwrap(target.contentView)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: "/tmp/workfollow-schedule-panel-renders", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        try snapshot(window, name: "repeat-footer-visible")
        let repeatingFrame = window.frame
        try press(try XCTUnwrap(values[.icon(.repeatEnd)]).frame, in: window)
        var (endingWindow, endingFrames) = try childFrames()
        XCTAssertNotNil(endingFrames[.option("永不结束")])
        try snapshot(endingWindow, name: "repeat-ending-options")
        try press(try XCTUnwrap(endingFrames[.option("按次数结束")]).frame, in: endingWindow)
        (endingWindow, endingFrames) = try childFrames()
        XCTAssertNotNil(endingFrames[.option("repeat-count-input")])
        XCTAssertNotNil(endingFrames[.option("repeat-count-stepper")])
        XCTAssertNotNil(endingFrames[.editorFooter(.repeatEnd)])
        try snapshot(endingWindow, name: "repeat-ending-count")
        let countFooter = try XCTUnwrap(endingFrames[.editorFooter(.repeatEnd)]).frame
        try press(CGRect(x: countFooter.midX + 20, y: countFooter.minY, width: 50, height: countFooter.height), in: endingWindow)
        XCTAssertEqual(values[.row(.repeatEnd)]?.label, "重复 10 次后结束")
        XCTAssertEqual(window.frame, repeatingFrame)
        XCTAssertEqual(workspace.task(for: id), task, "子确定只能修改外层 Draft")
        try press(try XCTUnwrap(values[.icon(.repeatEnd)]).frame, in: window)
        (endingWindow, endingFrames) = try childFrames()
        try press(try XCTUnwrap(endingFrames[.option("按日期结束")]).frame, in: endingWindow)
        (endingWindow, endingFrames) = try childFrames()
        XCTAssertNotNil(endingFrames[.option("repeat-end-calendar")])
        XCTAssertNil(endingFrames[.editorFooter(.repeatEnd)], "日期选择即更新外层草稿，不再加子Footer")
        let endRow = try XCTUnwrap(values[.row(.repeatEnd)]).frame
        let localRow = CGRect(x: endRow.minX,
            y: controller.view.isFlipped ? endRow.minY : controller.view.bounds.height - endRow.maxY,
            width: endRow.width, height: endRow.height)
        let rowTopInScreen = window.convertToScreen(controller.view.convert(localRow, to: nil)).maxY
        XCTAssertEqual(endingWindow.frame.minY, rowTopInScreen, accuracy: 0.5)
        XCTAssertEqual(window.frame, repeatingFrame)
        try snapshot(endingWindow, name: "repeat-ending-date")
    }
}
