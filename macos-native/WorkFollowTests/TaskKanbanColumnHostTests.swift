import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskKanbanColumnHostTests: XCTestCase {
    private struct Board: View {
        @ObservedObject var workspace: TaskWorkspaceModel
        let onSelect: (UUID) -> Void

        var body: some View {
            TaskKanbanView(groups: workspace.groups(for: .allTasks, grouping: .byPriority,
                                                    viewMode: .kanban),
                           workspace: workspace, onSelect: onSelect)
        }
    }

    func testColumnQuickAddReceivesKeyboardFocusAndKeepsColumnAttribute() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let existing = try XCTUnwrap(workspace.createTask(title: "已有任务", in: .inbox).taskID)
        _ = workspace.setPriority(existing, .high)
        var selection: UUID?
        let root = Board(workspace: workspace, onSelect: { selection = $0 })
            .frame(width: 900, height: 650)
            .environmentObject(AppEnvironment())
        let host = NSHostingView(rootView: AnyView(root))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 650)
        defer { window.close() }

        let column = try XCTUnwrap(columns(in: host).first { $0.target == .priority(.high) })
        XCTAssertGreaterThan(column.bounds.height, 100)
        XCTAssertTrue(column.registeredDraggedTypes.contains(.string))
        XCTAssertNotNil(column.dropLayout.cards[existing])
        XCTAssertGreaterThan(column.dropLayout.viewport.height, 100)
        // The in-process host may not vend an AX tree. Hit the rendered plus
        // control in the column header, then exercise real keyboard delivery.
        try InspectorPanelTestSupport.click(
            CGRect(x: column.bounds.width - WFSpace.sm - 22, y: 0, width: 22, height: 24),
            in: column, window: window)
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView,
                                  "原生落点容器应保留列内添加任务的自动聚焦")
        editor.insertText("列内新增", replacementRange: NSRange(location: NSNotFound, length: 0))
        try InspectorPanelTestSupport.sendReturn(to: window)
        let created = try XCTUnwrap(workspace.allTasks.first { $0.title == "列内新增" })
        XCTAssertEqual(created.priority, .high)
        XCTAssertEqual(selection, created.id)
        XCTAssertEqual(workspace.allTasks.count, 2)
        XCTAssertTrue(window.firstResponder is NSTextView, "提交后继续支持连续输入")
        XCTAssertTrue(column.registeredDraggedTypes.contains(.string), "内容更新后仍可接收拖放")
    }

    private func columns(in view: NSView) -> [TaskKanbanColumnDropView] {
        if let column = view as? TaskKanbanColumnDropView { return [column] }
        return view.subviews.flatMap { columns(in: $0) }
    }
}
