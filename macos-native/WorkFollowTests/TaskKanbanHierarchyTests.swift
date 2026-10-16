import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanHierarchyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!
    }

    private func task(_ title: String, parentID: UUID? = nil, order: Int = 0) -> Task {
        var value = Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: .high,
                         schedule: TaskSchedule(dueAt: now), parentID: parentID, childOrder: order,
                         createdAt: now, updatedAt: now)
        value.tags = ["设计"]
        return value
    }

    func testCompletionKeepsEachColumnIdentityAndListProjectionHasSeparateCache() throws {
        let cases = TaskListGrouping.allCases.map { ($0, false) } + [(.byDate, true)]
        for (grouping, pinned) in cases {
            var source = task("完成后留在原列")
            source.isPinned = pinned
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
                seedDemoData: false, initialTasks: [source], initialLists: ["工作"])
            let originalTask = try XCTUnwrap(workspace.task(for: source.id))
            let original = try XCTUnwrap(workspace.groups(for: .allTasks, grouping: grouping,
                                                         viewMode: .kanban).first)
            XCTAssertNotNil(workspace.complete(source.id).taskID)
            let closed = try XCTUnwrap(workspace.groups(for: .allTasks, grouping: grouping,
                                                       viewMode: .kanban).first)
            XCTAssertEqual(closed.id, original.id, "\(grouping) 完成后仍属于同一列")
            XCTAssertEqual(closed.creationTarget, original.creationTarget)
            XCTAssertEqual(closed.tasks.map(\.id), [source.id])
            XCTAssertTrue(closed.tasks[0].isClosed)
            XCTAssertNotEqual(closed.kind, .completed)
            XCTAssertEqual(workspace.groups(for: .allTasks, grouping: grouping).map(\.kind), [.completed],
                           "切回列表仍使用原来的底部关闭组")
            XCTAssertEqual(workspace.groups(for: .allTasks, grouping: grouping,
                                             viewMode: .kanban).map(\.id), [original.id])
            XCTAssertTrue(workspace.groups(for: .allTasks, grouping: grouping,
                                            hidesCompleted: true, viewMode: .kanban).isEmpty)
            workspace.undo()
            let restored = try XCTUnwrap(workspace.groups(for: .allTasks, grouping: grouping,
                                                         viewMode: .kanban).first)
            XCTAssertEqual(restored.id, original.id)
            XCTAssertEqual(restored.tasks, [originalTask])
            XCTAssertFalse(workspace.canUndo)
        }
    }

    func testCustomColumnsRetainClosedTasksAndDedicatedClosedPagesStayDateGrouped() throws {
        let section = TaskListSection(id: "review", listName: "工作", title: "待评审")
        let empty = TaskListSection(id: "delivery", listName: "工作", title: "待交付", sortOrder: 1)
        var completed = task("评审已完成")
        completed.sectionID = section.id
        var abandoned = task("评审已取消")
        abandoned.sectionID = section.id
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [completed, abandoned], initialLists: ["工作"],
            initialListSections: [section, empty])
        _ = workspace.complete(completed.id)
        _ = workspace.abandon(abandoned.id)
        let columns = workspace.groups(for: .allTasks, query: TaskListQuery(list: "工作"), viewMode: .kanban)
        XCTAssertEqual(columns.map(\.sectionID), [section.id, empty.id])
        XCTAssertEqual(Set(columns[0].tasks.map(\.id)), [completed.id, abandoned.id])
        XCTAssertEqual(TaskListGroup.closedTitle(for: columns[0].tasks), "已完成&已放弃")
        XCTAssertEqual(columns[0].creationTarget, .section(list: "工作", sectionID: section.id))
        XCTAssertTrue(columns[1].tasks.isEmpty)
        let hidden = workspace.groups(for: .allTasks, query: TaskListQuery(list: "工作"),
                                      hidesCompleted: true, viewMode: .kanban)
        XCTAssertEqual(hidden.map(\.sectionID), columns.map(\.sectionID))
        XCTAssertTrue(hidden.allSatisfy { $0.tasks.isEmpty })
        for (scope, id) in [(TaskListScope.completed, completed.id), (.abandoned, abandoned.id)] {
            let history = workspace.groups(for: scope, hidesCompleted: true, viewMode: .kanban)
            XCTAssertEqual(history.flatMap(\.tasks).map(\.id), [id])
            XCTAssertTrue(history.allSatisfy { $0.kind == .completed })
        }
    }

    func testSavedFilterKeepsClosedColumnIdentityAndCreationTarget() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-hierarchy-filter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = task("筛选中的完成任务")
        var other = task("不匹配的任务")
        other.tags = ["生活"]
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [source, other])
        let filters = FilterStore(directory: directory)
        workspace.attachFilterStore(filters)
        let filter = SavedFilter(name: "设计任务", tags: ["设计"])
        XCTAssertTrue(filters.add(filter))
        workspace.openFilter(filter.id)
        let before = try XCTUnwrap(workspace.groups(for: .allTasks, viewMode: .kanban).first)
        _ = workspace.complete(source.id)
        let after = try XCTUnwrap(workspace.groups(for: .allTasks, viewMode: .kanban).first)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.creationTarget, before.creationTarget)
        XCTAssertEqual(after.tasks.map(\.id), [source.id])
        XCTAssertTrue(after.tasks[0].isClosed)
    }

    func testInlineChildrenKeepOrderAndIdentityThroughCompletionFoldingAndHideCompleted() throws {
        let parent = task("父卡片")
        let first = task("子任务一", parentID: parent.id)
        let second = task("子任务二", parentID: parent.id, order: 1)
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [parent, second, first])
        let before = workspace.kanbanNodes(for: parent).map(\.task)
        XCTAssertEqual(workspace.kanbanNodes(for: parent).map(\.task.id), [parent.id, first.id, second.id])
        XCTAssertEqual(workspace.kanbanNodes(for: parent).map(\.depth), [0, 1, 1])
        _ = workspace.complete(first.id)
        XCTAssertEqual(workspace.subtaskProgress(for: parent.id), "1/2")
        XCTAssertFalse(try XCTUnwrap(workspace.task(for: parent.id)).isClosed)
        XCTAssertEqual(workspace.groups(for: .allTasks, viewMode: .kanban).flatMap(\.tasks).map(\.id),
                       [parent.id], "子任务只在父卡片内出现，不另造一张根卡片")
        XCTAssertEqual(workspace.kanbanNodes(for: parent, hidesCompleted: true).map(\.task.id),
                       [parent.id, second.id])
        workspace.toggleExpanded(parent.id)
        XCTAssertEqual(workspace.kanbanNodes(for: parent).map(\.task.id), [parent.id])
        workspace.toggleExpanded(parent.id)
        workspace.undo()
        XCTAssertEqual(workspace.kanbanNodes(for: parent).map(\.task), before)
        XCTAssertEqual(workspace.subtaskProgress(for: parent.id), "0/2")
    }

    private struct LiveCard: View {
        @ObservedObject var workspace: TaskWorkspaceModel
        let id: UUID
        let onSelect: (UUID) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let task = workspace.task(for: id) {
                    TaskKanbanCardView(task: task, workspace: workspace, onSelect: onSelect)
                        .frame(width: 256)
                }
                Spacer(minLength: 0)
            }
        }
    }

    func testRenderedChildControlsSelectCompleteAndOpenOwnDateWithoutSelectingParent() throws {
        let parent = task("交付卡片")
        let first = task("整理附件", parentID: parent.id)
        let second = task("核对内容", parentID: parent.id, order: 1)
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
            seedDemoData: false, initialTasks: [parent, first, second])
        var frames: [TaskTreeRenderAnchor: CGRect] = [:]
        var selections: [UUID] = []
        let root = LiveCard(workspace: workspace, id: parent.id) { selections.append($0) }
            .frame(width: 600, height: 700, alignment: .topLeading)
            .coordinateSpace(name: "task-tree-render")
            .environment(\.recordsTaskTreeFrames, true)
            .onPreferenceChange(TaskTreeFramesKey.self) { frames = $0 }
            .environmentObject(AppEnvironment())
        let host = NSHostingView(rootView: root)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 700)
        defer { window.close() }
        func click(_ id: UUID, _ part: TaskTreeRenderPart) throws {
            try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.init(taskID: id, part: part)]),
                                                 in: host, window: window)
        }
        try click(parent.id, .disclosure)
        XCTAssertNil(frames[.init(taskID: first.id, part: .row)])
        XCTAssertTrue(selections.isEmpty)
        try click(parent.id, .disclosure)
        XCTAssertNotNil(frames[.init(taskID: second.id, part: .row)])
        try click(first.id, .title)
        XCTAssertEqual(selections, [first.id])
        try click(first.id, .checkbox)
        XCTAssertTrue(try XCTUnwrap(workspace.task(for: first.id)).isClosed)
        XCTAssertFalse(try XCTUnwrap(workspace.task(for: parent.id)).isClosed)
        XCTAssertEqual(workspace.subtaskProgress(for: parent.id), "1/2")
        XCTAssertEqual(selections, [first.id])
        try click(first.id, .checkbox)
        XCTAssertFalse(try XCTUnwrap(workspace.task(for: first.id)).isClosed)
        try click(second.id, .date)
        _ = try InspectorPanelTestSupport.panel(title: "日期属性", below: window)
        XCTAssertEqual(selections, [first.id])
        try InspectorPanelTestSupport.sendEscape(to: window)
    }
}
