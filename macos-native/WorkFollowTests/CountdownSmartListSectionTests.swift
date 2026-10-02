import XCTest
@testable import WorkFollow

/// 「显示」（`smartListDisplay`）真正生效的地方：智能清单里那节「倒数纪念日」。
///
/// 这一套钉的是**判据**（什么时候进清单、进哪一行、按什么顺序），
/// 不碰界面。时区固定 GMT+8，与 `CountdownEventTests` 同口径。
final class CountdownSmartListSectionTests: XCTestCase {
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

    /// 造一条「落点在今天之后第 `days` 天」的记录。
    private func event(_ name: String, daysFromToday days: Int,
                       display: CountdownSmartListDisplay?,
                       kind: CountdownKind = .countdown,
                       archived: Bool = false) -> CountdownEvent {
        let target = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today))!
        return CountdownEvent(name: name, kind: kind, rule: .once(target),
                              smartListDisplay: display,
                              archivedAt: archived ? today : nil)
    }

    // MARK: - 五个选项各自的窗口

    /// 默认档：**只在当天**进清单。这也是参照图唯一观察到的那一态。
    func testSameDayOnlyShowsOnTheDayItself() {
        let event = event("当天", daysFromToday: 0, display: .sameDay)
        XCTAssertTrue(CountdownSmartListProjection.isVisible(event, daysUntil: 0))
        XCTAssertFalse(CountdownSmartListProjection.isVisible(event, daysUntil: 1))
        XCTAssertFalse(CountdownSmartListProjection.isVisible(event, daysUntil: 2))
    }

    /// 「提前 3 天显示」= 从 3 天前开始显示，**0…3 共 4 天**（取舍，见实现里的注释）。
    func testThreeDaysBeforeCoversTheWholeLeadWindow() {
        let event = event("提前三天", daysFromToday: 0, display: .threeDaysBefore)
        for days in 0...3 {
            XCTAssertTrue(CountdownSmartListProjection.isVisible(event, daysUntil: days),
                          "第 \(days) 天应当在窗口内")
        }
        XCTAssertFalse(CountdownSmartListProjection.isVisible(event, daysUntil: 4))
    }

    func testSevenDaysBeforeCoversTheWholeLeadWindow() {
        let event = event("提前七天", daysFromToday: 0, display: .sevenDaysBefore)
        for days in 0...7 {
            XCTAssertTrue(CountdownSmartListProjection.isVisible(event, daysUntil: days),
                          "第 \(days) 天应当在窗口内")
        }
        XCTAssertFalse(CountdownSmartListProjection.isVisible(event, daysUntil: 8))
    }

    func testAlwaysShowsRegardlessOfDistance() {
        let event = event("一直显示", daysFromToday: 0, display: .always)
        XCTAssertTrue(CountdownSmartListProjection.isVisible(event, daysUntil: 0))
        XCTAssertTrue(CountdownSmartListProjection.isVisible(event, daysUntil: 300))
    }

    func testNeverNeverShows() {
        let event = event("不显示", daysFromToday: 0, display: .never)
        XCTAssertFalse(CountdownSmartListProjection.isVisible(event, daysUntil: 0))
        XCTAssertFalse(CountdownSmartListProjection.isVisible(event, daysUntil: 1))
    }

    /// 已经过去的落点一律不进清单，**含「一直显示」**。
    /// 这条是刻意钉住的取舍：参照图没观察到过期记录，放进去会让一条早就过完的
    /// 单次记录永远挂在「今天」。
    func testPastOccurrencesStayOutEvenForAlways() {
        for display in CountdownSmartListDisplay.allCases {
            let event = event("过期", daysFromToday: -3, display: display)
            XCTAssertFalse(CountdownSmartListProjection.isVisible(event, daysUntil: -1),
                           "\(display) 不该把过期记录放进清单")
        }
    }

    // MARK: - 存量记录（没有 smartListDisplay 这个键）

    /// 老字段 `showsInSmartList == false` 的存量记录，解出来 `smartListDisplay` 是 nil，
    /// 必须回退成「不显示」——加字段不能把已有记录的「显示」读成相反的意思。
    func testLegacyRecordWithoutNewKeyFallsBackToTheOldFlag() {
        let hidden = CountdownEvent(name: "旧的隐藏", rule: .once(today), showsInSmartList: false)
        XCTAssertNil(hidden.smartListDisplay)
        XCTAssertFalse(CountdownSmartListProjection.isVisible(hidden, daysUntil: 0))

        let shown = CountdownEvent(name: "旧的显示", rule: .once(today), showsInSmartList: true)
        XCTAssertEqual(shown.effectiveSmartListDisplay, .sameDay)
        XCTAssertTrue(CountdownSmartListProjection.isVisible(shown, daysUntil: 0))
    }

    // MARK: - 整节

    /// 参照图那一态：落点就是今天、默认档 → 进小节，标签是「今天」。
    func testSectionMatchesTheReferenceScreenshot() {
        let springFestival = event("春节", daysFromToday: 0, display: nil, kind: .festival)
        let section = CountdownSmartListProjection.section(events: [springFestival],
                                                           now: today, calendar: calendar)
        XCTAssertEqual(CountdownSmartListSection.title, "倒数纪念日")
        XCTAssertEqual(section.count, 1)
        XCTAssertEqual(section.entries.first?.name, "春节")
        XCTAssertEqual(section.entries.first?.daysUntil, 0)
        XCTAssertEqual(section.entries.first?.relativeLabel, "今天")
        XCTAssertEqual(section.entries.first?.id, springFestival.id)
    }

    /// 空小节返回 `.empty`——调用方据此**整节不渲染**，
    /// 否则屏幕上会出现「倒数纪念日 0」这种噪音。
    func testNoVisibleRecordsGivesEmptySection() {
        let hidden = event("不显示", daysFromToday: 0, display: .never)
        let faraway = event("很远", daysFromToday: 30, display: .sameDay)
        let section = CountdownSmartListProjection.section(events: [hidden, faraway],
                                                           now: today, calendar: calendar)
        XCTAssertTrue(section.isEmpty)
        XCTAssertEqual(section.count, 0)
    }

    /// 已归档的记录不进智能清单。
    func testArchivedRecordsAreExcluded() {
        let archived = event("归档了", daysFromToday: 0, display: .always, archived: true)
        let section = CountdownSmartListProjection.section(events: [archived],
                                                           now: today, calendar: calendar)
        XCTAssertTrue(section.isEmpty)
    }

    /// 近的在前；同一天保持传入顺序（store 已经排好，这里不另立一套）。
    func testEntriesAreOrderedNearestFirstAndStableWithinADay() {
        let day5 = event("五天", daysFromToday: 5, display: .sevenDaysBefore)
        let day1a = event("一天甲", daysFromToday: 1, display: .sevenDaysBefore)
        let todayEvent = event("今天", daysFromToday: 0, display: .sevenDaysBefore)
        let day1b = event("一天乙", daysFromToday: 1, display: .sevenDaysBefore)

        let section = CountdownSmartListProjection.section(
            events: [day5, day1a, todayEvent, day1b], now: today, calendar: calendar)
        XCTAssertEqual(section.entries.map(\.name), ["今天", "一天甲", "一天乙", "五天"])
    }

    /// 重复类记录的落点永远在未来，不会因为「过期一律不进」这条被误伤。
    func testRepeatingRecordRollsForwardAndStaysVisible() {
        // 春节：农历正月初一，2026-09-29 的下一次落在 2027-02-06（130 天）。
        let springFestival = CountdownEvent(
            name: "春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1),
            smartListDisplay: .always)
        let section = CountdownSmartListProjection.section(events: [springFestival],
                                                           now: today, calendar: calendar)
        XCTAssertEqual(section.count, 1)
        XCTAssertEqual(section.entries.first?.daysUntil, 130)

        // 换成「当天显示」就该消失了——落点远在 130 天之外。
        let sameDay = CountdownEvent(
            name: "春节", kind: .festival, rule: .lunarYearly(month: 1, day: 1),
            smartListDisplay: .sameDay)
        XCTAssertTrue(CountdownSmartListProjection
            .section(events: [sameDay], now: today, calendar: calendar).isEmpty)
    }

    // MARK: - 右侧标签

    /// 只有 0 天那一态有参照（「今天」）；其余是取舍，一并钉住免得以后悄悄改口径。
    func testRelativeLabels() {
        XCTAssertEqual(CountdownSmartListProjection.relativeLabel(daysUntil: 0), "今天")
        XCTAssertEqual(CountdownSmartListProjection.relativeLabel(daysUntil: 1), "明天")
        XCTAssertEqual(CountdownSmartListProjection.relativeLabel(daysUntil: 3), "3 天后")
        XCTAssertEqual(CountdownSmartListProjection.relativeLabel(daysUntil: -1), "昨天")
        XCTAssertEqual(CountdownSmartListProjection.relativeLabel(daysUntil: -3), "3 天前")
    }
}
