import Combine
import Foundation
import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanReorderTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28_800)!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
    }

    private func task(_ title: String, priority: TaskPriority = .high,
                      parent: UUID? = nil, childOrder: Int = 0) -> Task {
        Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: priority,
             schedule: TaskSchedule(), parentID: parent, childOrder: childOrder,
             createdAt: now, updatedAt: now)
    }

    private func workspace(_ tasks: [Task]) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false,
                           initialTasks: tasks, initialLists: ["工作", "个人"])
    }

    private func rootIDs(_ workspace: TaskWorkspaceModel) -> [UUID] {
        workspace.allTasks.filter { $0.parentID == nil }.map(\.id)
    }

    private func childIDs(_ workspace: TaskWorkspaceModel, parent: UUID) -> [UUID] {
        workspace.allTasks.filter { $0.parentID == parent }
            .sorted { $0.childOrder < $1.childOrder }.map(\.id)
    }

    func testRootMoveToColumnStartKeepsDescendantsAndOtherColumnOrder() {
        let first = task("列内首项"), middle = task("列内中项"), last = task("列内末项")
        let child = task("首项的子任务", priority: .low, parent: first.id)
        let otherFirst = task("其他列甲", priority: .medium)
        let otherLast = task("其他列乙", priority: .medium)
        let workspace = workspace([first, child, otherFirst, middle, otherLast, last])
        let original = workspace.allTasks
        let originalChild = workspace.task(for: child.id)

        XCTAssertTrue(workspace.canAcceptKanbanDrop(last.id, to: nil,
                                                   columnTaskIDs: [first.id, child.id, middle.id, last.id]))
        XCTAssertTrue(workspace.applyKanbanDrop(last.id, to: nil, insertion: .before(first.id),
                                               columnTaskIDs: [first.id, child.id, middle.id, last.id]))
        XCTAssertEqual(rootIDs(workspace), [last.id, first.id, otherFirst.id, middle.id, otherLast.id])
        XCTAssertEqual(workspace.task(for: child.id), originalChild)
        XCTAssertEqual(childIDs(workspace, parent: first.id), [child.id])
        XCTAssertEqual(workspace.allTasks.filter { $0.priority == .medium }.map(\.id),
                       [otherFirst.id, otherLast.id])
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testRootMoveToColumnEndKeepsOtherColumnOrderAndReplaysInOneStep() {
        let first = task("列内首项"), middle = task("列内中项"), last = task("列内末项")
        let otherFirst = task("其他列甲", priority: .low)
        let otherLast = task("其他列乙", priority: .low)
        let workspace = workspace([first, otherFirst, middle, otherLast, last])
        let original = workspace.allTasks

        XCTAssertTrue(workspace.applyKanbanDrop(first.id, to: .priority(.high), insertion: .after(last.id),
                                               columnTaskIDs: [first.id, middle.id, last.id]))
        XCTAssertEqual(rootIDs(workspace), [otherFirst.id, middle.id, otherLast.id, last.id, first.id])
        XCTAssertEqual(workspace.allTasks.filter { $0.priority == .low }.map(\.id),
                       [otherFirst.id, otherLast.id])
        let moved = workspace.allTasks
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, moved)
    }

    func testCrossColumnAttributeAndPositionPublishAndUndoTogether() throws {
        let first = task("目标列首项"), last = task("目标列末项")
        let unrelated = task("无关任务", priority: .medium)
        var source = task("跨列任务", priority: .low)
        source.schedule = TaskSchedule(dueAt: now, hasTime: true)
        source.reminderAt = now.addingTimeInterval(-600)
        let workspace = workspace([first, unrelated, last, source])
        let original = workspace.allTasks
        let originalRevision = workspace.revision
        var publications: [TaskChangeSet] = []
        let subscription = workspace.taskChanges.sink { publications.append($0) }
        defer { subscription.cancel() }

        XCTAssertTrue(workspace.applyKanbanDrop(source.id, to: .priority(.high), insertion: .before(last.id),
                                               columnTaskIDs: [first.id, last.id]))
        let movedSource = try XCTUnwrap(workspace.task(for: source.id))
        XCTAssertEqual(movedSource.priority, .high)
        XCTAssertEqual(movedSource.schedule, source.schedule)
        XCTAssertEqual(movedSource.reminderAt, source.reminderAt)
        XCTAssertEqual(rootIDs(workspace), [first.id, unrelated.id, source.id, last.id])
        XCTAssertEqual(publications.count, 1)
        XCTAssertEqual(publications.first?.entries.map(\.taskID), [source.id])
        XCTAssertNotNil(publications.first?.order)
        XCTAssertEqual(workspace.revision, originalRevision + 1)
        let moved = workspace.allTasks

        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
        workspace.redo()
        XCTAssertEqual(workspace.allTasks, moved)
    }

    func testSameParentChildrenReorderWithoutInheritingColumnAttributes() throws {
        let parent = task("父任务")
        var first = task("子任务甲", priority: .medium, parent: parent.id, childOrder: 0)
        first.schedule = TaskSchedule(dueAt: now.addingTimeInterval(86_400))
        var last = task("子任务乙", priority: .low, parent: parent.id, childOrder: 1)
        last.schedule = TaskSchedule(dueAt: now.addingTimeInterval(172_800), hasTime: true)
        last.tags = ["子任务自己的标签"]
        last.reminderAt = now.addingTimeInterval(172_200)
        let targets: [TaskKanbanCreationTarget] = [.priority(.high), .schedule(now), .list("工作")]

        for target in targets {
            let workspace = workspace([parent, first, last])
            let original = workspace.allTasks
            let originalLast = try XCTUnwrap(workspace.task(for: last.id))
            // 首次对带 dueAt 的任务提交时，`TaskWeeklyPlanning.recording` 会补一条
            // 周计划基线（`history` 从空变一条、`currentWeek` 落到本周），这不是丢数据，
            // 而是「首次观察补历史」的既定行为。期望值按同一规则走一遍，
            // 断言才能继续用完整相等。
            var expected = TaskWeeklyPlanning.recording(before: originalLast,
                                                        after: { var value = originalLast
                                                                value.childOrder = 0
                                                                return value }(),
                                                        at: now, calendar: calendar)
            XCTAssertTrue(workspace.canAcceptKanbanDrop(last.id, to: target,
                                                       columnTaskIDs: [parent.id, first.id, last.id]))
            XCTAssertTrue(workspace.applyKanbanDrop(last.id, to: target, insertion: .before(first.id),
                                                   columnTaskIDs: [parent.id, first.id, last.id]))
            XCTAssertEqual(childIDs(workspace, parent: parent.id), [last.id, first.id])
            XCTAssertEqual(workspace.task(for: last.id), expected)
            XCTAssertEqual(workspace.task(for: parent.id), original.first)
            workspace.undo()
            XCTAssertEqual(workspace.allTasks, original)
            XCTAssertFalse(workspace.canUndo)
        }
    }

    func testSamePositionAndAttributeOnlySameColumnDropsDoNotCreateHistory() {
        let first = task("首项"), last = task("末项")
        let workspace = workspace([first, last])
        let original = workspace.allTasks
        let revision = workspace.revision
        let columnIDs = [first.id, last.id]

        XCTAssertFalse(workspace.applyKanbanDrop(first.id, to: .priority(.high), insertion: .before(last.id),
                                                columnTaskIDs: columnIDs))
        XCTAssertFalse(workspace.applyKanbanDrop(last.id, to: nil, insertion: .after(first.id),
                                                columnTaskIDs: columnIDs))
        XCTAssertFalse(workspace.applyKanbanDrop(first.id, to: nil, insertion: nil,
                                                columnTaskIDs: columnIDs))
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertEqual(workspace.revision, revision)
        XCTAssertFalse(workspace.canUndo)
    }

    func testFieldSortedCrossColumnDropChangesAttributesWithoutReordering() {
        let source = task("源任务", priority: .low)
        let unrelated = task("无关任务", priority: .medium)
        let target = task("目标列任务")
        let workspace = workspace([source, unrelated, target])
        let originalIDs = workspace.allTasks.map(\.id)

        XCTAssertTrue(workspace.applyKanbanDrop(source.id, to: .priority(.high), insertion: nil,
                                               columnTaskIDs: [target.id]))
        XCTAssertEqual(workspace.task(for: source.id)?.priority, .high)
        XCTAssertEqual(workspace.allTasks.map(\.id), originalIDs)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: source.id)?.priority, .low)
        XCTAssertFalse(workspace.canUndo)
    }

    func testNilTargetOnlyAcceptsTasksAlreadyInTheDestinationColumn() {
        let source = task("源任务"), target = task("目标列任务")
        let workspace = workspace([source, target])
        XCTAssertFalse(workspace.canAcceptKanbanDrop(source.id, to: nil, columnTaskIDs: [target.id]))
        XCTAssertFalse(workspace.applyKanbanDrop(source.id, to: nil, insertion: .before(target.id),
                                                columnTaskIDs: [target.id]))
        XCTAssertFalse(workspace.canUndo)
    }

    func testPositionAnchorCannotChangeParentOrComeFromAnotherColumn() {
        let parent = task("父任务"), otherParent = task("其他父任务")
        let source = task("子任务", priority: .low, parent: parent.id)
        let unrelatedChild = task("其他子任务", parent: otherParent.id)
        let workspace = workspace([parent, source, otherParent, unrelatedChild])
        let original = workspace.allTasks

        XCTAssertFalse(workspace.applyKanbanDrop(source.id, to: .priority(.high), insertion: .before(unrelatedChild.id),
                                                columnTaskIDs: [otherParent.id, unrelatedChild.id]))
        XCTAssertFalse(workspace.applyKanbanDrop(parent.id, to: .priority(.high), insertion: .after(otherParent.id),
                                                columnTaskIDs: [parent.id, source.id]))
        XCTAssertFalse(workspace.applyKanbanDrop(source.id, to: .priority(.high), insertion: .childOf(otherParent.id),
                                                columnTaskIDs: [otherParent.id, unrelatedChild.id]))
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testCompletedTaskCanChangeColumnAttributesWithoutPositionChange() {
        var source = task("已完成任务", priority: .low)
        source.status = .completed
        source.completedAt = now
        let target = task("目标列任务")
        let workspace = workspace([source, target])
        let original = workspace.allTasks

        XCTAssertTrue(workspace.canAcceptKanbanDrop(source.id, to: .priority(.high), columnTaskIDs: [target.id]))
        XCTAssertFalse(workspace.applyKanbanDrop(source.id, to: .priority(.high), insertion: .before(target.id),
                                                columnTaskIDs: [target.id]))
        XCTAssertFalse(workspace.canUndo)
        XCTAssertTrue(workspace.applyKanbanDrop(source.id, to: .priority(.high), insertion: nil,
                                               columnTaskIDs: [target.id]))
        XCTAssertEqual(workspace.task(for: source.id)?.priority, .high)
        XCTAssertEqual(workspace.task(for: source.id)?.completedAt, source.completedAt)
        XCTAssertEqual(workspace.allTasks.map(\.id), original.map(\.id))
        workspace.undo()
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }
}
