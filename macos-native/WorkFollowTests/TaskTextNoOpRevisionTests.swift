import XCTest
@testable import WorkFollow

/// 第 1 期最小片的不变量：同值文本回写（绑定回写、IME 重复提交、焦点重写）
/// 不应递增 revision，也不应失效并重建投影缓存；只有真正改动才驱动刷新。
@MainActor
final class TaskTextNoOpRevisionTests: XCTestCase {
    func testUnchangedTitleDoesNotBumpRevisionOrRebuildProjection() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "原标题", in: .inbox).taskID)

        func read() -> [TaskTreeNode] {
            workspace.groups(for: .inbox).flatMap { workspace.nodes(for: $0, scope: .inbox) }
        }
        // 预热投影缓存，后续 no-op 若不失效缓存就不会重建。
        XCTAssertEqual(read().map(\.task.title), ["原标题"])
        let revision = workspace.revision
        let builds = workspace.projectionBuildCount

        let noop = workspace.setTitle(id, "原标题")
        XCTAssertEqual(noop.taskID, id, "no-op 仍是非失败结果，保留 taskID")
        XCTAssertFalse(noop.didChangeStore)
        XCTAssertEqual(workspace.revision, revision, "同值标题不应递增 revision")
        _ = read()
        XCTAssertEqual(workspace.projectionBuildCount, builds, "同值标题不应重建投影")

        let changed = workspace.setTitle(id, "新标题")
        XCTAssertTrue(changed.didChangeStore)
        XCTAssertEqual(workspace.revision, revision + 1, "改动标题应递增一次 revision")
        XCTAssertEqual(read().map(\.task.title), ["新标题"])
        XCTAssertGreaterThan(workspace.projectionBuildCount, builds, "改动标题应触发投影重建")
    }

    /// 组合编辑（属性 + 文本）里，末尾同值文本 no-op 不能抹掉前面属性改动的刷新。
    func testCompositeEditStillBumpsWhenTrailingTextIsNoOp() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "保持不变的标题", in: .inbox).taskID)
        let revision = workspace.revision
        let result = workspace.applyAutomationEdit(
            id, title: "保持不变的标题", list: nil, priority: .high,
            schedule: TaskSchedule(), document: nil)
        XCTAssertTrue(result.didChangeStore, "优先级改动应上报为已变更，即便标题是同值 no-op")
        XCTAssertEqual(workspace.revision, revision + 1)
        XCTAssertEqual(workspace.task(for: id)?.priority, .high)
    }
}
