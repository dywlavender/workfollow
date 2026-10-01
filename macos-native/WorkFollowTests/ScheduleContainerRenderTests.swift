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
        for index in 1...3 {
            probe.revision = index
            settle()
            XCTAssertEqual(window.frame.origin.x, baseline.origin.x, accuracy: 0.5)
            XCTAssertEqual(window.frame.origin.y, baseline.origin.y, accuracy: 0.5)
            XCTAssertEqual(window.frame.width, baseline.width, accuracy: 0.5)
            XCTAssertEqual(window.frame.height, baseline.height, accuracy: 0.5)
            XCTAssertEqual(probe.frames[.calendarSection]?.frame, calendarFrame)
            XCTAssertEqual(probe.frames[.propertyViewport]?.frame, viewport)
            XCTAssertEqual(probe.frames[.panel]?.frame.width, 260)
            XCTAssertEqual(probe.frames[.panel]?.frame.height, SchedulePopoverLayoutV2.height(availableHeight: NSScreen.main?.visibleFrame.height ?? 900))
            if index == 2 {
                let footer = try XCTUnwrap(probe.frames[.editorFooter(.reminder)])
                XCTAssertGreaterThan(footer.frame.maxY, viewport.maxY, "长内容应留在内部滚动区，不能撑大外框")
                func scrollView(in view: NSView) -> NSScrollView? {
                    if let scroll = view as? NSScrollView { return scroll }
                    return view.subviews.compactMap { scrollView(in: $0) }.first
                }
                let scroll = try XCTUnwrap(scrollView(in: controller.view))
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                settle()
                let visibleFooter = try XCTUnwrap(probe.frames[.editorFooter(.reminder)]).frame
                XCTAssertLessThanOrEqual(visibleFooter.maxY, viewport.maxY + 1)
                XCTAssertGreaterThanOrEqual(visibleFooter.minY, viewport.minY - 1)
                XCTAssertEqual(probe.frames[.calendarSection]?.frame, calendarFrame)
                XCTAssertEqual(window.frame, baseline)
            }
        }
        XCTAssertEqual(workspace.task(for: id), task)
    }

    func testHeightIsResolvedFromAvailableSpaceNotExpansion() {
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 900), 560)
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 550), 518)
    }
}
