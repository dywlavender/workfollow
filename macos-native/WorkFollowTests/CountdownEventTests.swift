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
        XCTAssertEqual(projection.captionPrefix, "距离 正月初一（2027/2/6）还有")
    }

    /// 已过去的一次性日期：`52` / `距离 2026/8/8 已经`。
    func testPastOneOffCountsForward() {
        let event = makeEvent("使用滴答清单", rule: .once(date(8, 8)))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(projection.days, 52)
        XCTAssertFalse(projection.isFuture, "已过去要显示「已经」")
        XCTAssertEqual(projection.captionPrefix, "距离 2026/8/8 已经")
    }

    /// 将来的一次性日期：`4` / `距离 2026/10/3 还有`。
    func testFutureOneOffCountsDown() {
        let event = makeEvent("周末", rule: .once(date(10, 3)))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(projection.days, 4)
        XCTAssertTrue(projection.isFuture)
        XCTAssertEqual(projection.captionPrefix, "距离 2026/10/3 还有")
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
        XCTAssertEqual(projection.captionPrefix, "距离 2026/9/29 还有")
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
        XCTAssertEqual(projection.captionPrefix, "距离 腊月廿九（2027/2/5）还有")
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
        XCTAssertEqual(projection.captionPrefix, "距离 2027/8/20 还有")
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

    // MARK: 主数字的单位（点卡片轮换）

    /// 参考图那三张：同一天、同一张卡，只是单位不同——
    /// `128` / `4月9天` / `18周2天`，而副标题三个都一样。
    func testSpringFestivalMagnitudeMatchesTheThreeReferenceShots() {
        let event = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        let october1 = date(10, 1)

        let day = event.magnitude(asOf: october1, unit: .day, calendar: calendar)
        XCTAssertEqual(day.text, "128")
        XCTAssertEqual(day.parts.map(\.unit), [""], "按天只有数字，不带单位字")

        let month = event.magnitude(asOf: october1, unit: .month, calendar: calendar)
        XCTAssertEqual(month.text, "4月9天")
        XCTAssertEqual(month.parts.map(\.value), [4, 9])

        let week = event.magnitude(asOf: october1, unit: .week, calendar: calendar)
        XCTAssertEqual(week.text, "18周2天")
        XCTAssertEqual(week.parts.map(\.value), [18, 2])

        // 换单位只动中间那个数字，副标题不动。
        XCTAssertEqual(event.projection(asOf: october1, calendar: calendar).captionPrefix,
                       "距离 正月初一（2027/2/6）还有")
    }

    // MARK: 完整句（只有一句话的位置用）

    /// `sentence(with:)` = 前缀 + 天数。卡片 tooltip 与已归档列表行**只有一句话的位置**，
    /// 必须用它；直接用前缀会断在「还有」，那两个落点当初就是这么坏的。
    func testSentenceCompletesTheCaptionPrefix() {
        let event = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        let october1 = date(10, 1)
        let projection = event.projection(asOf: october1, calendar: calendar)

        func sentence(_ unit: CountdownDisplayUnit) -> String {
            projection.sentence(with: event.magnitude(asOf: october1, unit: unit, calendar: calendar))
        }

        // 按天：画面上只有光秃秃的 `128`，读成一句话得补「天」，否则「还有 128」不成句。
        XCTAssertEqual(sentence(.day), "距离 正月初一（2027/2/6）还有 128 天")
        // 换单位句尾跟着换，且**不是**再拼一遍天数——用的是同一份 magnitude。
        XCTAssertEqual(sentence(.month), "距离 正月初一（2027/2/6）还有 4月9天")
        XCTAssertEqual(sentence(.week), "距离 正月初一（2027/2/6）还有 18周2天")

        // 完整句一定以前缀开头。断句缺陷的表现就是「前缀之后什么都没有」，
        // 这条断言把「句子至少不比前缀短」钉住。
        for unit in CountdownDisplayUnit.allCases {
            XCTAssertTrue(sentence(unit).hasPrefix(projection.captionPrefix),
                          "\(unit) 的完整句丢了前缀")
            XCTAssertGreaterThan(sentence(unit).count, projection.captionPrefix.count,
                                 "\(unit) 的完整句跟前缀一样长，说明天数没拼上")
        }
    }

    /// 已过去的方向（`已经`）同样要成句——`已经 52 天`，不是「已经」就没了。
    func testSentenceWorksForAPastDate() {
        let event = makeEvent("使用滴答清单", rule: .once(date(8, 8)))
        let projection = event.projection(asOf: today, calendar: calendar)
        XCTAssertEqual(projection.captionPrefix, "距离 2026/8/8 已经")
        XCTAssertEqual(projection.sentence(with: event.magnitude(asOf: today, unit: .day, calendar: calendar)),
                       "距离 2026/8/8 已经 52 天")
    }

    /// 「按月」要按**事件自己的历法**取自然月。春节是农历事件，落点 2027/2/6：
    /// 2026-10-01 → 2027-02-06 的农历差是 4 个月 9 天，公历差只有 4 个月 5 天。
    /// 这里拿一个落在**同一天**的公历事件做对照，它必须给出 4月5天——
    /// 两个数字不一样，才证明历法分支真的被走对了（都取公历会让这条挂掉）。
    func testMonthUsesTheEventsOwnCalendar() {
        let october1 = date(10, 1)

        let lunar = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        XCTAssertEqual(lunar.magnitude(asOf: october1, unit: .month, calendar: calendar).text,
                       "4月9天", "农历事件按农历月")

        let solar = makeEvent("公历", kind: .anniversary, rule: .solarYearly(month: 2, day: 6))
        XCTAssertEqual(solar.magnitude(asOf: october1, unit: .month, calendar: calendar).text,
                       "4月5天", "公历事件按公历月")
    }

    /// 规则里带 `lunar: true` 的非节日也要走农历月。
    func testLunarFlaggedRulesUseLunarMonths() {
        let monthly = makeEvent("农历每月", kind: .countdown,
                                rule: .monthly(day: 1, lunar: true, anchor: today))
        XCTAssertTrue(monthly.usesLunarCalendar)
        let solar = makeEvent("公历每月", kind: .countdown,
                              rule: .monthly(day: 1, lunar: false, anchor: today))
        XCTAssertFalse(solar.usesLunarCalendar)
        // 春节/除夕这两个固定走农历。
        XCTAssertTrue(makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
            .usesLunarCalendar)
        XCTAssertTrue(makeEvent("除夕", kind: .festival, rule: .lunarEve).usesLunarCalendar)
    }

    /// 不足一个更大单位就退回纯天数——免得出现「0月2天」「0周2天」。
    func testMagnitudeFallsBackToDaysBelowOneUnit() {
        let weekend = makeEvent("周末", rule: .once(date(10, 3)))   // 2 天
        XCTAssertEqual(weekend.magnitude(asOf: date(10, 1), unit: .day, calendar: calendar).text, "2")
        XCTAssertEqual(weekend.magnitude(asOf: date(10, 1), unit: .week, calendar: calendar).text, "2")
        XCTAssertEqual(weekend.magnitude(asOf: date(10, 1), unit: .month, calendar: calendar).text, "2")
    }

    /// 已过去的记录（落点在今天之前）也要能按月/按周算。
    /// 这条同时钉住一个坑：`dateComponents(from:to:)` 的方向反过来会得到**负数**
    /// （2026-10-01 → 2026-08-08 是 -1月-24天），所以实现里必须先排先后再算。
    func testMagnitudeWorksForPastEvents() {
        let past = makeEvent("使用滴答清单", rule: .once(date(8, 8)))
        let october1 = date(10, 1)

        XCTAssertEqual(past.magnitude(asOf: october1, unit: .day, calendar: calendar).text, "54")
        XCTAssertEqual(past.magnitude(asOf: october1, unit: .week, calendar: calendar).text, "7周5天")
        XCTAssertEqual(past.magnitude(asOf: october1, unit: .month, calendar: calendar).text, "1月23天")
    }

    /// 轮换顺序照参考图：天 → 月 → 周 → 天。
    func testDisplayUnitCyclesDayMonthWeek() {
        XCTAssertEqual(CountdownDisplayUnit.day.next, .month)
        XCTAssertEqual(CountdownDisplayUnit.month.next, .week)
        XCTAssertEqual(CountdownDisplayUnit.week.next, .day)
        XCTAssertEqual(CountdownDisplayUnit.allCases, [.day, .month, .week])
    }

    /// 读屏时按天那一档要补「天」，否则念出来是个没有单位的数。
    func testSpokenTextKeepsTheDayUnit() {
        let event = makeEvent("春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        XCTAssertEqual(event.magnitude(asOf: date(10, 1), unit: .day, calendar: calendar).spokenText,
                       "128 天")
        XCTAssertEqual(event.magnitude(asOf: date(10, 1), unit: .week, calendar: calendar).spokenText,
                       "18周2天", "带单位的照原样念")
    }

    /// 存量存档里没有 `displayUnit` 这个键 → 解出来 nil → 回退「天」。
    /// 用一个真实的编码结果删键来构造，免得手写 JSON 猜错 `CountdownRule` 的形状。
    func testLegacyJSONWithoutDisplayUnitFallsBackToDay() throws {
        var event = makeEvent("存量", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        event.displayUnit = .week
        let encoded = try JSONEncoder().encode(event)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "displayUnit"),
                        "键名变了这条测试就没意义了")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CountdownEvent.self, from: legacy)
        XCTAssertNil(decoded.displayUnit)
        XCTAssertEqual(decoded.effectiveDisplayUnit, .day)
        XCTAssertEqual(decoded.name, "存量", "其余字段照常解出来")
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

    // MARK: 农历的某一年（编辑器里「忽略年份」没勾）

    /// 农历日的名字要能覆盖 1…30。
    ///
    /// 这条是**回归测试**：`dayName` 原来把「初十」写成 `"初" + digits[10]`，
    /// 而 `digits` 只有 0…9 十个元素——下标越界，直接 SIGTRAP 崩进程。
    /// 之前没有界面会去枚举农历日名，所以一直没暴露；日期浮层的「日」下拉
    /// 一打开就崩。
    func testLunarDayNamesCoverTheWholeMonth() {
        XCTAssertEqual(CountdownLunar.dayName(1), "初一")
        XCTAssertEqual(CountdownLunar.dayName(9), "初九")
        XCTAssertEqual(CountdownLunar.dayName(10), "初十")
        XCTAssertEqual(CountdownLunar.dayName(11), "十一")
        XCTAssertEqual(CountdownLunar.dayName(19), "十九")
        XCTAssertEqual(CountdownLunar.dayName(20), "二十")
        XCTAssertEqual(CountdownLunar.dayName(21), "廿一")
        XCTAssertEqual(CountdownLunar.dayName(29), "廿九")
        XCTAssertEqual(CountdownLunar.dayName(30), "三十")
        // 逐个走一遍，越界就会崩在这里而不是在用户面前。
        for day in 1...30 {
            XCTAssertFalse(CountdownLunar.dayName(day).isEmpty, "第 \(day) 日")
        }
    }

    /// 农历 2027 年正月初一 = 公历 2027/2/6——与 `.lunarYearly(1, 1)` 同一个落点，
    /// 两处必须一致。
    func testLunarOnceResolvesToThatLunarYear() {
        let event = makeEvent("某年春节", rule: .lunarOnce(month: 1, day: 1, year: 2027))
        XCTAssertEqual(
            calendar.startOfDay(for: event.occurrence(onOrAfter: today, calendar: calendar)),
            calendar.startOfDay(for: date(2, 6, 2027)))
    }

    /// 已经过去的那一天不该被推到下一次——`.lunarOnce` 与 `.once` 同一口径，
    /// 卡片据此显示「已经 N 天」。
    func testLunarOnceInThePastStaysInThePast() {
        let event = makeEvent("过去的农历日", rule: .lunarOnce(month: 1, day: 1, year: 2026))
        XCTAssertLessThan(event.occurrence(onOrAfter: today, calendar: calendar),
                          calendar.startOfDay(for: today))
    }

    /// 落点必须真的落在它自称的那个农历月/日上。
    ///
    /// 这条钉的是 `lunarDate` 的实现路线：它从**公历**那年 1 月 1 日往上扫，
    /// 不能拿 `Calendar(identifier: .chinese)` 的 `.year` 组件直接构造日期——
    /// 那是 60 年一轮的干支年号，`DateComponents(year: 2027, …)` 根本落不到 2027 年。
    func testLunarOnceOccurrenceLandsOnTheRequestedLunarDay() {
        for (year, month, day) in [(2026, 8, 15), (2027, 1, 1), (2027, 5, 5), (2028, 12, 8)] {
            guard let resolved = CountdownEvent.lunarDate(year: year, month: month, day: day,
                                                          calendar: calendar) else {
                XCTFail("农历 \(year) 年 \(month)/\(day) 应当存在")
                continue
            }
            let parts = CountdownLunar.lunarComponents(of: resolved, calendar: calendar)
            XCTAssertEqual(parts?.month, month, "农历 \(year) 年 \(month)/\(day)")
            XCTAssertEqual(parts?.day, day, "农历 \(year) 年 \(month)/\(day)")
        }
    }

    /// 一次性、不进「重复」；日期行要**写出年份**——那正是它与 `.lunarYearly` 的差别。
    func testLunarOnceIsOneOffAndShowsItsYear() {
        let rule = CountdownRule.lunarOnce(month: 1, day: 1, year: 2027)
        XCTAssertFalse(rule.isRepeating)
        XCTAssertEqual(rule.repeatValue, .never)
        XCTAssertEqual(rule.dateText, "农历2027年正月初一")
        XCTAssertTrue(makeEvent("某年春节", rule: rule).usesLunarCalendar)
    }

    /// 新 case 要能落盘再读回来（规则是直接 `Codable` 合成的）。
    func testLunarOnceRoundTripsThroughCoding() throws {
        let rule = CountdownRule.lunarOnce(month: 5, day: 5, year: 2027)
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(CountdownRule.self, from: data), rule)
    }

    // MARK: 节日目录

    /// 目录里的规则必须两两不同。
    ///
    /// 重了的话两个节日名指向同一天，而 `name(for:)` 只返回第一个命中——
    /// 后一个名字永远显示不出来，也不会报错。
    func testFestivalCatalogueHasNoDuplicateRules() {
        let rules = CountdownFestival.all.map(\.rule)
        var unique: [CountdownRule] = []
        for rule in rules where !unique.contains(rule) { unique.append(rule) }
        XCTAssertEqual(unique.count, rules.count, "节日目录里有两条规则相同")
    }

    /// 目录不能是空的，而且每条都要能反查出名字。
    func testEveryCatalogueEntryIsReachableByName() {
        XCTAssertFalse(CountdownFestival.all.isEmpty)
        for option in CountdownFestival.all {
            XCTAssertEqual(CountdownFestival.name(for: option.rule), option.name)
        }
    }

    /// **除夕必须在目录里。**
    ///
    /// 这是 `.lunarEve` 唯一的构造来源：编辑器的 `draftBaseRule` 只会用「农历/公历
    /// 月/日」重建规则，而除夕的月/日是逐年变的（腊月廿九或三十），造不出来。
    /// 目录一旦漏了它，域模型里那条分支、`combinedRule` 里那段保留逻辑、
    /// 以及 `makeDraft` 里那个 case 就全都不可达了。
    func testCatalogueIsTheOnlyWayToReachLunarEve() {
        XCTAssertTrue(CountdownFestival.all.contains { $0.rule == .lunarEve },
                      "目录里没有除夕，.lunarEve 就没有任何构造路径")
        XCTAssertEqual(CountdownFestival.name(for: .lunarEve), "除夕")
    }

    /// 目录里的农历节日用 `.lunarYearly`，公历节日用 `.solarYearly`——
    /// 混了会让「春节」这类日子算到错误的落点上。
    func testCatalogueUsesTheMatchingCalendarForEachFestival() {
        XCTAssertEqual(CountdownFestival.name(for: .lunarYearly(month: 1, day: 1)), "春节")
        XCTAssertEqual(CountdownFestival.name(for: .solarYearly(month: 10, day: 1)), "国庆节")
    }
}
