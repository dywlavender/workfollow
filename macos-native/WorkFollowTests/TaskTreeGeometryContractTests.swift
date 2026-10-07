import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskTreeGeometryContractTests: XCTestCase {
    func testPreviewUsesWidthBelowMetadataAndTitleKeepsReadableSpace() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "需要展示更多文字的任务标题", in: .inbox).taskID)
        _ = workspace.setDocument(id, NativeDocument(plainText: String(repeating: "正文预览应使用整行空间", count: 8)))
        _ = workspace.setDueDate(id, Date())
        _ = workspace.setPriority(id, .high)
        for width: CGFloat in [340, 470] {
            let frames = render(workspace: workspace, rows: [(id, 0, false, false)], width: width)
            let title = try XCTUnwrap(frames[.init(taskID: id, part: .title)])
            let preview = try XCTUnwrap(frames[.init(taskID: id, part: .preview)])
            let date = try XCTUnwrap(frames[.init(taskID: id, part: .date)])
            XCTAssertEqual(preview.minX, title.minX, accuracy: 0.5)
            XCTAssertGreaterThan(preview.width, title.width + 30)
            XCTAssertEqual(preview.maxX, width - TaskListMetrics.rowHorizontalPadding, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(title.width, 96)
            XCTAssertLessThanOrEqual(title.maxX, date.minX)
        }
    }

    func testRenderedParentRootAndChildReserveTheSameDisclosureGutter() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = workspace.createTask(title: "父任务", in: .inbox).taskID!
        let root = workspace.createTask(title: "普通根任务", in: .inbox).taskID!
        let child = workspace.createChild(parent, title: "子任务").taskID!
        let frames = render(workspace: workspace, rows: [(parent, 0, true, true),
                                                        (root, 0, false, false),
                                                        (child, 1, false, false)])
        let parentBox = try XCTUnwrap(frames[.init(taskID: parent, part: .checkbox)])
        let rootBox = try XCTUnwrap(frames[.init(taskID: root, part: .checkbox)])
        let childBox = try XCTUnwrap(frames[.init(taskID: child, part: .checkbox)])
        XCTAssertEqual(parentBox.minX, rootBox.minX, accuracy: 0.5)
        XCTAssertEqual(parentBox.minX, 32, accuracy: 0.5)
        XCTAssertEqual(childBox.minX - parentBox.minX, 24, accuracy: 0.5)
        for id in [parent, root, child] {
            let gutter = try XCTUnwrap(frames[.init(taskID: id, part: .disclosure)])
            let box = try XCTUnwrap(frames[.init(taskID: id, part: .checkbox)])
            XCTAssertEqual(gutter.width, 22, accuracy: 0.5)
            XCTAssertEqual(box.minX - gutter.maxX, 2, accuracy: 0.5)
        }
    }

    func testFoldingHidesChildrenAndNeverSynthesizesTheirTitlesIntoPreview() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = workspace.createTask(title: "父任务", in: .inbox).taskID!
        let child = workspace.createChild(parent, title: "不能进入父行预览").taskID!
        XCTAssertTrue(workspace.visibleNodes(for: .inbox).contains { $0.task.id == child })
        workspace.toggleExpanded(parent)
        XCTAssertFalse(workspace.visibleNodes(for: .inbox).contains { $0.task.id == child })
        let folded = render(workspace: workspace, rows: [(parent, 0, true, false)])
        XCTAssertNil(folded[.init(taskID: parent, part: .preview)])
        _ = workspace.setDocument(parent, NativeDocument(plainText: "父任务自己的正文"))
        let withBody = render(workspace: workspace, rows: [(parent, 0, true, false)])
        XCTAssertNotNil(withBody[.init(taskID: parent, part: .preview)])
        workspace.toggleExpanded(parent)
        let expanded = render(workspace: workspace, rows: [(parent, 0, true, true)])
        XCTAssertNotNil(expanded[.init(taskID: parent, part: .preview)])
    }

    func testDragPreviewFitsTitleRatherThanRenderingAWideCard() {
        let host = NSHostingView(rootView: TaskDragPreview(title: "标题"))
        let long = NSHostingView(rootView: TaskDragPreview(title: String(repeating: "很长的任务标题", count: 20)))
        let empty = NSHostingView(rootView: TaskDragPreview(title: ""))
        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertLessThan(host.fittingSize.width, 100)
        XCTAssertGreaterThan(long.fittingSize.width, host.fittingSize.width)
        XCTAssertLessThanOrEqual(long.fittingSize.width, TaskListMetrics.dragPreviewMaxWidth + 0.5)
        XCTAssertLessThan(host.fittingSize.height, 30)
        XCTAssertGreaterThan(empty.fittingSize.width, 0)
        let marker = NSHostingView(rootView: TaskDropMarker().frame(width: 440))
        XCTAssertEqual(marker.fittingSize.height, 1, accuracy: 0.5)
    }

    private func render(workspace: TaskWorkspaceModel,
                        rows: [(UUID, Int, Bool, Bool)], width: CGFloat = 440) -> [TaskTreeRenderAnchor: CGRect] {
        var frames: [TaskTreeRenderAnchor: CGRect] = [:]
        let view = VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                TaskRowView(task: workspace.task(for: row.0)!, workspace: workspace,
                            depth: row.1, hasChildren: row.2, expanded: row.3,
                            selected: false,
                            onSelect: {}, onComplete: {}, onRestore: {}, onToggleExpanded: {})
            }
        }
        .frame(width: width, alignment: .topLeading)
        .coordinateSpace(name: "task-tree-render")
        .onPreferenceChange(TaskTreeFramesKey.self) { frames = $0 }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        window.orderOut(nil)
        return frames
    }
}
