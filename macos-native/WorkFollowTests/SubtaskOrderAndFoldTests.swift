import AppKit
import XCTest
@testable import WorkFollow

/// TI2-04：子任务拖拽排序的数据通道 + 折叠状态持久化。
///
/// 滴答证据：`TTSubtasksViewController` 实现 `pasteboardWriterForItem:` /
/// `writeItems:toPasteboard:`（拖拽排序）与 `containsCollapsedSubtasks` /
/// `tasklistDidFoldTasks:`（折叠持久化）。本地此前只能删了重建来调序、折叠态切任务即丢。
@MainActor
final class SubtaskOrderAndFoldTests: XCTestCase {

    // MARK: - 排序通道

    func testReorderMovesForwardByOne() throws {
        let (workspace, parent, children) = try makeTree()
        XCTAssertEqual(orderedChildren(workspace, parent), children)

        XCTAssertTrue(workspace.reorder(children[0], toSiblingIndex: 1))
        XCTAssertEqual(orderedChildren(workspace, parent), [children[1], children[0], children[2]])
    }

    func testReorderMovesToEnd() throws {
        let (workspace, parent, children) = try makeTree()
        XCTAssertTrue(workspace.reorder(children[0], toSiblingIndex: 2))
        XCTAssertEqual(orderedChildren(workspace, parent), [children[1], children[2], children[0]])
    }

    func testReorderMovesBackward() throws {
        let (workspace, parent, children) = try makeTree()
        XCTAssertTrue(workspace.reorder(children[2], toSiblingIndex: 0))
        XCTAssertEqual(orderedChildren(workspace, parent), [children[2], children[0], children[1]])
    }

    func testReorderToSamePlaceIsNoOp() throws {
        let (workspace, parent, children) = try makeTree()
        let revision = workspace.revision
        XCTAssertFalse(workspace.reorder(children[1], toSiblingIndex: 1))
        XCTAssertEqual(workspace.revision, revision, "没有位移就不该产生一次撤销点")
        XCTAssertEqual(orderedChildren(workspace, parent), children)
    }

    func testReorderClampsOutOfRangeToTheEnd() throws {
        let (workspace, parent, children) = try makeTree()
        XCTAssertTrue(workspace.reorder(children[0], toSiblingIndex: 99))
        XCTAssertEqual(orderedChildren(workspace, parent), [children[1], children[2], children[0]])
    }

    func testReorderOnlyTouchesSiblingsOfTheSameParent() throws {
        let (workspace, parent, children) = try makeTree()
        _ = workspace.createChild(children[0], title: "甲的孙任务")
        let grandchildren = workspace.allTasks.filter { $0.parentID == children[0] }
        XCTAssertEqual(grandchildren.count, 1)

        XCTAssertTrue(workspace.reorder(children[0], toSiblingIndex: 2))
        // 父级顺序变了，孙任务仍挂在甲下、childOrder 不受父级重排影响。
        XCTAssertEqual(orderedChildren(workspace, parent), [children[1], children[2], children[0]])
        XCTAssertEqual(workspace.allTasks.filter { $0.parentID == children[0] }.map(\.id),
                       grandchildren.map(\.id))
    }

    // MARK: - 拖拽落点判定

    func testDropAcceptsOnlySameParentAndBetweenRows() throws {
        let (workspace, parent, children) = try makeTree()
        let all = workspace.allTasks
        let coordinator = AppKitSubtaskOutlineView.Coordinator(foldStore: SubtaskFoldStore(defaults: UserDefaults()))
        coordinator.rootTasks = all.filter { $0.parentID == parent }.sorted { $0.childOrder < $1.childOrder }
        coordinator.allTasks = all
        coordinator.reload()

        XCTAssertTrue(coordinator.acceptsDrop(of: children[0], into: parent, at: 0))
        XCTAssertTrue(coordinator.acceptsDrop(of: children[0], into: parent, at: 3))
        XCTAssertFalse(coordinator.acceptsDrop(of: children[0], into: nil, at: 0), "跨父级不接")
        XCTAssertFalse(coordinator.acceptsDrop(of: children[0], into: parent, at: -1), "落在行上不接")
        XCTAssertFalse(coordinator.acceptsDrop(of: UUID(), into: parent, at: 0), "未知任务不接")
    }

