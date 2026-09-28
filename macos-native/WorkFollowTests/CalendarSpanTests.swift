import XCTest
@testable import WorkFollow

/// CalendarSpans：月/周视图跨天色带的纯布局逻辑——周行 lane 分配、跨周裁剪、
/// 格内让位计数。
///
/// 日历固定 GMT、周日为每周第一天（列 0），与打勾月网格的周起点一致。
/// 区间用 `dueEndAt` 表达：`deadlineAt` 是独立的截止点，永远不定义范围。
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

    private func makeTask(_ title: String,
                          dueAt: Date?,
                          dueEndAt: Date? = nil,
                          deadlineAt: Date? = nil) -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        return Task(id: UUID(), title: title, list: .inbox, priority: .none,
                    schedule: TaskSchedule(dueAt: dueAt, dueEndAt: dueEndAt,
                                           deadlineAt: deadlineAt),
                    status: .active, parentID: nil, childOrder: 0,
                    createdAt: stamp, updatedAt: stamp)
    }

    // MARK: - lanes：单任务单 lane / 重叠分道

    func testSingleSpanTaskTakesLaneZeroAndCoversItsDays() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("长任务", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 23)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].task.title, "长任务")
        XCTAssertEqual(spans[0].fromColumn, 1)
        XCTAssertEqual(spans[0].toColumn, 3)
        XCTAssertEqual(spans[0].columnCount, 3)
        XCTAssertEqual(spans[0].lane, 0)
        XCTAssertTrue(spans[0].startsInRow)
        XCTAssertTrue(spans[0].endsInRow)
        XCTAssertFalse(spans[0].continuesFromPreviousRow)
        XCTAssertFalse(spans[0].continuesIntoNextRow)
    }

    func testTwoOverlappingTasksStackIntoSeparateLanes() {
        // 传入顺序故意倒置：lane 布局必须按「最早开始优先、更长优先」自行排序。
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("后开的", dueAt: date(2026, 9, 22), dueEndAt: date(2026, 9, 25)),
            makeTask("先开的", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 24)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].task.title, "先开的")
        XCTAssertEqual(spans[0].lane, 0)
        XCTAssertEqual(spans[0].fromColumn, 1)
        XCTAssertEqual(spans[1].task.title, "后开的")
        XCTAssertEqual(spans[1].lane, 1)
        XCTAssertEqual(spans[1].fromColumn, 2)
    }

    func testTripleOverlapOccupiesThreeLanes() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("b", dueAt: date(2026, 9, 22), dueEndAt: date(2026, 9, 25)),
            makeTask("c", dueAt: date(2026, 9, 20), dueEndAt: date(2026, 9, 26)),
            makeTask("a", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 24)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 3)
        // 输出按 lane 排序；三道依次是 9/20 起最长的、9/21 的、9/22 的。
        XCTAssertEqual(spans.map(\.task.title), ["c", "a", "b"])
        XCTAssertEqual(spans.map(\.lane), [0, 1, 2])
        XCTAssertEqual(spans.map(\.fromColumn), [0, 1, 2])
    }

    func testNonOverlappingTasksShareLaneZero() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("前半周", dueAt: date(2026, 9, 20), dueEndAt: date(2026, 9, 21)),
            makeTask("后半周", dueAt: date(2026, 9, 23), dueEndAt: date(2026, 9, 24)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 2)
        XCTAssertTrue(spans.allSatisfy { $0.lane == 0 }, "列区间不重叠的任务共用同一道")
    }

    // MARK: - lanes：跨周边界裁剪

    func testWeekBoundaryClampingFlattensEdgesAndCutsColumns() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("整周穿过", dueAt: date(2026, 9, 15), dueEndAt: date(2026, 9, 30)),
            makeTask("往后跨", dueAt: date(2026, 9, 24), dueEndAt: date(2026, 10, 1)),
            makeTask("从前面来", dueAt: date(2026, 9, 17), dueEndAt: date(2026, 9, 21)),
        ], calendar: calendar)
        XCTAssertEqual(spans.count, 3)

        let through = spans.first { $0.task.title == "整周穿过" }
        XCTAssertEqual(through?.fromColumn, 0)
        XCTAssertEqual(through?.toColumn, 6)
        XCTAssertEqual(through?.columnCount, 7)
        XCTAssertEqual(through?.continuesFromPreviousRow, true)
        XCTAssertEqual(through?.continuesIntoNextRow, true)
        // 区间的两端都不在本行，所以这一份既不带勾选框也不带时刻。
        XCTAssertEqual(through?.startsInRow, false)
        XCTAssertEqual(through?.endsInRow, false)

        let tail = spans.first { $0.task.title == "往后跨" }
        XCTAssertEqual(tail?.fromColumn, 4)   // 9/24 周四
        XCTAssertEqual(tail?.toColumn, 6)
        XCTAssertEqual(tail?.continuesFromPreviousRow, false)
        XCTAssertEqual(tail?.continuesIntoNextRow, true)
        XCTAssertEqual(tail?.startsInRow, true)
        XCTAssertEqual(tail?.endsInRow, false)

        let head = spans.first { $0.task.title == "从前面来" }
        XCTAssertEqual(head?.fromColumn, 0)
        XCTAssertEqual(head?.toColumn, 1)     // 9/21 周一
        XCTAssertEqual(head?.continuesFromPreviousRow, true)
        XCTAssertEqual(head?.continuesIntoNextRow, false)
    }

    func testTasksOutsideTheWeekProduceNoSpan() {
        let outside = CalendarSpans.lanes(for: week, tasks: [
            makeTask("上周", dueAt: date(2026, 9, 10), dueEndAt: date(2026, 9, 12)),
            makeTask("下下周", dueAt: date(2026, 9, 28), dueEndAt: date(2026, 9, 30)),
        ], calendar: calendar)
        XCTAssertTrue(outside.isEmpty)
    }

    /// 行不是 7 天时返回空而不抛错。原版在这里 `throw`，因为它假定调用方已经
    /// 量好了一行；视图层不该因为一次量错就崩掉整页，所以原生改成空结果。
    func testShortWeekReturnsEmptyInsteadOfThrowing() {
        let shortWeek = CalendarSpans.lanes(for: Array(week.prefix(3)), tasks: [
            makeTask("长任务", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 23)),
        ], calendar: calendar)
        XCTAssertTrue(shortWeek.isEmpty)
    }

    // MARK: - 单日任务不出色带

    func testSingleDayAndDeadlineOnlyTasksProduceNoSpan() {
        let tasks = [
            makeTask("只有安排日", dueAt: date(2026, 9, 22)),
            makeTask("时刻跨天但同一天", dueAt: date(2026, 9, 22, hour: 14),
                     dueEndAt: date(2026, 9, 22, hour: 23)),
            makeTask("区间倒置", dueAt: date(2026, 9, 22), dueEndAt: date(2026, 9, 20)),
            makeTask("只有截止日", dueAt: nil, deadlineAt: date(2026, 9, 22)),
            makeTask("截止日不定义区间", dueAt: date(2026, 9, 22),
                     deadlineAt: date(2026, 9, 25)),
        ]
        XCTAssertTrue(CalendarSpans.lanes(for: week, tasks: tasks, calendar: calendar).isEmpty)
    }

    func testSpansMultipleDaysIgnoresTheClockAndTheDeadline() {
        // 同一天的 14:00–15:00 是收工时刻，不是第二天。
        XCTAssertFalse(PlanningProjection.spansMultipleDays(
            makeTask("当天收工", dueAt: date(2026, 9, 22, hour: 14),
                     dueEndAt: date(2026, 9, 22, hour: 15)), calendar: calendar))
        // 只有截止日期不构成区间。
        XCTAssertFalse(PlanningProjection.spansMultipleDays(
            makeTask("只有截止日", dueAt: date(2026, 9, 22), deadlineAt: date(2026, 9, 25)),
            calendar: calendar))
        XCTAssertTrue(PlanningProjection.spansMultipleDays(
            makeTask("真跨天", dueAt: date(2026, 9, 22), dueEndAt: date(2026, 9, 23)),
            calendar: calendar))
    }

    // MARK: - slotsOver（格内小条的让位数）

    func testSlotsOverCountsHighestCoveringLanePlusOne() {
        let spans = CalendarSpans.lanes(for: week, tasks: [
            makeTask("c", dueAt: date(2026, 9, 20), dueEndAt: date(2026, 9, 26)),
            makeTask("a", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 24)),
            makeTask("b", dueAt: date(2026, 9, 22), dueEndAt: date(2026, 9, 25)),
        ], calendar: calendar)
        // 列 0 只有整周色带（lane 0）→ 让 1 格；列 2 三条全在 → 让 3 格。
        XCTAssertEqual(CalendarSpans.slotsOver(spans, column: 0), 1)
        XCTAssertEqual(CalendarSpans.slotsOver(spans, column: 2), 3)
        XCTAssertEqual(CalendarSpans.slotsOver(spans, column: 6), 1)
        XCTAssertEqual(CalendarSpans.slotsOver([], column: 2), 0)
    }

    func testSlotsOverUsesHighestLaneNotSpanCount() {
        // 某列上方是 lane 0 与 lane 2、没有 lane 1：让出的仍是最高 lane + 1 = 3。
        let lane0 = CalendarSpan(task: makeTask("底", dueAt: week[0], dueEndAt: week[1]),
                                 startDay: week[0], endDay: week[1],
                                 fromColumn: 0, toColumn: 1, lane: 0,
                                 startsInRow: true, endsInRow: true)
        let lane2 = CalendarSpan(task: makeTask("顶", dueAt: week[0], dueEndAt: week[1]),
                                 startDay: week[0], endDay: week[1],
                                 fromColumn: 0, toColumn: 1, lane: 2,
                                 startsInRow: true, endsInRow: true)
        XCTAssertEqual(CalendarSpans.slotsOver([lane0, lane2], column: 1), 3)
        XCTAssertEqual(CalendarSpans.slotsOver([lane0, lane2], column: 5), 0)
    }

    // MARK: - 过滤

    func testLanesDropDeletedSkippedAbandonedAndConvertedTasks() {
        let stamp = Date(timeIntervalSince1970: 0)
        var deleted = makeTask("已删除", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 24))
        deleted.deletedAt = stamp
        var skipped = makeTask("已跳过", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 24))
        skipped.skippedAt = stamp
        var abandoned = makeTask("已放弃", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 24))
        abandoned.abandonedAt = stamp
        var converted = makeTask("已转笔记", dueAt: date(2026, 9, 21), dueEndAt: date(2026, 9, 24))
        converted.convertedNoteID = UUID()

        let spans = CalendarSpans.lanes(for: week,
                                        tasks: [deleted, skipped, abandoned, converted],
                                        calendar: calendar)
        XCTAssertTrue(spans.isEmpty)
    }
}
