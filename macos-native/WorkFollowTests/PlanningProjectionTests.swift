import XCTest
@testable import WorkFollow

/// PlanningProjection：日历与四象限共用的纯投影。
///
/// 口径逐条对齐 Flutter `task_projection.dart` / `workspace_controller.dart`：
/// 哪天有哪条任务、一条任务覆盖几天、四象限怎么归类。日历固定 GMT、周日为
/// 每周第一天，与打勾月网格的周起点一致。
final class PlanningProjectionTests: XCTestCase {
    private var baseCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        // 故意设成周一开头：用例要证明日历页自己把它掰回周日，而不是继承系统设置。
        value.firstWeekday = 2
        return value
    }

    private var calendar: Calendar { PlanningProjection.sundayFirstWeek(baseCalendar) }

    /// 默认落在当天 00:00：投影吐出来的日期都是 `startOfDay`，用例里的期望值
    /// 必须与之同口径。需要「当天某个时点」的地方显式传 hour。
    private func day(_ year: Int, _ month: Int, _ day: Int,
                     hour: Int = 0, minute: Int = 0) -> Date {
        baseCalendar.date(from: DateComponents(year: year, month: month, day: day,
                                               hour: hour, minute: minute))!
    }

    private func makeTask(_ title: String,
                          dueAt: Date? = nil,
                          dueEndAt: Date? = nil,
                          deadlineAt: Date? = nil,
                          priority: TaskPriority = .none,
                          status: TaskStatus = .active,
                          deleted: Bool = false,
                          skipped: Bool = false,
                          abandoned: Bool = false,
                          converted: Bool = false,
                          parentID: UUID? = nil) -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        var task = Task(id: UUID(), title: title, list: .inbox, priority: priority,
                        schedule: TaskSchedule(dueAt: dueAt, dueEndAt: dueEndAt,
                                               deadlineAt: deadlineAt),
                        status: status, parentID: parentID, childOrder: 0,
                        createdAt: stamp, updatedAt: stamp)
        task.deletedAt = deleted ? stamp : nil
        task.skippedAt = skipped ? stamp : nil
        task.abandonedAt = abandoned ? stamp : nil
        if converted { task.convertedNoteID = UUID() }
        return task
    }

    // MARK: - 周首日与月网格

    func testSundayFirstWeekOverridesTheInjectedCalendar() {
        // 2026-09-23 是周三；周一开头的日历会把它所在周的首日算成 9/21。
        XCTAssertEqual(PlanningProjection.weekStart(containing: day(2026, 9, 23),
                                                     calendar: calendar),
                       day(2026, 9, 20))
        // 掰过之后列 0 一定是周日，七天连续。
        let week = PlanningProjection.weekDays(containing: day(2026, 9, 23), calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first, day(2026, 9, 20))
        XCTAssertEqual(week.last, day(2026, 9, 26))
        XCTAssertEqual(week[0].weekdayOf(calendar), 1, "列 0 必须是周日")
        XCTAssertEqual(week[6].weekdayOf(calendar), 7, "列 6 必须是周六")
    }

    func testMonthGridFollowsTheMonthsOwnRowCountInsteadOfPaddingToSix() {
        // 2026-02-01 是周日、当月 28 天 → 正好四周，不补第五、第六行（补出来的
        // 空白行会把日期压扁）。
        let february = PlanningProjection.monthGridDays(containing: day(2026, 2, 15),
                                                        calendar: calendar)
        XCTAssertEqual(february.count, 28)
        XCTAssertEqual(february.first, day(2026, 2, 1))
        XCTAssertEqual(february.last, day(2026, 2, 28))
        XCTAssertTrue(february.allSatisfy { calendar.component(.month, from: $0) == 2 })
    }

    func testMonthGridPadsWithNeighbouringMonthsAndStartsOnSunday() throws {
        // 2026-04-01 是周三 → 前面补 3 天上月收尾，30 天凑成 5 行 = 35 格。
        let april = PlanningProjection.monthGridDays(containing: day(2026, 4, 15),
                                                     calendar: calendar)
        XCTAssertEqual(april.count, 35)
        XCTAssertEqual(april.first, day(2026, 3, 29))
        XCTAssertEqual(try XCTUnwrap(april.first).weekdayOf(calendar), 1)
        XCTAssertEqual(april[3], day(2026, 4, 1))
        XCTAssertEqual(april.last, day(2026, 5, 2))
        // 每一行都从周日开始：每七格一跳，星期编号必然回到 1。
        for row in 0..<5 {
            XCTAssertEqual(april[row * 7].weekdayOf(calendar), 1)
        }
    }

    // MARK: - 某一天有哪些任务

    func testTasksOnDayTakesTasksStartingThatDay() {
        let tasks = [
            makeTask("今天开始", dueAt: day(2026, 9, 22, hour: 9)),
            makeTask("今天开始（晚些）", dueAt: day(2026, 9, 22, hour: 21)),
            makeTask("明天开始", dueAt: day(2026, 9, 23)),
            makeTask("没有安排", dueAt: nil, deadlineAt: day(2026, 9, 22)),
        ]
        let onDay = PlanningProjection.tasks(on: day(2026, 9, 22), from: tasks,
                                             calendar: calendar)
        XCTAssertEqual(onDay.map(\.title), ["今天开始", "今天开始（晚些）"],
                       "同一天内的时点不分组、也不重排：取数保持任务库自身的次序")
    }

    func testTasksOnDayDropsHiddenTasks() {
        let tasks = [
            makeTask("已删除", dueAt: day(2026, 9, 22), deleted: true),
            makeTask("已跳过", dueAt: day(2026, 9, 22), skipped: true),
            makeTask("已放弃", dueAt: day(2026, 9, 22), abandoned: true),
            makeTask("已转笔记", dueAt: day(2026, 9, 22), converted: true),
            makeTask("留下的", dueAt: day(2026, 9, 22)),
        ]
        XCTAssertEqual(PlanningProjection.tasks(on: day(2026, 9, 22), from: tasks,
                                                calendar: calendar).map(\.title),
                       ["留下的"])
    }

    func testSingleDayTasksExcludeTheBandLayer() {
        let tasks = [
            makeTask("单日", dueAt: day(2026, 9, 22)),
            makeTask("跨天", dueAt: day(2026, 9, 22), dueEndAt: day(2026, 9, 24)),
        ]
        let single = PlanningProjection.singleDayTasks(on: day(2026, 9, 22), from: tasks,
                                                       calendar: calendar)
        XCTAssertEqual(single.map(\.title), ["单日"],
                       "跨天任务整个交给色带层，格内再画一次就是同一天画两遍")
    }

    // MARK: - 跨天区间

    func testEndDayFallsBackToStartAndIgnoresDeadline() {
        let oneDay = makeTask("单日", dueAt: day(2026, 9, 22), deadlineAt: day(2026, 9, 30))
        XCTAssertEqual(PlanningProjection.endDay(of: oneDay, calendar: calendar),
                       day(2026, 9, 22))
        let ranged = makeTask("区间", dueAt: day(2026, 9, 22), dueEndAt: day(2026, 9, 25))
        XCTAssertEqual(PlanningProjection.endDay(of: ranged, calendar: calendar),
                       day(2026, 9, 25))
    }

    func testMultiDayTasksKeepsOnlyRunsIntersectingTheRow() {
        let tasks = [
            makeTask("上周的", dueAt: day(2026, 9, 10), dueEndAt: day(2026, 9, 12)),
            makeTask("正好贴左缘", dueAt: day(2026, 9, 17), dueEndAt: day(2026, 9, 20)),
            makeTask("穿过", dueAt: day(2026, 9, 21), dueEndAt: day(2026, 9, 24)),
            makeTask("下下周的", dueAt: day(2026, 9, 28), dueEndAt: day(2026, 9, 30)),
            makeTask("单日不算", dueAt: day(2026, 9, 22)),
        ]
        let runs = PlanningProjection.multiDayTasks(from: tasks,
                                                     first: day(2026, 9, 20),
                                                     last: day(2026, 9, 26),
                                                     calendar: calendar)
        XCTAssertEqual(runs.map(\.title), ["正好贴左缘", "穿过"])
    }

    func testMultiDayTasksOrderLongestRunFirstAmongEqualStarts() {
        let tasks = [
            makeTask("短的", dueAt: day(2026, 9, 20), dueEndAt: day(2026, 9, 21)),
            makeTask("长的", dueAt: day(2026, 9, 20), dueEndAt: day(2026, 9, 26)),
            makeTask("晚一天起", dueAt: day(2026, 9, 21), dueEndAt: day(2026, 9, 26)),
        ]
        let runs = PlanningProjection.multiDayTasks(from: tasks,
                                                     first: day(2026, 9, 20),
                                                     last: day(2026, 9, 26),
                                                     calendar: calendar)
        XCTAssertEqual(runs.map(\.title), ["长的", "短的", "晚一天起"],
                       "同日开始时长的在前：五天的带子压在两天带子之上")
    }

    // MARK: - 四象限归类

    func testImportantIsHighOrMediumOnly() {
        XCTAssertTrue(PlanningProjection.isImportant(makeTask("高", priority: .high)))
        XCTAssertTrue(PlanningProjection.isImportant(makeTask("中", priority: .medium)))
        XCTAssertFalse(PlanningProjection.isImportant(makeTask("低", priority: .low)))
        XCTAssertFalse(PlanningProjection.isImportant(makeTask("无", priority: .none)))
    }

    func testUrgentWindowIsTodayPlusThreeDaysInclusive() {
        let now = day(2026, 9, 22, hour: 10)
        func urgent(_ due: Date?) -> Bool {
            PlanningProjection.isUrgent(makeTask("t", dueAt: due), now: now, calendar: calendar)
        }
        XCTAssertFalse(urgent(nil), "没有安排日就谈不上紧急")
        XCTAssertTrue(urgent(day(2026, 9, 22)))
        XCTAssertTrue(urgent(day(2026, 9, 25)), "第 3 天仍在窗口内")
        XCTAssertFalse(urgent(day(2026, 9, 26)), "第 4 天不在窗口内")
        XCTAssertTrue(urgent(day(2026, 9, 20)), "过期的也算紧急")
        XCTAssertTrue(urgent(day(2026, 9, 22, hour: 23, minute: 59)),
                      "只比日期，不比时点")
    }

    func testUrgentIgnoresTheDeadline() {
        let now = day(2026, 9, 22, hour: 10)
        let task = makeTask("只有截止日", dueAt: nil, deadlineAt: day(2026, 9, 22))
        XCTAssertFalse(PlanningProjection.isUrgent(task, now: now, calendar: calendar))
    }

    func testQuadrantFollowsTheImportanceAndUrgencyTable() {
        let now = day(2026, 9, 22, hour: 10)
        func quadrant(_ priority: TaskPriority, _ due: Date?) -> Int {
            PlanningProjection.quadrant(makeTask("t", dueAt: due, priority: priority),
                                        now: now, calendar: calendar)
        }
        XCTAssertEqual(quadrant(.high, day(2026, 9, 22)), 0)
        XCTAssertEqual(quadrant(.medium, day(2026, 9, 25)), 0)
        XCTAssertEqual(quadrant(.high, day(2026, 9, 30)), 1)
        XCTAssertEqual(quadrant(.high, nil), 1)
        XCTAssertEqual(quadrant(.low, day(2026, 9, 22)), 2)
        XCTAssertEqual(quadrant(.none, day(2026, 9, 22)), 2)
        XCTAssertEqual(quadrant(.low, day(2026, 9, 30)), 3)
        XCTAssertEqual(quadrant(.none, nil), 3)
    }
}

private extension Date {
    /// 该日期在给定日历里的星期编号（周日 1 … 周六 7）。
    func weekdayOf(_ calendar: Calendar) -> Int { calendar.component(.weekday, from: self) }
}
