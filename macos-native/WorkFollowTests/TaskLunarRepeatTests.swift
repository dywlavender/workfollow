import Foundation
import XCTest
@testable import WorkFollow

/// 农历重复：金标日期（Foundation 农历历换算，时区 Asia/Shanghai）、
/// 小月钳制、闰月策略、规则校验与 additive 解码。
final class TaskLunarRepeatTests: XCTestCase {
    private var calendar: Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return gregorian
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - 农历每年

    /// 金标：2026 春节（正月初一，2026-02-17）的下一次 = 2027-02-06 09:00。
    func testLunarYearlyNextAfterChineseNewYear() {
        let rule = RecurrenceRule(lunarMonth: 1, lunarDay: 1, lunarIsLeapMonth: false)
        let next = rule.nextOccurrence(after: date(2026, 2, 17), frequency: .lunarYearly, calendar: calendar)
        XCTAssertEqual(next, date(2027, 2, 6))
    }

    /// 链式推进：农历年长度 354/384 天浮动，2027 春节之后是 2028-01-26。
    func testLunarYearlyChain() {
        let rule = RecurrenceRule(lunarMonth: 1, lunarDay: 1, lunarIsLeapMonth: false)
        let first = rule.nextOccurrence(after: date(2026, 2, 17), frequency: .lunarYearly, calendar: calendar)
        let second = first.flatMap {
            rule.nextOccurrence(after: $0, frequency: .lunarYearly, calendar: calendar)
        }
        XCTAssertEqual(second, date(2028, 1, 26))
    }

    /// 端午（五月初五）：2026-06-19 → 2027-06-09，时刻分量原样保留。
    func testLunarYearlyKeepsClockTime() {
        let rule = RecurrenceRule(lunarMonth: 5, lunarDay: 5, lunarIsLeapMonth: false)
        let next = rule.nextOccurrence(after: date(2026, 6, 19, 14), frequency: .lunarYearly, calendar: calendar)
        XCTAssertEqual(next, date(2027, 6, 9, 14))
    }

    // MARK: - 农历每月

