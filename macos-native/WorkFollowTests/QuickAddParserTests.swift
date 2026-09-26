import XCTest
@testable import WorkFollow

final class QuickAddParserTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "zh_CN")
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 8))!
    }

    func testSmartCaptureCombinesDateListTagPriorityAndRepeat() {
        let result = QuickAddParser.parse("每天 明早9点 #工作 @个人 !!!准备季度评审",
                                         now: now, calendar: calendar,
                                         availableLists: ["收集箱", "个人"])

        XCTAssertEqual(result.title, "准备季度评审")
        XCTAssertEqual(result.listName, "个人")
        XCTAssertEqual(result.tags, ["工作"])
        XCTAssertEqual(result.priority, .high)
        XCTAssertEqual(result.recurrence, .daily)
        XCTAssertEqual(result.dueAt, calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 9)))
        XCTAssertTrue(result.hasTime)
        XCTAssertEqual(result.reminderAt, result.dueAt)
        XCTAssertEqual(result.tokens.count, 5)
    }

    func testWeeklyRecurrenceWithClockTargetsNextMatchingWeekday() {
        let result = QuickAddParser.parse("每周一 9点复盘", now: now,
                                         calendar: calendar, availableLists: ["收集箱"])

        XCTAssertEqual(result.title, "复盘")
        XCTAssertEqual(result.recurrence, .weekly)
        XCTAssertEqual(result.recurrenceRule?.weekday, 2)
        XCTAssertEqual(result.dueAt, calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9)))
        XCTAssertEqual(result.reminderAt, result.dueAt)
    }

    func testWeekdayDateTokensMatchFlutterWeekdayRules() {
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 16))!
        func parse(_ input: String) -> Date? {
            QuickAddParser.parse(input, now: sunday, calendar: calendar,
                                 availableLists: ["收集箱"]).dueAt
        }

        XCTAssertEqual(parse("周一开会"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
        XCTAssertEqual(parse("周五理账"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        XCTAssertEqual(parse("下周三提交"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 23)))
        XCTAssertEqual(parse("周日休息"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))
    }

    func testUnknownListMarkerRemainsInTitleAndRelativeDurationIsExact() {
        let result = QuickAddParser.parse("整理资料 @不存在 2小时后", now: now,
                                         calendar: calendar, availableLists: ["收集箱"])

        XCTAssertEqual(result.title, "整理资料 @不存在")
        XCTAssertNil(result.listName)
        XCTAssertEqual(result.dueAt, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertEqual(result.reminderAt, result.dueAt)
        XCTAssertTrue(result.hasTime)
    }

    func testMonthlyTokenProducesRuleAndIsRemovedFromTitle() {
        let result = QuickAddParser.parse("每月15号提交报表", now: now,
                                         calendar: calendar, availableLists: ["收集箱"])
        XCTAssertEqual(result.title, "提交报表")
        XCTAssertEqual(result.recurrence, .monthly)
        XCTAssertEqual(result.recurrenceRule?.monthDay, 15)
    }

    func testHalfHourRelativeTokenMeansThirtyMinutes() {
        let result = QuickAddParser.parse("半小时后提醒我", now: now,
                                         calendar: calendar, availableLists: ["收集箱"])
        XCTAssertEqual(result.title, "提醒我")
        XCTAssertEqual(result.dueAt, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(result.reminderAt, result.dueAt)
    }

    func testQuickAddTimingDraftUsesParsedScheduleBeforeViewDefault() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let parsed = QuickAddParser.parse("明天 评审", now: now, calendar: calendar,
                                         availableLists: ["收集箱"])
        let draft = QuickAddScheduleDraft(parsed: parsed, defaultDueAt: now)

        XCTAssertEqual(draft.dueAt, tomorrow)
        XCTAssertFalse(draft.hasTime)
        XCTAssertEqual(draft.schedule.dueAt, tomorrow)

        let inboxParsed = QuickAddParser.parse("整理资料", now: now, calendar: calendar,
                                               availableLists: ["收集箱"])
        let inboxDraft = QuickAddScheduleDraft(parsed: inboxParsed, defaultDueAt: nil)
        let explicitlyCleared = QuickAddScheduleDraft()
        XCTAssertNil(inboxDraft.dueAt)
        XCTAssertNil(explicitlyCleared.schedule.dueAt)
        XCTAssertEqual(explicitlyCleared.repeatFrequency, .never)
    }

    func testRemovingDateOrTimeTokenSuppressesTodayDefaultButNotOtherTokens() throws {
        let input = "明天 下午3点 #工作 评审"
        let parsed = QuickAddParser.parse(input, now: now, calendar: calendar,
                                          availableLists: ["收集箱"])
        let dateID = try XCTUnwrap(parsed.tokens.first { $0.kind == .date }?.id)
        let tagID = try XCTUnwrap(parsed.tokens.first { $0.kind == .tag }?.id)

        XCTAssertTrue(QuickAddParser.hasDismissedScheduleToken(in: input, now: now,
            calendar: calendar, availableLists: ["收集箱"], dismissedTokenIDs: [dateID]))
        XCTAssertFalse(QuickAddParser.hasDismissedScheduleToken(in: input, now: now,
            calendar: calendar, availableLists: ["收集箱"], dismissedTokenIDs: [tagID]))

        let timeInput = "3点 #工作"
        let timeParsed = QuickAddParser.parse(timeInput, now: now, calendar: calendar,
                                              availableLists: ["收集箱"])
        let timeID = try XCTUnwrap(timeParsed.tokens.first { $0.kind == .time }?.id)
        XCTAssertTrue(QuickAddParser.hasDismissedScheduleToken(in: timeInput, now: now,
            calendar: calendar, availableLists: ["收集箱"], dismissedTokenIDs: [timeID]))
    }

    func testDismissingRecognizedTokenKeepsItAsPlainTitleText() {
        let input = "明天 下午3点 #工作 评审"
        let recognized = QuickAddParser.parse(input, now: now, calendar: calendar,
                                              availableLists: ["收集箱"])
        let dateToken = recognized.tokens.first { $0.kind == .date }!
        let result = QuickAddParser.parse(input, now: now, calendar: calendar,
                                          availableLists: ["收集箱"],
                                          dismissedTokenIDs: [dateToken.id])

        XCTAssertEqual(result.title, "明天 下午3点 评审")
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.reminderAt)
        XCTAssertEqual(result.tags, ["工作"])
        XCTAssertFalse(result.tokens.contains { $0.id == dateToken.id })
    }
}
