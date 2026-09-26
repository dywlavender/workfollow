import XCTest
@testable import WorkFollow

/// 习惯页纯展示函数（`HabitViewLogic`）：页头概览文案、打卡日历日期数组、
/// 统计行文案。日历列序为周一开头，与滴答打卡日历对齐。
final class HabitViewLogicTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: 页头概览文案

    func testOverviewTextJoinsTodayProgressAndLongestStreak() {
        XCTAssertEqual(
            HabitViewLogic.overviewText(todayDone: 2, todayTotal: 5, longestStreak: 6),
            "今日 2/5 · 连续最长 6 天")
        // 全部完成与空列表也要保持一行可读。
        XCTAssertEqual(
            HabitViewLogic.overviewText(todayDone: 3, todayTotal: 3, longestStreak: 12),
            "今日 3/3 · 连续最长 12 天")
        XCTAssertEqual(
            HabitViewLogic.overviewText(todayDone: 0, todayTotal: 0, longestStreak: 0),
            "今日 0/0 · 连续最长 0 天")
    }

    // MARK: 打卡日历日期数组

    func testMonthDatesStartOnMondayAndCoverWholeMonth() throws {
        // 2026-09-01 是周二：1 个 nil 占位 + 30 天。
        let september = HabitViewLogic.monthDates(inMonthOf: date(2026, 9, 26), calendar: calendar)
        XCTAssertEqual(september.count, 31)
        // [Date?].first 是 Date??（.some(nil)），flatMap 展平后再断言。
        XCTAssertNil(september.first.flatMap { $0 })
        let septemberDays = september.compactMap { $0 }
        XCTAssertEqual(septemberDays.count, 30)
        XCTAssertEqual(Habit.dayKey(septemberDays[0], calendar: calendar), "2026-09-01")
        XCTAssertEqual(Habit.dayKey(septemberDays[29], calendar: calendar), "2026-09-30")
        // 9 月 7 日是周一，应落在占位后的第 7 个位置（index 7）。
        XCTAssertEqual(Habit.dayKey(try XCTUnwrap(september[7]), calendar: calendar), "2026-09-07")

        // 2026-02-01 是周日：6 个 nil 占位 + 28 天。
        let february = HabitViewLogic.monthDates(inMonthOf: date(2026, 2, 14), calendar: calendar)
        XCTAssertEqual(february.count, 34)
        XCTAssertTrue(february.prefix(6).allSatisfy { $0 == nil })
        XCTAssertEqual(
            Habit.dayKey(try XCTUnwrap(february.compactMap { $0 }.first), calendar: calendar),
            "2026-02-01")

        // 2024 年闰年 2 月有 29 天；2024-02-01 是周四：3 个 nil 占位。
        let leapFebruary = HabitViewLogic.monthDates(inMonthOf: date(2024, 2, 5), calendar: calendar)
        XCTAssertEqual(leapFebruary.count, 32)
        XCTAssertTrue(leapFebruary.prefix(3).allSatisfy { $0 == nil })
        XCTAssertEqual(
            Habit.dayKey(try XCTUnwrap(leapFebruary.compactMap { $0 }.first), calendar: calendar),
            "2024-02-01")
        XCTAssertEqual(
            Habit.dayKey(try XCTUnwrap(leapFebruary.compactMap { $0 }.last), calendar: calendar),
            "2024-02-29")
    }

    func testMonthDatesReturnsStartOfDayDates() {
        let dates = HabitViewLogic.monthDates(inMonthOf: date(2026, 9, 26), calendar: calendar)
        for date in dates.compactMap({ $0 }) {
            XCTAssertEqual(date, calendar.startOfDay(for: date))
        }
    }

    // MARK: 统计行文案

    func testStatsTextJoinsTotalStreakAndMonthRate() {
        XCTAssertEqual(
            HabitViewLogic.statsText(totalCheckIns: 12, currentStreak: 3, monthRate: "85%"),
            "共打卡 12 次 · 连续 3 天 · 本月打卡率 85%")
        XCTAssertEqual(
            HabitViewLogic.statsText(totalCheckIns: 0, currentStreak: 0, monthRate: "—"),
            "共打卡 0 次 · 连续 0 天 · 本月打卡率 —")
    }

    func testMonthRateTextRoundsPercentAndFallsBackWhenUnscheduled() {
        XCTAssertEqual(HabitViewLogic.monthRateText(checked: 17, scheduled: 20), "85%")
        XCTAssertEqual(HabitViewLogic.monthRateText(checked: 2, scheduled: 3), "67%")  // 四舍五入
        XCTAssertEqual(HabitViewLogic.monthRateText(checked: 0, scheduled: 1), "0%")
        XCTAssertEqual(HabitViewLogic.monthRateText(checked: 5, scheduled: 5), "100%")
        // 区间内没有计划日时不显示 0%，显示占位符。
        XCTAssertEqual(HabitViewLogic.monthRateText(checked: 0, scheduled: 0), "—")
        XCTAssertEqual(HabitViewLogic.monthRateText(checked: 3, scheduled: 0), "—")
    }
}