    /// 只按农历日推进，不锁月份：2026-09-30（八月二十）的下一次二十
    /// 是 2026-10-29（九月二十）。
    func testLunarMonthlyIgnoresMonth() {
        let rule = RecurrenceRule(lunarMonth: 8, lunarDay: 20, lunarIsLeapMonth: false)
        let next = rule.nextOccurrence(after: date(2026, 9, 30), frequency: .lunarMonthly, calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 29))
        let lunar = ChineseWorkCalendar.lunarCalendar(matching: calendar)
        XCTAssertEqual(lunar.dateComponents([.day], from: next!).day, 20)
    }

    // MARK: - 小月钳制

    /// 三十在小月钳制为当月最后一天：2026 农历年的腊月只有 29 天
    /// （2027-02-05 是除夕），目标三十落在 02-05，而不是跳进正月的三十。
    func testLunarDayThirtyClampsToShortMonth() {
        let rule = RecurrenceRule(lunarMonth: 12, lunarDay: 30, lunarIsLeapMonth: false)
        let next = rule.nextOccurrence(after: date(2026, 11, 15), frequency: .lunarYearly, calendar: calendar)
        XCTAssertEqual(next, date(2027, 2, 5))
        let lunar = ChineseWorkCalendar.lunarCalendar(matching: calendar)
        XCTAssertEqual(lunar.dateComponents([.day], from: next!).day, 29)
    }

    // MARK: - 闰月策略

    /// 平月目标永不落在闰月 occurrence：2028-06-23 起是闰五月，
    /// 五月初五的推进链全部是平月。
    func testNonLeapTargetNeverLandsOnLeapMonth() {
        let rule = RecurrenceRule(lunarMonth: 5, lunarDay: 5, lunarIsLeapMonth: false)
        let lunar = ChineseWorkCalendar.lunarCalendar(matching: calendar)
        var cursor = date(2026, 6, 19)
        for _ in 0..<4 {
            guard let next = rule.nextOccurrence(after: cursor, frequency: .lunarYearly, calendar: calendar) else {
                return XCTFail("农历每年推进提前中断")
            }
            XCTAssertNotEqual(lunar.dateComponents([.month, .day], from: next).isLeapMonth, true)
            cursor = next
        }
    }

    /// 闰月目标只落闰月：闰五月初五 = 2028-06-27；其间的 2027（无闰五月）跳过。
    func testLeapTargetSkipsYearsWithoutLeapMonth() {
        let rule = RecurrenceRule(lunarMonth: 5, lunarDay: 5, lunarIsLeapMonth: true)
        let next = rule.nextOccurrence(after: date(2026, 6, 19), frequency: .lunarYearly, calendar: calendar)
        XCTAssertEqual(next, date(2028, 6, 27))
        let lunar = ChineseWorkCalendar.lunarCalendar(matching: calendar)
        XCTAssertEqual(lunar.dateComponents([.month, .day], from: next!).isLeapMonth, true)
    }

    // MARK: - 校验与持久化

    func testNormalizedRejectsOutOfRangeLunarFields() {
        XCTAssertNil(RecurrenceRule(lunarMonth: 13).normalized(calendar: calendar))
        XCTAssertNil(RecurrenceRule(lunarDay: 31).normalized(calendar: calendar))
        XCTAssertNil(RecurrenceRule(lunarDay: 0).normalized(calendar: calendar))
        XCTAssertNotNil(RecurrenceRule(lunarMonth: 12, lunarDay: 30).normalized(calendar: calendar))
    }

    /// additive Codable：旧快照没有农历键照常解码；新字段编码往返一致。
    func testAdditiveCodingRoundTrip() throws {
        let legacy = try JSONDecoder().decode(RecurrenceRule.self, from: Data(#"{"interval":1}"#.utf8))
        XCTAssertNil(legacy.lunarMonth)
        XCTAssertNil(legacy.lunarDay)
        XCTAssertNil(legacy.lunarIsLeapMonth)

        let full = RecurrenceRule(lunarMonth: 5, lunarDay: 5, lunarIsLeapMonth: true)
        let data = try JSONEncoder().encode(full)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        XCTAssertEqual(decoded.lunarMonth, 5)
        XCTAssertEqual(decoded.lunarDay, 5)
        XCTAssertEqual(decoded.lunarIsLeapMonth, true)
    }

    /// TaskRepeat 新 case 的标题（列表行与 chip 的显示文案）。
    func testLunarRepeatTitles() {
        XCTAssertEqual(TaskRepeat.lunarYearly.title, "农历每年")
        XCTAssertEqual(TaskRepeat.lunarMonthly.title, "农历每月")
    }

    /// 农历命名：月份名（含闰）、日名、完整日期描述。
    func testLunarNaming() {
        XCTAssertEqual(ChineseWorkCalendar.lunarMonthName(1, isLeapMonth: false), "正月")
        XCTAssertEqual(ChineseWorkCalendar.lunarMonthName(11, isLeapMonth: false), "冬月")
        XCTAssertEqual(ChineseWorkCalendar.lunarMonthName(12, isLeapMonth: false), "腊月")
        XCTAssertEqual(ChineseWorkCalendar.lunarMonthName(5, isLeapMonth: true), "闰五月")
        XCTAssertEqual(ChineseWorkCalendar.lunarDayName(1), "初一")
        XCTAssertEqual(ChineseWorkCalendar.lunarDayName(30), "三十")
        XCTAssertEqual(ChineseWorkCalendar.lunarDateName(for: date(2026, 6, 19), calendar: calendar), "五月初五")
        XCTAssertEqual(ChineseWorkCalendar.lunarDateName(for: date(2028, 6, 27), calendar: calendar), "闰五月初五")
    }

    // MARK: - 农历自选日期

    /// 未来农历月枚举：含当前月、按序推进、月长与闰月标记正确。
    /// 2026-10-03 = 八月廿三；列表应从八月起，2028 年出现闰五月。
    func testUpcomingLunarMonths() {
        let months = ChineseWorkCalendar.upcomingLunarMonths(
            after: date(2026, 10, 3), calendar: calendar, count: 24)
        XCTAssertEqual(months.count, 24)
        XCTAssertEqual(months.first?.month, 8)
        XCTAssertEqual(months.first?.isLeapMonth, false)
        let lunar = ChineseWorkCalendar.lunarCalendar(matching: calendar)
        for info in months {
            // 每个条目的月首确实是农历初一。
            XCTAssertEqual(lunar.dateComponents([.day], from: info.firstDay).day, 1)
            let comps = lunar.dateComponents([.month], from: info.firstDay)
            XCTAssertEqual(comps.month, info.month)
            XCTAssertEqual(comps.isLeapMonth == true, info.isLeapMonth)
            XCTAssertEqual(lunar.range(of: .day, in: .month, for: info.firstDay)?.count,
                           info.dayCount)
            XCTAssertGreaterThanOrEqual(info.dayCount, 29)
            XCTAssertLessThanOrEqual(info.dayCount, 30)
        }
        // 相邻条目首日间隔 29 或 30 天，且严格递增。
        for (lhs, rhs) in zip(months, months.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: lhs.firstDay, to: rhs.firstDay).day ?? 0
            XCTAssertTrue((29...30).contains(gap), "gap \(gap)")
        }
        XCTAssertTrue(months.contains { $0.isLeapMonth }, "两年窗口内应出现闰月")
    }

    /// 自选落地语义：选"农历五月初五"→ 截止日跳到下一次五月初五
    /// （2026 端午已过 → 2027-06-09），锚定日同步后规则正是所选农历字段。
    @MainActor
    func testLunarPickJumpsDateAndDerivesRule() {
        let anchor = date(2026, 10, 3, 9)
        let task = Task(id: UUID(), title: "农历自选", recurrence: .never, recurrenceRule: nil,
                        reminderAt: nil, list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: anchor),
                        parentID: nil, childOrder: 0, createdAt: anchor, updatedAt: anchor)
        let model = TaskDateDraftModel(task: task, calendar: calendar,
                                       now: { self.date(2026, 10, 3, 10) }, deadline: false)
        let rule = RecurrenceRule(lunarMonth: 5, lunarDay: 5, lunarIsLeapMonth: false)
        // 引擎按 base(当天零点)的时刻推进;UI 里 select() 会把原时刻接回。
        let target = rule.nextOccurrence(after: calendar.startOfDay(for: date(2026, 10, 3, 10)),
                                         frequency: .lunarYearly, calendar: calendar)
        XCTAssertEqual(target, date(2027, 6, 9, 0))
        model.select(target!)
        model.syncRecurrenceAnchor()
        model.chooseFrequency(.lunarYearly)
        let draft = model.draftRule
        XCTAssertEqual(draft?.lunarMonth, 5)
        XCTAssertEqual(draft?.lunarDay, 5)
        XCTAssertEqual(draft?.lunarIsLeapMonth, false)
        // 时刻保留 9:00(原锚定日时刻),日期跳到 2027-06-09。
        XCTAssertEqual(model.recurrenceAnchorDate, date(2027, 6, 9, 9))
    }

