import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskInspectorShellContractTests: XCTestCase {
    func testHeaderKeepsPriorityAtRightWithLongDateAndConditionalProperties() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = workspace.createTask(title: "任务", in: .inbox).taskID!
        var task = workspace.task(for: id)!
        task.reminderOffsets = [-30]
        task.recurrence = .daily
        for width: CGFloat in [320, 760] {
            let header = TaskInspectorHeader(task: task, showBack: width == 320,
                onBack: {}, onComplete: {}, onReminder: {}, onRepeat: {},
                schedule: { Text(String(repeating: "很长的日期区间", count: 8)) },
                priority: { Image(systemName: "flag").frame(width: 34, height: 34) })
            let frames = render(header, width: width, height: 58)
            let priority = try XCTUnwrap(frames[.priority])
            let completion = try XCTUnwrap(frames[.completion])
            let divider = try XCTUnwrap(frames[.divider])
            let viewport = try XCTUnwrap(frames[.scheduleViewport])
            XCTAssertEqual(frames[.header]?.height, 58)
            XCTAssertEqual(priority.maxX, width - 20, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(divider.minX, completion.maxX)
            XCTAssertEqual(divider.width, 1, accuracy: 0.5)
            XCTAssertEqual(divider.height, 20, accuracy: 0.5)
            XCTAssertLessThanOrEqual(viewport.maxX, priority.minX)
            XCTAssertNotNil(frames[.reminder])
            XCTAssertNotNil(frames[.repeatControl])
            XCTAssertEqual(frames[.back] != nil, width == 320)
        }
        task.reminderOffsets = nil
        task.recurrence = .never
        let plain = TaskInspectorHeader(task: task, showBack: false,
            onBack: {}, onComplete: {}, onReminder: {}, onRepeat: {},
            schedule: { Text("安排日期") }, priority: { Text("旗标") })
        let frames = render(plain, width: 320, height: 58)
        XCTAssertNil(frames[.reminder])
        XCTAssertNil(frames[.repeatControl])
        task.reminderAt = Date()
        task.recurrenceRule = RecurrenceRule()
        typealias Header = TaskInspectorHeader<Text, Text>
        XCTAssertTrue(Header.showsReminder(task))
        XCTAssertTrue(Header.showsRepeat(task))
    }

    func testChildBreadcrumbRendersBeforeTheTitleInTheActualInspector() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = workspace.createTask(title: "父任务名字", in: .inbox).taskID!
        let child = workspace.createChild(parent, title: "子任务名字").taskID!
        workspace.select(child)
        let frames = render(TaskInspectorShell(workspace: workspace, showBack: false),
                            width: 500, height: 600)
        let breadcrumb = try XCTUnwrap(frames[.breadcrumb])
        let title = try XCTUnwrap(frames[.title])
        XCTAssertEqual(breadcrumb.height, 30, accuracy: 0.5)
        XCTAssertLessThanOrEqual(breadcrumb.maxY, title.minY)
    }

    func testEmptyInspectorContentCentersWithinThePane() throws {
        let frames = render(TaskEmptyInspectorView(), width: 500, height: 600)
        let content = try XCTUnwrap(frames[.emptyContent])
        XCTAssertEqual(content.midX, 250, accuracy: 0.5)
        XCTAssertEqual(content.midY, 300, accuracy: 0.5)
    }

    private func render<V: View>(_ view: V, width: CGFloat,
                                  height: CGFloat) -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = view.frame(width: width, height: height)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        window.orderOut(nil)
        return frames
    }
}
