import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTimelineInteractionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func task(timed: Bool = true, repeating: Bool = false, point: Bool = false) -> Task {
        Task(id: UUID(), title: "排期交付", document: NativeDocument(plainText: "保留正文"),
             tags: ["交付"], recurrence: repeating ? .daily : .never,
             reminderAt: date(18, 8, 45), reminderOffsets: [-15, 0],
             list: TaskList(name: "工作"), priority: .high,
             schedule: TaskSchedule(dueAt: timed ? date(18, 9) : date(18), hasTime: timed,
                dueEndAt: point ? nil : (timed ? date(19, 10) : date(20)), deadlineAt: date(28)),
             childOrder: 0, createdAt: date(1), updatedAt: date(1))
    }
    private func workspace(_ tasks: [Task]) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.date(18, 12) }, calendar: calendar,
            seedDemoData: false, initialTasks: tasks, initialLists: ["工作"])
    }
    private func controller(_ workspace: TaskWorkspaceModel) -> TaskTimelineInteractionController {
        TaskTimelineInteractionController(workspace: workspace, tasks: workspace.allTasks)
    }
    private func committed(_ outcome: CalendarInteractionOutcome,
                           file: StaticString = #filePath, line: UInt = #line) {
        guard case .committed(let result) = outcome, case .success = result else {
            return XCTFail("Expected one committed schedule action", file: file, line: line)
        }
    }

    func testDayMovePreservesClockDurationReminderAndSingleUndoRedo() throws {
        let original = task()
        let workspace = workspace([original])
        let before = try XCTUnwrap(workspace.task(for: original.id))
        let revision = workspace.revision
        committed(controller(workspace).move(original.id, byDays: 2))
        let after = try XCTUnwrap(workspace.task(for: original.id))
        XCTAssertEqual(after.schedule.dueAt, date(20, 9))
        XCTAssertEqual(after.schedule.dueEndAt, date(21, 10))
        XCTAssertEqual(after.reminderAt, date(20, 8, 45))
        XCTAssertEqual(after.reminderOffsets, before.reminderOffsets)
        XCTAssertEqual(after.schedule.deadlineAt, before.schedule.deadlineAt)
        XCTAssertEqual(after.document, before.document)
        XCTAssertEqual(after.tags, before.tags)
        XCTAssertEqual(after.priority, before.priority)
        XCTAssertEqual(workspace.revision, revision + 1)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: original.id), before)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.task(for: original.id), after)
    }

    func testAllDayMoveKeepsInclusiveSpanAndOtherProperties() throws {
        let original = task(timed: false)
        let workspace = workspace([original])
        let before = try XCTUnwrap(workspace.task(for: original.id))
        committed(controller(workspace).move(original.id, byDays: 4))
        let after = try XCTUnwrap(workspace.task(for: original.id))
        XCTAssertEqual(after.schedule.dueAt, date(22))
        XCTAssertEqual(after.schedule.dueEndAt, date(24))
        XCTAssertFalse(after.schedule.hasTime)
        XCTAssertEqual(after.reminderAt, date(22, 8, 45))
        workspace.undo()
        XCTAssertEqual(workspace.task(for: original.id), before)
        XCTAssertFalse(workspace.canUndo)
    }

    func testTimedAndAllDayBoundaryResizesKeepOppositeEdgeAndUndoTogether() throws {
        for timed in [false, true] {
            for edge in [CalendarResizeEdge.start, .end] {
                let original = task(timed: timed)
                let workspace = workspace([original])
                let before = try XCTUnwrap(workspace.task(for: original.id))
                let days = edge == .start ? -2 : 2
                committed(controller(workspace).resize(original.id, edge: edge, byDays: days))
                let after = try XCTUnwrap(workspace.task(for: original.id))
                if edge == .start {
                    XCTAssertEqual(after.schedule.dueAt, timed ? date(16, 9) : date(16))
                    XCTAssertEqual(after.schedule.dueEndAt, before.schedule.dueEndAt)
                    XCTAssertEqual(after.reminderAt, date(16, 8, 45))
                } else {
                    XCTAssertEqual(after.schedule.dueAt, before.schedule.dueAt)
                    XCTAssertEqual(after.schedule.dueEndAt, timed ? date(21, 10) : date(22))
                    XCTAssertEqual(after.reminderAt, before.reminderAt)
                }
                XCTAssertEqual(after.schedule.deadlineAt, before.schedule.deadlineAt)
                XCTAssertEqual(after.schedule.hasTime, timed)
                workspace.undo()
                XCTAssertEqual(workspace.task(for: original.id), before)
                XCTAssertFalse(workspace.canUndo)
            }
        }
    }

    func testPointCanExpandLeftWithItsOriginalDateAsTheFixedRightEdge() throws {
        let original = task(point: true)
        let workspace = workspace([original])
        committed(controller(workspace).resize(original.id, edge: .start, byDays: -1))
        let after = try XCTUnwrap(workspace.task(for: original.id))
        XCTAssertEqual(after.schedule.dueAt, date(17, 9))
        XCTAssertEqual(after.schedule.dueEndAt, date(18, 9))
        XCTAssertEqual(after.reminderAt, date(17, 8, 45))
    }

    func testFirstPoolDropSchedulesTheSameTaskWithoutInventingAnEnd() throws {
        var original = task()
        original.schedule = TaskSchedule(deadlineAt: date(28))
        let workspace = workspace([original])
        let before = try XCTUnwrap(workspace.task(for: original.id))
        committed(controller(workspace).drop([original.id.uuidString], on: date(22, 16)))
        let after = try XCTUnwrap(workspace.task(for: original.id))
        XCTAssertEqual(after.schedule.dueAt, date(22))
        XCTAssertFalse(after.schedule.hasTime)
        XCTAssertNil(after.schedule.dueEndAt)
        XCTAssertEqual(after.schedule.deadlineAt, before.schedule.deadlineAt)
        XCTAssertEqual(after.reminderAt, before.reminderAt)
        XCTAssertEqual(after.reminderOffsets, before.reminderOffsets)
        XCTAssertEqual(after.document, before.document)
        XCTAssertTrue(TaskTimelineLayout.partition(workspace.allTasks).unscheduled.isEmpty)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: original.id), before)
        XCTAssertFalse(workspace.canUndo)
    }

    func testSameDayAndCancelledDraftLeaveHistoryUntouched() throws {
        let original = task()
        let workspace = workspace([original])
        let before = workspace.allTasks
        guard case .unchanged = controller(workspace).move(original.id, byDays: 0) else {
            return XCTFail("Same schedule is unchanged")
        }
        var draft = TaskTimelineGestureDraft()
        draft.update(original.schedule, operation: .end, translation: 88,
                     dayWidth: 88, calendar: calendar)
        XCTAssertEqual(draft.schedule?.dueEndAt, date(20, 10))
        XCTAssertEqual(workspace.allTasks, before)
        draft.cancel()
        draft.update(original.schedule, operation: .end, translation: 176,
                     dayWidth: 88, calendar: calendar)
        XCTAssertNil(draft.finish())
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(workspace.canUndo)
    }

    func testDragUpdatesStayLocalAndUseTheOriginalScheduleUntilOneMouseUpCommit() throws {
        let original = task()
        let workspace = workspace([original])
        let before = workspace.allTasks
        let revision = workspace.revision
        var draft = TaskTimelineGestureDraft()
        for translation in [CGFloat(88), CGFloat(176), CGFloat(88)] {
            draft.update(original.schedule, operation: .move, translation: translation,
                         dayWidth: 88, calendar: calendar)
            XCTAssertEqual(workspace.allTasks, before)
            XCTAssertEqual(workspace.revision, revision)
            XCTAssertFalse(workspace.canUndo)
        }
        let schedule = try XCTUnwrap(draft.finish())
        XCTAssertEqual(schedule.dueAt, date(19, 9), "Translation is relative to the press, not the previous preview")
        committed(controller(workspace).apply(original.id, schedule: schedule))
        XCTAssertEqual(workspace.revision, revision + 1)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(workspace.canUndo)
    }

    func testRepeatMoveRequestsScopeBeforeAnyWriteAndOnlyThisUndoesOnce() throws {
        let original = task(repeating: true)
        let workspace = workspace([original])
        let before = workspace.allTasks
        let revision = workspace.revision
        let interaction = controller(workspace)
        guard case .requiresScope(let occurrence, let plan) = interaction.move(original.id, byDays: 2) else {
            return XCTFail("Stored repeating tasks must also request a scope")
        }
        XCTAssertEqual(plan.schedule.dueAt, date(20, 9))
        XCTAssertEqual(plan.reminder, date(20, 8, 45))
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertEqual(workspace.revision, revision)
        XCTAssertFalse(workspace.canUndo)
        let request = TaskTimelinePendingSchedule(occurrence: occurrence, plan: plan)
        XCTAssertNotNil(interaction.confirm(request, scope: .onlyThis).taskID)
        let after = try XCTUnwrap(workspace.task(for: original.id))
        XCTAssertEqual(after.schedule.dueAt, date(20, 9))
        XCTAssertEqual(after.occurrenceOverride?.occurrence, occurrence.key)
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(workspace.canUndo)
    }

    func testRepeatRangeScopesUseStoredOccurrencesAndKeepCompletedHistory() throws {
        for scope in [RecurrenceEditScope.thisAndFuture, .allNotCompleted] {
            var source = task(repeating: true)
            source.schedule = TaskSchedule(dueAt: date(17, 9), hasTime: true, dueEndAt: date(17, 10), deadlineAt: date(28))
            source.reminderAt = date(17, 8, 45)
            let series = TaskSeries(task: source, calendar: calendar, now: date(18))
            var stored = (0..<4).map { ordinal in
                let start = date(17 + ordinal, 9)
                let key = OccurrenceKey(seriesID: series.id, nominalDate: start, ordinal: ordinal)
                return series.template.task(id: ordinal == 0 ? source.id : UUID(), at: start, series: series, key: key)
            }
            stored[0].status = .completed; stored[0].completedAt = date(17, 11)
            let targetID = stored[2].id
            let earlierID = stored[1].id
            let laterID = stored[3].id
            let workspace = workspace(stored)
            let before = workspace.allTasks
            let interaction = TaskTimelineInteractionController(workspace: workspace,
                tasks: workspace.allTasks.filter { !$0.isClosed })
            guard case .requiresScope(let occurrence, let plan) = interaction.move(targetID, byDays: 2) else {
                return XCTFail("Expected a recurrence scope")
            }
            let request = TaskTimelinePendingSchedule(occurrence: occurrence, plan: plan)
            XCTAssertNotNil(interaction.confirm(request, scope: scope).taskID)
            XCTAssertEqual(workspace.task(for: source.id), before.first { $0.id == source.id })
            XCTAssertEqual(workspace.task(for: targetID)?.schedule.dueAt, date(21, 9))
            XCTAssertEqual(workspace.task(for: laterID)?.schedule.dueAt, date(22, 9))
            XCTAssertEqual(workspace.task(for: earlierID)?.schedule.dueAt,
                           scope == .thisAndFuture ? date(18, 9) : date(20, 9))
            XCTAssertEqual(workspace.task(for: targetID)?.reminderAt, date(21, 8, 45))
            workspace.undo()
            XCTAssertEqual(workspace.allTasks, before)
            XCTAssertFalse(workspace.canUndo)
        }
    }

    private final class DragState: ObservableObject {
        @Published var draft = TaskTimelineGestureDraft()
        var escapeCount = 0
        func cancel() { escapeCount += 1; draft.cancel() }
    }
    private struct EscapeHarness: View {
        @ObservedObject var state: DragState
        var body: some View {
            Color.clear.background(TaskTimelineGestureEscapeRouter(isActive: state.draft.isActive) { state.cancel() })
        }
    }

    func testNativeEscapeCancelsActiveDragWhenAnotherResponderOwnsFocus() throws {
        let original = task()
        let workspace = workspace([original])
        let before = workspace.allTasks
        let state = DragState()
        state.draft.update(original.schedule, operation: .move, translation: 88,
                           dayWidth: 88, calendar: calendar)
        let host = NSHostingView(rootView: EscapeHarness(state: state).frame(width: 400, height: 160))
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))
        host.frame = NSRect(x: 0, y: 60, width: 400, height: 160)
        let field = NSTextField(string: "其他输入框")
        field.frame = NSRect(x: 10, y: 10, width: 200, height: 28)
        root.addSubview(host); root.addSubview(field)
        let window = InspectorPanelTestSupport.ownerWindow(for: root, width: 400, height: 220)
        defer { window.contentView = nil; window.close() }
        XCTAssertTrue(window.makeFirstResponder(field))
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(escape)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(state.escapeCount, 1)
        state.draft.update(original.schedule, operation: .move, translation: 176,
                           dayWidth: 88, calendar: calendar)
        if let schedule = state.draft.finish() { _ = controller(workspace).apply(original.id, schedule: schedule) }
        XCTAssertEqual(workspace.allTasks, before)
        XCTAssertFalse(workspace.canUndo)
        state.draft.update(original.schedule, operation: .move, translation: 88,
                           dayWidth: 88, calendar: calendar)
        let next = try XCTUnwrap(state.draft.finish(), "A new press can commit after Escape")
        committed(controller(workspace).apply(original.id, schedule: next))
        XCTAssertEqual(workspace.task(for: original.id)?.schedule.dueAt, date(19, 9))
    }
}
