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
                                         knownLists: ["收集箱", "个人"])

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
                                         calendar: calendar, knownLists: ["收集箱"])

        XCTAssertEqual(result.title, "复盘")
        XCTAssertEqual(result.recurrence, .weekly)
        XCTAssertEqual(result.recurrenceRule?.weekday, 2)
        XCTAssertEqual(result.dueAt, calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9)))
        XCTAssertEqual(result.reminderAt, result.dueAt)
    }

    func testWeekdayDateTokensUseNaturalWeekForExplicitNextWeek() {
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 16))!
        func parse(_ input: String) -> Date? {
            QuickAddParser.parse(input, now: sunday, calendar: calendar,
                                 knownLists: ["收集箱"]).dueAt
        }

        XCTAssertEqual(parse("周一开会"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
        XCTAssertEqual(parse("周五理账"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        XCTAssertEqual(parse("下周三提交"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 16)))
        XCTAssertEqual(parse("周日休息"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))
    }

    func testUnknownListMarkerRemainsInTitleAndRelativeDurationIsExact() {
        let result = QuickAddParser.parse("整理资料 @不存在 2小时后", now: now,
                                         calendar: calendar, knownLists: ["收集箱"])

        XCTAssertEqual(result.title, "整理资料 @不存在")
        XCTAssertNil(result.listName)
        XCTAssertEqual(result.dueAt, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertEqual(result.reminderAt, result.dueAt)
        XCTAssertTrue(result.hasTime)
    }

    func testUnknownListMarkerIsShownAsChipButRemainsInTitle() throws {
        let input = "买牛奶 @冰箱"
        let result = QuickAddParser.parse(input, now: now, calendar: calendar,
                                          knownLists: ["收集箱"])
        let token = try XCTUnwrap(result.tokens.first { $0.kind == .list })

        XCTAssertTrue(token.retainsInTitle)
        XCTAssertEqual(result.title, input)
        XCTAssertEqual(result.text(removing: token), input)
    }

    func testDismissingUnknownListMarkerKeepsItAsTitleText() throws {
        let input = "买牛奶 @冰箱"
        let recognized = QuickAddParser.parse(input, now: now, calendar: calendar,
                                             knownLists: ["收集箱"])
        let token = try XCTUnwrap(recognized.tokens.first { $0.kind == .list })
        let dismissed = QuickAddParser.parse(
            input, now: now, calendar: calendar, knownLists: ["收集箱"],
            dismissedTokenIDs: [token.id])

        XCTAssertEqual(dismissed.title, input)
        XCTAssertNil(dismissed.listName)
        XCTAssertFalse(dismissed.tokens.contains { $0.id == token.id })
    }

    func testKnownListMarkerIsRecognizedAndRemovedFromTitle() {
        let result = QuickAddParser.parse("整理资料 @个人", now: now,
                                         calendar: calendar, knownLists: ["收集箱", "个人"])

        XCTAssertEqual(result.listName, "个人")
        XCTAssertEqual(result.title, "整理资料")
        XCTAssertEqual(result.tokens.first { $0.kind == .list }?.label, "@个人")
    }

    func testMonthlyTokenProducesRuleAndIsRemovedFromTitle() {
        let result = QuickAddParser.parse("每月15号提交报表", now: now,
                                         calendar: calendar, knownLists: ["收集箱"])
        XCTAssertEqual(result.title, "提交报表")
        XCTAssertEqual(result.recurrence, .monthly)
        XCTAssertEqual(result.recurrenceRule?.monthDay, 15)
    }

    func testDateAndRecurrenceWordsInsideQuotedTagStayInItsName() {
        let name = "明天 9点 每天"
        let input = QuickAddComposition.replacingTrailingMarker(in: "跟进 #明", with: name)
        let parsed = QuickAddParser.parse(input, now: now, calendar: calendar, knownLists: [])
        XCTAssertEqual(parsed.title, "跟进")
        XCTAssertEqual(parsed.tags, [name])
        XCTAssertNil(parsed.dueAt)
        XCTAssertNil(parsed.reminderAt)
        XCTAssertEqual(parsed.recurrence, .never)
        XCTAssertEqual(parsed.tokens.map(\.kind), [.tag])
    }

    func testDismissedQuotedTagKeepsLiteralTextWithoutReactivatingItsDateWords() throws {
        let input = QuickAddComposition.replacingTrailingMarker(in: "跟进 #明", with: "明天 9点") + "#工作"
        let parsed = QuickAddParser.parse(input, now: now, calendar: calendar, knownLists: [])
        let token = try XCTUnwrap(parsed.tokens.first { $0.raw.hasPrefix("#\"") })
        let dismissed = QuickAddParser.parse(input, now: now, calendar: calendar, knownLists: [],
                                             dismissedTokenIDs: [token.id])
        XCTAssertEqual(dismissed.title, "跟进 " + token.raw)
        XCTAssertEqual(dismissed.tags, ["工作"])
        XCTAssertNil(dismissed.dueAt)
        XCTAssertNil(dismissed.reminderAt)
        XCTAssertEqual(dismissed.tokens.map(\.label), ["#工作"])
        XCTAssertEqual(parsed.text(removing: token), dismissed.title)
    }

    func testHalfHourRelativeTokenMeansThirtyMinutes() {
        let result = QuickAddParser.parse("半小时后提醒我", now: now,
                                         calendar: calendar, knownLists: ["收集箱"])
        XCTAssertEqual(result.title, "提醒我")
        XCTAssertEqual(result.dueAt, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(result.reminderAt, result.dueAt)
    }

    func testQuickAddTimingDraftUsesParsedScheduleBeforeViewDefault() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let parsed = QuickAddParser.parse("明天 评审", now: now, calendar: calendar,
                                         knownLists: ["收集箱"])
        let draft = QuickAddScheduleDraft(parsed: parsed, defaultDueAt: now)

        XCTAssertEqual(draft.dueAt, tomorrow)
        XCTAssertFalse(draft.hasTime)
        XCTAssertEqual(draft.schedule.dueAt, tomorrow)

        let inboxParsed = QuickAddParser.parse("整理资料", now: now, calendar: calendar,
                                               knownLists: ["收集箱"])
        let inboxDraft = QuickAddScheduleDraft(parsed: inboxParsed, defaultDueAt: nil)
        let explicitlyCleared = QuickAddScheduleDraft()
        XCTAssertNil(inboxDraft.dueAt)
        XCTAssertNil(explicitlyCleared.schedule.dueAt)
        XCTAssertEqual(explicitlyCleared.repeatFrequency, .never)
    }

    func testQuickAddScheduleDraftPreservesSelectedDateRange() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let draft = QuickAddScheduleDraft(dueAt: start, dueEndAt: end)

        XCTAssertEqual(draft.schedule.dueAt, start)
        XCTAssertEqual(draft.schedule.dueEndAt, end)
    }

    func testRemovingDateOrTimeTokenSuppressesTodayDefaultButNotOtherTokens() throws {
        let input = "明天 下午3点 #工作 评审"
        let parsed = QuickAddParser.parse(input, now: now, calendar: calendar,
                                          knownLists: ["收集箱"])
        let dateID = try XCTUnwrap(parsed.tokens.first { $0.kind == .date }?.id)
        let tagID = try XCTUnwrap(parsed.tokens.first { $0.kind == .tag }?.id)

        XCTAssertTrue(QuickAddParser.hasDismissedScheduleToken(in: input, now: now,
            calendar: calendar, knownLists: ["收集箱"], dismissedTokenIDs: [dateID]))
        XCTAssertFalse(QuickAddParser.hasDismissedScheduleToken(in: input, now: now,
            calendar: calendar, knownLists: ["收集箱"], dismissedTokenIDs: [tagID]))

        let timeInput = "3点 #工作"
        let timeParsed = QuickAddParser.parse(timeInput, now: now, calendar: calendar,
                                              knownLists: ["收集箱"])
        let timeID = try XCTUnwrap(timeParsed.tokens.first { $0.kind == .time }?.id)
        XCTAssertTrue(QuickAddParser.hasDismissedScheduleToken(in: timeInput, now: now,
            calendar: calendar, knownLists: ["收集箱"], dismissedTokenIDs: [timeID]))
    }

    func testDismissingRecognizedTokenKeepsItAsPlainTitleText() {
        let input = "明天 下午3点 #工作 评审"
        let recognized = QuickAddParser.parse(input, now: now, calendar: calendar,
                                              knownLists: ["收集箱"])
        let dateToken = recognized.tokens.first { $0.kind == .date }!
        let result = QuickAddParser.parse(input, now: now, calendar: calendar,
                                          knownLists: ["收集箱"],
                                          dismissedTokenIDs: [dateToken.id])

        XCTAssertEqual(result.title, "明天 下午3点 评审")
        XCTAssertNil(result.dueAt)
        XCTAssertNil(result.reminderAt)
        XCTAssertEqual(result.tags, ["工作"])
        XCTAssertFalse(result.tokens.contains { $0.id == dateToken.id })
    }

    // MARK: - chip 删除的文本投影（text(removing:)）

    func testTextRemovingTokenDemotesFragmentToPlainTitleText() throws {
        let input = "明天 下午3点 #工作 评审"
        let parsed = QuickAddParser.parse(input, now: now, calendar: calendar,
                                          knownLists: ["收集箱"])
        let dateToken = try XCTUnwrap(parsed.tokens.first { $0.kind == .date })
        let tagToken = try XCTUnwrap(parsed.tokens.first { $0.kind == .tag })

        // 被删片段退化为普通标题文字，其余识别片段仍被剥离。
        XCTAssertEqual(parsed.text(removing: dateToken), "明天 下午3点 评审")
        XCTAssertEqual(parsed.text(removing: tagToken), "#工作 评审")
        // 原 token 自身携带源文本区间。
        XCTAssertEqual(dateToken.range.location, 0)
        XCTAssertEqual(parsed.sourceText, input)
    }

    func testTextRemovingListTokenKeepsMarkerAsPlainTitle() throws {
        let parsed = QuickAddParser.parse("买牛奶 @个人", now: now, calendar: calendar,
                                          knownLists: ["收集箱", "个人"])
        let listToken = try XCTUnwrap(parsed.tokens.first { $0.kind == .list })

        XCTAssertEqual(parsed.listName, "个人")
        XCTAssertEqual(parsed.text(removing: listToken), "买牛奶 @个人")
    }

    // MARK: - 识别摘要行

    func testSummaryLineComposesAllRecognizedProperties() {
        let line = QuickAddParser.summaryLine(for: "每天 明早9点 #工作 @个人 !!!准备评审",
                                              knownLists: ["收集箱", "个人"],
                                              now: now, calendar: calendar)

        XCTAssertEqual(line, "→ 9月15日 09:00 · 每天 · #工作 · @个人 · 高优先级")
    }

    func testSummaryLineIncludesDateOnlyWithoutTime() {
        let line = QuickAddParser.summaryLine(for: "明天 评审", knownLists: ["收集箱"],
                                              now: now, calendar: calendar)

        XCTAssertEqual(line, "→ 9月15日")
    }

    func testSummaryLineOmitsDismissedSmartTokens() throws {
        let input = "明天 #工作 评审"
        let parsed = QuickAddParser.parse(input, now: now, calendar: calendar,
                                          knownLists: ["收集箱"])
        let dateID = try XCTUnwrap(parsed.tokens.first { $0.kind == .date }?.id)

        XCTAssertEqual(QuickAddParser.summaryLine(
            for: input, knownLists: ["收集箱"], dismissedTokenIDs: [dateID],
            now: now, calendar: calendar), "→ #工作")
    }

    func testSummaryLineOmitsMissingComponentsAndUnknownList() {
        XCTAssertEqual(QuickAddParser.summaryLine(for: "整理资料", knownLists: ["收集箱"],
                                                  now: now, calendar: calendar), "")

        let unknownList = QuickAddParser.summaryLine(for: "买牛奶 @冰箱", knownLists: ["收集箱"],
                                                     now: now, calendar: calendar)
        XCTAssertEqual(unknownList, "")
        XCTAssertFalse(unknownList.contains("@冰箱"))
    }

    // MARK: - 滴答「🕑 智能识别」表格对齐

    /// 时段词单独出现时按默认钟点落到最近的有效时刻。
    /// 参考：滴答帮助「智能识别」日期和时间表（早上 7 点 … 晚上 8 点）。
    func testBarePeriodWordsResolveToDefaultClocks() {
        func due(_ input: String) -> Date? {
            QuickAddParser.parse(input, now: now, calendar: calendar,
                                 knownLists: ["收集箱"]).dueAt
        }
        // now = 2026-09-14(周一) 08:00，晚于 07:00 的时段顺延到次日。
        XCTAssertEqual(due("早上"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 7)))
        XCTAssertEqual(due("上午"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9)))
        XCTAssertEqual(due("中午"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12)))
        XCTAssertEqual(due("下午"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 13)))
        XCTAssertEqual(due("傍晚"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 17)))
        XCTAssertEqual(due("晚上"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 20)))
        // 时段词不再留在标题里。
        XCTAssertEqual(QuickAddParser.parse("下午", now: now, calendar: calendar,
                                           knownLists: []).title, "")
    }

    func testIntervalRecurrenceKeepsCadenceAndClearsTitle() {
        func parse(_ input: String) -> QuickAddParseResult {
            QuickAddParser.parse(input, now: now, calendar: calendar, knownLists: ["收集箱"])
        }
        XCTAssertEqual(parse("每2天").recurrenceRule?.interval, 2)
        XCTAssertEqual(parse("每2天").recurrence, .daily)
        XCTAssertEqual(parse("每2周").recurrenceRule?.interval, 2)
        XCTAssertEqual(parse("每2周").recurrence, .weekly)
        XCTAssertEqual(parse("每2月").recurrenceRule?.interval, 2)
        XCTAssertEqual(parse("每2月").recurrence, .monthly)
        XCTAssertEqual(parse("每2天").title, "")
        // 裸「每周」不再被当成标题文字。
        XCTAssertEqual(parse("每周").recurrence, .weekly)
        XCTAssertEqual(parse("每周").title, "")
    }

    func testYearlyWorkdayAndWeekendRecurrenceVocabulary() {
        func parse(_ input: String) -> QuickAddParseResult {
            QuickAddParser.parse(input, now: now, calendar: calendar, knownLists: ["收集箱"])
        }
        let march = parse("每年3月")
        XCTAssertEqual(march.recurrence, .yearly)
        XCTAssertEqual(march.recurrenceRule?.month, 3)
        XCTAssertEqual(march.recurrenceRule?.monthDay, 1)

        let march6 = parse("每年3月6日")
        XCTAssertEqual(march6.recurrence, .yearly)
        XCTAssertEqual(march6.recurrenceRule?.month, 3)
        XCTAssertEqual(march6.recurrenceRule?.monthDay, 6)

        XCTAssertEqual(parse("每个工作日").recurrence, .workdays)
        XCTAssertEqual(parse("每周末").recurrence, .weekends)
        XCTAssertEqual(parse("每月1日").recurrenceRule?.monthDay, 1)
        XCTAssertEqual(parse("每月最后1天").recurrenceRule?.monthlyOrdinal, -1)
    }

    /// 滴答把「提前 N」解析成准时 + 提前 N 的双提醒。
    func testAdvanceReminderProducesTimelyPlusEarlyOffsets() {
        func offsets(_ input: String) -> [Int] {
            QuickAddParser.parse(input, now: now, calendar: calendar,
                                 knownLists: ["收集箱"]).reminderOffsets
        }
        XCTAssertEqual(offsets("今天下午3点，提前3分钟"), [-3, 0])
        XCTAssertEqual(offsets("今天下午3点 提前1小时"), [-60, 0])
        XCTAssertEqual(offsets("今天下午3点 提前1天"), [-1440, 0])
        // 「提前提醒我」按表格默认 5 分钟。
        XCTAssertEqual(offsets("今天下午3点 提前提醒我"), [-5, 0])
        // 提醒片段不再污染标题。
        XCTAssertEqual(QuickAddParser.parse("今天下午3点，提前3分钟", now: now,
                                           calendar: calendar, knownLists: []).title, "")
        // 没有提前提醒时不产出 offsets，旧路径不受影响。
        XCTAssertTrue(offsets("今天下午3点").isEmpty)
    }

    func testRelativeIntervalsCoverCompositeWeeksMonthsAndYears() {
        func due(_ input: String) -> Date? {
            QuickAddParser.parse(input, now: now, calendar: calendar,
                                 knownLists: ["收集箱"]).dueAt
        }
        // 组合时长曾错误地只吃下「1小时」，把「30分钟后」留在标题里。
        XCTAssertEqual(due("1小时30分钟后"), now.addingTimeInterval(90 * 60))
        XCTAssertEqual(due("2周后"), calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        XCTAssertEqual(due("1个月后"), calendar.date(from: DateComponents(year: 2026, month: 10, day: 14)))
        XCTAssertEqual(due("1年后"), calendar.date(from: DateComponents(year: 2027, month: 9, day: 14)))
        XCTAssertEqual(QuickAddParser.parse("1小时30分钟后", now: now, calendar: calendar,
                                           knownLists: []).title, "")
    }

    func testReminderOffsetsLabelReadsAsTimelyPlusEarly() {
        XCTAssertEqual(QuickAddParser.reminderOffsetsLabel([-3, 0]), "提前3分钟 + 准时")
        XCTAssertEqual(QuickAddParser.reminderOffsetsLabel([-60, 0]), "提前1小时 + 准时")
    }

    /// 时段词只是普通名词的一部分时不能被吃进日程（「下午茶」「早上好」）。
    func testPeriodWordInsideLargerWordStaysInTitle() {
        for word in ["下午茶时间", "早上好", "晚上市"] {
            let parsed = QuickAddParser.parse(word, now: now, calendar: calendar,
                                              knownLists: ["收集箱"])
            XCTAssertNil(parsed.dueAt, "\(word) 不应被识别成时间")
            XCTAssertEqual(parsed.title, word)
        }
        // 紧跟动词时仍按默认钟点生效。
        let meeting = QuickAddParser.parse("下午开会", now: now, calendar: calendar,
                                           knownLists: ["收集箱"])
        XCTAssertEqual(meeting.title, "开会")
        XCTAssertEqual(meeting.dueAt, calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 13)))
    }

    /// 时段词 + 数字时钟时，下午/傍晚/晚上都要推进到 24 小时制。
    func testAfternoonPeriodWordsShiftClockIntoTwentyFourHourRange() {
        func hour(_ input: String) -> Int? {
            QuickAddParser.parse(input, now: now, calendar: calendar, knownLists: ["收集箱"])
                .dueAt.map { calendar.component(.hour, from: $0) }
        }
        XCTAssertEqual(hour("下午3点"), 15)
        XCTAssertEqual(hour("傍晚5点"), 17)
        XCTAssertEqual(hour("晚上8点"), 20)
        XCTAssertEqual(hour("上午9点"), 9)
        XCTAssertEqual(hour("中午12点"), 12)
    }

    func testChineseNumeralsCoverElevenThroughTwentyThree() {
        func hour(_ input: String) -> Int? {
            QuickAddParser.parse(input, now: now, calendar: calendar, knownLists: ["收集箱"])
                .dueAt.map { calendar.component(.hour, from: $0) }
        }
        XCTAssertEqual(hour("十一点"), 11)
        XCTAssertEqual(hour("十点"), 10)
        XCTAssertEqual(hour("二十三点"), 23)
    }

    /// 识别 chip 的可编辑性：只有日程类能点开面板改值，标签/清单/优先级不行。
    func testOnlyScheduleTokensAreEditableThroughChip() {
        XCTAssertTrue(QuickAddToken.Kind.date.isEditableScheduleToken)
        XCTAssertTrue(QuickAddToken.Kind.time.isEditableScheduleToken)
        XCTAssertTrue(QuickAddToken.Kind.reminder.isEditableScheduleToken)
        XCTAssertTrue(QuickAddToken.Kind.recurrence.isEditableScheduleToken)
        XCTAssertFalse(QuickAddToken.Kind.tag.isEditableScheduleToken)
        XCTAssertFalse(QuickAddToken.Kind.list.isEditableScheduleToken)
        XCTAssertFalse(QuickAddToken.Kind.priority.isEditableScheduleToken)
    }

    /// 提前提醒 chip 点开的是提醒页，保证「点 chip 改值」落到正确的面板页。
    func testChipEditTargetsMatchingSchedulePage() {
        func page(_ kind: QuickAddToken.Kind) -> TaskDatePopoverV2.Page? {
            QuickAddParser
                .parse("今天下午3点 提前3分钟", now: now, calendar: calendar, knownLists: [])
                .tokens.first(where: { $0.kind == kind })
                .flatMap { TaskDatePopoverV2.Page(editing: $0) }
        }
        XCTAssertEqual(page(.reminder), .reminder)
        XCTAssertEqual(page(.date), .main)

        let tag = QuickAddParser.parse("#工作 买牛奶", now: now, calendar: calendar, knownLists: [])
            .tokens.first(where: { $0.kind == .tag })!
        XCTAssertNil(TaskDatePopoverV2.Page(editing: tag))
    }

    // MARK: - 面板改值回写文字

    private func draft(_ due: Date?, end: Date? = nil, hasTime: Bool = true,
                       offsets: [Int] = [], repeat repeatFrequency: TaskRepeat = .never,
                       rule: RecurrenceRule? = nil) -> QuickAddScheduleDraft {
        QuickAddScheduleDraft(dueAt: due, dueEndAt: end, hasTime: hasTime,
                              reminderOffsets: offsets, repeatFrequency: repeatFrequency,
                              recurrenceRule: rule)
    }

    private func rewritten(_ text: String, _ value: QuickAddScheduleDraft) -> String? {
        QuickAddScheduleTextSync.rewrite(text, to: value, now: now, calendar: calendar,
                                         knownLists: ["收集箱", "个人"])
    }

    /// 核心诉求：面板把「提前3分钟」改成 30 分钟后，文字和 chip 要立刻跟上。
    func testSchedulePanelEditRewritesReminderText() throws {
        let text = "开会 今天下午3点，提前3分钟"
        let updated = draft(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 15)),
                            offsets: [-30, 0])
        let result = try XCTUnwrap(rewritten(text, updated))
        XCTAssertTrue(result.contains("提前30分钟"), result)
        XCTAssertFalse(result.contains("提前3分钟"), result)

        let reparsed = QuickAddParser.parse(result, now: now, calendar: calendar, knownLists: [])
        XCTAssertEqual(reparsed.reminderOffsets, [-30, 0])
        XCTAssertEqual(reparsed.title, "开会")
    }

    func testSchedulePanelEditRewritesDateAndKeepsOtherTokens() throws {
        let text = "评审 明天9点 提前1小时 #工作 @个人"
        let updated = draft(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9)),
                            offsets: [-60, 0])
        let result = try XCTUnwrap(rewritten(text, updated))
        let reparsed = QuickAddParser.parse(result, now: now, calendar: calendar,
                                            knownLists: ["个人"])
        XCTAssertEqual(reparsed.dueAt, calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 9)))
        XCTAssertEqual(reparsed.reminderOffsets, [-60, 0])
        // 标签与清单必须原样存活，标题不被污染。
        XCTAssertEqual(reparsed.tags, ["工作"])
        XCTAssertEqual(reparsed.listName, "个人")
        XCTAssertEqual(reparsed.title, "评审")
    }

    /// 新增重复：文字里原本没有重复片段时也要落笔，否则 chip 会漏掉这一项。
    func testSchedulePanelEditCanIntroduceNewRecurrence() throws {
        let text = "开会 今天下午3点，提前3分钟"
        let updated = draft(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 15)),
                            offsets: [-3, 0], repeat: .daily)
        let result = try XCTUnwrap(rewritten(text, updated))
        let reparsed = QuickAddParser.parse(result, now: now, calendar: calendar, knownLists: [])
        XCTAssertEqual(reparsed.recurrence, .daily)
        XCTAssertEqual(reparsed.reminderOffsets, [-3, 0])
    }

    func testSchedulePanelEditCarriesTimeRange() throws {
        let text = "开会 今天下午3点，提前3分钟"
        let updated = draft(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 15)),
                            end: calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 17)),
                            offsets: [-3, 0])
        let result = try XCTUnwrap(rewritten(text, updated))
        let reparsed = QuickAddParser.parse(result, now: now, calendar: calendar, knownLists: [])
        XCTAssertEqual(reparsed.dueEndAt,
                       calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 17)))
    }

    /// 清空提醒后文字里不该残留悬空标点。
    func testClearingReminderLeavesNoDanglingPunctuation() throws {
        let text = "开会 今天下午3点，提前3分钟"
        let updated = draft(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 15)))
        let result = try XCTUnwrap(rewritten(text, updated))
        XCTAssertFalse(result.hasSuffix("，"), result)
        XCTAssertFalse(result.hasSuffix(","), result)
        XCTAssertEqual(QuickAddParser.parse(result, now: now, calendar: calendar,
                                            knownLists: []).reminderOffsets, [])
    }

    /// 没有日程片段的纯标题：不回写，交给 override（避免把标题改坏）。
    func testTextWithoutScheduleTokensIsNotRewritten() {
        XCTAssertNil(rewritten("开会", draft(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 15)))))
    }

    func testTextRangeParsingProducesEndTime() {
        let parsed = QuickAddParser.parse("9点至11点 开会", now: now, calendar: calendar,
                                          knownLists: [])
        XCTAssertEqual(parsed.title, "开会")
        XCTAssertEqual(parsed.dueAt,
                       calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9)))
        XCTAssertEqual(parsed.dueEndAt,
                       calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 11)))
        // 跨天区间：结束落到次日。
        let overnight = QuickAddParser.parse("23点至1点", now: now, calendar: calendar,
                                             knownLists: [])
        XCTAssertEqual(overnight.dueEndAt,
                       calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 1)))
    }

    func testAbsoluteYearDateParsesForWriteBack() {
        let parsed = QuickAddParser.parse("2026年9月15日 09:00 开会", now: now,
                                          calendar: calendar, knownLists: [])
        XCTAssertEqual(parsed.title, "开会")
        XCTAssertEqual(parsed.dueAt,
                       calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 9, minute: 0)))
    }
}
