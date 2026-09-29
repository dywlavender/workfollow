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

    private func makeTask(due: Date? = nil, hasTime: Bool = false, dueEnd: Date? = nil,
                          deadline: Date? = nil,
                          reminder: Date? = nil, recurrence: TaskRepeat = .never,
                          rule: RecurrenceRule? = nil) -> Task {
        Task(id: UUID(), title: "date popover test", recurrence: recurrence, recurrenceRule: rule,
             reminderAt: reminder, list: .inbox, priority: .none,
             schedule: TaskSchedule(dueAt: due, hasTime: hasTime, dueEndAt: dueEnd,
                                    deadlineAt: deadline),
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
        let model = makeModel(task: makeTask(due: date(8, 10, 8, 0), hasTime: true, dueEnd: date(8, 12)))
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

    /// 区间由 `dueEndAt` 表达，不是 `deadlineAt`：后者是独立的截止点，
    /// 只有它时面板仍停在日期页签。
    func testDeadlineAloneKeepsTheDateTab() {
        let model = makeModel(task: makeTask(due: date(8, 10), deadline: date(8, 12)))
        XCTAssertEqual(model.tab, .date)
        XCTAssertNil(model.periodEnd)
    }

    // MARK: Time

    func testSetStartTimeKeepsTheDay() {
        let model = makeModel(task: makeTask(due: date(8, 22, 14, 0), hasTime: true))
        model.setStartTime(date(8, 25, 8, 15))
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

    func testCommitPeriodTabWritesStartAndRangeEnd() {
        let task = makeTask()
        let model = makeModel(task: task)
        model.setTab(.period)
        model.select(date(8, 10))
        model.select(date(8, 12))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, calendar.startOfDay(for: date(8, 10)))
        XCTAssertFalse(plan.schedule.hasTime)
        XCTAssertEqual(plan.schedule.dueEndAt, calendar.startOfDay(for: date(8, 12)))
        XCTAssertNil(plan.schedule.deadlineAt, "时间段页签不碰截止日期")
    }

    // MARK: 时间段开始 / 结束时间（Flutter parity）

    /// 定时区间提交：开始与结束**各留自己的时分**。
    /// 这一条锁的是上一版的缺陷——`dueEndAt` 被压成 `startOfDay`，
    /// 「9月30日 17:45」实际存成「9月30日 00:00」。
    func testCommitTimedRangeKeepsBothTimesOfDay() {
        let task = makeTask(due: date(9, 29))
        let model = makeModel(task: task)
        model.setTab(.period)
        model.select(date(9, 30))
        model.setHasTime(true)
        model.setStartTime(date(9, 29, 9, 30))
        model.setEndTime(date(9, 30, 17, 45))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, date(9, 29, 9, 30))
        XCTAssertEqual(plan.schedule.dueEndAt, date(9, 30, 17, 45))
        XCTAssertTrue(plan.schedule.hasTime)
    }

    /// 已有定时区间打开面板：开始与结束时间都要还原出来。
    func testReopeningATimedRangeRestoresBothTimes() {
        let model = makeModel(task: makeTask(due: date(9, 29, 9, 30), hasTime: true,
                                             dueEnd: date(9, 30, 17, 45)))
        XCTAssertEqual(model.tab, .period)
        XCTAssertEqual(model.startTimeAnchor, date(9, 29, 9, 30))
        XCTAssertEqual(model.endTimeAnchor, date(9, 30, 17, 45))
        XCTAssertTrue(model.hasEndTime)
    }

    /// 只改结束时间：开始时间不动，`dueEndAt` 更新。
    func testEditingOnlyTheEndTimeLeavesTheStartAlone() {
        let task = makeTask(due: date(9, 29, 9, 30), hasTime: true, dueEnd: date(9, 30, 17, 45))
        let model = makeModel(task: task)
        model.setEndTime(date(9, 30, 11, 43))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, date(9, 29, 9, 30))
        XCTAssertEqual(plan.schedule.dueEndAt, date(9, 30, 11, 43))
    }

    /// 分钟精度必须能存下来：半小时列表只是快捷选择，不是数据精度。
    func testMinutePrecisionSurvivesCommit() {
        let task = makeTask(due: date(9, 29), dueEnd: date(9, 30))
        let model = makeModel(task: task)
        model.setHasTime(true)
        model.setStartTime(date(9, 29, 9, 17))
        model.setEndTime(date(9, 30, 11, 43))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, date(9, 29, 9, 17))
        XCTAssertEqual(plan.schedule.dueEndAt, date(9, 30, 11, 43))
    }

    /// 时间段 → 日期：旧的 `dueEndAt` 必须清掉，否则「日期」页签还留着区间。
    func testSwitchingToTheDateTabClearsTheStaleRangeEnd() {
        let task = makeTask(due: date(9, 29, 9, 30), hasTime: true, dueEnd: date(9, 30, 17, 45))
        let model = makeModel(task: task)
        XCTAssertEqual(model.tab, .period)
        model.setTab(.date)
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, date(9, 29, 9, 30))
        XCTAssertNil(plan.schedule.dueEndAt, "日期页签没有区间")
    }

    /// 改安排区间不许碰截止日期：`dueAt` / `dueEndAt` / `deadlineAt` 三个概念独立。
    func testRangeEditsNeverTouchTheDeadline() {
        let task = makeTask(due: date(9, 29), dueEnd: date(9, 30), deadline: date(10, 3))
        let model = makeModel(task: task)
        model.setHasTime(true)
        model.setStartTime(date(9, 29, 9, 30))
        model.setEndTime(date(9, 30, 17, 45))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueEndAt, date(9, 30, 17, 45))
        XCTAssertEqual(plan.schedule.deadlineAt, task.schedule.deadlineAt,
                       "改安排区间不许碰截止日期")
    }

    /// 清除安排：开始与区间结束都清掉，截止日期保留。
    func testClearOnThePeriodTabKeepsTheDeadline() {
        let task = makeTask(due: date(9, 29, 9, 30), hasTime: true,
                            dueEnd: date(9, 30, 17, 45), deadline: date(10, 3))
        let model = makeModel(task: task)
        let plan = model.clearPlan(for: task)
        XCTAssertNil(plan.schedule.dueAt)
        XCTAssertNil(plan.schedule.dueEndAt)
        XCTAssertEqual(plan.schedule.deadlineAt, task.schedule.deadlineAt)
    }

    /// 结束早于开始 → 禁止确认（Flutter `apply()` 的同一判据）。
    func testEndBeforeStartBlocksCommit() {
        let task = makeTask(due: date(9, 29))
        let model = makeModel(task: task)
        model.setTab(.period)
        model.setHasTime(true)
        model.setStartTime(date(9, 29, 17, 0))
        model.setEndTime(date(9, 29, 9, 0))
        XCTAssertEqual(model.rangeError, "结束时间不能早于开始时间")
        XCTAssertFalse(model.canCommit)
    }

    /// Flutter 只判 `to.isBefore(from)`：**相等合法**，不要自己收紧成 `<=`。
    func testEqualStartAndEndIsAllowed() {
        let task = makeTask(due: date(9, 29))
        let model = makeModel(task: task)
        model.setTab(.period)
        model.setHasTime(true)
        model.setStartTime(date(9, 29, 9, 0))
        model.setEndTime(date(9, 29, 9, 0))
        XCTAssertNil(model.rangeError)
        XCTAssertTrue(model.canCommit)
    }

    /// 全天区间没有时刻可比，不该报错（也不该被时间逻辑碰到）。
    func testAllDayRangeHasNoRangeErrorAndStaysAllDay() {
        let task = makeTask(due: date(9, 29))
        let model = makeModel(task: task)
        model.setTab(.period)
        model.select(date(9, 30))
        XCTAssertNil(model.rangeError)
        let plan = model.commitPlan(for: task)
        XCTAssertFalse(plan.schedule.hasTime)
        XCTAssertEqual(plan.schedule.dueAt, calendar.startOfDay(for: date(9, 29)))
        XCTAssertEqual(plan.schedule.dueEndAt, calendar.startOfDay(for: date(9, 30)))
    }

    /// 结束时间锚点只属于时间段页签；日期页签上写结束时间是空操作。
    ///
    /// 注意：切到日期页签时草稿**故意保留** `periodEnd`（切回时间段要还原区间），
    /// 清掉它的是 `commitPlan`（见 `testSwitchingToTheDateTabClearsTheStaleRangeEnd`）。
    func testEndTimeIsScopedToThePeriodTab() {
        let model = makeModel(task: makeTask(due: date(9, 29), dueEnd: date(9, 30)))
        XCTAssertEqual(model.tab, .period)
        XCTAssertNotNil(model.endTimeAnchor)
        model.setTab(.date)
        XCTAssertNil(model.endTimeAnchor)
        XCTAssertFalse(model.hasEndTime)
        model.setEndTime(date(9, 30, 17, 45))
        XCTAssertEqual(model.periodEnd, date(9, 30), "日期页签上不该改到结束时间")
    }

    /// 还没有结束日时改结束时间：落到开始那天，形成单日定时区间。
    func testSettingAnEndTimeWithoutAnEndDayMaterialisesTheStartDay() {
        let task = makeTask(due: date(9, 29))
        let model = makeModel(task: task)
        model.setTab(.period)
        model.setHasTime(true)
        model.setStartTime(date(9, 29, 9, 30))
        XCTAssertNil(model.periodEnd)
        model.setEndTime(date(9, 30, 17, 45))
        XCTAssertEqual(model.periodEnd, date(9, 29, 17, 45), "结束落在开始那天")
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueEndAt, date(9, 29, 17, 45))
    }

    /// 回归：**已定时**的区间（开始恰好 00:00）改结束时间，开始时间必须一动不动。
    ///
    /// Flutter `editTime(isEnd: true)` 只写 `endTime`；而原生 `setHasTime` 里那句
    /// 「全天 → 09:00」的兜底如果不判跃迁，就会被「点结束时间顺便置 timed = true」
    /// 这条路带出来，把 00:00 悄悄改成 09:00。这条用例就是钉住那个边界的。
    func testSettingAnEndTimeDoesNotMoveAnAlreadyTimedStart() {
        let task = makeTask(due: allDay(9, 26), hasTime: true, dueEnd: allDay(9, 30))
        let model = makeModel(task: task)
        XCTAssertEqual(model.tab, .period)
        XCTAssertEqual(model.startTimeAnchor, allDay(9, 26))

        // 用户只做了「点结束时间 → 选 02:30」这一件事。
        model.setHasTime(true)
        model.setEndTime(date(9, 30, 2, 30))

        XCTAssertEqual(model.periodStart, allDay(9, 26), "开始时间不该被结束时间的操作改写")
        XCTAssertEqual(model.startTimeAnchor, allDay(9, 26))
        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, allDay(9, 26))
        XCTAssertEqual(plan.schedule.dueEndAt, date(9, 30, 2, 30))
    }

    /// 兜底本身要留着：全天任务开定时仍然默认 09:00（Flutter `initState` 的初值；
    /// 日期页签那一路由上面的 `testEnablingTimeOnAllDayDraftDefaultsToNine` 覆盖）。
    /// 这里补的是**第二次置 true 必须是空操作**——否则每次置位都会重新搬动开始时间。
    func testReEnablingTimeDoesNotMoveAnAlreadyTimedStart() {
        let task = makeTask(due: allDay(9, 26), dueEnd: allDay(9, 30))
        let model = makeModel(task: task)
        XCTAssertFalse(model.hasTime)
        model.setHasTime(true)
        XCTAssertEqual(model.periodStart, date(9, 26, 9, 0), "全天 → 定时的跃迁仍补 09:00")
        model.setStartTime(date(9, 26, 7, 15))
        model.setHasTime(true)
        XCTAssertEqual(model.periodStart, date(9, 26, 7, 15), "已定时后再置 true 不得改写开始时间")
    }

    // MARK: Clear

    func testClearDateTabKeepsDeadlineAndDropsTheRest() {
        let task = makeTask(due: allDay(8, 22), dueEnd: allDay(8, 25), deadline: date(9, 1, 0, 0),
                            reminder: date(8, 22, 10, 0), recurrence: .daily)
        let model = makeModel(task: task)
        XCTAssertEqual(model.tab, .period)
        model.setTab(.date)
        let plan = model.clearPlan(for: task)
        XCTAssertNil(plan.schedule.dueAt)
        XCTAssertFalse(plan.schedule.hasTime)
        XCTAssertNil(plan.schedule.dueEndAt, "清除清掉整段安排，不含页签之分")
        XCTAssertEqual(plan.schedule.deadlineAt, calendar.startOfDay(for: date(9, 1)),
                       "截止日期是另一个字段，清除动不到它")
        XCTAssertNil(plan.reminder)
        XCTAssertEqual(plan.frequency, .never)
        XCTAssertNil(plan.recurrenceRule)
    }

    func testClearPeriodTabDropsTheWholeRange() {
        let task = makeTask(due: date(8, 10), dueEnd: date(8, 12))
        let model = makeModel(task: task)
        XCTAssertEqual(model.tab, .period)
        let plan = model.clearPlan(for: task)
        XCTAssertNil(plan.schedule.dueAt)
        XCTAssertNil(plan.schedule.dueEndAt)
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
