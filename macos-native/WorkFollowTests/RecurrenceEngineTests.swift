import XCTest
@testable import WorkFollow

/// Round A1 migration tests: recurrence engine (RecurrenceRule.nextOccurrence /
/// normalized), the Chinese work calendar, completion spawning the next
/// occurrence, skipOccurrence, reminder offsets and the schedule panel draft.
final class RecurrenceEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func date(_ year: Int = 2026, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 30) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func day(_ year: Int = 2026, _ month: Int, _ day: Int) -> Date {
        date(year, month, day, 0, 0)
    }

    private func makeActions(_ clock: @escaping () -> Date) -> (WorkspaceStore, TaskActions) {
        let store = WorkspaceStore()
        return (store, TaskActions(store: store, clock: clock, calendar: calendar))
    }

    private func makeTask(due: Date? = nil, hasTime: Bool = false, deadline: Date? = nil,
                          reminder: Date? = nil, offsets: [Int]? = nil,
                          recurrence: TaskRepeat = .never, rule: RecurrenceRule? = nil) -> Task {
        var task = Task(id: UUID(), title: "recurrence test", recurrence: recurrence, recurrenceRule: rule,
                        reminderAt: reminder, list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: due, hasTime: hasTime, deadlineAt: deadline),
                        parentID: nil, childOrder: 0, createdAt: date(2026, 1, 1), updatedAt: date(2026, 1, 1))
        task.reminderOffsets = offsets
        return task
    }

    // MARK: ChineseWorkCalendar

    func testHolidayPeriodOverridesOrdinaryWeekday() {
        // 2025-01-29 (春节, Wednesday) sits inside the Spring Festival break.
        XCTAssertFalse(ChineseWorkCalendar.isWorkday(date: day(2025, 1, 29), calendar: calendar))
        XCTAssertTrue(ChineseWorkCalendar.isHoliday(date: day(2025, 1, 29), calendar: calendar))
        XCTAssertEqual(ChineseWorkCalendar.override(for: day(2025, 1, 29), calendar: calendar), false)
    }

    func testMakeupWeekendIsWorkday() {
        // 调休: ordinary weekends turned into working days.
        XCTAssertEqual(ChineseWorkCalendar.override(for: day(2025, 1, 26), calendar: calendar), true)
        XCTAssertTrue(ChineseWorkCalendar.isWorkday(date: day(2025, 1, 26), calendar: calendar))
        XCTAssertFalse(ChineseWorkCalendar.isHoliday(date: day(2025, 1, 26), calendar: calendar))
        XCTAssertTrue(ChineseWorkCalendar.isWorkday(date: day(2026, 10, 10), calendar: calendar))
    }

    func testYearsWithoutTableFallBackToOrdinaryWeeks() {
        XCTAssertFalse(ChineseWorkCalendar.hasYear(2027))
        XCTAssertTrue(ChineseWorkCalendar.isWorkday(date: day(2027, 1, 4), calendar: calendar)) // Monday
        XCTAssertFalse(ChineseWorkCalendar.isWorkday(date: day(2027, 1, 2), calendar: calendar)) // Saturday
        XCTAssertNil(ChineseWorkCalendar.override(for: day(2027, 1, 2), calendar: calendar))
    }

    func testFestivalNamesCoverStatutoryHolidays() {
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2025, 1, 1), calendar: calendar), "元旦")
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2026, 2, 16), calendar: calendar), "除夕")
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2026, 2, 17), calendar: calendar), "春节")
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2025, 4, 4), calendar: calendar), "清明节")
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2026, 6, 19), calendar: calendar), "端午节")
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2026, 9, 25), calendar: calendar), "中秋节")
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2025, 10, 6), calendar: calendar), "中秋节")
        XCTAssertEqual(ChineseWorkCalendar.festivalName(date: day(2026, 10, 1), calendar: calendar), "国庆节")
        XCTAssertNil(ChineseWorkCalendar.festivalName(date: day(2026, 3, 3), calendar: calendar))
    }

    // MARK: RecurrenceRule.nextOccurrence

    func testNextOccurrencePreservesClockForDailyAndWeekly() {
        let wednesday = date(2026, 1, 7, 9, 30)
        let daily = RecurrenceRule().nextOccurrence(after: wednesday, frequency: .daily, calendar: calendar)
        XCTAssertEqual(daily, date(2026, 1, 8, 9, 30))
        // Gregorian weekday 6 = Friday; Wednesday → next Friday.
        let weekly = RecurrenceRule(weekday: 6).nextOccurrence(after: wednesday, frequency: .weekly, calendar: calendar)
        XCTAssertEqual(weekly, date(2026, 1, 9, 9, 30))
        // Same weekday rolls a full week forward.
        let sameWeek = RecurrenceRule(weekday: 4).nextOccurrence(after: wednesday, frequency: .weekly, calendar: calendar)
        XCTAssertEqual(sameWeek, date(2026, 1, 14, 9, 30))
    }

    func testMonthlyClampsToMonthEndAndReturnsToTargetDay() {
        let rule = RecurrenceRule(monthDay: 31)
        let january = date(2026, 1, 31, 14, 0)
        XCTAssertEqual(rule.nextOccurrence(after: january, frequency: .monthly, calendar: calendar), date(2026, 2, 28, 14, 0))
        XCTAssertEqual(rule.nextOccurrence(after: date(2026, 2, 28, 14, 0), frequency: .monthly, calendar: calendar),
                       date(2026, 3, 31, 14, 0))
    }

    func testYearlyUsesConfiguredMonthAndDay() {
        let rule = RecurrenceRule(monthDay: 15, month: 3)
        let base = date(2026, 1, 10, 8, 0)
        XCTAssertEqual(rule.nextOccurrence(after: base, frequency: .yearly, calendar: calendar), date(2027, 3, 15, 8, 0))
    }

    func testWeekdaysAndWeekendsSkipForward() {
        // Friday → Monday.
        let weekdays = RecurrenceRule().nextOccurrence(after: date(2026, 1, 9), frequency: .weekdays, calendar: calendar)
        XCTAssertEqual(weekdays, date(2026, 1, 12))
        // Monday → Saturday.
        let weekends = RecurrenceRule().nextOccurrence(after: date(2026, 1, 12), frequency: .weekends, calendar: calendar)
        XCTAssertEqual(weekends, date(2026, 1, 17))
    }

    func testWorkdaysHonourHolidayTableAndMakeupDays() {
        // Friday before Spring Festival 2025 → the Sunday makeup workday.
        let workdays = RecurrenceRule().nextOccurrence(after: date(2025, 1, 24), frequency: .workdays, calendar: calendar)
        XCTAssertEqual(workdays, date(2025, 1, 26))
    }

    func testHolidaysMatchRestDaysInsideHolidayPeriod() {
        // Thursday before the break → Saturday; inside the break every day rests.
        XCTAssertEqual(RecurrenceRule().nextOccurrence(after: date(2025, 1, 23), frequency: .holidays, calendar: calendar),
                       date(2025, 1, 25))
        XCTAssertEqual(RecurrenceRule().nextOccurrence(after: date(2025, 1, 29), frequency: .holidays, calendar: calendar),
                       date(2025, 1, 30))
    }

    func testCountBoundaryStopsTheChain() {
        let last = RecurrenceRule(remainingCount: 1)
        XCTAssertNil(last.nextOccurrence(after: date(2026, 1, 7), frequency: .daily, calendar: calendar))
        let rule = RecurrenceRule(remainingCount: 2)
        XCTAssertEqual(rule.nextOccurrence(after: date(2026, 1, 7), frequency: .daily, calendar: calendar), date(2026, 1, 8))
        XCTAssertEqual(rule.following.remainingCount, 1)
    }

    func testEndDateIncludesTheWholeDay() {
        let rule = RecurrenceRule(endDate: day(2026, 1, 9))
        XCTAssertEqual(rule.nextOccurrence(after: date(2026, 1, 8, 23, 0), frequency: .daily, calendar: calendar),
                       date(2026, 1, 9, 23, 0))
        XCTAssertNil(rule.nextOccurrence(after: date(2026, 1, 9, 23, 0), frequency: .daily, calendar: calendar))
    }

    func testNormalizedRepairsAndRejects() {
        XCTAssertNil(RecurrenceRule(weekday: 9).normalized(calendar: calendar))
        XCTAssertNil(RecurrenceRule(monthDay: 0).normalized(calendar: calendar))
        XCTAssertNil(RecurrenceRule(monthDay: 32).normalized(calendar: calendar))
        XCTAssertNil(RecurrenceRule(month: 13).normalized(calendar: calendar))
        // A zero/negative count degrades to never-ending, not to invalid.
        XCTAssertEqual(RecurrenceRule(remainingCount: 0).normalized(calendar: calendar)?.remainingCount, nil)
        XCTAssertEqual(RecurrenceRule(interval: 0).normalized(calendar: calendar)?.interval, 1)
        // endDate collapses to the start of its day.
        XCTAssertEqual(RecurrenceRule(endDate: date(2026, 1, 9, 18, 0)).normalized(calendar: calendar)?.endDate,
                       day(2026, 1, 9))
        XCTAssertEqual(RecurrenceRule(interval: 2, weekday: 3).normalized(calendar: calendar),
                       RecurrenceRule(interval: 2, weekday: 3))
    }

    func testOccurrenceDaysConsumeTheCount() {
        // Count 3 includes the current occurrence: two future days remain.
        let days = RecurrenceRule(remainingCount: 3).occurrenceDays(after: day(2026, 1, 1), frequency: .daily,
                                                                    calendar: calendar, limit: 12)
        XCTAssertEqual(days, Set([day(2026, 1, 2), day(2026, 1, 3)]))
    }

    func testLegacyEngineAnchorsUndatedTasksOnToday() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.date(2026, 1, 7, 15, 0) }, calendar: calendar)
        let id = actions.create(title: "undated recurring").taskID!
        actions.setRepeat(id, .daily)
        let next = RecurrenceEngine.next(for: store.task(id)!, now: date(2026, 1, 7, 15, 0), calendar: calendar)
        XCTAssertEqual(next, day(2026, 1, 8))
    }

    // MARK: Completion spawns the next occurrence

    func testCompletionSpawnsNextOccurrenceAndReturnsItsID() {
        let (store, actions) = makeActions { self.date(2026, 1, 7, 10, 0) }
        let id = actions.create(title: "weekly", schedule: TaskSchedule(dueAt: date(2026, 1, 7, 9, 30), hasTime: true,
                                                                        deadlineAt: date(2026, 1, 8))).taskID!
        actions.setReminder(id, date(2026, 1, 7, 8, 30))
        actions.setReminderOffsets(id, [0, -30])
        actions.setRecurrence(id, frequency: .weekly, rule: RecurrenceRule(remainingCount: 4, weekday: 6))

        let result = actions.complete(id)
        let spawnID = result.taskID!
        XCTAssertNotEqual(spawnID, id)
        XCTAssertEqual(store.tasks.count, 2)

        let original = store.task(id)!
        XCTAssertEqual(original.status, .completed)
        XCTAssertEqual(original.recurrence, .weekly)
        XCTAssertEqual(original.recurrenceRule?.remainingCount, 4)

        let spawn = store.task(spawnID)!
        XCTAssertEqual(spawn.status, .active)
        XCTAssertEqual(spawn.schedule.dueAt, date(2026, 1, 9, 9, 30))
        XCTAssertTrue(spawn.schedule.hasTime)
        XCTAssertEqual(spawn.schedule.deadlineAt, date(2026, 1, 10))
        XCTAssertEqual(spawn.reminderAt, date(2026, 1, 9, 8, 30))
        XCTAssertEqual(spawn.reminderOffsets, [-30, 0])
        XCTAssertEqual(spawn.recurrenceRule?.remainingCount, 3)
        XCTAssertEqual(spawn.recurrence, .weekly)
    }

    /// 区间任务生成下一实例：`dueAt` 与 `dueEndAt` 按**同一 delta** 平移，
    /// 区间长度与结束时刻都不变（只挪开始日会把区间压扁、把 17:45 丢成 00:00）。
    func testCompletionShiftsTheWholeRangeByTheSameDelta() {
        let (store, actions) = makeActions { self.date(2026, 1, 7, 10, 0) }
        let id = actions.create(title: "ranged weekly",
                                schedule: TaskSchedule(dueAt: date(2026, 1, 7, 9, 30), hasTime: true,
                                                       dueEndAt: date(2026, 1, 8, 17, 45))).taskID!
        actions.setRecurrence(id, frequency: .weekly, rule: RecurrenceRule(weekday: 6))

        let spawn = store.task(actions.complete(id).taskID!)!
        XCTAssertEqual(spawn.schedule.dueAt, date(2026, 1, 9, 9, 30))
        XCTAssertEqual(spawn.schedule.dueEndAt, date(2026, 1, 10, 17, 45))
        XCTAssertEqual(spawn.schedule.dueEndAt!.timeIntervalSince(spawn.schedule.dueAt!),
                       date(2026, 1, 8, 17, 45).timeIntervalSince(date(2026, 1, 7, 9, 30)),
                       "区间长度必须原样保留")
    }

    func testCompletionCarriesChildrenIncompleteWithoutRepeatRules() {
        let (store, actions) = makeActions { self.date(2026, 1, 5, 12, 0) }
        let parent = actions.create(title: "daily parent", schedule: TaskSchedule(dueAt: date(2026, 1, 5, 9, 0), hasTime: true)).taskID!
        actions.setRecurrence(parent, frequency: .daily, rule: RecurrenceRule(remainingCount: 9))
        let child = actions.createChild(parent, title: "step").taskID!
        actions.setSchedule(child, TaskSchedule(dueAt: date(2026, 1, 5, 10, 0), hasTime: true))
        actions.setReminder(child, date(2026, 1, 5, 9, 45))
        actions.setReminderOffsets(child, [-5])
        actions.setRecurrence(child, frequency: .weekly, rule: RecurrenceRule(weekday: 1))

        actions.complete(parent)
        XCTAssertEqual(store.tasks.count, 4) // parent, child, spawn, carried child

        let spawnID = store.tasks.first { $0.parentID == nil && $0.id != parent }!.id
        let carried = store.tasks.first { $0.parentID == spawnID }!
        XCTAssertEqual(carried.title, "step")
        XCTAssertEqual(carried.status, .active)
        XCTAssertNil(carried.completedAt)
        XCTAssertEqual(carried.recurrence, .never)
        XCTAssertNil(carried.recurrenceRule)
        XCTAssertEqual(carried.schedule.dueAt, date(2026, 1, 6, 10, 0))
        XCTAssertEqual(carried.reminderAt, date(2026, 1, 6, 9, 45))
        XCTAssertEqual(carried.reminderOffsets, [-5])
        XCTAssertEqual(carried.childOrder, 0)

        let originalChild = store.task(child)!
        XCTAssertEqual(originalChild.status, .completed)
        XCTAssertEqual(originalChild.recurrence, .weekly) // original record untouched
    }

    func testUndoCompletionRemovesSpawnAndCarriedChildren() {
        let (store, actions) = makeActions { self.date(2026, 1, 5, 12, 0) }
        let parent = actions.create(title: "daily parent", schedule: TaskSchedule(dueAt: date(2026, 1, 5, 9, 0))).taskID!
        actions.setRecurrence(parent, frequency: .daily, rule: nil)
        actions.createChild(parent, title: "step")
        let before = store.tasks
        actions.complete(parent)
        XCTAssertEqual(store.tasks.count, 4)
        actions.undo()
        XCTAssertEqual(store.tasks, before)
        XCTAssertEqual(store.task(parent)?.status, .active)
        XCTAssertEqual(store.task(parent)?.recurrenceRule?.remainingCount, nil)
    }

    // MARK: skipOccurrence

    func testSkipOccurrenceStampsSkippedAndSpawnsNext() {
        let (store, actions) = makeActions { self.date(2026, 1, 5, 10, 0) }
        let id = actions.create(title: "daily", schedule: TaskSchedule(dueAt: date(2026, 1, 5, 9, 0), hasTime: true)).taskID!
        actions.setRecurrence(id, frequency: .daily, rule: nil)
        let before = store.tasks

        let result = actions.skipOccurrence(id)
        let spawnID = result.taskID!
        XCTAssertNotEqual(spawnID, id)

        let original = store.task(id)!
        XCTAssertEqual(original.status, .active)
        XCTAssertNotNil(original.skippedAt)
        XCTAssertEqual(original.recurrence, .daily) // rule survives the skip
        XCTAssertNil(original.completedAt)

        let spawn = store.task(spawnID)!
        XCTAssertEqual(spawn.status, .active)
        XCTAssertNil(spawn.skippedAt)
        XCTAssertEqual(spawn.schedule.dueAt, date(2026, 1, 6, 9, 0))

        actions.undo()
        XCTAssertEqual(store.tasks, before)
        XCTAssertNil(store.task(id)?.skippedAt)
    }

    func testSkipRejectsNonRecurringClosedOrDeletedTasks() {
        let (store, actions) = makeActions { self.date(2026, 1, 5, 10, 0) }
        let plain = actions.create(title: "plain").taskID!
        XCTAssertEqual(actions.skipOccurrence(plain), .failure(.missingTask))
        let recurring = actions.create(title: "recurring").taskID!
        actions.setRepeat(recurring, .daily)
        actions.complete(recurring)
        XCTAssertEqual(actions.skipOccurrence(recurring), .failure(.missingTask))
        let deleted = actions.create(title: "deleted").taskID!
        actions.setRepeat(deleted, .daily)
        actions.delete(deleted)
        XCTAssertEqual(actions.skipOccurrence(deleted), .failure(.missingTask))
        XCTAssertTrue(store.task(plain)!.skippedAt == nil)
    }

    // MARK: Reminder offsets

    func testSetReminderOffsetsNormalizesToAscendingEarlyValues() {
        let (store, actions) = makeActions { self.date(2026, 1, 5, 10, 0) }
        let id = actions.create(title: "offsets").taskID!
        actions.setReminderOffsets(id, [0, -30, -30, 5, 90])
        XCTAssertEqual(store.task(id)?.reminderOffsets, [-90, -30, -5, 0])
        actions.setReminderOffsets(id, [])
        XCTAssertNil(store.task(id)?.reminderOffsets)
        actions.setReminderOffsets(id, nil)
        XCTAssertNil(store.task(id)?.reminderOffsets)
    }

    func testSaveTimingWritesAndClearsOffsets() {
        let (store, actions) = makeActions { self.date(2026, 1, 5, 10, 0) }
        let id = actions.create(title: "timing").taskID!
        actions.saveTiming(id, schedule: TaskSchedule(dueAt: date(2026, 1, 6, 9, 0), hasTime: true),
                           reminder: nil, frequency: .never, reminderOffsets: [0, -1440])
        XCTAssertEqual(store.task(id)?.reminderOffsets, [-1440, 0])
        // nil leaves them untouched; an explicit list (even empty) replaces.
        actions.saveTiming(id, schedule: TaskSchedule(dueAt: date(2026, 1, 6, 9, 0), hasTime: true),
                           reminder: nil, frequency: .never)
        XCTAssertEqual(store.task(id)?.reminderOffsets, [-1440, 0])
        actions.saveTiming(id, schedule: TaskSchedule(dueAt: date(2026, 1, 6, 9, 0), hasTime: true),
                           reminder: nil, frequency: .never, reminderOffsets: [])
        XCTAssertNil(store.task(id)?.reminderOffsets)
    }

    func testBatchReminderOffsetsOperation() {
        let (store, actions) = makeActions { self.date(2026, 1, 5, 10, 0) }
        let id = actions.create(title: "batched").taskID!
        actions.batch([id], operation: .reminderOffsets([-60]))
        XCTAssertEqual(store.task(id)?.reminderOffsets, [-60])
        actions.undo()
        XCTAssertNil(store.task(id)?.reminderOffsets)
    }

    // MARK: ReminderSchedule

    func testFireDatesFromOffsetsForTimedTask() {
        let task = makeTask(due: date(2026, 1, 9, 14, 30), hasTime: true, offsets: [-30, 0, -1440])
        XCTAssertEqual(ReminderSchedule.fireDates(for: task, calendar: calendar),
                       [date(2026, 1, 8, 14, 30), date(2026, 1, 9, 14, 0), date(2026, 1, 9, 14, 30)])
    }

    func testAllDayOffsetsAnchorAtNine() {
        let task = makeTask(due: day(2026, 1, 9), offsets: [-60, 0])
        XCTAssertEqual(ReminderSchedule.fireDates(for: task, calendar: calendar),
                       [date(2026, 1, 9, 8, 0), date(2026, 1, 9, 9, 0)])
    }

    func testLegacyAbsoluteReminderStillSchedules() {
        let legacy = makeTask(due: date(2026, 1, 9, 14, 30), hasTime: true, reminder: date(2026, 1, 9, 8, 0))
        XCTAssertEqual(ReminderSchedule.fireDates(for: legacy, calendar: calendar), [date(2026, 1, 9, 8, 0)])
        // Offsets without a due degrade to the legacy reminder.
        XCTAssertEqual(ReminderSchedule.fireDates(for: makeTask(offsets: [-30]), calendar: calendar), [])
    }

    func testSignatureTracksOffsetsAndEligibility() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.date(2026, 1, 5, 10, 0) }, calendar: calendar)
        let id = actions.create(title: "remind me", schedule: TaskSchedule(dueAt: date(2026, 1, 9, 14, 30), hasTime: true)).taskID!
        actions.setReminder(id, date(2026, 1, 9, 14, 0))
        let legacy = ReminderSignature.values(store.tasks, calendar: calendar)
        actions.setReminderOffsets(id, [0, -30])
        let multi = ReminderSignature.values(store.tasks, calendar: calendar)
        XCTAssertNotEqual(multi, legacy)
        XCTAssertEqual(multi.first?.dates.count, 2)
        actions.complete(id)
        XCTAssertTrue(ReminderSignature.values(store.tasks, calendar: calendar).isEmpty)
    }

    // MARK: TaskDateDraftModel (schedule panel draft)

    private func makeModel(task: Task, deadline: Bool = false) -> TaskDateDraftModel {
        makeModel(task: task, now: date(2026, 8, 22, 9, 30), deadline: deadline)
    }

    private func makeModel(task: Task, now: Date, deadline: Bool = false) -> TaskDateDraftModel {
        TaskDateDraftModel(task: task, calendar: calendar, now: { now }, deadline: deadline)
    }

    func testDraftReadsStoredOffsetsAndRowState() {
        let model = makeModel(task: makeTask(due: date(2026, 8, 25, 14, 30), hasTime: true, offsets: [-30, 0]))
        XCTAssertTrue(model.hasReminderDraft)
        XCTAssertEqual(model.reminderOffsetsDraft, [-30, 0])
        let legacy = makeModel(task: makeTask(due: date(2026, 8, 25, 14, 30), hasTime: true))
        XCTAssertFalse(legacy.hasReminderDraft)
    }

    func testToggleOffsetsAndLegacyOptionReplaceEachOther() {
        let model = makeModel(task: makeTask(due: date(2026, 8, 25, 14, 30), hasTime: true))
        model.toggleReminderOffset(0)
        model.toggleReminderOffset(-30)
        XCTAssertEqual(model.reminderOffsetsDraft, [-30, 0])
        model.toggleReminderOffset(-30) // untoggle
        XCTAssertEqual(model.reminderOffsetsDraft, [0])
        model.chooseReminderOption(.custom) // absolute custom replaces offsets
        XCTAssertTrue(model.reminderOffsets.isEmpty)
        model.clearReminder()
        XCTAssertFalse(model.hasReminderDraft)
        model.addCustomReminderOffset(minutes: 90)
        XCTAssertEqual(model.reminderOffsetsDraft, [-90])
        XCTAssertEqual(TaskDateDraftModel.offsetTitle(-90), "提前90分钟")
        XCTAssertEqual(TaskDateDraftModel.offsetTitle(0), "准时")
        XCTAssertEqual(TaskDateDraftModel.offsetTitle(-1440), "提前1天")
        XCTAssertEqual(TaskDateDraftModel.offsetTitle(-20), "提前20分钟")
    }

    func testCommitPlanCarriesOffsetsAndEarliestReminder() {
        let task = makeTask(due: date(2026, 8, 25, 14, 30), hasTime: true)
        let model = makeModel(task: task)
        model.toggleReminderOffset(0)
        model.toggleReminderOffset(-30)
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.reminderOffsets, [-30, 0])
        XCTAssertEqual(plan.reminder, date(2026, 8, 25, 14, 0)) // earliest offset
        XCTAssertEqual(plan.schedule.dueAt, date(2026, 8, 25, 14, 30))
    }

    func testCommitPlanPeriodTabCarriesOffsetsWithAllDayAnchor() {
        let task = makeTask()
        let model = makeModel(task: task)
        model.setTab(.period)
        model.select(day(2026, 8, 25)) // first pick completes the range, second restarts it
        model.select(day(2026, 8, 25))
        model.toggleReminderOffset(-30)
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.reminderOffsets, [-30])
        XCTAssertEqual(plan.schedule.dueAt, day(2026, 8, 25))
        XCTAssertFalse(plan.schedule.hasTime)
        XCTAssertEqual(plan.reminder, date(2026, 8, 25, 8, 30)) // 09:00 anchor − 30 min
    }

    func testClearPlanDropsOffsets() {
        let task = makeTask(due: day(2026, 8, 25), offsets: [-30])
        let model = makeModel(task: task)
        let plan = model.clearPlan(for: task)
        XCTAssertTrue(plan.reminderOffsets.isEmpty)
        XCTAssertNil(plan.reminder)
    }

    func testDeadlineModeKeepsCurrentOffsetsUntouched() {
        let task = makeTask(due: day(2026, 8, 25), offsets: [-30])
        let model = makeModel(task: task, deadline: true)
        model.select(date(2026, 9, 1))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.reminderOffsets, [-30])
        XCTAssertEqual(plan.reminder, task.reminderAt)
        XCTAssertEqual(plan.schedule.deadlineAt, day(2026, 9, 1))
    }

    func testTonightShortcutSetsTodayAt2000Timed() {
        let task = makeTask(due: date(2026, 8, 22, 9, 0), hasTime: true)
        let model = makeModel(task: task)
        model.selectTonight()
        XCTAssertTrue(model.hasTime)
        XCTAssertEqual(model.selectedDate, date(2026, 8, 22, 20, 0))
    }

    func testOccurrencePreviewDaysRespectCountEnding() {
        let task = makeTask(due: day(2026, 8, 22), recurrence: .weekly, rule: RecurrenceRule(remainingCount: 3))
        let model = makeModel(task: task)
        XCTAssertEqual(model.occurrencePreviewDays(), Set([day(2026, 8, 29), day(2026, 9, 5)]))
        let none = makeModel(task: makeTask())
        XCTAssertTrue(none.occurrencePreviewDays().isEmpty)
    }

    // MARK: Codable compatibility

    func testTaskDecodeKeepsOldSnapshotsWithoutOffsetsReadable() throws {
        let task = makeTask(due: day(2026, 1, 9), reminder: date(2026, 1, 9, 8, 0))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder.encode(task)) as? [String: Any])
        XCTAssertNil(json["reminderOffsets"])
        json.removeValue(forKey: "reminderOffsets")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(Task.self, from: data)
        XCTAssertNil(decoded.reminderOffsets)
        XCTAssertEqual(decoded.reminderAt, task.reminderAt)
        // And a snapshot carrying offsets decodes them back.
        var withOffsets = task
        withOffsets.reminderOffsets = [0, -30]
        let roundTripped = try decoder.decode(Task.self, from: try encoder.encode(withOffsets))
        XCTAssertEqual(roundTripped.reminderOffsets, [0, -30])
    }
}
