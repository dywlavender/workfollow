import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanMultiTagTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_123_200)
    private func task(_ title: String, tags: [String] = [], parent: UUID? = nil) -> Task {
        var value = Task(id: UUID(), title: title, list: .inbox, priority: .none,
            schedule: TaskSchedule(), parentID: parent, childOrder: 0, createdAt: now, updatedAt: now)
        value.tags = tags
        return value
    }

    func testMultiTagCardsShareIdentitySelectionHierarchyAndCompletionAcrossColumns() throws {
        let parent = task("双标签任务", tags: ["设计", "本周"])
        let child = task("检查材料", parent: parent.id)
        let untagged = task("未分类")
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false,
            initialTasks: [parent, child, untagged])
        let columns = workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban)
        let tagged = columns.filter { $0.label != "无标签" }
        XCTAssertEqual(Set(tagged.compactMap(\.label)), ["设计", "本周"])
        XCTAssertTrue(tagged.allSatisfy { $0.tasks.map(\.id) == [parent.id] })
        XCTAssertEqual(columns.last?.tasks.map(\.id), [untagged.id])
        XCTAssertEqual(workspace.allTasks.count, 3, "重复显示不能复制领域任务")
        for group in tagged {
            XCTAssertEqual(workspace.kanbanNodes(for: try XCTUnwrap(group.tasks.first)).map { $0.task.id },
                           [parent.id, child.id])
        }
        workspace.select(parent.id)
        _ = workspace.setTitle(parent.id, "同一任务已更新")
        XCTAssertTrue(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban)
            .filter { $0.label != "无标签" }.allSatisfy { $0.tasks.first?.title == "同一任务已更新" })
        XCTAssertNotNil(workspace.complete(parent.id).taskID)
        let closedColumns = workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban)
            .filter { $0.label != "无标签" }
        XCTAssertEqual(closedColumns.map(\.id), tagged.map(\.id))
        XCTAssertTrue(closedColumns.allSatisfy { $0.tasks.first?.isClosed == true })
        XCTAssertEqual(workspace.selectedTaskID, parent.id)
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byTag,
            hidesCompleted: true, viewMode: .kanban).map(\.label), ["无标签"])
        workspace.undo()
        XCTAssertTrue(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban)
            .filter { $0.label != "无标签" }.allSatisfy { $0.tasks.first?.isClosed == false })
        let list = workspace.groups(for: .allTasks, grouping: .byTag)
        XCTAssertEqual(list.flatMap(\.tasks).map(\.id).filter { $0 == parent.id }.count, 1,
                       "平铺列表仍保持唯一行身份，切换视图不串缓存")
    }

    func testCreatingInTagColumnAddsItsTagAndLaterTagEditsUpdateMembership() throws {
        let workspace = TaskWorkspaceModel(clock: { self.now }, seedDemoData: false, initialTasks: [])
        let id = try XCTUnwrap(workspace.createKanbanTask(title: "列内创建 #本周", target: .tag("设计")))
        XCTAssertEqual(Set(try XCTUnwrap(workspace.task(for: id)).tags), ["设计", "本周"])
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban).count, 2)
        _ = workspace.setTags(id, ["本周"])
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban).map(\.label), ["本周"])
        workspace.undo()
        XCTAssertEqual(workspace.groups(for: .allTasks, grouping: .byTag, viewMode: .kanban).count, 2)
    }
}
