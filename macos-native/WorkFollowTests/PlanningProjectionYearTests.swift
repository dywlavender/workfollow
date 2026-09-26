import XCTest
@testable import WorkFollow

final class PlanningProjectionYearTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 1
        return value
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeTask(
        _ title: String, dueAt: Date? = nil, deadlineAt: Date? = nil,
        status: TaskStatus = .active, deleted: Bool = false,
        abandoned: Bool = false, skipped: Bool = false
    ) -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        var task = Task(id: UUID(), title: title, list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: dueAt, deadlineAt: deadlineAt),
                        status: status, parentID: nil, childOrder: 0,
                        createdAt: stamp, updatedAt: stamp)
        task.deletedAt = deleted ? stamp : nil
        task.abandonedAt = abandoned ? stamp : nil
        task.skippedAt = skipped ? stamp : nil
        return task
    }

    // MARK: - yearMonths

    func testYearMonthsReturnsTwelveMonthFirstDays() {
        let months = PlanningProjection.yearMonths(containing: 2026, calendar: calendar)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first, calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        XCTAssertEqual(months.last, calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        XCTAssertTrue(months.enumerated().allSatisfy { index, month in
            calendar.component(.month, from: month) == index + 1
                && calendar.component(.day, from: month) == 1
        })
    }

    // MARK: - monthGrid

    func testMonthGridForFebruary2026KeepsTwentyEightDaysAndTrailingPadding() throws {
        // 2026-02-01 is a Sunday and the test calendar starts weeks on Sunday,
        // so the 28-day month only pads the 14 trailing slots of the 6x7 grid.
        let grid = PlanningProjection.monthGrid(in: day(2026, 2, 15), calendar: calendar)
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(grid.compactMap { $0 }.count, 28)
        XCTAssertTrue(grid[0..<28].allSatisfy { $0 != nil })
        XCTAssertTrue(grid[28..<42].allSatisfy { $0 == nil })
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(grid[0])), 1)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(grid[27])), 28)
        XCTAssertTrue(grid.compactMap { $0 }.allSatisfy { calendar.component(.month, from: $0) == 2 })
    }

    func testMonthGridPadsLeadingAndTrailingSlotsForApril2026() throws {
        // 2026-04-01 is a Wednesday: three leading empty slots before the 30
        // days, nine trailing empty slots after. Non-nil slots must equal the
        // in-month slice of monthDays, proving the shared week-start rule.
        let grid = PlanningProjection.monthGrid(in: day(2026, 4, 15), calendar: calendar)
        XCTAssertEqual(grid.count, 42)
        XCTAssertTrue(grid[0..<3].allSatisfy { $0 == nil })
        let first = try XCTUnwrap(grid[3])
        XCTAssertEqual(calendar.component(.month, from: first), 4)
        XCTAssertEqual(calendar.component(.day, from: first), 1)
        let last = try XCTUnwrap(grid[32])
        XCTAssertEqual(calendar.component(.day, from: last), 30)
        XCTAssertTrue(grid[33..<42].allSatisfy { $0 == nil })
        XCTAssertEqual(
            grid.compactMap { $0 },
            PlanningProjection.monthDays(containing: day(2026, 4, 15), calendar: calendar)
                .filter { calendar.isDate($0, equalTo: day(2026, 4, 15), toGranularity: .month) })
    }

    // MARK: - countsByDay

    func testCountsByDayAggregatesSameDayAndSpansMonths() {
        let tasks = [
            makeTask("morning", dueAt: day(2026, 2, 10, hour: 9)),
            makeTask("evening", dueAt: day(2026, 2, 10, hour: 21)),
            makeTask("march", dueAt: day(2026, 3, 5)),
            makeTask("december", dueAt: day(2026, 12, 31)),
        ]
        let counts = PlanningProjection.countsByDay(tasks: tasks, in: 2026,
                                                    calendar: calendar, includeCompleted: true)
        XCTAssertEqual(counts[calendar.startOfDay(for: day(2026, 2, 10))], 2)
        XCTAssertEqual(counts[calendar.startOfDay(for: day(2026, 3, 5))], 1)
        XCTAssertEqual(counts[calendar.startOfDay(for: day(2026, 12, 31))], 1)
        XCTAssertEqual(counts.count, 3)
        XCTAssertEqual(counts.values.reduce(0, +), 4)
    }

    func testCountsByDayIgnoresOtherYearsUndatedAndDeadlineOnlyTasks() {
        let tasks = [
            makeTask("previous year", dueAt: day(2025, 12, 31)),
            makeTask("next year", dueAt: day(2027, 1, 1)),
            makeTask("undated", dueAt: nil),
            makeTask("deadline only", deadlineAt: day(2026, 2, 10)),
        ]
        let counts = PlanningProjection.countsByDay(tasks: tasks, in: 2026,
                                                    calendar: calendar, includeCompleted: true)
        XCTAssertTrue(counts.isEmpty)
    }

    func testCountsByDayHonorsIncludeCompletedFilter() {
        let tasks = [
            makeTask("done", dueAt: day(2026, 2, 10), status: .completed),
            makeTask("open", dueAt: day(2026, 2, 10)),
        ]
        let key = calendar.startOfDay(for: day(2026, 2, 10))
        XCTAssertEqual(PlanningProjection.countsByDay(tasks: tasks, in: 2026,
                                                      calendar: calendar, includeCompleted: true)[key], 2)
        XCTAssertEqual(PlanningProjection.countsByDay(tasks: tasks, in: 2026,
                                                      calendar: calendar, includeCompleted: false)[key], 1)
    }

    func testCountsByDayAlwaysDropsDeletedAbandonedAndSkippedTasks() {
        let tasks = [
            makeTask("deleted", dueAt: day(2026, 2, 10), deleted: true),
            makeTask("abandoned", dueAt: day(2026, 2, 10), abandoned: true),
            makeTask("skipped", dueAt: day(2026, 2, 10), skipped: true),
            makeTask("kept", dueAt: day(2026, 2, 10)),
        ]
        let key = calendar.startOfDay(for: day(2026, 2, 10))
        XCTAssertEqual(PlanningProjection.countsByDay(tasks: tasks, in: 2026,
                                                      calendar: calendar, includeCompleted: true)[key], 1)
        XCTAssertEqual(PlanningProjection.countsByDay(tasks: tasks, in: 2026,
                                                      calendar: calendar, includeCompleted: false)[key], 1)
    }

    func testCountsByDayMatchesTasksOnDayRule() {
        // The heat map must not invent a second day rule: for the visible task
        // set, each day's count equals PlanningProjection.tasks(on:).count.
        let tasks = [
            makeTask("a", dueAt: day(2026, 2, 10, hour: 8)),
            makeTask("b", dueAt: day(2026, 2, 10, hour: 9), deleted: true),
            makeTask("c", dueAt: day(2026, 2, 11)),
        ]
        let visible = tasks.filter { $0.deletedAt == nil && $0.skippedAt == nil && !$0.isAbandoned }
        let key = calendar.startOfDay(for: day(2026, 2, 10))
        let counts = PlanningProjection.countsByDay(tasks: tasks, in: 2026,
                                                    calendar: calendar, includeCompleted: true)
        XCTAssertEqual(counts[key],
                       PlanningProjection.tasks(on: key, from: visible, calendar: calendar).count)
    }

    // MARK: - heatLevel

    func testHeatLevelBucketsCountBoundaries() {
        XCTAssertEqual(PlanningProjection.heatLevel(count: 0), 0)
        XCTAssertEqual(PlanningProjection.heatLevel(count: 1), 1)
        XCTAssertEqual(PlanningProjection.heatLevel(count: 2), 2)
        XCTAssertEqual(PlanningProjection.heatLevel(count: 3), 3)
        XCTAssertEqual(PlanningProjection.heatLevel(count: 4), 3)
        XCTAssertEqual(PlanningProjection.heatLevel(count: 5), 4)
        XCTAssertEqual(PlanningProjection.heatLevel(count: 12), 4)
    }
}
