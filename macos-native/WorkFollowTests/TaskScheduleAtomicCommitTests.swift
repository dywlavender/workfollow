import XCTest
@testable import WorkFollow

@MainActor
final class TaskScheduleAtomicCommitTests: XCTestCase {
    func testTimingAndOffsetsCommitOnceWithoutBulkSelectionOrFeedbackAndUndoTogether() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = workspace.createTask(title: "日期测试", in: .inbox).taskID!
        let other = workspace.createTask(title: "保留选择", in: .inbox).taskID!
        workspace.bulkSelection = [other]
        let before = try XCTUnwrap(workspace.task(for: id))
        let revision = workspace.revision
        let feedback = FeedbackCenter()
        workspace.feedbackSink = feedback
        let due = Date(timeIntervalSince1970: 1_790_000_000)
        let schedule = TaskSchedule(dueAt: due, hasTime: true)
        workspace.saveTiming(id, schedule: schedule, reminder: due.addingTimeInterval(-1800),
                             frequency: .monthly, reminderOffsets: [-30, 0])
        let saved = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(saved.schedule, schedule)
        XCTAssertEqual(saved.reminderOffsets, [-30, 0])
        XCTAssertEqual(saved.recurrence, .monthly)
        XCTAssertEqual(workspace.revision, revision + 1)
        XCTAssertEqual(workspace.bulkSelection, [other])
        XCTAssertNil(feedback.presentation)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id), before, "A single undo restores the whole timing edit")
    }

    func testClearScheduleAndOffsetsUndoAsOneOperation() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = workspace.createTask(title: "清除测试", in: .inbox).taskID!
        let due = Date(timeIntervalSince1970: 1_790_000_000)
        workspace.saveTiming(id, schedule: TaskSchedule(dueAt: due, hasTime: true),
                             reminder: due, frequency: .daily, reminderOffsets: [0])
        let before = try XCTUnwrap(workspace.task(for: id))
        let draft = TaskDateDraftModel(task: before, calendar: workspace.calendar, now: workspace.clock, deadline: false)
        let plan = draft.clearPlan(for: before)
        workspace.saveTiming(id, schedule: plan.schedule, reminder: plan.reminder,
                             frequency: plan.frequency, recurrenceRule: plan.recurrenceRule,
                             reminderOffsets: plan.reminderOffsets)
        XCTAssertNil(workspace.task(for: id)?.schedule.dueAt)
        XCTAssertEqual(workspace.task(for: id)?.reminderOffsets ?? [], [])
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id), before)
    }
}
