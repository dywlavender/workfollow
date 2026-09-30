import XCTest
@testable import WorkFollow

@MainActor
final class FocusTaskPickerInteractionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
    }

    func testOpenStartsTodayWithEmptySearchAndReopeningResetsBoth() {
        let session = FocusTaskPickerSession()
        session.scope = .tomorrow
        session.query = "stale query"

        session.present()

        XCTAssertTrue(session.isPresented)
        XCTAssertEqual(session.scope, .today)
        XCTAssertEqual(session.query, "")

        session.selectScope(.tomorrow)
        session.query = "another query"
        session.dismiss()
        session.present()

        XCTAssertTrue(session.isPresented)
        XCTAssertFalse(session.isScopePickerPresented)
        XCTAssertEqual(session.scope, .today)
        XCTAssertEqual(session.query, "")
    }

    func testSelectingTomorrowClosesOnlyScopePanelAndImmediatelyChangesResults() {
        let tomorrow = makeTask("明天任务", dueAt: date(2026, 10, 1))
        let today = makeTask("今天任务", dueAt: now)
        let workspace = makeWorkspace(tasks: [today, tomorrow])
        let session = FocusTaskPickerSession()
        session.present()
        session.presentScopePicker()

        session.selectScope(.tomorrow)

        XCTAssertTrue(session.isPresented)
        XCTAssertFalse(session.isScopePickerPresented)
        XCTAssertEqual(session.scope, .tomorrow)
        let results = FocusTaskPickerProjection.groups(
            tasks: workspace.allTasks, scope: session.scope, query: session.query,
            now: now, calendar: calendar
        ).flatMap(\.tasks)
        XCTAssertEqual(results.map(\.id), [tomorrow.id])
    }

    func testSelectingTaskClosesPickerAndUpdatesLinkedTaskTitle() {
        let task = makeTask("准备季度评审", dueAt: now)
        let workspace = makeWorkspace(tasks: [task])
        let session = FocusTaskPickerSession()
        session.present()

        session.selectTask(task.id)

        XCTAssertFalse(session.isPresented)
        XCTAssertEqual(session.linkedTaskID, task.id)
        XCTAssertEqual(workspace.task(for: session.linkedTaskID!)?.title, "准备季度评审")
    }

    func testSelectingUnlinkClearsTaskAndClosesPicker() {
        let task = makeTask("已关联任务", dueAt: now)
        let session = FocusTaskPickerSession(linkedTaskID: task.id)
        session.present()

        session.selectTask(nil)

        XCTAssertNil(session.linkedTaskID)
        XCTAssertFalse(session.isPresented)
    }

    func testOutsideDismissalUsesPopoverBindingAndDoesNotChangeLinkedTask() {
        let originalTaskID = UUID()
        let session = FocusTaskPickerSession(linkedTaskID: originalTaskID)
        session.present()
        session.presentScopePicker()

        session.presentationBinding.wrappedValue = false

        XCTAssertFalse(session.isPresented)
        XCTAssertFalse(session.isScopePickerPresented)
        XCTAssertEqual(session.linkedTaskID, originalTaskID)
    }

    func testEscapeClosesScopeThenPickerWithoutChangingLinkedTask() {
        let originalTaskID = UUID()
        let session = FocusTaskPickerSession(linkedTaskID: originalTaskID)
        session.present()
        session.presentScopePicker()

        session.handleEscape()

        XCTAssertFalse(session.isScopePickerPresented)
        XCTAssertTrue(session.isPresented)
        XCTAssertEqual(session.linkedTaskID, originalTaskID)

        session.handleEscape()

        XCTAssertFalse(session.isPresented)
        XCTAssertEqual(session.linkedTaskID, originalTaskID)
    }

    private func makeWorkspace(tasks: [Task]) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
                           seedDemoData: false, initialTasks: tasks)
    }

    private func makeTask(_ title: String, dueAt: Date) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none,
             schedule: TaskSchedule(dueAt: dueAt), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }
}
