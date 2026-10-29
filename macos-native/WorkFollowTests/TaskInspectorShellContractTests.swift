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
                onBack: {}, onComplete: {}, onRepeat: {},
                schedule: { Text(String(repeating: "很长的日期区间", count: 8)) },
                priority: { Image(systemName: "flag").frame(width: 34, height: 34) })
            let frames = render(header, width: width, height: 58)
            let priority = try XCTUnwrap(frames[.priority])
            let completion = try XCTUnwrap(frames[.completion])
            let divider = try XCTUnwrap(frames[.divider])
            let viewport = try XCTUnwrap(frames[.scheduleViewport])
            XCTAssertEqual(frames[.header]?.height, TaskInspectorMetrics.headerHeight)
            XCTAssertEqual(priority.maxX, width - TaskInspectorMetrics.horizontalPadding, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(divider.minX, completion.maxX)
            XCTAssertEqual(divider.width, 1, accuracy: 0.5)
            XCTAssertEqual(divider.height, 20, accuracy: 0.5)
            XCTAssertLessThanOrEqual(viewport.maxX, priority.minX)
            XCTAssertNil(frames[.reminder], "Reminder belongs inside the schedule panel, not the header")
            XCTAssertNotNil(frames[.repeatControl])
            XCTAssertEqual(frames[.back] != nil, width == 320)
        }
        task.reminderOffsets = nil
        task.recurrence = .never
        let plain = TaskInspectorHeader(task: task, showBack: false,
            onBack: {}, onComplete: {}, onRepeat: {},
            schedule: { Text("设置日期") }, priority: { Text("旗标") })
        let frames = render(plain, width: 320, height: 58)
        XCTAssertNil(frames[.reminder])
        XCTAssertNil(frames[.repeatControl])
        task.reminderAt = Date()
        task.recurrenceRule = RecurrenceRule()
        typealias Header = TaskInspectorHeader<Text, Text>
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

    func testTitleAndDocumentShareContentOriginAndCompactGap() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = workspace.createTask(title: "codex", in: .inbox).taskID!
        workspace.select(id)
        let frames = render(TaskInspectorShell(workspace: workspace, showBack: false), width: 500, height: 600)
        let title = try XCTUnwrap(frames[.title])
        let document = try XCTUnwrap(frames[.document])
        XCTAssertEqual(title.minX, TaskInspectorMetrics.horizontalPadding, accuracy: 0.5)
        XCTAssertEqual(document.minY - title.maxY, TaskInspectorMetrics.titleDocumentGap, accuracy: 0.5)
        XCTAssertEqual(TaskInspectorMetrics.documentLeadingPadding + TaskInspectorMetrics.documentFragmentPadding,
                       TaskInspectorMetrics.horizontalPadding)
        XCTAssertEqual(TaskInspectorMetrics.completionSize, 15)
        // 断言"渲染出来的框"，而不只是常量：可见墨迹 15pt、在 24pt 命中区内左对齐。
        let ink = try XCTUnwrap(frames[.completionInk])
        XCTAssertEqual(ink.width, TaskInspectorMetrics.completionSize, accuracy: 0.5)
        XCTAssertEqual(ink.height, TaskInspectorMetrics.completionSize, accuracy: 0.5)
        XCTAssertEqual(ink.minX, TaskInspectorMetrics.horizontalPadding, accuracy: 0.5)
    }

    func testEmptyInspectorContentCentersWithinThePane() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let frames = render(TaskInspectorShell(workspace: workspace, showBack: false), width: 500, height: 600)
        let content = try XCTUnwrap(frames[.emptyContent])
        XCTAssertNil(frames[.header])
        XCTAssertNil(frames[.title])
        XCTAssertEqual(content.width, 176, accuracy: 0.5)
        XCTAssertEqual(content.midX, 250, accuracy: 0.5)
        XCTAssertEqual(content.midY, 300, accuracy: 0.5)
    }

    func testInspectorScheduleLabelsAndColorsUseTickTickGrammar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
        let old = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 20, minute: 30))!
        typealias Schedule = TaskInspectorSchedulePresentation
        XCTAssertEqual(Schedule.label(date: nil, hasTime: false, now: now, calendar: calendar), "设置日期")
        XCTAssertEqual(Schedule.label(date: now, hasTime: false, now: now, calendar: calendar), "今天, 9月30日")
        XCTAssertEqual(Schedule.label(date: old, hasTime: true, now: now, calendar: calendar), "9月20日, 20:30")
        let lastSunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 20, minute: 30))!
        XCTAssertEqual(Schedule.label(date: lastSunday, hasTime: true, now: now, calendar: calendar), "上周日, 9月27日, 20:30")
        XCTAssertEqual(Schedule.tone(date: nil, hasTime: false, now: now, calendar: calendar), .empty)
        XCTAssertEqual(Schedule.tone(date: now, hasTime: false, now: now, calendar: calendar), .scheduled)
        XCTAssertEqual(Schedule.tone(date: old, hasTime: true, now: now, calendar: calendar), .overdue)
        let future = calendar.date(byAdding: .day, value: 2, to: now)!
        XCTAssertEqual(Schedule.tone(date: future, hasTime: false, now: now, calendar: calendar), .scheduled)
    }

    func testScheduleChipIncludesTimedAndAllDayRangeEnds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day,
                                               hour: hour, minute: minute))!
        }
        let start = date(19, 9, 17)
        typealias Presentation = TaskInspectorSchedulePresentation
        XCTAssertEqual(Presentation.label(schedule: TaskSchedule(dueAt: start, hasTime: true,
            dueEndAt: date(19, 11, 43)), now: date(19, 12), calendar: calendar),
            "10月19日, 09:17 - 11:43, 延迟17分钟")
        XCTAssertEqual(Presentation.label(schedule: TaskSchedule(dueAt: date(19),
            dueEndAt: date(20)), now: date(19, 12), calendar: calendar),
            "今天, 10月19日 - 明天, 10月20日")
        XCTAssertEqual(Presentation.label(schedule: TaskSchedule(dueAt: date(19),
            dueEndAt: date(19)), now: date(19, 12), calendar: calendar), "今天, 10月19日")
    }

    func testOverdueHeaderKeepsCalendarIconAndOpensTheDatePanel() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let due = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26))!
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "逾期日期", in: .inbox).taskID)
        workspace.saveTiming(id, schedule: TaskSchedule(dueAt: due), reminder: nil, frequency: .never)
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace)
        let owner = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { owner.close() }
        func buttons(in view: NSView) -> [NSButton] {
            [view as? NSButton].compactMap { $0 } + view.subviews.flatMap { buttons(in: $0) }
        }
        let chip = try XCTUnwrap(buttons(in: host).first { $0.attributedTitle.string == "9月26日, 延迟29天" })
        XCTAssertNotNil(chip.image, "详情顶部仍保留日历图标")
        try InspectorPanelTestSupport.clickButton(containing: "9月26日, 延迟29天", in: owner)
        let datePanel = try InspectorPanelTestSupport.panel(title: "日期属性", below: owner)
        XCTAssertTrue(datePanel.isVisible)
        try InspectorPanelTestSupport.sendEscape(to: datePanel)
        XCTAssertFalse(datePanel.isVisible)
    }

    private func render<V: View>(_ view: V, width: CGFloat,
                                  height: CGFloat) -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = view.frame(width: width, height: height)
            .environmentObject(AppEnvironment())
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
