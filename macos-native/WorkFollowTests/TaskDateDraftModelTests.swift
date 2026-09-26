import XCTest
@testable import WorkFollow

final class TaskDateDraftModelTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        value.firstWeekday = 1
        return value
    }

    private var fixedNow: Date { date(8, 22, 9, 30) } // 2026-08-22, a Saturday

    private func date(_ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 30) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    /// All-day dues are stored at start of day.
    private func allDay(_ month: Int, _ day: Int) -> Date { date(month, day, 0, 0) }

    private func makeTask(due: Date? = nil, hasTime: Bool = false, deadline: Date? = nil,
                          reminder: Date? = nil, recurrence: TaskRepeat = .never,
                          rule: RecurrenceRule? = nil) -> Task {
        Task(id: UUID(), title: "date popover test", recurrence: recurrence, recurrenceRule: rule,
             reminderAt: reminder, list: .inbox, priority: .none,
             schedule: TaskSchedule(dueAt: due, hasTime: hasTime, deadlineAt: deadline),
             parentID: nil, childOrder: 0, createdAt: fixedNow, updatedAt: fixedNow)
    }

    private func makeModel(task: Task, now: Date? = nil, deadline: Bool = false) -> TaskDateDraftModel {
        TaskDateDraftModel(task: task, calendar: calendar, now: { now ?? self.fixedNow }, deadline: deadline)
    }

    // MARK: Selection

    func testQuickShortcutsKeepTimeOfDay() {
        let model = makeModel(task: makeTask(due: date(8, 22, 14, 0), hasTime: true))
        model.quick(1)
        XCTAssertEqual(model.selectedDate, date(8, 23, 14, 0))
        model.quick(7)
        XCTAssertEqual(model.selectedDate, date(8, 29, 14, 0))
    }

    func testWeekendShortcutLandsOnNextSaturday() {
        let wednesday = date(8, 19, 9, 0)
        let model = makeModel(task: makeTask(), now: wednesday)
        XCTAssertEqual(model.nextWeekend(), allDay(8, 22))
        model.selectWeekend()
        XCTAssertEqual(model.selectedDate, allDay(8, 22))
        // Today is already Saturday → stay on today.
        let saturdayModel = makeModel(task: makeTask())
        XCTAssertEqual(saturdayModel.nextWeekend(), fixedNow.startOfDay(with: calendar))
    }

    func testPeriodRangeBuilding() {
        let model = makeModel(task: makeTask(due: allDay(8, 10)))
        model.setTab(.period)
        XCTAssertEqual(model.periodStart, allDay(8, 10))
        XCTAssertNil(model.periodEnd)
        model.select(allDay(8, 12))
        XCTAssertEqual(model.periodRange, allDay(8, 10)...allDay(8, 12))
        model.select(allDay(8, 11)) // completed range → restart selection
        XCTAssertEqual(model.periodStart, allDay(8, 11))
        XCTAssertNil(model.periodEnd)
        model.select(allDay(8, 9)) // earlier day → moves the start
        XCTAssertEqual(model.periodStart, allDay(8, 9))
        XCTAssertNil(model.periodEnd)
    }

    func testBothDatesOpenOnPeriodTabAndSwitchSyncsDrafts() {
        let model = makeModel(task: makeTask(due: date(8, 10, 8, 0), hasTime: true, deadline: date(8, 12)))
        XCTAssertEqual(model.tab, .period)
        XCTAssertEqual(model.periodStart, date(8, 10, 8, 0))
        model.setTab(.date)
        XCTAssertEqual(model.selectedDate, date(8, 10, 8, 0))
        model.select(date(8, 20))
        model.setTab(.period)
        XCTAssertEqual(model.periodStart, date(8, 20, 8, 0)) // start day follows the date tab, time kept
        XCTAssertNil(model.periodEnd) // end < start was dropped
        XCTAssertEqual(model.periodRange, date(8, 20, 8, 0)...date(8, 20, 8, 0)) // single-point range
    }

    // MARK: Time

    func testSetTimeKeepsTheDay() {
        let model = makeModel(task: makeTask(due: date(8, 22, 14, 0), hasTime: true))
        model.setTime(date(8, 25, 8, 15))
        XCTAssertEqual(model.selectedDate, date(8, 22, 8, 15))
    }

    func testEnablingTimeOnAllDayDraftDefaultsToNine() {
        let model = makeModel(task: makeTask(due: allDay(8, 25)))
        model.setHasTime(true)
        XCTAssertEqual(model.selectedDate, date(8, 25, 9, 0))
    }

    // MARK: Reminder

    func testReminderPresetsAnchorToDueMoment() {
        let model = makeModel(task: makeTask(due: date(8, 25, 14, 30), hasTime: true))
        XCTAssertEqual(model.reminderDate(for: .onTime), date(8, 25, 14, 30))
        XCTAssertEqual(model.reminderDate(for: .minutes30), date(8, 25, 14, 0))
        XCTAssertEqual(model.reminderDate(for: .day1), date(8, 24, 14, 30))
        XCTAssertNil(model.reminderDate(for: .none))
    }

    func testAllDayDueAnchorsPresetsAtNine() {
        let model = makeModel(task: makeTask(due: date(8, 25)))
        XCTAssertEqual(model.reminderDate(for: .onTime), date(8, 25, 9, 0))
        XCTAssertEqual(model.reminderDate(for: .hour1), date(8, 25, 8, 0))
    }

    func testExistingReminderMapsToPresetOrCustom() {
        let preset = makeModel(task: makeTask(due: date(8, 25, 14, 30), hasTime: true, reminder: date(8, 25, 14, 0)))
        XCTAssertEqual(preset.reminderOption, .minutes30)
        let custom = makeModel(task: makeTask(due: date(8, 25, 14, 30), hasTime: true, reminder: date(8, 26, 10, 0)))
        XCTAssertEqual(custom.reminderOption, .custom)
        let none = makeModel(task: makeTask())
        XCTAssertEqual(none.reminderOption, .none)
    }

    // MARK: Commit

    func testCommitDateTabWritesScheduleAndReminder() {
        let task = makeTask(due: allDay(8, 22))
        let model = makeModel(task: task)
        model.select(date(8, 25))
        model.setHasTime(true)
        model.chooseReminderOption(.minutes30)
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, date(8, 25, 9, 0))
        XCTAssertTrue(plan.schedule.hasTime)
        XCTAssertEqual(plan.reminder, date(8, 25, 8, 30))
        XCTAssertEqual(plan.frequency, .never)
        XCTAssertNil(plan.recurrenceRule)
    }

    func testCommitBuildsRuleWhenRecurrenceTouched() {
        let task = makeTask(due: date(8, 22))
        let model = makeModel(task: task)
        model.chooseFrequency(.weekly)
        model.chooseWeekday(4) // Wednesday
        model.chooseEnding(.count)
        model.chooseRepeatCount(5)
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.frequency, .weekly)
        XCTAssertEqual(plan.recurrenceRule?.weekday, 4)
        XCTAssertEqual(plan.recurrenceRule?.remainingCount, 5)
        XCTAssertNil(plan.recurrenceRule?.endDate)
    }

    func testUntouchedRecurrencePassesThrough() {
        let rule = RecurrenceRule(interval: 2, weekday: 4)
        let task = makeTask(due: date(8, 22), recurrence: .weekly, rule: rule)
        let model = makeModel(task: task)
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.frequency, .weekly)
        XCTAssertEqual(plan.recurrenceRule, rule)
    }

    func testCommittingNeverFrequencyDropsTheRule() {
        let task = makeTask(due: date(8, 22), recurrence: .weekly, rule: RecurrenceRule(interval: 2))
        let model = makeModel(task: task)
        model.chooseFrequency(.never)
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.frequency, .never)
        XCTAssertNil(plan.recurrenceRule)
    }

    func testCommitPeriodTabWritesStartAndDeadline() {
        let task = makeTask()
        let model = makeModel(task: task)
        model.setTab(.period)
        model.select(date(8, 10))
        model.select(date(8, 12))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, calendar.startOfDay(for: date(8, 10)))
        XCTAssertFalse(plan.schedule.hasTime)
        XCTAssertEqual(plan.schedule.deadlineAt, calendar.startOfDay(for: date(8, 12)))
    }

    // MARK: Clear

    func testClearDateTabKeepsDeadlineAndDropsTheRest() {
        let task = makeTask(due: allDay(8, 22), deadline: date(9, 1, 0, 0), reminder: date(8, 22, 10, 0), recurrence: .daily)
        let model = makeModel(task: task)
        model.setTab(.date) // both dates set → opens on the period tab; clear on the date tab keeps the deadline
        let plan = model.clearPlan(for: task)
        XCTAssertNil(plan.schedule.dueAt)
        XCTAssertFalse(plan.schedule.hasTime)
        XCTAssertEqual(plan.schedule.deadlineAt, calendar.startOfDay(for: date(9, 1)))
        XCTAssertNil(plan.reminder)
        XCTAssertEqual(plan.frequency, .never)
        XCTAssertNil(plan.recurrenceRule)
    }

    func testClearPeriodTabDropsDeadlineToo() {
        let task = makeTask(due: date(8, 10), deadline: date(8, 12))
        let model = makeModel(task: task)
        XCTAssertEqual(model.tab, .period)
        let plan = model.clearPlan(for: task)
        XCTAssertNil(plan.schedule.dueAt)
        XCTAssertNil(plan.schedule.deadlineAt)
    }

    func testDeadlineModeCommitAndClearOnlyTouchDeadline() {
        let task = makeTask(due: date(8, 22), deadline: date(9, 1), reminder: date(8, 22, 10, 0), recurrence: .daily)
        let model = makeModel(task: task, deadline: true)
        model.select(date(9, 15, 16, 0))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.deadlineAt, calendar.startOfDay(for: date(9, 15)))
        XCTAssertEqual(plan.schedule.dueAt, date(8, 22))
        XCTAssertEqual(plan.reminder, date(8, 22, 10, 0))
        XCTAssertEqual(plan.frequency, .daily)
        let cleared = model.clearPlan(for: task)
        XCTAssertNil(cleared.schedule.deadlineAt)
        XCTAssertEqual(cleared.schedule.dueAt, date(8, 22))
        XCTAssertEqual(cleared.reminder, date(8, 22, 10, 0))
        XCTAssertEqual(cleared.frequency, .daily)
    }

    // MARK: Workspace integration

    @MainActor
    func testCommitThroughWorkspacePersistsAndKeepsConcurrentEdits() {
        let task = makeTask(due: allDay(8, 22))
        let workspace = TaskWorkspaceModel(clock: { self.fixedNow }, calendar: calendar,
                                           seedDemoData: false, initialTasks: [task])
        let model = makeModel(task: task)
        _ = workspace.setPriority(task.id, .high) // lands after the popover opened
        model.select(date(8, 25))
        model.setHasTime(true)
        model.chooseReminderOption(.onTime)
        let current = workspace.task(for: task.id)!
        let plan = model.commitPlan(for: current)
        workspace.saveTiming(task.id, schedule: plan.schedule, reminder: plan.reminder,
                             frequency: plan.frequency, recurrenceRule: plan.recurrenceRule)
        let saved = workspace.task(for: task.id)!
        XCTAssertEqual(saved.schedule.dueAt, date(8, 25, 9, 0))
        XCTAssertEqual(saved.reminderAt, date(8, 25, 9, 0))
        XCTAssertEqual(saved.priority, .high) // concurrent edit survived
    }
}

private extension Date {
    func startOfDay(with calendar: Calendar) -> Date {
        calendar.startOfDay(for: self)
    }
}
