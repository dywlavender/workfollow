import XCTest
@testable import WorkFollow

final class CalendarInteractionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 1
        return value
    }
    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func poolTask() -> Task {
        Task(id: UUID(), title: "整理交付检查项", tags: ["交付"], list: TaskList(name: "工作"), priority: .medium,
             schedule: TaskSchedule(deadlineAt: date(17)), childOrder: 0, createdAt: date(1), updatedAt: date(1))
    }
    @MainActor func testArrangePoolDropIntoTimelineUsesWorkspaceResolverAndUndoesAsOneAction() {
        let original = poolTask()
        let workspace = TaskWorkspaceModel(clock: { self.date(13, hour: 12) }, calendar: calendar,
                                           seedDemoData: false, initialTasks: [original])
        let storedBefore = workspace.task(for: original.id)!
        // The rendering occurrence window contains no unscheduled task.
        let interaction = CalendarInteractionController(workspace: workspace, occurrences: [], calendar: calendar)
        let outcome = interaction.drop([original.id.uuidString], at: .time(day: date(14), minute: 720))
        XCTAssertTrue(outcome.acceptsDrop)
        let arranged = workspace.task(for: original.id)!
        XCTAssertEqual(arranged.schedule.dueAt, date(14, hour: 12))
        XCTAssertTrue(arranged.schedule.hasTime)
        XCTAssertNil(arranged.schedule.dueEndAt)
        XCTAssertEqual(arranged.schedule.deadlineAt, storedBefore.schedule.deadlineAt)
        XCTAssertEqual(arranged.list, storedBefore.list)
        XCTAssertEqual(arranged.tags, storedBefore.tags)
        XCTAssertTrue(CalendarProjection.arrangePool(tasks: workspace.allTasks, preferences: CalendarPreferences()).isEmpty)
        XCTAssertEqual(CalendarProjection.timed(on: date(14), tasks: workspace.allTasks, preferences: CalendarPreferences(), calendar: calendar).map(\.id), [original.id])
        workspace.undo()
        XCTAssertEqual(workspace.task(for: original.id), storedBefore)
        XCTAssertFalse(workspace.canUndo)
    }
    @MainActor func testArrangePoolDropIntoAllDayAndMonthUsesTheSameCommandPath() {
        for destination in [CalendarDropDestination.allDay(date(14)), .day(date(14))] {
            let original = poolTask()
            let workspace = TaskWorkspaceModel(clock: { self.date(13) }, calendar: calendar,
                                               seedDemoData: false, initialTasks: [original])
            let interaction = CalendarInteractionController(workspace: workspace, occurrences: [], calendar: calendar)
            XCTAssertTrue(interaction.drop([original.id.uuidString], at: destination).acceptsDrop)
            let arranged = workspace.task(for: original.id)!
            XCTAssertEqual(arranged.schedule.dueAt, date(14))
            XCTAssertFalse(arranged.schedule.hasTime)
            XCTAssertNil(arranged.schedule.dueEndAt)
            XCTAssertEqual(CalendarProjection.agenda(on: date(14), tasks: workspace.allTasks, preferences: CalendarPreferences(), calendar: calendar).map(\.id), [original.id])
            XCTAssertTrue(CalendarProjection.arrangePool(tasks: workspace.allTasks, preferences: CalendarPreferences()).isEmpty)
        }
    }
    @MainActor func testSameScheduleDropCreatesNoHistoryEntry() {
        var original = poolTask(); original.schedule.dueAt = date(14)
        let workspace = TaskWorkspaceModel(clock: { self.date(13) }, calendar: calendar,
                                           seedDemoData: false, initialTasks: [original])
        let interaction = CalendarInteractionController(workspace: workspace, occurrences: [], calendar: calendar)
        guard case .unchanged = interaction.drop([original.id.uuidString], at: .day(date(14))) else {
            return XCTFail("Same schedule must stay a no-op")
        }
        XCTAssertFalse(workspace.canUndo)
    }
    @MainActor func testPointResizePreviewsARangeAndCommitsOnceAtMouseUp() throws {
        var original = poolTask()
        original.schedule = TaskSchedule(dueAt: date(14, hour: 10), hasTime: true, deadlineAt: date(17))
        let workspace = TaskWorkspaceModel(clock: { self.date(13) }, calendar: calendar,
            seedDemoData: false, initialTasks: [original])
        let before = try XCTUnwrap(workspace.task(for: original.id))
        var draft = CalendarResizeDraft()
        draft.update(before.schedule, day: date(14), edge: .end, translationMinutes: 45, calendar: calendar)
        let preview = CalendarTimeBlockGeometry(schedule: try XCTUnwrap(draft.schedule), day: date(14), calendar: calendar)
        XCTAssertEqual(preview.startMinute, 600)
        XCTAssertEqual(preview.endMinute, 645)
        XCTAssertEqual(preview.displayMinutes, 45)
        XCTAssertEqual(workspace.task(for: original.id), before)
        XCTAssertFalse(workspace.canUndo)
        let interaction = CalendarInteractionController(workspace: workspace, occurrences: [], calendar: calendar)
        guard case .committed = interaction.apply(original.id, schedule: try XCTUnwrap(draft.finish())) else {
            return XCTFail("Mouse-up must commit the completed resize draft")
        }
        XCTAssertEqual(workspace.task(for: original.id)?.schedule.dueEndAt, date(14, hour: 10, minute: 45))
        XCTAssertEqual(workspace.task(for: original.id)?.schedule.deadlineAt, before.schedule.deadlineAt)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: original.id), before)
        XCTAssertFalse(workspace.canUndo)
    }
    @MainActor func testFutureDropWaitsForScopeAndOnlyThisKeepsOtherPeriods() {
        var original = poolTask(); original.schedule = TaskSchedule(dueAt: date(16, hour: 9), hasTime: true)
        original.recurrence = .weekly
        let workspace = TaskWorkspaceModel(clock: { self.date(13) }, calendar: calendar,
                                           seedDemoData: false, initialTasks: [original])
        let baseline = workspace.allTasks
        let range = DateInterval(start: date(11), end: date(31))
        let projected = TaskOccurrenceProjection.occurrences(tasks: workspace.allTasks, in: range, calendar: calendar)
        let future = projected.first { $0.isVirtual && $0.task.schedule.dueAt == date(23, hour: 9) }!
        let interaction = CalendarInteractionController(workspace: workspace, occurrences: projected, calendar: calendar)
        guard case .requiresScope(let occurrence, let plan) = interaction.drop([future.task.id.uuidString], at: .time(day: date(24), minute: 615)) else {
            return XCTFail("Recurring drop must offer a scope before writing")
        }
        XCTAssertEqual(workspace.allTasks, baseline)
        _ = workspace.saveOccurrenceSchedule(plan, occurrence: occurrence, scope: .onlyThis)
        let after = TaskOccurrenceProjection.occurrences(tasks: workspace.allTasks, in: range, calendar: calendar)
        XCTAssertFalse(after.contains { $0.task.schedule.dueAt == date(23, hour: 9) })
        XCTAssertTrue(after.contains { $0.task.schedule.dueAt == date(24, hour: 10, minute: 15) && $0.key == future.key })
        XCTAssertTrue(after.contains { $0.task.schedule.dueAt == date(30, hour: 9) })
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, baseline)
    }
}
