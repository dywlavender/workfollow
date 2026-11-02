import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskViewInvalidationTests: XCTestCase {
    func testWorkspaceLayoutOnlyObservesChangesToItsStructure() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let a = try XCTUnwrap(workspace.createTask(title: "虚构甲", in: .inbox).taskID)
        let b = try XCTUnwrap(workspace.createTask(title: "虚构乙", in: .inbox).taskID)
        workspace.select(a)
        var changes = 0
        let subscription = workspace.layoutObservation.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        workspace.select(b)
        workspace.setTitle(a, "虚构甲更新")
        workspace.refreshDates()
        workspace.toggleExpanded(a)
        XCTAssertEqual(changes, 0, "任务内容与选中身份变化不应重建分栏布局")
        workspace.select(nil)
        XCTAssertEqual(changes, 1)
        workspace.bulkSelection = [a]
        XCTAssertEqual(changes, 2)
        workspace.bulkSelection = [a, b]
        XCTAssertEqual(changes, 2)
        workspace.setTaskListPaneWidth(workspace.taskListPaneWidth + 5)
        XCTAssertEqual(changes, 3)
    }

    func testSwitchingSelectedKanbanTaskKeepsColumnRoots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let now = Date()
        let tasks = (0..<2).map { Task(id: UUID(), title: "虚构看板 \($0)", list: .inbox, priority: .none,
            schedule: TaskSchedule(), childOrder: $0, createdAt: now, updatedAt: now) }
        try NativePreviewRepository(directory: directory).save(.init(tasks: tasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false
        let workspace = environment.taskWorkspace
        let a = tasks[0].id
        let b = tasks[1].id
        workspace.select(a)
        environment.navigation.destination = .allTasks
        let key = TaskViewScopeKey.key(destination: .allTasks, activeList: nil, activeTag: nil)
        environment.viewPreferences.setViewMode(.kanban, for: key)
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        InspectorPanelTestSupport.settle(window, duration: 0.2)
        func columns(in view: NSView) -> [TaskKanbanColumnDropView] {
            (view as? TaskKanbanColumnDropView).map { [$0] } ?? view.subviews.flatMap { columns(in: $0) }
        }
        let visibleColumns = columns(in: host)
        XCTAssertFalse(visibleColumns.isEmpty)
        // Measure this shell's columns; other tests may still have a window
        // completing an asynchronous update and share the global counter.
        let before = visibleColumns.map(\.rootAssignmentCount)
        let globalBefore = TaskKanbanColumnDropView.rootAssignments
        for id in [b, a, b] { workspace.select(id); InspectorPanelTestSupport.settle(window) }
        XCTAssertEqual(columns(in: host).map(ObjectIdentifier.init), visibleColumns.map(ObjectIdentifier.init))
        print("KANBAN_SELECTION_ROOTS current=\(zip(visibleColumns.map(\.rootAssignmentCount), before).map { $0 - $1 }) global=\(TaskKanbanColumnDropView.rootAssignments - globalBefore)")
        XCTAssertEqual(visibleColumns.map(\.rootAssignmentCount), before,
                       "切换选中卡片应更新卡片高亮，不重设整列 SwiftUI rootView")
    }
}
