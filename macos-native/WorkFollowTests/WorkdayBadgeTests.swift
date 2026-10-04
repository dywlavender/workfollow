import XCTest
@testable import WorkFollow

/// 日历上的「休 / 班」徽标与节日文案。
///
/// 这里量的是**国务院公布的那张表**在界面上的表现，不是重算一遍假期：期望值全部
/// 来自《国务院办公厅关于2026年部分节假日安排的通知》（国办发明电〔2025〕7号），
/// 以及滴答 2026-10 月历页的实测（哪天有绿「休」、哪天有红「班」）。
///
/// 单独一个文件是因为它守的是一条**界面契约**：`ChineseWorkCalendar` 的表对不对
/// 由 `RecurrenceEngineTests` 守（那是重复规则的输入），这里守的是这张表翻成记号
/// 之后有没有漏、有没有多。
final class WorkdayBadgeTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func badge(_ year: Int, _ month: Int, _ day: Int) -> WorkdayBadgeKind? {
        WorkdayBadgeKind(ChineseWorkCalendar.override(for: date(year, month, day),
                                                      calendar: calendar))
    }

    // MARK: - 放假（休）

    /// 2026 年七段假期，逐段核对首日、末日与中段。
    ///
    /// 首尾日是最容易错一格的地方：表里存的是「起始日 + 天数」，而末日的判断是
    /// `date < start + length`——差一天不会崩，只会让假期少一天或多一天。
    func testEveryHolidayPeriodIsMarkedRest() {
        let periods: [(name: String, start: (Int, Int), length: Int)] = [
            ("元旦", (1, 1), 3),
            ("春节", (2, 15), 9),
            ("清明节", (4, 4), 3),
            ("劳动节", (5, 1), 5),
            ("端午节", (6, 19), 3),
            ("中秋节", (9, 25), 3),
            ("国庆节", (10, 1), 7),
        ]
        for period in periods {
            let start = date(2026, period.start.0, period.start.1)
            for offset in [0, period.length / 2, period.length - 1] {
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                let parts = calendar.dateComponents([.month, .day], from: day)
                XCTAssertEqual(
                    WorkdayBadgeKind(ChineseWorkCalendar.override(for: day, calendar: calendar)),
                    .rest,
                    "\(period.name) 第 \(offset + 1) 天（\(parts.month!)月\(parts.day!)日）应当是「休」")
            }
        }
    }

    /// 假期结束的次日不是假期。国庆放到 10/7，10/8 是普通周四。
    func testDayAfterHolidayHasNoBadge() {
        XCTAssertEqual(badge(2026, 10, 7), .rest)
        XCTAssertNil(badge(2026, 10, 8))
    }

    // MARK: - 补班（班）

    /// 2026 年全部 6 个调休上班日（表里 11 条是 2025 + 2026 两年合计）。
    func testEveryMakeupWorkdayIsMarkedMakeup() {
        let makeup: [(Int, Int)] = [
            (1, 4),                                  // 元旦调休
            (2, 14), (2, 28),                        // 春节调休
            (5, 9),                                  // 劳动节调休
            (9, 20), (10, 10),                       // 国庆调休
        ]
        XCTAssertEqual(makeup.count, 6, "2026 年的调休上班日就是这 6 天")
        for (month, day) in makeup {
            XCTAssertEqual(badge(2026, month, day), .makeup,
                           "\(month)月\(day)日 是国务院指定的上班日")
        }
    }

    /// 补班日落在周末，所以它**必须**有徽标——这正是这个记号存在的理由：
    /// 周六周日按常识是休息，只有官方调休能让它变成工作日。
    func testMakeupDaysFallOnWeekends() {
        for (month, day) in [(1, 4), (2, 14), (2, 28), (5, 9), (9, 20), (10, 10)] {
            let weekday = calendar.component(.weekday, from: date(2026, month, day))
            XCTAssertTrue(weekday == 1 || weekday == 7,
                          "\(month)月\(day)日 应当是周末（否则不必印「班」）")
        }
    }

    // MARK: - 不该有徽标的日子

    /// 普通周末没有徽标。这是刻意的：周末是常识，印成「休」会把真正要提醒的
    /// 补班日淹掉。滴答同此口径（实测 10/17 周六无徽标）。
    func testOrdinaryWeekendHasNoBadge() {
        XCTAssertNil(badge(2026, 10, 17))   // 周六
        XCTAssertNil(badge(2026, 10, 18))   // 周日
        XCTAssertNil(badge(2026, 10, 24))   // 周六
    }

    /// 普通工作日也没有徽标。
    func testOrdinaryWorkdayHasNoBadge() {
        XCTAssertNil(badge(2026, 10, 12))   // 周一
        XCTAssertNil(badge(2026, 10, 15))   // 周四
    }

    /// 没有官方表的年份退化成「周一到周五上班」，于是**一个徽标都不该有**。
    ///
    /// 这一条守的是"降级要安静"：宁可什么都不标，也不能拿上一年的表去标下一年
    /// ——2027 年的假期安排与 2026 年不同，套用会给出错误的放假提示。
    func testYearWithoutTableShowsNoBadgeAtAll() {
        for (month, day) in [(1, 1), (2, 16), (5, 1), (10, 1), (10, 10)] {
            XCTAssertNil(badge(2027, month, day),
                         "2027 年没有官方表，不该出现徽标")
        }
    }

    // MARK: - 记号的翻译

    /// `override` 的三态与记号的对应关系。翻译只在一处，这条用例钉住它。
    func testBadgeKindMapping() {
        XCTAssertEqual(WorkdayBadgeKind(true), .makeup)
        XCTAssertEqual(WorkdayBadgeKind(false), .rest)
        XCTAssertNil(WorkdayBadgeKind(Optional<Bool>.none))
    }

    // MARK: - 节日文案（月网格与日期弹层必须同源）

    /// 月网格用的合并来源：两个表各出一半。
    func testMonthGridFestivalSourceCoversBothTables() {
        // 只在公历/农历表里：重阳节是农历九月初九，2026 年落在 10 月 18 日
        // （滴答 2026-10 月历页在这一格印的就是「重阳节」）。
        XCTAssertEqual(
            LunarCalendarService.festivalLabelIncludingStatutory(for: date(2026, 10, 18),
                                                                  calendar: calendar),
            "重阳节")
        // 只在法定表里：清明节是节气不是农历节日，公历/农历表里没有它。
        XCTAssertNil(LunarCalendarService.festivalLabel(for: date(2026, 4, 5), calendar: calendar))
        XCTAssertEqual(
            LunarCalendarService.festivalLabelIncludingStatutory(for: date(2026, 4, 5),
                                                                  calendar: calendar),
            "清明节")
        // 两张表都有的日子只能出一个名字，不能拼成两个。
        XCTAssertEqual(
            LunarCalendarService.festivalLabelIncludingStatutory(for: date(2026, 10, 1),
                                                                  calendar: calendar),
            "国庆节")
        XCTAssertEqual(
            LunarCalendarService.festivalLabelIncludingStatutory(for: date(2026, 2, 17),
                                                                  calendar: calendar),
            "春节")
        // 普通日子仍然是 nil——合并不能让每一天都有名字。
        XCTAssertNil(LunarCalendarService.festivalLabelIncludingStatutory(for: date(2026, 10, 12),
                                                                          calendar: calendar))
    }

    /// 浮层用的补漏来源：**只**给主表没有的，否则两层会各印一遍。
    func testGapLabelOnlyReturnsWhatTheGridCannotDraw() {
        XCTAssertEqual(
            LunarCalendarService.statutoryFestivalGapLabel(for: date(2026, 4, 5),
                                                            calendar: calendar),
            "清明节")
        // 国庆节主表已经有了，补漏必须让开。
        XCTAssertNil(LunarCalendarService.statutoryFestivalGapLabel(for: date(2026, 10, 1),
                                                                    calendar: calendar))
        XCTAssertNil(LunarCalendarService.statutoryFestivalGapLabel(for: date(2026, 10, 18),
                                                                     calendar: calendar))
    }

    /// 非本月的日子照样带徽标：9 月 27 日是中秋假期最后一天，在 10 月的网格里
    /// 是上月收尾的格子，但它就是放假——滴答在那里也画了绿徽标。
    func testOutOfMonthDayStillCarriesBadge() {
        XCTAssertEqual(badge(2026, 9, 27), .rest)
    }
}
