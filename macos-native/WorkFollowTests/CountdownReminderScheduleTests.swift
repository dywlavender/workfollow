import XCTest
@testable import WorkFollow

/// 倒计时记录的提醒排程。
///
/// 这里钉得最紧的是**符号约定**：任务的 `reminderOffsets` 是「相对到期时刻的
/// 分钟数」，提前用负数；倒计时用的是同一个字段名、同一个单位，但语义是
/// 「提前多少分钟」，**非负**。抄错一边不会报错，只会把「提前 3 天」安静地
/// 排成「推后 3 天」——偏移量本身合法，排程也会成功。
///
/// 时区固定 GMT+8：农历日界跟着时区走。
final class CountdownReminderScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        value.firstWeekday = 1
        return value
    }

    /// 参考图那一天：2026-09-29。
    private var today: Date { date(9, 29) }

    private func date(_ month: Int, _ day: Int, _ year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeEvent(_ name: String, kind: CountdownKind = .countdown,
                           rule: CountdownRule,
                           reminders: [Int] = CountdownEvent.defaultReminderOffsets) -> CountdownEvent {
        CountdownEvent(name: name, kind: kind, rule: rule, reminderOffsets: reminders)
    }

    private func fireDates(_ event: CountdownEvent) -> [Date] {
        ReminderSchedule.fireDates(for: event, calendar: calendar, now: today)
    }

    // MARK: 符号约定

    /// 「提前 N 天」要排到**更早**的时刻。
    ///
    /// 这是整套映射里唯一会静默出错的地方，所以断言直接盯住时间差的方向，
    /// 不去硬编码农历日期——硬编码会让这个用例在别的年份悄悄失去意义。
    func testEarlyOffsetsGoBackwardsNotForwards() {
        let event = makeEvent("春节", kind: .festival,
                              rule: .lunarYearly(month: 1, day: 1),
                              reminders: [0, 3 * CountdownEvent.minutesPerDay])
        let dates = fireDates(event)

        XCTAssertEqual(dates.count, 2)
        // 升序：早的那条在前。两条相差正好 3 天，且是**后者比前者晚**——
        // 反过来就是「提前」被实现成了「推后」。
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]),
                       3 * 24 * 3600,
                       "「提前 3 天」应当排在当天那条之前 3 天")
    }

    /// 当天那条落在发生日的 09:00——与任务的全天提醒同一时刻，也与编辑器
    /// 「提醒」下拉里挂着的 `09:00` 一致。
    func testOnTheDayReminderLandsAtNineOnTheOccurrenceDay() {
        let rule = CountdownRule.lunarYearly(month: 1, day: 1)
        let event = makeEvent("春节", kind: .festival, rule: rule, reminders: [0])
        let occurrence = CountdownEvent.occurrence(of: rule, onOrAfter: today,
                                                   calendar: calendar)

        let dates = fireDates(event)
        XCTAssertEqual(dates.count, 1)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: dates[0])
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(calendar.startOfDay(for: dates[0]),
                       calendar.startOfDay(for: occurrence))
    }

    /// 一周的那一档也要往后退 7 天，不是「除以 7」之类。
    func testWeekOffsetIsSevenDaysBack() {
        let event = makeEvent("春节", kind: .festival,
                              rule: .lunarYearly(month: 1, day: 1),
                              reminders: [0, 7 * CountdownEvent.minutesPerDay])
        let dates = fireDates(event)
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 7 * 24 * 3600)
    }

    // MARK: 不该排的情况

    func testArchivedEventIsNotScheduled() {
        var event = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        event.archivedAt = today
        XCTAssertTrue(fireDates(event).isEmpty, "已归档的记录不该再提醒")
    }

    func testEmptyOffsetsMeanNoNotification() {
        let event = makeEvent("无提醒", kind: .countdown, rule: .once(today), reminders: [])
        XCTAssertTrue(fireDates(event).isEmpty)
    }

    // MARK: 除夕

    /// 除夕（`.lunarEve`）也能排出提醒——它落在腊月廿九或三十，逐年不同，
    /// 排程必须走 `occurrence(of:)` 去算，不能自己拿月/日拼。
    func testLunarEveSchedulesOffItsNextOccurrence() {
        let event = makeEvent("除夕", kind: .festival, rule: .lunarEve, reminders: [0])
        let dates = fireDates(event)

        XCTAssertEqual(dates.count, 1, "除夕应当排得出提醒")
        let occurrence = CountdownEvent.occurrence(of: .lunarEve, onOrAfter: today,
                                                   calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: dates[0]),
                       calendar.startOfDay(for: occurrence))
    }

    // MARK: 签名与来源

    func testSignatureCarriesTheCountdownSource() {
        let event = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        let values = ReminderSignature.values([], countdowns: [event],
                                              calendar: calendar, now: today)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.source, .countdown)
        XCTAssertEqual(values.first?.title, "春节")
    }

    /// 两类记录的标识符前缀必须分开。
    ///
    /// `reconcile` 是「按前缀删掉自己的、再加回来」。共用前缀时，后跑的那轮会把
    /// 另一类刚排好的通知一起删掉——而签名比对看不出这件事，因为它是另一类算的。
    func testIdentifierPrefixesSeparateTasksFromCountdowns() {
        XCTAssertNotEqual(ReminderSignature.Source.task.identifierPrefix,
                          ReminderSignature.Source.countdown.identifierPrefix)
        XCTAssertEqual(ReminderSignature.Source.task.identifierPrefix, "task.")
        XCTAssertEqual(ReminderSignature.Source.countdown.identifierPrefix, "countdown.")
    }

    func testSignatureIgnoresCountdownsWithoutReminders() {
        let event = makeEvent("无提醒", kind: .countdown, rule: .once(today), reminders: [])
        XCTAssertTrue(ReminderSignature.values([], countdowns: [event],
                                               calendar: calendar, now: today).isEmpty)
    }
}
