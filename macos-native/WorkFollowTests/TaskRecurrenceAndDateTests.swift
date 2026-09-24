import XCTest
@testable import WorkFollow

final class TaskRecurrenceAndDateTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private func date(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: 30))!
    }

    func testMonthlyClampsAndReturnsToOriginalDay() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.date(1, 31) }, calendar: calendar)
        let id = actions.create(title: "monthly", schedule: TaskSchedule(dueAt: date(1, 31), hasTime: true)).taskID!
        actions.setRepeat(id, .monthly)
        actions.complete(id)
        let feb = store.tasks.last!
        XCTAssertEqual(feb.schedule.dueAt, date(2, 28))
        actions.complete(feb.id)
        XCTAssertEqual(store.tasks.last?.schedule.dueAt, date(3, 31))
    }

    func testIntervalAndCountIncludeCurrentOccurrence() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.date(1, 1) }, calendar: calendar)
        let id = actions.create(title: "every 3 days", schedule: TaskSchedule(dueAt: date(1, 1))).taskID!
        actions.setRecurrence(id, frequency: .daily, rule: RecurrenceRule(interval: 3, remainingCount: 2))
        actions.complete(id)
        XCTAssertEqual(store.tasks.last?.schedule.dueAt, date(1, 4))
        XCTAssertEqual(store.tasks.last?.recurrenceRule?.remainingCount, 1)
        actions.complete(store.tasks.last!.id)
        XCTAssertEqual(store.tasks.count, 2)
    }

    func testEndDateIncludesWholeDay() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.date(1, 1) }, calendar: calendar)
        let id = actions.create(title: "daily", schedule: TaskSchedule(dueAt: date(1, 1))).taskID!
        actions.setRecurrence(id, frequency: .daily, rule: RecurrenceRule(endDate: calendar.startOfDay(for: date(1, 2))))
        actions.complete(id)
        XCTAssertEqual(store.tasks.count, 2)
        actions.complete(store.tasks.last!.id)
        XCTAssertEqual(store.tasks.count, 2)
    }

    func testDateChangePreservesTimeAndDeadline() {
        let current = TaskSchedule(dueAt: date(1, 1, 14), hasTime: true, deadlineAt: date(2, 1))
        let moved = TaskDateDraft.movingDay(current.dueAt!, to: date(1, 5), calendar: calendar)
        let result = TaskDateDraft.applying(date: moved, hasTime: true, deadline: false, to: current, calendar: calendar)
        XCTAssertEqual(result.dueAt, date(1, 5, 14))
        XCTAssertEqual(result.deadlineAt, current.deadlineAt)
        XCTAssertTrue(result.hasTime)
        XCTAssertEqual(current.dueAt, date(1, 1, 14))
    }

    func testClearAndDeadlineAreIndependent() {
        let current = TaskSchedule(dueAt: date(1, 1), hasTime: true, deadlineAt: date(2, 1))
        let cleared = TaskDateDraft.applying(date: nil, hasTime: true, deadline: false, to: current, calendar: calendar)
        XCTAssertNil(cleared.dueAt)
        XCTAssertFalse(cleared.hasTime)
        XCTAssertEqual(cleared.deadlineAt, current.deadlineAt)
        let deadline = TaskDateDraft.applying(date: nil, hasTime: false, deadline: true, to: current, calendar: calendar)
        XCTAssertEqual(deadline.dueAt, current.dueAt)
        XCTAssertTrue(deadline.hasTime)
        XCTAssertNil(deadline.deadlineAt)
    }

    func testUndoCompletionRemovesNewOccurrenceAndRestoresCount() {
        let store = WorkspaceStore()
        let actions = TaskActions(store: store, clock: { self.date(1, 1) }, calendar: calendar)
        let id = actions.create(title: "task").taskID!
        actions.setRecurrence(id, frequency: .weekly, rule: RecurrenceRule(remainingCount: 3))
        actions.complete(id)
        actions.undo()
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.task(id)?.status, .active)
        XCTAssertEqual(store.task(id)?.recurrenceRule?.remainingCount, 3)
    }
}
