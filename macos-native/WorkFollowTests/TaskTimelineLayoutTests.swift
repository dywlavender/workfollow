import XCTest
import SwiftUI
@testable import WorkFollow

/// 时间线的**几何**（纯函数）+ 看板/时间线的**渲染冒烟**（NSHostingView，
/// 照 `TaskTreeGeometryContractTests` 的做法：视图至少要真的能渲染出来）。
final class TaskTimelineLayoutTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
    }

    private func task(_ title: String, dueDaysFromNow: Int?, spanDays: Int = 0,
                      list: String = "工作") -> Task {
        var schedule = TaskSchedule()
        if let dueDaysFromNow,
           let due = calendar.date(byAdding: .day, value: dueDaysFromNow,
                                   to: calendar.startOfDay(for: now)) {
            schedule = TaskSchedule(dueAt: due, hasTime: false,
                                    dueEndAt: spanDays > 0
                                        ? calendar.date(byAdding: .day, value: spanDays, to: due)
                                        : nil)
        }
        return Task(id: UUID(), title: title, list: TaskList(name: list), priority: .none,
                    schedule: schedule, parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
    }

    func testSingleDayTaskIsOneSpanAtItsOffset() {
        let rows = TaskTimelineLayout.rows(tasks: [task("今天", dueDaysFromNow: 0),
                                                  task("后天", dueDaysFromNow: 2)],
                                           now: now, calendar: calendar)
        XCTAssertEqual(rows.map(\.start), [0, 2])
        XCTAssertEqual(rows.map(\.span), [1, 1], "没有 dueEndAt 就是单日")
    }

    func testPeriodTaskSpanFollowsDueEnd() {
        let rows = TaskTimelineLayout.rows(tasks: [task("跨 3 天", dueDaysFromNow: 1, spanDays: 2)],
                                           now: now, calendar: calendar)
        XCTAssertEqual(rows.first?.start, 1)
        XCTAssertEqual(rows.first?.span, 3, "1 日 → 3 日 = 3 天（含首尾）")
    }

    func testRangeStartPullsBackForOverdueTasks() {
        let overdue = task("逾期 4 天", dueDaysFromNow: -4)
        let start = TaskTimelineLayout.rangeStart(tasks: [overdue], now: now, calendar: calendar)
        XCTAssertEqual(start, calendar.date(byAdding: .day, value: -4,
                                            to: calendar.startOfDay(for: now)),
                       "有逾期任务时范围起点提前，逾期条也在视野里")
        XCTAssertEqual(TaskTimelineLayout.rows(tasks: [overdue], now: now,
                                               calendar: calendar).first?.start, 0)
        XCTAssertEqual(TaskTimelineLayout.rangeStart(tasks: [task("今天", dueDaysFromNow: 0)],
                                                     now: now, calendar: calendar),
                       calendar.startOfDay(for: now), "没有逾期就从今天开始")
    }

    func testTasksWithoutDateStayOutOfTimeline() {
        let rows = TaskTimelineLayout.rows(tasks: [task("无日期", dueDaysFromNow: nil),
                                                  task("有日期", dueDaysFromNow: 1)],
                                           now: now, calendar: calendar)
        XCTAssertEqual(rows.count, 1, "无日期任务不进时间线")
        XCTAssertEqual(rows.first?.task.title, "有日期")
    }

    func testDuplicateTasksAppearOnce() {
        let shared = task("共享", dueDaysFromNow: 1)
        XCTAssertEqual(TaskTimelineLayout.rows(tasks: [shared, shared], now: now,
                                               calendar: calendar).count, 1,
                       "同一任务出现在多个分组里也只画一根条")
    }

    @MainActor
    func testKanbanAndTimelineRenderWithoutFalling() {
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [],
                                           initialLists: ["工作"])
        let groups = [TaskListGroup(kind: .plain, day: nil,
                                    tasks: [task("卡片", dueDaysFromNow: 1)],
                                    label: "进行中", sectionID: "s1")]
        let kanban = NSHostingView(rootView: TaskKanbanView(groups: groups, workspace: workspace) { _ in })
        XCTAssertGreaterThan(kanban.fittingSize.height, 0, "看板要真的渲染得出来")
        let timeline = NSHostingView(rootView: TaskTimelineView(groups: groups, workspace: workspace) { _ in })
        XCTAssertGreaterThan(timeline.fittingSize.height, 0, "时间线要真的渲染得出来")
    }
}
