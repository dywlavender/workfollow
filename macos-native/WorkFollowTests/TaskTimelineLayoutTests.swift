import XCTest
import SwiftUI
@testable import WorkFollow

final class TaskTimelineLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private var now: Date { date(18, 10) }
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func task(_ title: String, schedule: TaskSchedule = TaskSchedule()) -> Task {
        Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: .none,
             schedule: schedule, childOrder: 0, createdAt: now, updatedAt: now)
    }
    private var range: TaskTimelineRange {
        TaskTimelineRange(start: date(18), dayCount: 14, visibleDayCount: 7, dayWidth: 88)
    }

    func testPartitionKeepsInputOrderAndIdentityIncludingMatchedChildren() {
        let first = task("较晚的任务", schedule: TaskSchedule(dueAt: date(20)))
        var child = task("匹配子任务", schedule: TaskSchedule(dueAt: date(18)))
        child.parentID = first.id
        let unscheduled = task("未安排", schedule: TaskSchedule(deadlineAt: date(22)))
        let result = TaskTimelineLayout.partition([first, child, first, unscheduled, unscheduled])
        XCTAssertEqual(result.scheduled.map(\.id), [first.id, child.id])
        XCTAssertEqual(result.unscheduled.map(\.id), [unscheduled.id], "截止日期不冒充安排日期")
    }

    func testViewportIncludesRecentPastAndTracksWidthAnchorAndNavigation() {
        var viewport = TaskTimelineViewport(anchorDate: now)
        let compact = viewport.range(availableWidth: 440, calendar: calendar)
        let wide = viewport.range(availableWidth: 1400, calendar: calendar)
        XCTAssertEqual(compact.start, date(15), "默认包含近期逾期任务，且不受最老任务拖动")
        XCTAssertGreaterThan(wide.dayCount, compact.dayCount)
        let original = viewport.anchorDate
        viewport.step(1, availableWidth: 440, calendar: calendar)
        XCTAssertEqual(viewport.anchorDate, calendar.date(byAdding: .day, value: compact.visibleDayCount, to: original))
        viewport.step(-1, availableWidth: 440, calendar: calendar)
        XCTAssertEqual(viewport.anchorDate, original)
        viewport.anchorDate = date(30)
        viewport.goToday(now, calendar: calendar)
        XCTAssertEqual(viewport.range(availableWidth: 440, calendar: calendar).start, compact.start)
    }

    func testDayWeekMonthScalesAlignCalendarAndChangeDensity() {
        let widths = TaskTimelineScale.allCases.map { scale -> CGFloat in
            let result = TaskTimelineViewport(anchorDate: now, scale: scale)
                .range(availableWidth: 600, calendar: calendar)
            XCTAssertLessThan(result.start, date(18))
            if scale == .week { XCTAssertEqual(calendar.component(.weekday, from: result.start), 2) }
            if scale == .month { XCTAssertEqual(calendar.component(.day, from: result.start), 1) }
            return result.dayWidth
        }
        XCTAssertEqual(widths, widths.sorted(by: >))
        XCTAssertEqual(Set(widths).count, 3)
    }

    func testMonthScaleKeepsTodayInsideFirstVisibleScreenAcrossMonthBoundary() {
        let today = date(16)
        let range = TaskTimelineViewport(anchorDate: today, scale: .month)
            .range(availableWidth: 804, calendar: calendar)
        let todayX = TaskTimelineLayout.coordinate(for: today, in: range, calendar: calendar)
        XCTAssertGreaterThanOrEqual(todayX, 0)
        XCTAssertLessThan(todayX + range.dayWidth, 804,
                          "对齐上个月月初不能把今天挤出初始可视区域")
        let bands = TaskTimelineLayout.headerSegments(in: range, scale: .month, calendar: calendar)
        XCTAssertEqual(bands.first?.dayCount, 7, "首个部分月份仍按真实月界线分段")
    }

    func testWeekAndMonthHeaderBandsCoverEveryDateOnce() {
        for scale in [TaskTimelineScale.week, .month] {
            let range = TaskTimelineViewport(anchorDate: now, scale: scale)
                .range(availableWidth: 650, calendar: calendar)
            let segments = TaskTimelineLayout.headerSegments(in: range, scale: scale, calendar: calendar)
            let indices = segments.flatMap { Array($0.startIndex..<($0.startIndex + $0.dayCount)) }
            XCTAssertEqual(indices, Array(0..<range.dayCount))
            XCTAssertGreaterThan(segments.dropFirst().first?.dayCount ?? 0, 1)
            let unit: Calendar.Component = scale == .week ? .weekOfYear : .month
            for segment in segments.dropFirst() {
                XCTAssertEqual(calendar.dateInterval(of: unit, for: segment.date)?.start, segment.date,
                               "部分首段之后仍严格对齐周/月边界")
            }
        }
    }

    func testAllDayBarsIncludeBothCalendarEndpoints() throws {
        let single = try XCTUnwrap(TaskTimelineLayout.bar(for: TaskSchedule(dueAt: date(19)),
                                                         in: range, calendar: calendar))
        let period = try XCTUnwrap(TaskTimelineLayout.bar(for: TaskSchedule(dueAt: date(19), dueEndAt: date(21)),
                                                         in: range, calendar: calendar))
        XCTAssertEqual(single.x, 88)
        XCTAssertEqual(single.width, 88)
        XCTAssertEqual(period.width, 3 * 88)
        let monthRange = TaskTimelineRange(start: date(18), dayCount: 60, visibleDayCount: 28, dayWidth: 18)
        XCTAssertEqual(TaskTimelineLayout.bar(for: TaskSchedule(dueAt: date(19)),
            in: monthRange, calendar: calendar)?.width, 18, "全天跨度不因月比例的最小命中宽度而多占一天")
    }

    func testTimedRangeUsesActualClockAndMidnightEndWithoutAnExtraDay() throws {
        let schedule = TaskSchedule(dueAt: date(18, 9), hasTime: true, dueEndAt: date(19))
        let geometry = try XCTUnwrap(TaskTimelineLayout.bar(for: schedule, in: range, calendar: calendar))
        XCTAssertEqual(geometry.x, 88 * 9 / 24, accuracy: 0.01)
        XCTAssertEqual(geometry.width, 88 * 15 / 24, accuracy: 0.01)
        XCTAssertEqual(schedule.dueEndAt, date(19))
    }

    func testBarsClipToTheNavigableRangeAndCanBeLocatedOutsideIt() throws {
        let spanning = TaskSchedule(dueAt: date(16), dueEndAt: date(19))
        let clipped = try XCTUnwrap(TaskTimelineLayout.bar(for: spanning, in: range, calendar: calendar))
        XCTAssertEqual(clipped.x, 0)
        XCTAssertEqual(clipped.width, 176)
        XCTAssertTrue(clipped.clippedStart)
        XCTAssertNil(TaskTimelineLayout.bar(for: TaskSchedule(dueAt: date(3)), in: range, calendar: calendar))
        let located = TaskTimelineViewport(anchorDate: date(3)).range(availableWidth: 400, calendar: calendar)
        XCTAssertNotNil(TaskTimelineLayout.bar(for: TaskSchedule(dueAt: date(3)), in: located, calendar: calendar))
    }

    func testBlankDateProducesAnAllDayPointWithoutImplicitEnd() {
        let schedule = TaskTimelineLayout.creation(at: 2 * 88 + 17, in: range, calendar: calendar)
        XCTAssertEqual(schedule.dueAt, date(20))
        XCTAssertFalse(schedule.hasTime)
        XCTAssertNil(schedule.dueEndAt)
    }

    @MainActor
    func testKanbanAndTimelineRenderWithoutFalling() {
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [], initialLists: ["工作"])
        let card = task("卡片", schedule: TaskSchedule(dueAt: date(19)))
        let groups = [TaskListGroup(kind: .plain, day: nil, tasks: [card], label: "进行中", sectionID: "s1")]
        let environment = AppEnvironment()
        // Keep the existing dirty change: kanban's child hosts need AppEnvironment.
        let kanban = NSHostingView(rootView: TaskKanbanView(groups: groups, workspace: workspace) { _ in }
            .environmentObject(environment))
        XCTAssertGreaterThan(kanban.fittingSize.height, 0)
        let timeline = NSHostingView(rootView: TaskTimelineView(tasks: [card], workspace: workspace,
            allowsCreation: true, onCreate: { _ in }, onSelect: { _ in }).frame(width: 900, height: 540))
        XCTAssertGreaterThan(timeline.fittingSize.height, 0)
    }

    private final class FrameProbe { var frames: [TaskTimelineRenderAnchor: CGRect] = [:] }

    @MainActor
    func testNativeHorizontalScrollKeepsLabelsFixedAndHeaderWithGrid() throws {
        let card = task("固定名称", schedule: TaskSchedule(dueAt: date(18)))
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [card], initialLists: ["工作"])
        let probe = FrameProbe()
        let host = NSHostingView(rootView: TaskTimelineView(tasks: [card], workspace: workspace,
            onSelect: { _ in }).frame(width: 900, height: 540)
            .onPreferenceChange(TaskTimelineRenderFramesKey.self) { probe.frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 540)
        defer { window.close() }
        let labelsBefore = try XCTUnwrap(probe.frames[.labels])
        let headerBefore = try XCTUnwrap(probe.frames[.header])
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first {
            ($0.documentView?.frame.width ?? 0) > $0.contentSize.width + 200 && $0.contentSize.width > 100
        })
        scroll.contentView.scroll(to: NSPoint(x: 180, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        InspectorPanelTestSupport.settle(window)
        let labelsAfter = try XCTUnwrap(probe.frames[.labels])
        let headerAfter = try XCTUnwrap(probe.frames[.header])
        let gridAfter = try XCTUnwrap(probe.frames[.grid])
        XCTAssertEqual(labelsAfter.minX, labelsBefore.minX, accuracy: 0.5)
        XCTAssertLessThan(headerAfter.minX, headerBefore.minX - 100)
        XCTAssertEqual(headerAfter.minX, gridAfter.minX, accuracy: 0.5)
        XCTAssertEqual(headerAfter.width, gridAfter.width, accuracy: 0.5)
    }

    @MainActor
    func testBlankGridClickCallsCreationWithoutWritingWorkspace() throws {
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [], initialLists: ["工作"])
        let probe = FrameProbe()
        var created: [TaskSchedule] = []
        let host = NSHostingView(rootView: TaskTimelineView(tasks: [], workspace: workspace,
            allowsCreation: true, onCreate: { created.append($0) }, onSelect: { _ in })
            .frame(width: 900, height: 540)
            .onPreferenceChange(TaskTimelineRenderFramesKey.self) { probe.frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 540)
        defer { window.close() }
        let grid = try XCTUnwrap(probe.frames[.grid])
        let target = CGRect(x: grid.minX + 2 * 88 + 12, y: grid.minY + 110, width: 2, height: 2)
        XCTAssertTrue(host.bounds.contains(target.origin), "The blank-date point must be visible: \(target), grid: \(grid)")
        try InspectorPanelTestSupport.click(target, in: host, window: window)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.dueAt, date(17))
        XCTAssertTrue(workspace.allTasks.isEmpty)
        XCTAssertFalse(workspace.canUndo)
    }

    @MainActor
    func testTaskBarAndBlankDateUseSeparateClickTargets() throws {
        let card = task("详情入口", schedule: TaskSchedule(dueAt: date(18)))
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [card], initialLists: ["工作"])
        let probe = FrameProbe()
        var selected: [UUID] = []
        var created: [TaskSchedule] = []
        let host = NSHostingView(rootView: TaskTimelineView(tasks: [card], workspace: workspace,
            allowsCreation: true, onCreate: { created.append($0) }, onSelect: { selected.append($0) })
            .frame(width: 900, height: 540)
            .onPreferenceChange(TaskTimelineRenderFramesKey.self) { probe.frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 540)
        defer { window.close() }
        let bar = try XCTUnwrap(probe.frames[.taskBar(card.id)])
        XCTAssertTrue(host.bounds.contains(CGPoint(x: bar.midX, y: bar.midY)),
                      "The actual task bar must be visible: \(bar)")
        try InspectorPanelTestSupport.click(bar, in: host, window: window)
        XCTAssertEqual(selected, [card.id])
        XCTAssertTrue(created.isEmpty, "The creation gesture only belongs to the background")
        let grid = try XCTUnwrap(probe.frames[.grid])
        let blank = CGRect(x: grid.minX + 16, y: bar.midY - 1, width: 2, height: 2)
        try InspectorPanelTestSupport.click(blank, in: host, window: window)
        XCTAssertEqual(created.count, 1, "同一任务行的空白日期仍可添加")
        XCTAssertEqual(created.first?.dueAt, date(15))
        XCTAssertEqual(selected, [card.id])
        XCTAssertFalse(workspace.canUndo)
    }

    @MainActor
    func testUnscheduledPoolClickOpensSharedDetailsOnFirstPress() throws {
        let card = task("未安排详情")
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [card], initialLists: ["工作"])
        let probe = FrameProbe()
        var selected: [UUID] = []
        let host = NSHostingView(rootView: TaskTimelineView(tasks: [card], workspace: workspace,
            onSelect: { selected.append($0) }).frame(width: 900, height: 540)
            .onPreferenceChange(TaskTimelineRenderFramesKey.self) { probe.frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 540)
        defer { window.close() }
        let cardFrame = try XCTUnwrap(probe.frames[.poolTask(card.id)])
        try InspectorPanelTestSupport.click(cardFrame, in: host, window: window)
        XCTAssertEqual(selected, [card.id])
        XCTAssertNil(workspace.task(for: card.id)?.schedule.dueAt)
        XCTAssertFalse(workspace.canUndo)
    }
}
