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
        // 补的四种节奏也要能反查回下拉里的选项。
        XCTAssertEqual(makeEvent("f", rule: .daily(lunar: false, anchor: today)).repeatValue, .daily)
        XCTAssertEqual(makeEvent("g", rule: .weekly(weekday: 3, lunar: false,
                                                    anchor: today)).repeatValue, .weekly)
        XCTAssertEqual(makeEvent("h", rule: .monthly(day: 1, lunar: true,
                                                     anchor: today)).repeatValue, .monthly)
        XCTAssertEqual(makeEvent("i", rule: .interval(days: 10, lunar: false,
                                                      anchor: today)).repeatValue, .custom)
    }

    // MARK: 重复下拉的六个选项（参考图）

    /// 参考图的「重复」下拉：无 / 每天 / 每周（周二）/ 每月（初一）/ 每年（正月初一）/ 自定义。
    /// 括注是算出来的——这一天是 2026-09-29（周二），日期是 农历正月初一。
    func testRepeatLabelsMatchTheReferenceDropdown() {
        let festival = CountdownRule.lunarYearly(month: 1, day: 1)
        func label(_ value: CountdownRepeat, rule: CountdownRule? = nil) -> String {
            CountdownRepeat.label(value, rule: rule, asOf: today, calendar: calendar)
        }
        XCTAssertEqual(label(.never), "无")
        XCTAssertEqual(label(.daily), "每天")
        XCTAssertEqual(label(.weekly), "每周（周二）", "2026-09-29 是周二")
        XCTAssertEqual(label(.monthly, rule: festival), "每月（初一）")
        XCTAssertEqual(label(.yearly, rule: festival), "每年（正月初一）")
        XCTAssertEqual(label(.custom), "自定义")

        // 顺序也要照参考图，`allCases` 直接驱动下拉的排列。
        XCTAssertEqual(CountdownRepeat.allCases,
                       [.never, .daily, .weekly, .monthly, .yearly, .custom])
        // 没有锚点时只退化到没有括注，不能编一个出来。
        XCTAssertEqual(label(.monthly), "每月")
        XCTAssertEqual(label(.yearly), "每年")
    }

    func testWeekdayNamesCoverTheWholeWeek() {
        XCTAssertEqual(CountdownRepeat.weekdayName(1), "周日")
        XCTAssertEqual(CountdownRepeat.weekdayName(3), "周二")
        XCTAssertEqual(CountdownRepeat.weekdayName(7), "周六")
    }

    // MARK: 提醒下拉（参考图）

    /// 参考图的「提醒」下拉带提醒时刻：`当天 (09:00)` … `提前 1 周 (09:00)`。
    func testReminderOptionLabelsMatchTheReferenceDropdown() {
        XCTAssertEqual(CountdownEvent.reminderChoices,
                       [0, 1440, 2880, 4320, 10080], "当天 / 1 天 / 2 天 / 3 天 / 1 周")
        XCTAssertEqual(CountdownEvent.reminderOptionLabel(0), "当天 (09:00)")
        XCTAssertEqual(CountdownEvent.reminderOptionLabel(1440), "提前 1 天 (09:00)")
        XCTAssertEqual(CountdownEvent.reminderOptionLabel(2880), "提前 2 天 (09:00)")
        XCTAssertEqual(CountdownEvent.reminderOptionLabel(4320), "提前 3 天 (09:00)")
        XCTAssertEqual(CountdownEvent.reminderOptionLabel(10080), "提前 1 周 (09:00)")
        // 行里不带时刻（参考图的「添加」面板是 `当天, 提前 3 天`）。
        XCTAssertEqual(CountdownEvent.reminderLabel(10080), "提前 1 周")
    }

    /// 归一化改成「只收整天」之后，名单外的整天值不能再被静默吃掉。
    func testReminderNormalizationKeepsWholeDayOffsets() {
        XCTAssertEqual(CountdownEvent.normalizedReminderOffsets([30 * 1440]), [30 * 1440],
                       "旧的「提前 30 天」不在预设名单里，但它是整天，要留着")
        XCTAssertEqual(CountdownEvent.normalizedReminderOffsets([1440, 0, 1440]), [0, 1440])
        XCTAssertEqual(CountdownEvent.normalizedReminderOffsets([-1440, 60]), [],
                       "负值与不足一天的值丢掉")
    }

    // MARK: 显示下拉（参考图）

    /// 参考图的「显示」下拉：标题「在智能清单中」+ 五项。
    func testSmartListDisplayOptionsMatchTheReferenceDropdown() {
        XCTAssertEqual(CountdownSmartListDisplay.groupTitle, "在智能清单中")
        XCTAssertEqual(CountdownSmartListDisplay.allCases.map(\.title),
                       ["当天显示", "提前 3 天显示", "提前 7 天显示", "一直显示", "不显示"])
        XCTAssertEqual(CountdownSmartListDisplay.sameDay.rowText, "在智能清单中当天显示")
        XCTAssertEqual(CountdownSmartListDisplay.sevenDaysBefore.rowText, "在智能清单中提前 7 天显示")
        XCTAssertEqual(CountdownSmartListDisplay.never.rowText, "不在智能清单中显示")
        XCTAssertFalse(CountdownSmartListDisplay.never.showsInSmartList)
        XCTAssertTrue(CountdownSmartListDisplay.always.showsInSmartList)
    }

    // MARK: 新增的四种节奏

    func testDailyLandsOnToday() {
        let rule = CountdownRule.daily(lunar: false, anchor: date(9, 1))
        XCTAssertEqual(CountdownEvent.occurrence(of: rule, onOrAfter: today, calendar: calendar),
                       calendar.startOfDay(for: today))
    }

    /// 2026-09-29 是周二：要周二就是今天，要周四是两天后。
    func testWeeklyLandsOnTheRequestedWeekday() {
        let tuesday = CountdownEvent.occurrence(
            of: .weekly(weekday: 3, lunar: false, anchor: today),
            onOrAfter: today, calendar: calendar)
        XCTAssertEqual(tuesday, calendar.startOfDay(for: today))

        let thursday = CountdownEvent.occurrence(
            of: .weekly(weekday: 5, lunar: false, anchor: today),
            onOrAfter: today, calendar: calendar)
        XCTAssertEqual(thursday, calendar.startOfDay(for: date(10, 1)))
    }

    func testSolarMonthlyLandsOnTheRequestedDayOfMonth() {
        let rule = CountdownRule.monthly(day: 1, lunar: false, anchor: today)
        let occurrence = CountdownEvent.occurrence(of: rule, onOrAfter: today, calendar: calendar)
        XCTAssertEqual(occurrence, calendar.startOfDay(for: date(10, 1)))
    }

    func testLunarMonthlyLandsOnTheFirstDayOfALunarMonth() {
        let rule = CountdownRule.monthly(day: 1, lunar: true, anchor: today)
        let occurrence = CountdownEvent.occurrence(of: rule, onOrAfter: today, calendar: calendar)
        XCTAssertGreaterThanOrEqual(occurrence, calendar.startOfDay(for: today))
        XCTAssertEqual(CountdownLunar.lunarComponents(of: occurrence, calendar: calendar)?.day, 1)
    }

    /// 自定义间隔从锚点按整数倍前进：9/1 起每 10 天，9/29 之后的第一跳是 10/1。
    func testCustomIntervalStepsFromTheAnchor() {
        let rule = CountdownRule.interval(days: 10, lunar: false, anchor: date(9, 1))
        XCTAssertEqual(CountdownEvent.occurrence(of: rule, onOrAfter: today, calendar: calendar),
                       calendar.startOfDay(for: date(10, 1)))
    }

    // MARK: 「显示」字段的存量兼容

    /// 加 `smartListDisplay` 之前落盘的 JSON 没有这个键，解出来要回退到老字段，
    /// 不能把已有记录的「显示」读没。
    ///
    /// 注意 `Optional` 的合成编码用的是 `encodeIfPresent`——值为 nil 时**键直接不写**，
    /// 所以「键不存在」这条路径不是要另外构造的，它就是没选过「显示」时的正常产物。
    func testEventsWithoutTheDisplayFieldFallBackToTheLegacyFlag() throws {
        func decode(_ event: CountdownEvent) throws -> CountdownEvent {
            try JSONDecoder().decode(CountdownEvent.self, from: try JSONEncoder().encode(event))
        }

        let legacy = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(object["smartListDisplay"], "nil 不写进 JSON，旧文件天然兼容")
        XCTAssertNotNil(object["showsInSmartList"], "老字段还在写，存量读的是它")

        let shown = try decode(legacy)
        XCTAssertNil(shown.smartListDisplay)
        XCTAssertEqual(shown.effectiveSmartListDisplay, .sameDay)

        var hidden = legacy
        hidden.showsInSmartList = false
        XCTAssertEqual(try decode(hidden).effectiveSmartListDisplay, .never)
    }

    /// 新字段本身要能往返，而且写入时把老字段同步过去。
    func testDisplayFieldRoundTripsAndSyncsTheLegacyFlag() throws {
        let event = CountdownEvent(name: "春节", kind: .festival,
                                   rule: .lunarYearly(month: 1, day: 1),
                                   smartListDisplay: .sevenDaysBefore)
        XCTAssertTrue(event.showsInSmartList, "「提前 7 天显示」也是要显示的")
        let decoded = try JSONDecoder().decode(CountdownEvent.self,
                                               from: try JSONEncoder().encode(event))
        XCTAssertEqual(decoded.smartListDisplay, .sevenDaysBefore)
        XCTAssertEqual(decoded.effectiveSmartListDisplay, .sevenDaysBefore)

        let hidden = CountdownEvent(name: "春节", kind: .festival,
                                    rule: .lunarYearly(month: 1, day: 1),
                                    smartListDisplay: .never)
        XCTAssertFalse(hidden.showsInSmartList)
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
