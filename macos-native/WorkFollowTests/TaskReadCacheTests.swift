import XCTest
@testable import WorkFollow

@MainActor
final class TaskReadCacheTests: XCTestCase {
    func testSelectionReusesProjectionsWhileEditsUndoQueriesAndFoldingRefresh() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let child = try XCTUnwrap(workspace.createChild(parent, title: "子任务").taskID)
        func read() -> [TaskTreeNode] {
            workspace.groups(for: .inbox).flatMap { workspace.nodes(for: $0, scope: .inbox) }
        }
        XCTAssertEqual(read().map(\.task.id), [parent, child])
        XCTAssertEqual(workspace.count(for: NativeDestination.inbox), 2)
        let warm = workspace.projectionBuildCount
        for id in [child, parent, child] {
            workspace.select(id)
            _ = read()
            _ = workspace.count(for: NativeDestination.inbox)
        }
        XCTAssertEqual(workspace.projectionBuildCount, warm)
        workspace.toggleExpanded(parent)
        XCTAssertEqual(read().map(\.task.id), [parent])
        workspace.toggleExpanded(parent)
        _ = workspace.setTitle(child, "新子任务")
        XCTAssertEqual(read().last?.task.title, "新子任务")
        XCTAssertTrue(workspace.groups(for: .inbox, query: TaskListQuery(search: "不存在")).isEmpty)
        _ = workspace.moveTask(child, to: .rootAfter(parent))
        XCTAssertEqual(read().last?.depth, 0)
        workspace.undo()
        XCTAssertEqual(read().last?.depth, 1)
    }

    func testDayRolloverInvalidatesSidebarAndGroupsWithoutMutation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "明天任务", in: .inbox).taskID)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        _ = workspace.setSchedule(id, TaskSchedule(dueAt: tomorrow))
        XCTAssertTrue(workspace.groups(for: .today).isEmpty)
        XCTAssertEqual(workspace.count(for: NativeDestination.today), 0)
        now = tomorrow
        XCTAssertEqual(workspace.groups(for: .today).flatMap(\.tasks).map(\.id), [id])
        XCTAssertEqual(workspace.count(for: NativeDestination.today), 1)
    }

    func testReadIndexTracksTransactionReparentingDeletionAndUndo() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func task(_ title: String, parent: UUID? = nil) -> Task {
            Task(id: UUID(), title: title, list: .inbox, priority: .none,
                 schedule: TaskSchedule(), parentID: parent, childOrder: 0, createdAt: now, updatedAt: now)
        }
        let first = task("父一"), second = task("父二")
        var child = task("子任务", parent: first.id)
        let store = WorkspaceStore()
        store.commit([first, child, second])
        store.clearUndo()
        XCTAssertEqual(store.children(of: first.id).map(\.id), [child.id])
        store.transaction {
            child.parentID = second.id
            store.commit([first, child, second])
            XCTAssertTrue(store.children(of: first.id).isEmpty)
            XCTAssertEqual(store.children(of: second.id).map(\.id), [child.id])
            child.deletedAt = now
            store.commit([first, child, second])
            XCTAssertTrue(store.children(of: second.id).isEmpty)
            XCTAssertEqual(store.children(of: second.id, includingDeleted: true).map(\.id), [child.id])
            XCTAssertEqual(store.task(child.id)?.deletedAt, now)
        }
        store.undo()
        XCTAssertEqual(store.children(of: first.id).map(\.id), [child.id])
        XCTAssertTrue(store.children(of: second.id).isEmpty)
        XCTAssertNil(store.task(child.id)?.deletedAt)
    }
}
