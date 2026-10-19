import XCTest
@testable import WorkFollow

@MainActor
final class TaskTagScopeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_368_000)

    private func task(_ title: String, tags: [String]) -> Task {
        Task(id: UUID(), title: title, tags: tags, list: .inbox, priority: .none,
             schedule: TaskSchedule(), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private func matchingIDs(_ name: String, in workspace: TaskWorkspaceModel,
                             mode: TaskListViewMode = .list) -> Set<UUID> {
        Set(workspace.groups(for: .allTasks, query: TaskListQuery(tag: name),
            grouping: .byTag, hidesCompleted: true, viewMode: mode)
            .flatMap(\.tasks).map(\.id))
    }

    func testParentTagListsDescendantTasksOnceAndKeepsAssignments() {
        let parent = TaskTag(name: "项目")
        let child = TaskTag(name: "交付", parentID: parent.id)
        let grandchild = TaskTag(name: "验收", parentID: child.id)
        let direct = task("父标签任务", tags: [parent.name])
        let nested = task("子标签任务", tags: [child.name])
        let deep = task("下级标签任务", tags: [grandchild.name])
        let both = task("多标签任务", tags: [parent.name, child.name])
        let unrelated = task("其他任务", tags: ["其他"])
        let tasks = [direct, nested, deep, both, unrelated]
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: tasks, initialTags: [parent, child, grandchild])
        let original = workspace.allTasks
        let expected = Set([direct.id, nested.id, deep.id, both.id])

        XCTAssertEqual(matchingIDs(parent.name, in: workspace), expected)
        XCTAssertEqual(matchingIDs(parent.name, in: workspace, mode: .kanban), expected)
        XCTAssertEqual(matchingIDs(child.name, in: workspace), Set([nested.id, deep.id, both.id]))
        XCTAssertEqual(matchingIDs(grandchild.name, in: workspace), [deep.id])
        XCTAssertEqual(workspace.tagSidebarCounts[parent.name], 4)
        XCTAssertEqual(workspace.tagSidebarCounts[child.name], 3)
        XCTAssertEqual(workspace.allTasks, original)
        XCTAssertFalse(workspace.canUndo)
    }

    func testReparentAndUndoRefreshParentScope() {
        let first = TaskTag(name: "原项目")
        let second = TaskTag(name: "新项目")
        let child = TaskTag(name: "交付", parentID: first.id)
        let nested = task("交付任务", tags: [child.name])
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [nested], initialTags: [first, second, child])

        XCTAssertEqual(matchingIDs(first.name, in: workspace), [nested.id])
        XCTAssertTrue(matchingIDs(second.name, in: workspace).isEmpty)
        XCTAssertEqual(workspace.tagSidebarCounts[first.name], 1)
        XCTAssertTrue(workspace.reparentTag(child.id, parentID: second.id))
        XCTAssertTrue(matchingIDs(first.name, in: workspace).isEmpty)
        XCTAssertEqual(matchingIDs(second.name, in: workspace), [nested.id])
        XCTAssertNil(workspace.tagSidebarCounts[first.name])
        XCTAssertEqual(workspace.tagSidebarCounts[second.name], 1)
        workspace.undo()
        XCTAssertEqual(matchingIDs(first.name, in: workspace), [nested.id])
        XCTAssertTrue(matchingIDs(second.name, in: workspace).isEmpty)
        XCTAssertEqual(workspace.tagSidebarCounts[first.name], 1)
        XCTAssertNil(workspace.tagSidebarCounts[second.name])
    }

    func testParentBadgeCountsOpenTasksOnceAndExcludesArchivedLists() {
        let parent = TaskTag(name: "项目")
        let child = TaskTag(name: "交付", parentID: parent.id)
        let both = task("同时标父子", tags: [parent.name, child.name])
        var closed = task("已完成", tags: [child.name])
        closed.status = .completed
        var archived = task("归档清单任务", tags: [child.name])
        archived.list = TaskList(name: "归档项目")
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [both, closed, archived], initialTags: [parent, child])
        XCTAssertTrue(workspace.setListArchived(archived.list.name, true))

        XCTAssertEqual(workspace.tagSidebarCounts[parent.name], 1)
        XCTAssertEqual(workspace.tagSidebarCounts[child.name], 1)
    }
}
