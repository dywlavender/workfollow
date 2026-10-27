import XCTest
@testable import WorkFollow

final class CalendarPlanningTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 1
        return value
    }
    private func date(_ day: Int, hour: Int = 0, minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func task(_ title: String, start: Date?, end: Date? = nil, timed: Bool = false) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none,
             schedule: TaskSchedule(dueAt: start, hasTime: timed, dueEndAt: end),
             childOrder: 0,
             createdAt: date(1), updatedAt: date(1))
    }
    func testMonthBrowsingKeepsCreationAndWeekAnchorInTheBrowsedMonth() {
        var viewport = CalendarViewport(date: date(13), calendar: calendar)
        viewport.step(1, calendar: calendar)
        XCTAssertEqual(viewport.selectedDate, date(13, month: 11))
        viewport.mode = .week
        let interval = viewport.visibleRange(calendar: calendar)
        XCTAssertTrue(interval.contains(date(13, month: 11)))
        viewport.mode = .month
        viewport.browseMonth(date(1, month: 2, year: 2027), calendar: calendar)
        XCTAssertEqual(viewport.selectedDate, date(13, month: 2, year: 2027))
    }
    func testCompletedAndCrossDayAgendaAreSharedAcrossModes() {
        let spanning = task("跨天", start: date(13), end: date(16))
        var done = task("完成", start: date(14)); done.status = .completed
        var prefs = CalendarPreferences(); prefs.showCompleted = false
        XCTAssertEqual(CalendarProjection.agenda(on: date(15), tasks: [spanning, done], preferences: prefs, calendar: calendar).map(\.id), [spanning.id])
        XCTAssertEqual(CalendarProjection.agenda(on: date(14), tasks: [spanning, done], preferences: prefs, calendar: calendar).map(\.id), [spanning.id])
        let interval = DateInterval(start: date(11), end: date(18))
        XCTAssertEqual(CalendarProjection.allDay(tasks: [spanning, done], range: interval, preferences: prefs, calendar: calendar).map(\.id), [spanning.id])
    }
    func testOverlapsPartitionAndAdjacentRangesReuseFullWidth() {
        let a = task("A", start: date(13, hour: 9), end: date(13, hour: 10), timed: true)
        let b = task("B", start: date(13, hour: 9, minute: 30), end: date(13, hour: 10, minute: 30), timed: true)
        let c = task("C", start: date(13, hour: 10, minute: 30), end: date(13, hour: 11), timed: true)
        let blocks = CalendarProjection.timed(on: date(13), tasks: [c, b, a], preferences: CalendarPreferences(), calendar: calendar)
        XCTAssertEqual(blocks.first { $0.id == a.id }?.laneCount, 2)
        XCTAssertEqual(blocks.first { $0.id == b.id }?.laneCount, 2)
        XCTAssertNotEqual(blocks.first { $0.id == a.id }?.lane, blocks.first { $0.id == b.id }?.lane)
        XCTAssertEqual(blocks.first { $0.id == c.id }?.laneCount, 1)
    }
    func testTimePointDoesNotAcquireAnImplicitDuration() {
        let created = CalendarGestureDraft.creation(on: date(13), from: 600, to: nil, calendar: calendar)
        XCTAssertEqual(created.dueAt, date(13, hour: 10))
        XCTAssertNil(created.dueEndAt)
        let point = task("安排池任务", start: created.dueAt, timed: true)
        let block = CalendarProjection.timed(on: date(13), tasks: [point], preferences: CalendarPreferences(), calendar: calendar).first!
        XCTAssertEqual(block.kind, .timePoint)
        XCTAssertNil(block.endMinute)
    }
    func testEscCancelsUntilMouseUpAndNextPressCanCommit() {
        var gesture = CalendarGestureSession()
        XCTAssertTrue(gesture.beginIfNeeded())
        gesture.cancel()
        XCTAssertFalse(gesture.beginIfNeeded())
        XCTAssertTrue(gesture.isCancelled)
        XCTAssertFalse(gesture.finish())
        XCTAssertTrue(gesture.beginIfNeeded())
        XCTAssertTrue(gesture.finish())
    }
    func testResizeDraftPreviewsGeometryAndEscRestoresTheOriginalRange() {
        let original = TaskSchedule(dueAt: date(13, hour: 9), hasTime: true,
            dueEndAt: date(13, hour: 10), deadlineAt: date(17))
        var draft = CalendarResizeDraft()
        draft.update(original, day: date(13), edge: .start, translationMinutes: -30, calendar: calendar)
        let preview = CalendarTimeBlockGeometry(schedule: draft.schedule!, day: date(13), calendar: calendar)
        XCTAssertEqual(preview.startMinute, 510)
        XCTAssertEqual(preview.endMinute, 600)
        XCTAssertEqual(preview.displayMinutes, 90)
        XCTAssertEqual(draft.schedule?.deadlineAt, original.deadlineAt)
        draft.cancel()
        draft.update(original, day: date(13), edge: .start, translationMinutes: -60, calendar: calendar)
        XCTAssertNil(draft.schedule)
        XCTAssertNil(draft.finish())
        let restored = CalendarTimeBlockGeometry(schedule: draft.schedule ?? original, day: date(13), calendar: calendar)
        XCTAssertEqual(restored.startMinute, 540)
        XCTAssertEqual(restored.displayMinutes, 60)
        draft.update(original, day: date(13), edge: .end, translationMinutes: 30, calendar: calendar)
        XCTAssertEqual(draft.finish()?.dueEndAt, date(13, hour: 10, minute: 30))
        XCTAssertNil(draft.schedule)
    }
    func testTimelineZoomKeepsTheVisibleTimeAtItsCentreOrPointer() {
        var pinch = CalendarTimelineScaleDraft(hourHeight: 64, scrollOffset: 512, viewportHeight: 400)
        let centreMinute = pinch.anchorMinute
        pinch.magnify(1.5)
        XCTAssertEqual(pinch.hourHeight, 96)
        XCTAssertEqual((pinch.scrollOffset + 200) / pinch.hourHeight * 60, centreMinute, accuracy: 0.001)
        var wheel = CalendarTimelineScaleDraft(hourHeight: 64, scrollOffset: 512, viewportHeight: 400, anchorY: 120)
        let pointerMinute = wheel.anchorMinute
        wheel.scroll(12)
        XCTAssertGreaterThan(wheel.hourHeight, 64)
        XCTAssertEqual((wheel.scrollOffset + 120) / wheel.hourHeight * 60, pointerMinute, accuracy: 0.001)
    }
    func testZoomWheelLeavesOrdinaryScrollingAndHorizontalPagingAlone() {
        XCTAssertFalse(CalendarDisplaySizing.acceptsZoomWheel(control: false, deltaX: 0, deltaY: 12))
        XCTAssertFalse(CalendarDisplaySizing.acceptsZoomWheel(control: true, deltaX: 20, deltaY: 3))
        XCTAssertTrue(CalendarDisplaySizing.acceptsZoomWheel(control: true, deltaX: 0, deltaY: 12))
    }
    @MainActor func testDisplayGesturePreferencesPersistSeparatelyFromTaskHistory() {
        let suite = "calendar-gesture-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PlanningSettingsStore(defaults: defaults)
        let original = task("保持任务", start: date(13, hour: 9), timed: true)
        let workspace = TaskWorkspaceModel(clock: { self.date(13) }, calendar: calendar,
            seedDemoData: false, initialTasks: [original])
        let before = workspace.allTasks
        var draft = CalendarTimelineScaleDraft(hourHeight: settings.calendar.hourHeight,
            scrollOffset: 512, viewportHeight: 400)
        draft.magnify(1.25)
        XCTAssertEqual(settings.calendar.hourHeight, 64)
        settings.updateCalendar {
            $0.hourHeight = draft.hourHeight
            $0.allDayHeight = CalendarDisplaySizing.allDayHeight(156)
        }
        let reopened = PlanningSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.calendar.hourHeight, 80)
        XCTAssertEqual(reopened.calendar.allDayHeight, 156)
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(workspace.canUndo)
        XCTAssertFalse(settings.canUndoConfiguration)
    }
    @MainActor func testArrangePaneOpensOnceForExistingInstallThenRespectsTheToggle() throws {
        let suite = "calendar-arrange-migration-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(CalendarPreferences(showArrangePane: false)),
                     forKey: "workfollow.planning.calendar.v1")
        let migrated = PlanningSettingsStore(defaults: defaults)
        XCTAssertTrue(migrated.calendar.showArrangePane, "周计划页删除后，安排任务面板升级时应默认打开")
        migrated.updateCalendar { $0.showArrangePane = false }
        let reopened = PlanningSettingsStore(defaults: defaults)
        XCTAssertFalse(reopened.calendar.showArrangePane, "用户手动关闭后不再被迁移覆盖")
    }
    @MainActor func testWeekStartMigratesFromSundayToMondayOnce() throws {
        let suite = "calendar-monday-migration-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = CalendarPreferences()
        legacy.firstWeekday = 1
        defaults.set(try JSONEncoder().encode(legacy), forKey: "workfollow.planning.calendar.v1")
        let migrated = PlanningSettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.calendar.firstWeekday, 2, "旧默认（周日）应一次性迁移到周一")
        migrated.updateCalendar { $0.firstWeekday = 1 }
        let reopened = PlanningSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.calendar.firstWeekday, 1, "用户手动改回周日后面不再被迁移")
    }
    func testDragRangeAndMovePreserveAnExplicitDurationAndDeadline() {
        var schedule = CalendarGestureDraft.creation(on: date(13), from: 600, to: 540, calendar: calendar)
        XCTAssertEqual(schedule.dueAt, date(13, hour: 9))
        XCTAssertEqual(schedule.dueEndAt, date(13, hour: 10))
        schedule.deadlineAt = date(17)
        let moved = CalendarGestureDraft.moved(schedule, to: date(14, hour: 14), hasTime: true, calendar: calendar)
        XCTAssertEqual(moved.dueEndAt, date(14, hour: 15))
        XCTAssertEqual(moved.deadlineAt, date(17))
    }
    func testFutureOccurrenceCacheDoesNotInsertTasksAndRebuildsForNewWindow() {
        var weekly = task("周五", start: date(16, hour: 9), timed: true)
        weekly.recurrence = .weekly
        let cache = CalendarOccurrenceCache()
        let range = DateInterval(start: date(11), end: date(1, month: 11))
        let first = cache.occurrences(tasks: [weekly], in: range, revision: 1, dateRevision: 0, calendar: calendar)
        XCTAssertTrue(first.contains { $0.isVirtual && $0.task.schedule.dueAt == date(23, hour: 9) })
        _ = cache.occurrences(tasks: [weekly], in: range, revision: 1, dateRevision: 0, calendar: calendar)
        XCTAssertEqual(cache.buildCount, 1)
        _ = cache.occurrences(tasks: [weekly], in: DateInterval(start: date(1, month: 7, year: 2027), end: date(1, month: 8, year: 2027)),
                              revision: 1, dateRevision: 0, calendar: calendar)
        XCTAssertEqual(cache.buildCount, 2)
        XCTAssertNil(weekly.series)
    }
    func testArrangePaneRespectsTheSameScopeAsTheCalendar() {
        var work = task("工作", start: nil); work.list = TaskList(name: "工作")
        var personal = task("个人", start: nil); personal.list = TaskList(name: "个人")
        var preferences = CalendarPreferences(); preferences.listNames = ["工作"]
        XCTAssertEqual(CalendarProjection.arrangePool(tasks: [personal, work], preferences: preferences).map(\.id), [work.id])
    }
}
