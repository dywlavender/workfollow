import XCTest
@testable import WorkFollow

final class MatrixConfigurationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    private var now: Date { date(13, hour: 12) }
    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func task(priority: TaskPriority = .none, start: Date? = nil, end: Date? = nil) -> Task {
        Task(id: UUID(), title: "方案", list: .inbox, priority: priority,
             schedule: TaskSchedule(dueAt: start, hasTime: start.map { calendar.component(.hour, from: $0) != 0 } ?? false, dueEndAt: end),
             childOrder: 0,
             createdAt: date(1), updatedAt: date(1))
    }
    func testNarrowRowsCollapseSecondaryMetadataAndBoundLongListNames() {
        let narrow = MatrixTaskRowLayout(width: 240)
        XCTAssertFalse(narrow.showsSecondaryIcons)
        XCTAssertEqual(narrow.listNameWidth, 0)
        let medium = MatrixTaskRowLayout(width: 360)
        XCTAssertFalse(medium.showsSecondaryIcons)
        XCTAssertLessThanOrEqual(medium.listNameWidth, 64)
        let wide = MatrixTaskRowLayout(width: 600)
        XCTAssertTrue(wide.showsSecondaryIcons)
        XCTAssertLessThanOrEqual(wide.listNameWidth, 96)
    }
    func testLegacyClassificationSurvivesDefaultConfiguration() {
        for priority in TaskPriority.menuOrder {
            for start in [nil, date(10), date(13), date(16), date(17)] {
                let value = task(priority: priority, start: start)
                XCTAssertEqual(MatrixConfiguration.legacy.quadrant(for: value, now: now, calendar: calendar)?.rawValue,
                               PlanningProjection.quadrant(value, now: now, calendar: calendar))
            }
        }
    }
    func testPriorityPresetDropKeepsScheduleAndChangesOnlyPriority() {
        let original = task(start: date(20, hour: 9), end: date(20, hour: 10))
        let proposal = MatrixDropPlanner.propose(task: original, target: .doNow, configuration: .makePreset(.priority), now: now, calendar: calendar)
        XCTAssertEqual(proposal.priority, .high)
        XCTAssertNil(proposal.schedule)
        XCTAssertTrue(proposal.canCommit)
    }
    func testSameQuadrantDropIsANoOpForTaskAttributes() {
        let original = task(priority: .medium, start: date(14, hour: 9), end: date(14, hour: 10))
        let proposal = MatrixDropPlanner.propose(task: original, target: .doNow, configuration: .legacy, now: now, calendar: calendar)
        XCTAssertTrue(proposal.isNoOp)
    }
    func testCrossQuadrantChangesNearestRequiredDayAndPreservesTimeAndDuration() {
        let original = task(start: date(20, hour: 9), end: date(20, hour: 10))
        let proposal = MatrixDropPlanner.propose(task: original, target: .doNow, configuration: .legacy, now: now, calendar: calendar)
        XCTAssertEqual(proposal.schedule?.dueAt, date(16, hour: 9))
        XCTAssertEqual(proposal.schedule?.dueEndAt, date(16, hour: 10))
        XCTAssertEqual(proposal.priority, .high)
    }
    func testDisplayOrderDoesNotChangeClassificationPrecedence() {
        var configuration = MatrixConfiguration.legacy
        let original = task(priority: .high, start: date(13))
        configuration.move(.later, before: .doNow)
        XCTAssertEqual(configuration.displayOrder.first, .later)
        XCTAssertEqual(configuration.quadrant(for: original, now: now, calendar: calendar), .doNow)
    }
    func testRuleCanExcludeTasksAndOrganizationProposalIsExplicit() {
        var configuration = MatrixConfiguration.makePreset(.priority)
        for index in configuration.quadrants.indices { configuration.quadrants[index].rule.listNames = ["工作"] }
        let original = task(priority: .high)
        XCTAssertNil(configuration.quadrant(for: original, now: now, calendar: calendar))
        let proposal = MatrixDropPlanner.propose(task: original, target: .doNow, configuration: configuration, now: now, calendar: calendar)
        XCTAssertEqual(proposal.list?.name, "工作")
        XCTAssertEqual(proposal.listChoices, ["工作"])
        XCTAssertNil(proposal.priority)
        XCTAssertTrue(proposal.canCommit)
    }
    @MainActor func testCrossQuadrantAttributeTransactionUndoesInOneStep() {
        let original = task(start: date(20, hour: 9), end: date(20, hour: 10))
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false, initialTasks: [original])
        let storedBefore = workspace.task(for: original.id)!
        let proposal = MatrixDropPlanner.propose(task: storedBefore, target: .doNow, configuration: .legacy, now: now, calendar: calendar)
        _ = workspace.updateAttributes(original.id, priority: proposal.priority, schedule: proposal.schedule)
        XCTAssertEqual(workspace.task(for: original.id)?.priority, .high)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: original.id), storedBefore)
        XCTAssertFalse(workspace.canUndo)
    }
    @MainActor func testConfigurationPersistenceAndUndoDoNotTouchTasks() {
        let suite = "planning-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlanningSettingsStore(defaults: defaults)
        store.updateMatrix { $0 = .makePreset(.priority) }
        store.updateCalendar { $0.mode = .week; $0.showCompleted = false }
        let reopened = PlanningSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.matrix.preset, .priority)
        XCTAssertEqual(reopened.calendar.mode, .week)
        XCTAssertFalse(reopened.calendar.showCompleted)
        store.undoConfiguration()
        XCTAssertEqual(store.matrix.preset, .legacyThreeDays)
        store.redoConfiguration()
        XCTAssertEqual(store.matrix.preset, .priority)
    }
}
