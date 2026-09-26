import XCTest
@testable import WorkFollow

/// CalendarSpans：月/周视图跨天色带的纯逻辑——周行 lane 分配、跨周裁剪、
/// 格内让位计数与区间整体平移。日历固定 GMT、周日为每周第一天（列 0），
/// 与打勾月网格的周起点一致。
final class CalendarSpanTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 1
        return value
    }

    /// 2026-09-20 是周日：本周行 = 9/20（列 0）… 9/26（列 6）。
    private var week: [Date] {
        PlanningProjection.weekDays(containing: date(2026, 9, 23), calendar: calendar)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeTask(_ title: String, dueAt: Date?, deadlineAt: Date? = nil) -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        return Task(id: UUID(), title: title, list: .inbox, priority: .none,
                    schedule: TaskSchedule(dueAt: dueAt, deadlineAt: deadlineAt),
                    status: .active, parentID: nil, childOrder: 0,
                    createdAt: stamp, updatedAt: stamp)
    }

    // MARK: - lanes：单任务单 lane / 重叠分道

    func testSingleSpanTaskTakesLaneZeroAndCoversItsDays() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("长任务", dueAt: date(2026, 9, 21), deadlineAt: date(2026, 9, 23)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].task.title, "长任务")
        XCTAssertEqual(spans[0].startDayIndex, 1)
        XCTAssertEqual(spans[0].endDayIndex, 3)
        XCTAssertEqual(spans[0].spanDays, 3)
        XCTAssertEqual(spans[0].laneIndex, 0)
        XCTAssertFalse(spans[0].startClamped)
        XCTAssertFalse(spans[0].endClamped)
    }

    func testTwoOverlappingTasksStackIntoSeparateLanes() {
        // 传入顺序故意倒置：lane 布局必须按「最早开始优先、更长优先」自行排序。
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("后开的", dueAt: date(2026, 9, 22), deadlineAt: date(2026, 9, 25)),
            makeTask("先开的", dueAt: date(2026, 9, 21), deadlineAt: date(2026, 9, 24)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].task.title, "先开的")
        XCTAssertEqual(spans[0].laneIndex, 0)
        XCTAssertEqual(spans[0].startDayIndex, 1)
        XCTAssertEqual(spans[1].task.title, "后开的")
        XCTAssertEqual(spans[1].laneIndex, 1)
        XCTAssertEqual(spans[1].startDayIndex, 2)
    }

    func testTripleOverlapOccupiesThreeLanes() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("b", dueAt: date(2026, 9, 22), deadlineAt: date(2026, 9, 25)),
            makeTask("c", dueAt: date(2026, 9, 20), deadlineAt: date(2026, 9, 26)),
            makeTask("a", dueAt: date(2026, 9, 21), deadlineAt: date(2026, 9, 24)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 3)
        // 输出按 lane 排序；三道依次是 9/20 起最长的、9/21 的、9/22 的。
        XCTAssertEqual(spans.map(\.task.title), ["c", "a", "b"])
        XCTAssertEqual(spans.map(\.laneIndex), [0, 1, 2])
        XCTAssertEqual(spans.map(\.startDayIndex), [0, 1, 2])
    }

    func testNonOverlappingTasksShareLaneZero() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("前半周", dueAt: date(2026, 9, 20), deadlineAt: date(2026, 9, 21)),
            makeTask("后半周", dueAt: date(2026, 9, 23), deadlineAt: date(2026, 9, 24)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(spans.allSatisfy { $0.laneIndex == 0 }, "列区间不重叠的任务共用同一道")
    }

    // MARK: - lanes：跨周边界裁剪

    func testWeekBoundaryClampingMarksClampedEdgesAndCutsColumns() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("整周穿过", dueAt: date(2026, 9, 15), deadlineAt: date(2026, 9, 30)),
            makeTask("往后跨", dueAt: date(2026, 9, 24), deadlineAt: date(2026, 10, 1)),
            makeTask("从前面来", dueAt: date(2026, 9, 17), deadlineAt: date(2026, 9, 21)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 3)

        let through = spans.first { $0.task.title == "整周穿过" }
        XCTAssertEqual(through?.startClamped, true)
        XCTAssertEqual(through?.endClamped, true)
        XCTAssertEqual(through?.startDayIndex, 0)
        XCTAssertEqual(through?.endDayIndex, 6)
        XCTAssertEqual(through?.spanDays, 7)
        XCTAssertEqual(through?.continuesFromPreviousWeek, true)
        XCTAssertEqual(through?.continuesIntoNextWeek, true)

        let tail = spans.first { $0.task.title == "往后跨" }
        XCTAssertEqual(tail?.startClamped, false)
        XCTAssertEqual(tail?.endClamped, true)
        XCTAssertEqual(tail?.startDayIndex, 4)   // 9/24 周四
        XCTAssertEqual(tail?.endDayIndex, 6)

        let head = spans.first { $0.task.title == "从前面来" }
        XCTAssertEqual(head?.startClamped, true)
        XCTAssertEqual(head?.endClamped, false)
        XCTAssertEqual(head?.startDayIndex, 0)
        XCTAssertEqual(head?.endDayIndex, 1)     // 9/21 周一
    }

    func testTasksOutsideTheWeekAndShortWeeksProduceNoSpans() {
        let outside = CalendarSpans.lanes(for: week, tasks: [
            makeTask("上周", dueAt: date(2026, 9, 10), deadlineAt: date(2026, 9, 12)),
            makeTask("下下周", dueAt: date(2026, 9, 28), deadlineAt: date(2026, 9, 30)),
        ], calendar: calendar)
        XCTAssertTrue(outside.isEmpty)

        // 非 7 天的输入直接返回空，不产生错位色带。
        let shortWeek = CalendarSpans.lanes(for: Array(week.prefix(3)), tasks: [
            makeTask("长任务", dueAt: date(2026, 9, 21), deadlineAt: date(2026, 9, 23)),
        ], calendar: calendar)
        XCTAssertTrue(shortWeek.isEmpty)
    }

    // MARK: - 单日任务不出色带

    func testSingleDayTasksProduceNoSpan() {
        let tasks = [
            makeTask("只有安排日", dueAt: date(2026, 9, 22)),
            makeTask("截止日同天", dueAt: date(2026, 9, 22), deadlineAt: date(2026, 9, 22, hour: 23)),
            makeTask("截止日早于安排", dueAt: date(2026, 9, 22), deadlineAt: date(2026, 9, 20)),
            makeTask("只有截止日", dueAt: nil, deadlineAt: date(2026, 9, 22)),
        ]
        XCTAssertTrue(CalendarSpans.lanes(for: week, tasks: tasks, calendar: calendar).isEmpty)
        XCTAssertFalse(CalendarSpans.isMultiDay(tasks[1], calendar: calendar))
        XCTAssertNil(CalendarSpans.spanRange(of: tasks[2], calendar: calendar))
    }

    // MARK: - slotsOver（格内小条的让位数）

    func testSlotsOverCountsHighestCoveringLanePlusOne() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("c", dueAt: date(2026, 9, 20), deadlineAt: date(2026, 9, 26)),
            makeTask("a", dueAt: date(2026, 9, 21), deadlineAt: date(2026, 9, 24)),
            makeTask("b", dueAt: date(2026, 9, 22), deadlineAt: date(2026, 9, 25)),
        ], calendar: calendar)
        // 列 0 只有整周色带（lane 0）→ 让 1 格；列 2 三条全在 → 让 3 格。
        XCTAssertEqual(CalendarSpans.slotsOver(spans, column: 0), 1)
        XCTAssertEqual(CalendarSpans.slotsOver(spans, column: 2), 3)
        XCTAssertEqual(CalendarSpans.slotsOver(spans, column: 6), 1)
        XCTAssertEqual(CalendarSpans.slotsOver([], column: 2), 0)
    }

    func testSlotsOverUsesHighestLaneNotSpanCount() {
        // 某列上方是 lane 0 与 lane 2、没有 lane 1：让出的仍是最高 lane + 1 = 3。
        let lane0 = CalendarSpanBar(task: makeTask("底", dueAt: week[0], deadlineAt: week[1]),
                                    startDay: week[0], endDay: week[1],
                                    startDayIndex: 0, endDayIndex: 1,
                                    laneIndex: 0, startClamped: false, endClamped: false)
        let lane2 = CalendarSpanBar(task: makeTask("顶", dueAt: week[0], deadlineAt: week[1]),
                                    startDay: week[0], endDay: week[1],
                                    startDayIndex: 0, endDayIndex: 1,
                                    laneIndex: 2, startClamped: false, endClamped: false)
        XCTAssertEqual(CalendarSpans.slotsOver([lane0, lane2], column: 1), 3)
        XCTAssertEqual(CalendarSpans.slotsOver([lane0, lane2], column: 5), 0)
    }

    // MARK: - intervalShift（拖动色带 = 平移整个区间）

    func testIntervalShiftMovesWholeRangeByWholeWeek() throws {
        let task = makeTask("长任务", dueAt: date(2026, 9, 23, hour: 14), deadlineAt: date(2026, 9, 25))

        // 往后挪一周：拖到 9/30（同星期三），dueAt 保留原时点，截止日同移。
        let forward = try XCTUnwrap(CalendarSpans.intervalShift(
            task: task, to: date(2026, 9, 30, hour: 9), calendar: calendar))
        XCTAssertEqual(forward.dueAt, date(2026, 9, 30, hour: 14))
        XCTAssertEqual(forward.deadlineAt, calendar.startOfDay(for: date(2026, 10, 2)))

        // 往前挪一周：区间长度不变（9/23→9/25 仍是两天后截止）。
        let backward = try XCTUnwrap(CalendarSpans.intervalShift(
            task: task, to: date(2026, 9, 16), calendar: calendar))
        XCTAssertEqual(backward.dueAt, date(2026, 9, 16, hour: 14))
        XCTAssertEqual(backward.deadlineAt, calendar.startOfDay(for: date(2026, 9, 18)))
        XCTAssertEqual(calendar.dateComponents([.day], from: calendar.startOfDay(for: backward.dueAt),
                                               to: calendar.startOfDay(for: backward.deadlineAt!)).day, 2)
    }

    func testIntervalShiftReturnsNilForSingleDayTasks() {
        XCTAssertNil(CalendarSpans.intervalShift(
            task: makeTask("单日", dueAt: date(2026, 9, 23)),
            to: date(2026, 9, 30), calendar: calendar))
    }
}
