import XCTest
@testable import WorkFollow

/// 倒数纪念日的日期规则与投影。
///
/// 时区固定 GMT+8：农历日界跟着时区走，用别的时区会把「正月初一」挪到前一天，
/// 于是断言里那些参考图上的日期就不再成立。
final class CountdownEventTests: XCTestCase {
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
                           rule: CountdownRule, showsAge: Bool = false,
                           reminders: [Int] = CountdownEvent.defaultReminderOffsets) -> CountdownEvent {
        CountdownEvent(name: name, kind: kind, rule: rule, reminderOffsets: reminders,
                       showsAge: showsAge)
    }

    // MARK: 参考图上的三张卡片

    /// 春节：`130` / `距离 正月初一（2027/2/6）还有`。
    /// 这条同时钉住两件事——农历 1/1 落在 2027-02-06，以及副标题用的是**算出来的**
    /// 农历名而不是另存的一份字符串。
    func testSpringFestivalMatchesTheReferenceCard() {
        let event = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: projection.occurrence),
                       calendar.startOfDay(for: date(2, 6, 2027)))
        XCTAssertEqual(projection.days, 130)
        XCTAssertTrue(projection.isFuture)
        XCTAssertEqual(projection.caption, "距离 正月初一（2027/2/6）还有")
    }

    /// 已过去的一次性日期：`52` / `距离 2026/8/8 已经`。
    func testPastOneOffCountsForward() {
        let event = makeEvent("使用滴答清单", rule: .once(date(8, 8)))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(projection.days, 52)
        XCTAssertFalse(projection.isFuture, "已过去要显示「已经」")
        XCTAssertEqual(projection.caption, "距离 2026/8/8 已经")
    }

    /// 将来的一次性日期：`4` / `距离 2026/10/3 还有`。
    func testFutureOneOffCountsDown() {
        let event = makeEvent("周末", rule: .once(date(10, 3)))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(projection.days, 4)
        XCTAssertTrue(projection.isFuture)
        XCTAssertEqual(projection.caption, "距离 2026/10/3 还有")
    }

    // MARK: 公历每年

    func testSolarYearlyUsesThisYearWhenStillAhead() {
        let event = makeEvent("圣诞节", kind: .festival, rule: .solarYearly(month: 12, day: 25))
        XCTAssertEqual(event.occurrence(onOrAfter: today, calendar: calendar),
                       calendar.startOfDay(for: date(12, 25)))
    }

    func testSolarYearlyRollsToNextYearOncePassed() {
        let event = makeEvent("元旦", kind: .festival, rule: .solarYearly(month: 1, day: 1))
        XCTAssertEqual(event.occurrence(onOrAfter: today, calendar: calendar),
                       calendar.startOfDay(for: date(1, 1, 2027)))
    }

    /// 当天就是发生日：0 天且算「还有」。参考图没有这种态，这里按最直白的读法定。
    func testTodayIsZeroAndCountsAsUpcoming() {
        let event = makeEvent("今天", rule: .once(today))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(projection.days, 0)
        XCTAssertTrue(projection.isFuture)
        XCTAssertEqual(projection.caption, "距离 2026/9/29 还有")
    }

    // MARK: 农历

    func testMidAutumnResolvesToTheLunarDate() {
        let event = makeEvent("中秋节", kind: .festival, rule: .lunarYearly(month: 8, day: 15))
        XCTAssertEqual(event.occurrence(onOrAfter: today, calendar: calendar),
                       calendar.startOfDay(for: date(9, 15, 2027)))
    }

    /// 除夕不能写成固定的 `lunarYearly(12, 30)`：2027 年的除夕是腊月廿九。
    func testLunarEveIsTheDayBeforeNewYearAndLabelsItself() {
        let event = makeEvent("除夕", kind: .festival, rule: .lunarEve)
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: projection.occurrence),
                       calendar.startOfDay(for: date(2, 5, 2027)))
        XCTAssertEqual(projection.caption, "距离 腊月廿九（2027/2/5）还有")
    }

    /// 农历规则扫不到时要退回「今天」而不是编一个日期出来。
    func testUnresolvableLunarFallsBackToTheStartDay() {
        // 农历没有 13 月，扫描必然落空。
        let result = CountdownEvent.nextLunar(month: 13, day: 1, onOrAfter: today,
                                             calendar: calendar, searchLimit: 40)
        XCTAssertEqual(result, calendar.startOfDay(for: today))
    }

    // MARK: 农历文案

    func testLunarLabelsUseTheStandardChineseForms() {
        XCTAssertEqual(CountdownLunar.label(month: 1, day: 1), "正月初一")
        XCTAssertEqual(CountdownLunar.label(month: 1, day: 15), "正月十五")
        XCTAssertEqual(CountdownLunar.label(month: 5, day: 5), "五月初五")
        XCTAssertEqual(CountdownLunar.label(month: 8, day: 15), "八月十五")
        XCTAssertEqual(CountdownLunar.label(month: 12, day: 8), "腊月初八")
        XCTAssertEqual(CountdownLunar.label(month: 12, day: 29), "腊月廿九")
        XCTAssertEqual(CountdownLunar.label(month: 12, day: 30), "腊月三十")
        XCTAssertEqual(CountdownLunar.label(month: 1, day: 20), "正月二十")
        XCTAssertEqual(CountdownLunar.label(month: 11, day: 1), "冬月初一")
    }

    /// 公历文案不补零（参考图是 2027/2/6，不是 2027/02/06）。
    func testSolarTextDoesNotPad() {
        XCTAssertEqual(CountdownEvent.solarText(date(2, 6, 2027), calendar: calendar), "2027/2/6")
        XCTAssertEqual(CountdownEvent.solarText(date(10, 3), calendar: calendar), "2026/10/3")
    }

    // MARK: 类型的默认值

    func testKindDefaultsMatchTheReferencePanel() {
        // 参考图 4 张各开一种类型：纪念日 / 生日 → 「纪念」，倒数日 / 节日 → 「名称」。
        XCTAssertEqual(CountdownKind.anniversary.namePlaceholder, "纪念")
        XCTAssertEqual(CountdownKind.birthday.namePlaceholder, "纪念")
        XCTAssertEqual(CountdownKind.countdown.namePlaceholder, "名称")
        XCTAssertEqual(CountdownKind.festival.namePlaceholder, "名称")

        // 参考图：纪念日 / 倒数日的「重复」是「无」，生日 / 节日是「每年」。
        XCTAssertEqual(CountdownKind.anniversary.defaultRepeat, .never)
        XCTAssertEqual(CountdownKind.countdown.defaultRepeat, .never)
        XCTAssertEqual(CountdownKind.birthday.defaultRepeat, .yearly)
        XCTAssertEqual(CountdownKind.festival.defaultRepeat, .yearly)

        // 只有生日有「显示岁数」。
        XCTAssertTrue(CountdownKind.birthday.hasAgeOption)
        XCTAssertFalse(CountdownKind.anniversary.hasAgeOption)
        XCTAssertFalse(CountdownKind.festival.hasAgeOption)
    }

    func testRepeatValueIsDerivedFromTheRule() {
        XCTAssertEqual(makeEvent("a", rule: .once(today)).repeatValue, .never)
        XCTAssertEqual(makeEvent("b", rule: .solarYearly(month: 1, day: 1)).repeatValue, .yearly)
        XCTAssertEqual(makeEvent("c", rule: .lunarYearly(month: 1, day: 1)).repeatValue, .yearly)
        XCTAssertEqual(makeEvent("d", rule: .lunarEve).repeatValue, .yearly)
        XCTAssertEqual(makeEvent("e", rule: .birthday(month: 8, day: 20, birthYear: 2000)).repeatValue,
                       .yearly)
    }

    // MARK: 生日

    /// 生日每年都过：落点是**下一个**生日，不是出生那天。
    func testBirthdayRecursToTheNextBirthday() {
        let event = makeEvent("生日", kind: .birthday,
                              rule: .birthday(month: 8, day: 20, birthYear: 2000))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: projection.occurrence),
                       calendar.startOfDay(for: date(8, 20, 2027)))
        XCTAssertEqual(projection.days, 325)
        XCTAssertEqual(projection.caption, "距离 2027/8/20 还有")
    }

    /// 周岁：今年生日还没到就要减一。
    func testAgeIsFullYearsAndSubtractsBeforeThisYearsBirthday() {
        let passed = makeEvent("生日", kind: .birthday,
                               rule: .birthday(month: 8, day: 20, birthYear: 2000), showsAge: true)
        XCTAssertEqual(passed.ageText(asOf: today, calendar: calendar), "26 岁")

        let upcoming = makeEvent("生日", kind: .birthday,
                                 rule: .birthday(month: 12, day: 31, birthYear: 2000), showsAge: true)
        XCTAssertEqual(upcoming.ageText(asOf: today, calendar: calendar), "25 岁",
                       "2026-12-31 还没到，周岁要减一")
    }

    // MARK: 提醒

    func testReminderTextMatchesTheReference() {
        XCTAssertEqual(CountdownEvent.reminderText([0, 3 * 24 * 60]), "当天, 提前 3 天")
        XCTAssertEqual(CountdownEvent.reminderText([3 * 24 * 60, 0]), "当天, 提前 3 天",
                       "排序后拼接，与传入顺序无关")
        XCTAssertNil(CountdownEvent.reminderText([]))
        // 白名单外的值被丢掉，不会凭空出现在文案里。
        XCTAssertEqual(CountdownEvent.normalizedReminderOffsets([0, 0, 999]), [0])
    }

    // MARK: 生日岁数

    func testAgeOnlyAppliesToBirthdaysWithTheToggleOn() {
        let birthday = makeEvent("生日", kind: .birthday,
                                 rule: .birthday(month: 8, day: 20, birthYear: 2000), showsAge: true)
        XCTAssertEqual(birthday.ageText(asOf: today, calendar: calendar), "26 岁")

        let hidden = makeEvent("生日", kind: .birthday,
                               rule: .birthday(month: 8, day: 20, birthYear: 2000), showsAge: false)
        XCTAssertNil(hidden.ageText(asOf: today, calendar: calendar))

        let notBirthday = makeEvent("纪念日", kind: .anniversary,
                                    rule: .solarYearly(month: 8, day: 20), showsAge: true)
        XCTAssertNil(notBirthday.ageText(asOf: today, calendar: calendar),
                     "非生日类型不该有岁数")

        // 「重复 = 无」的生日：日期本身就是出生日，岁数照样算得出来。
        let noRepeat = makeEvent("生日", kind: .birthday,
                                 rule: .once(date(8, 20, 2000)), showsAge: true)
        XCTAssertEqual(noRepeat.ageText(asOf: today, calendar: calendar), "26 岁")
    }

    // MARK: 节日目录

    /// 目录里每一条都要能算出日期，且名字能被反查回来（编辑面板靠它回填）。
    func testFestivalCatalogIsSelfConsistent() {
        for option in CountdownFestival.all {
            let event = makeEvent(option.name, kind: .festival, rule: option.rule)
            let occurrence = event.occurrence(onOrAfter: today, calendar: calendar)
            XCTAssertGreaterThanOrEqual(occurrence, calendar.startOfDay(for: today),
                                        "\(option.name) 的落点不该在过去")
            XCTAssertLessThanOrEqual(
                calendar.dateComponents([.day], from: today, to: occurrence).day ?? 999, 800,
                "\(option.name) 的落点不该超过一个农历年")
            XCTAssertEqual(CountdownFestival.name(for: option.rule), option.name)
        }
    }

    func testFestivalCatalogNamesAreUnique() {
        let names = CountdownFestival.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
