import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 任务栏优化第三批：列表区批量动作条。
///
/// 滴答证据：`isMultipleModeForOneSelected` / `firstModelForMultipleSelection`
/// （多选是显式模式）、`TTTaskListViewController` 的批量态动作。
/// 本地语义不变：所有动作都转发到 `TaskBatchOperation`。
@MainActor
final class TaskBulkActionBarTests: XCTestCase {

    private final class FrameBox { var height: CGFloat = 0 }

    func testBarShowsSelectionCount() throws {
        let (environment, window) = try makeBar(selected: 3)
        defer { window.close() }
        XCTAssertEqual(environment.taskWorkspace.bulkSelection.count, 3)
    }

    func testCompleteActionAppliesToWholeSelection() throws {
        let (environment, window) = try makeBar(selected: 3)
        defer { window.close() }
        let workspace = environment.taskWorkspace
        let ids = workspace.bulkSelection
        workspace.applyBulk(.complete)
        XCTAssertTrue(workspace.bulkSelection.isEmpty, "批量动作后清空选择（与右侧面板一致）")
        for id in ids {
            XCTAssertEqual(workspace.task(for: id)?.status, .completed)
        }
    }

    func testCompleteIsOneUndoStep() throws {
        let (environment, window) = try makeBar(selected: 3)
        defer { window.close() }
        let workspace = environment.taskWorkspace
        let ids = workspace.bulkSelection
        workspace.applyBulk(.complete)
        workspace.undo()
        for id in ids {
            XCTAssertNotEqual(workspace.task(for: id)?.status, .completed,
                              "批量完成要一步撤销（与右侧面板同一语义）")
        }
    }

    func testDeleteMovesAllToTrash() throws {
        let (environment, window) = try makeBar(selected: 2)
        defer { window.close() }
        let workspace = environment.taskWorkspace
        let ids = workspace.bulkSelection
        workspace.applyBulk(.delete)
        for id in ids {
            XCTAssertNotNil(workspace.task(for: id)?.deletedAt)
        }
    }

    func testBarReplacesQuickAddOnlyWhileSelectionExists() throws {
        let (environment, window) = try makeListWindow(selected: 2)
        defer { window.close() }
        let workspace = environment.taskWorkspace
        XCTAssertFalse(workspace.bulkSelection.isEmpty)
        workspace.clearBulkSelection()
        XCTAssertTrue(workspace.bulkSelection.isEmpty, "清空后快速添加条应回来（bar 由 bulkSelection 投影）")
    }

    // MARK: - Helpers

    private func makeBar(selected count: Int) throws -> (AppEnvironment, NSWindow) {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        var ids: [UUID] = []
        for index in 0..<count {
            if let id = workspace.createTask(title: "批量 \(index)", in: .today).taskID { ids.append(id) }
        }
        workspace.setBulkSelection(in: ids)
        let root = TaskBulkActionBar(workspace: workspace, onOpenPanel: {})
            .frame(width: 800)
            .environmentObject(environment)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return (environment, window)
    }

    private func makeListWindow(selected count: Int) throws -> (AppEnvironment, NSWindow) {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let navigation = environment.navigation
        navigation.destination = .today
        var ids: [UUID] = []
        for index in 0..<count {
            if let id = workspace.createTask(title: "批量 \(index)", in: .today).taskID { ids.append(id) }
        }
        workspace.setBulkSelection(in: ids)
        let root = TaskListView(workspace: workspace, navigation: navigation, navigationVisible: true)
            .environmentObject(environment)
            .frame(width: 900, height: 700)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return (environment, window)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bulk-bar-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
