import XCTest
@testable import WorkFollow

final class TaskTextMutationTests: XCTestCase {
    private func fixture(count: Int) -> (WorkspaceStore, TaskActions, [Task]) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = (0..<count).map { index in
            Task(id: UUID(), title: "任务\(index)", list: .inbox, priority: .none,
                 schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                 createdAt: now, updatedAt: now)
        }
        let store = WorkspaceStore()
        store.commit(tasks)
        store.clearUndo()
        return (store, TaskActions(store: store, clock: { now }), tasks)
    }

    func testTextEditLatencyWithTaskVolumeAndBusinessHistory() {
        for count in [100, 500] {
            for history in [0, 50] {
                let (store, actions, tasks) = fixture(count: count)
                let id = tasks[0].id
                for index in 0..<history {
                    _ = actions.setPriority(id, index.isMultiple(of: 2) ? .high : .low)
                }
                var events = 0
                store.onTaskChanges = { _ in events += 1 }
                _ = store.task(id)
                let indexes = store.readIndexBuildCount
                let fullDiffs = store.fullDiffBuildCount
                var samples: [Double] = []
                for index in 0..<100 {
                    let document = NativeDocument(plainText: "正文输入\(index)")
                    let start = ProcessInfo.processInfo.systemUptime
                    XCTAssertNotNil(actions.setDocument(id, document).taskID)
                    samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
                samples.sort()
                XCTAssertEqual(events, 100)
                XCTAssertEqual(store.readIndexBuildCount, indexes)
                XCTAssertEqual(store.fullDiffBuildCount, fullDiffs)
                XCTAssertEqual(store.task(id)?.document.plainText, "正文输入99")
                if history > 0 {
                    store.undo()
                    XCTAssertEqual(store.task(id)?.document.plainText, "正文输入99")
                }
                print("TASK_TEXT_EDIT tasks=\(count) history=\(history) p50_ms=\(samples[50]) p95_ms=\(samples[95])")
            }
        }
    }

    func testLaterBusinessSnapshotsDoNotInheritEarlierTextRebases() {
        let (store, actions, tasks) = fixture(count: 2)
        let first = tasks[0].id, second = tasks[1].id
        _ = actions.setPriority(first, .high)
        _ = actions.setTitle(first, "已编辑标题")
        _ = actions.setDocument(second, NativeDocument(plainText: "第二任务正文"))
        // A later recorded document command must keep its own undo snapshot,
        // not inherit a stale text override from an earlier business command.
        var changed = store.tasks
        changed[0].title = "业务命令标题"
        store.commit(changed)
        store.undo()
        XCTAssertEqual(store.task(first)?.title, "已编辑标题")
        store.undo()
        XCTAssertEqual(store.task(first)?.priority, TaskPriority.none)
        XCTAssertEqual(store.task(first)?.title, "已编辑标题")
        XCTAssertEqual(store.task(second)?.document.plainText, "第二任务正文")
    }

    func testTextEventsMatchSnapshotDiffAndRetainLegacyObserver() {
        let (store, actions, tasks) = fixture(count: 2)
        var events: [TaskChangeSet] = []
        var snapshots: [([Task], [Task])] = []
        store.onTaskChanges = { events.append($0) }
        store.onTasksChanged = { snapshots.append(($0, $1)) }
        let document = NativeDocument(plainText: "新正文")
        _ = actions.setTitle(tasks[0].id, "  新标题  ")
        _ = actions.setDocument(tasks[1].id, document)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(snapshots.count, 2)
        for index in events.indices {
            XCTAssertEqual(events[index], TaskChangeSet(before: snapshots[index].0, after: snapshots[index].1))
            XCTAssertEqual(events[index].entries.count, 1)
        }
        XCTAssertTrue(events[0].affectsReminders)
        XCTAssertFalse(events[1].affectsReminders)
        XCTAssertEqual(store.task(tasks[0].id)?.title, "新标题")
        let revision = store.readRevision
        _ = actions.setDocument(tasks[1].id, document)
        XCTAssertEqual(store.readRevision, revision)
        XCTAssertEqual(events.count, 2)
    }

    func testTextUpdatesInsideTransactionPublishOneAggregateChange() {
        let (store, actions, tasks) = fixture(count: 2)
        var events: [TaskChangeSet] = []
        var snapshots: [([Task], [Task])] = []
        store.onTaskChanges = { events.append($0) }
        store.onTasksChanged = { snapshots.append(($0, $1)) }
        store.transaction {
            _ = actions.setTitle(tasks[0].id, "事务标题")
            _ = actions.setDocument(tasks[0].id, NativeDocument(plainText: "事务正文"))
            _ = actions.setDocument(tasks[1].id, NativeDocument(plainText: "其他任务正文"))
            XCTAssertTrue(events.isEmpty)
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(store.fullDiffBuildCount, 1)
        XCTAssertEqual(events[0], TaskChangeSet(before: tasks, after: store.tasks))
        store.undo()
        XCTAssertEqual(store.tasks, tasks)
        XCTAssertEqual(events.count, 2)
    }
}