    func testAdjustedDropIndexAccountsForTheDraggedRowItself() {
        // 拖到当前行之前：下标不动
        XCTAssertEqual(AppKitSubtaskOutlineView.Coordinator.adjustedDropIndex(proposed: 0, currentIndex: 2), 0)
        // 拖到当前行之后：下标 −1（被拖行会先被移除）
        XCTAssertEqual(AppKitSubtaskOutlineView.Coordinator.adjustedDropIndex(proposed: 2, currentIndex: 0), 1)
        XCTAssertEqual(AppKitSubtaskOutlineView.Coordinator.adjustedDropIndex(proposed: 3, currentIndex: 0), 2)
    }

    // MARK: - 折叠持久化

    func testFoldStorePersistsPerTaskID() throws {
        let suiteName = "fold-\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let first = UUID()
        let second = UUID()
        let store = SubtaskFoldStore(defaults: suite)
        XCTAssertFalse(store.isCollapsed(first))

        store.setCollapsed(true, for: first)
        XCTAssertTrue(SubtaskFoldStore(defaults: suite).isCollapsed(first), "换一个实例仍读得到（已落盘）")
        XCTAssertFalse(store.isCollapsed(second))

        store.setCollapsed(false, for: first)
        XCTAssertFalse(store.isCollapsed(first), "展开后要能清掉记录")

        store.setCollapsed(true, for: second)
        store.reset()
        XCTAssertFalse(store.isCollapsed(second))
    }

    func testOutlineRestoresCollapsedStateAndOtherwiseExpands() throws {
        let (workspace, parent, children) = try makeTree()
        _ = workspace.createChild(children[0], title: "甲的孙任务")
        let all = workspace.allTasks
        let alpha = try XCTUnwrap(all.first { $0.id == children[0] })

        let suiteName = "fold-\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = SubtaskFoldStore(defaults: suite)
        store.setCollapsed(true, for: alpha.id)

        let collapsed = AppKitSubtaskOutlineView.Coordinator(foldStore: store)
        collapsed.rootTasks = all.filter { $0.parentID == parent }
            .sorted { $0.childOrder < $1.childOrder }
        collapsed.allTasks = all
        collapsed.reload()
        let item = try XCTUnwrap(collapsed.outlineView.item(atRow: 0))
        XCTAssertFalse(collapsed.outlineView.isItemExpanded(item), "折叠过的子任务默认收起")
        XCTAssertEqual(collapsed.outlineView.numberOfRows, 3, "收起后孙任务不占行")

        let expandedStore = SubtaskFoldStore(defaults: UserDefaults())
        let expanded = AppKitSubtaskOutlineView.Coordinator(foldStore: expandedStore)
        expanded.rootTasks = all.filter { $0.parentID == parent }
            .sorted { $0.childOrder < $1.childOrder }
        expanded.allTasks = all
        expanded.reload()
        let expandedItem = try XCTUnwrap(expanded.outlineView.item(atRow: 0))
        XCTAssertTrue(expanded.outlineView.isItemExpanded(expandedItem), "没有记录时默认展开")
        XCTAssertEqual(expanded.outlineView.numberOfRows, 4)
    }

    // MARK: - Helpers

    private func makeTree() throws -> (workspace: TaskWorkspaceModel, parent: UUID, children: [UUID]) {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        var children: [UUID] = []
        for title in ["甲", "乙", "丙"] {
            children.append(try XCTUnwrap(workspace.createChild(parent, title: title).taskID))
        }
        return (workspace, parent, children)
    }

    private func orderedChildren(_ workspace: TaskWorkspaceModel, _ parent: UUID) -> [UUID] {
        workspace.allTasks.filter { $0.parentID == parent }
            .sorted { $0.childOrder < $1.childOrder }
            .map(\.id)
    }
}
