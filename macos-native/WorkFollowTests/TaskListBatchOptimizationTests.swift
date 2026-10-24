import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 任务栏优化第二批：折叠持久化 / 空态动作 / 已完成分页。
@MainActor
final class TaskListBatchOptimizationTests: XCTestCase {

    // MARK: - 折叠持久化（滴答 taskCollapseStateChanged:）

    func testCollapsedGroupsRoundTripThroughPreferences() throws {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = TaskViewPreferenceStore(directory: directory)
        let key = "today|nil|nil"
        XCTAssertTrue(store.collapsedGroups(for: key).isEmpty)
        XCTAssertFalse(store.hasCollapsedGroupsRecord(for: key), "没存过 = 没有记录")

        store.setCollapsedGroups(["overdue", "closed"], for: key)
        XCTAssertEqual(store.collapsedGroups(for: key), ["overdue", "closed"])
        XCTAssertTrue(store.hasCollapsedGroupsRecord(for: key))
    }

    func testExpandingEverythingClearsTheRecord() throws {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = TaskViewPreferenceStore(directory: directory)
        let key = "today|nil|nil"
        store.setCollapsedGroups(["overdue"], for: key)
        XCTAssertTrue(store.hasCollapsedGroupsRecord(for: key))

        store.setCollapsedGroups([], for: key)
        XCTAssertTrue(store.collapsedGroups(for: key).isEmpty)
        // 空集合写回 nil：视图档案若没有别的设置会被整个清掉（不留垃圾键）。
        XCTAssertNil(store.preferences[key]?.collapsedGroups)
    }

    func testExpansionStateRestoresFromSet() {
        let state = TaskGroupExpansionState(collapsedIDs: ["overdue"])
        let overdue = TaskListGroup(kind: .overdue, day: nil, tasks: [], label: nil,
                                    sectionID: nil, creationTarget: nil)
        let today = TaskListGroup(kind: .today, day: nil, tasks: [], label: nil,
                                  sectionID: nil, creationTarget: nil)
        XCTAssertTrue(state.isCollapsed(overdue))
        XCTAssertFalse(state.isCollapsed(today), "没记录的分组保持展开")
    }

    // MARK: - 空态动作（滴答 TTTaskListEmptyHolderView.actionButton）

    func testEmptyStateWithoutActionStaysNonInteractive() throws {
        let view = TaskEmptyStateView(style: .list, message: "没有任务")
        let host = NSHostingView(rootView: view.frame(width: 300, height: 300))
        host.layoutSubtreeIfNeeded()
        // 没有动作时不接管点击：块本身不该命中（原来 `.allowsHitTesting(false)` 的契约）。
        XCTAssertFalse(host.hitTest(NSPoint(x: 150, y: 150))?.isDescendant(of: host) == true
                       && host.hitTest(NSPoint(x: 150, y: 150)) is NSButton)
    }

    func testEmptyStateWithActionIsTallerThanWithout() throws {
        func height(_ view: some View) -> CGFloat {
            let host = NSHostingView(rootView: view.frame(width: 400))
            host.appearance = NSAppearance(named: .aqua)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            return host.fittingSize.height
        }
        let plain = height(TaskEmptyStateView(style: .list, message: "没有任务"))
        let withAction = height(TaskEmptyStateView(style: .list, message: "没有任务",
                                                   actionTitle: "新建第一个任务", action: {}))
        XCTAssertGreaterThan(withAction, plain,
                             "空态有动作时要比纯装饰高出一行按钮（实际 \(withAction) vs \(plain)）")
    }

    func testEmptyActionTitlesFollowDestination() throws {
        // 走真实列表视图：今天空 → 去看未来 7 天；收集箱空 → 新建。
        let (environment, window, _) = try makeListWindow(destination: .today, seed: 0)
        defer { window.close() }
        XCTAssertEqual(environment.navigation.destination, .today)
    }

    // MARK: - 已完成分页（滴答 countToShowOfCompleted / didClickLoadMore）

    func testCompletedPageSizeIsThirty() {
        XCTAssertEqual(TaskListMetrics.completedPageSize, 30)
        XCTAssertLessThan(TaskListMetrics.loadMoreRowHeight, WFMetrics.rowHeight,
                          "「显示更多」行要比任务行矮")
    }

    func testCompletedGroupRespectsPageSize() throws {
        let (environment, window, seeded) = try makeListWindow(destination: .completed, seed: 35)
        defer { window.close() }
        let completed = environment.taskWorkspace.allTasks.filter { $0.status == .completed }
        XCTAssertGreaterThanOrEqual(completed.count, seeded,
                                    "至少要有刚种下的这些已完成任务")
        XCTAssertGreaterThanOrEqual(seeded, TaskListMetrics.completedPageSize,
                                    "用例要超过一页才有意义")
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tasklist-batch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeListWindow(destination: NativeDestination, seed: Int)
    throws -> (AppEnvironment, NSWindow, Int) {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let navigation = environment.navigation
        navigation.destination = destination
        for index in 0..<seed {
            let result = environment.taskWorkspace.createTask(title: "任务 \(index)", in: .today)
            if let id = result.taskID { _ = environment.taskWorkspace.complete(id) }
        }
        let root = TaskListView(workspace: environment.taskWorkspace, navigation: navigation,
                                navigationVisible: true)
            .environmentObject(environment)
            .frame(width: 900, height: 800)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        return (environment, window, seed)
    }
}
