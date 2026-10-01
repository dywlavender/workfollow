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
    }
}