// MARK: - 艾宾浩斯记忆法（阶段 2,标准曲线 1/2/4/7/15/30,滴答实测后校正常量）

/// 第 N 次完成(interval=N)→ 下一实例 = 到期日 + 序列[N-1];走完循环。
func testEbbinghausIntervalSequence() {
    var anchor = date(2026, 10, 4)
    let expected = ["2026-10-05", "2026-10-07", "2026-10-11", "2026-10-18", "2026-11-02", "2026-12-02"]
    for (index, _) in RecurrenceRule.ebbinghausIntervals.enumerated() {
        var stepRule = RecurrenceRule()
        stepRule.interval = index + 1  // TaskActions:第 N 次完成时 interval=N
        let next = stepRule.nextOccurrence(after: anchor, frequency: .ebbinghaus,
                                           calendar: calendar)
        XCTAssertNotNil(next, "step \(index)")
        let comps = calendar.dateComponents([.year, .month, .day], from: next!)
        let got = String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
        XCTAssertEqual(got, expected[index], "step \(index+1) (interval=\(index+1))")
        anchor = next!  // 真实完成流:从当前到期日继续推进
    }
    // 走完循环:第 7 次(interval=7)→ 序列[0] = +1
    var rule7 = RecurrenceRule()
    rule7.interval = 7
    let next = rule7.nextOccurrence(after: date(2026, 10, 4), frequency: .ebbinghaus, calendar: calendar)
    XCTAssertEqual(next, date(2026, 10, 5), "序列走完循环回 +1")
}

func testEbbinghausMigrationRoundTrip() throws {
    let data = try JSONEncoder().encode(TaskRepeat.ebbinghaus)
    let decoded = try JSONDecoder().decode(TaskRepeat.self, from: data)
    XCTAssertEqual(decoded, .ebbinghaus)
}

    /// AC-2.1 机器等效:重复选项全集含艾宾浩斯入口,标题唯一。
    func testEbbinghausAppearsInRepeatOptions() {
        let titles = TaskRepeat.allCases.map { $0.title }
        XCTAssertTrue(titles.contains("艾宾浩斯记忆法"), "重复选项缺少艾宾浩斯入口")
        XCTAssertEqual(Set(titles).count, titles.count, "重复选项标题有重复")
    }

}
