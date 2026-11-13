import AppKit
import XCTest
@testable import WorkFollow

/// 任务详情「子任务」行尾 hover 删除按钮：几何、悬停显隐、点击路由与 cell 复用复位。
@MainActor
final class SubtaskHoverDeleteTests: XCTestCase {
    private struct Fixture {
        let row: SubtaskRowView
        let deleteButton: NSButton
        let coordinator: AppKitSubtaskOutlineView.Coordinator
        let task: Task
        let workspace: TaskWorkspaceModel
    }

    private func makeFixture(dateText: String? = nil) throws -> Fixture {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let childID = try XCTUnwrap(workspace.createChild(parent, title: "第一条子任务").taskID)
        let task = try XCTUnwrap(workspace.task(for: childID))
        let coordinator = AppKitSubtaskOutlineView.Coordinator(foldStore: SubtaskFoldStore())
        let row = SubtaskRowView(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
        row.coordinator = coordinator
        row.configure(task: task, completionSize: 19, dateText: dateText)
        row.layout()
        let button = try XCTUnwrap(descendants(row).compactMap { $0 as? NSButton }
            .first { $0.toolTip == "删除子任务" })
        return Fixture(row: row, deleteButton: button, coordinator: coordinator,
                       task: task, workspace: workspace)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func hoverEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
    }

    private func titleField(_ row: SubtaskRowView) throws -> SubtaskTitleField {
        try XCTUnwrap(descendants(row).compactMap { $0 as? SubtaskTitleField }.first)
    }

    func testDeleteButtonHiddenUntilHoverAndGeometryMatchesChecklistRow() throws {
        let f = try makeFixture()
        XCTAssertTrue(f.deleteButton.isHidden, "默认不显示，鼠标悬浮才出现")
        XCTAssertEqual(f.deleteButton.frame.width, 24, accuracy: 0.5)
        XCTAssertEqual(f.deleteButton.frame.height, 24, accuracy: 0.5)
        XCTAssertEqual(f.row.bounds.maxX - f.deleteButton.frame.maxX, 10, accuracy: 0.5,
                       "与笔记正文检查项的 24pt 行尾命中区同几何")
        let before = try titleField(f.row).frame
        f.row.mouseEntered(with: try hoverEvent())
        XCTAssertFalse(f.deleteButton.isHidden)
        f.row.layout()
        XCTAssertEqual(try titleField(f.row).frame, before,
                       "按钮位常驻预留，hover 只切可见性，标题不能重排")
        f.row.mouseExited(with: try hoverEvent())
        XCTAssertTrue(f.deleteButton.isHidden)
    }

    func testClickingDeleteRoutesToHost() throws {
        let f = try makeFixture()
        var deleted: UUID?
        f.coordinator.onDelete = { deleted = $0 }
        f.row.mouseEntered(with: try hoverEvent())
        f.deleteButton.performClick(nil)
        XCTAssertEqual(deleted, f.task.id, "只把 id 交给宿主，由宿主走软删 + HUD 撤销")
    }

    func testCellReuseResetsDeleteButtonAndAccessibilityLabel() throws {
        let f = try makeFixture()
        f.row.mouseEntered(with: try hoverEvent())
        XCTAssertFalse(f.deleteButton.isHidden)
        let parentID = try XCTUnwrap(f.task.parentID)
        let otherID = try XCTUnwrap(f.workspace.createChild(parentID, title: "第二条子任务").taskID)
        let other = try XCTUnwrap(f.workspace.task(for: otherID))
        f.row.configure(task: other, completionSize: 19, dateText: nil)
        XCTAssertTrue(f.deleteButton.isHidden, "cell 复用不能带着上一行亮着的删除按钮")
        XCTAssertTrue(f.deleteButton.accessibilityLabel()?.contains("第二条子任务") == true,
                      "AX 标签要跟着当前行更新")
    }

    func testOpenArrowIsAlwaysVisibleAndRoutesToOpen() throws {
        let f = try makeFixture()
        let open = try XCTUnwrap(descendants(f.row).compactMap { $0 as? NSButton }
            .first { $0.toolTip == "打开子任务" })
        XCTAssertFalse(open.isHidden, "跳转箭头常驻显示，不随悬停显隐")
        XCTAssertEqual(open.frame.width, 18, accuracy: 0.5)
        XCTAssertLessThanOrEqual(open.frame.maxX, f.deleteButton.frame.minX,
                                 "箭头必须在删除按钮左侧，两者不重叠")
        var opened: UUID?
        f.coordinator.onOpen = { opened = $0 }
        open.performClick(nil)
        XCTAssertEqual(opened, f.task.id, "点箭头打开该子任务详情")
    }

    func testDateFieldMakesRoomForDeleteButton() throws {
        let f = try makeFixture(dateText: "11月7日")
        let date = try XCTUnwrap(descendants(f.row).compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "11月7日" })
        XCTAssertLessThanOrEqual(date.frame.maxX, f.deleteButton.frame.minX,
                                 "日期列必须常驻让位，hover 时不能压到删除按钮上")
    }

    /// 视觉预览：AppKit 离屏渲染，不依赖锁屏/前台。mouseEntered 是真实 AppKit 事件路径，
    /// 但不是屏幕上的真实指针（真实指针验收需解锁会话后另做）。
    func testRenderHoverPreviewSnapshot() throws {
        let f = try makeFixture(dateText: "11月7日")
        f.row.mouseEntered(with: try hoverEvent())
        f.row.layout()
        f.row.display()
        let bitmap = try XCTUnwrap(f.row.bitmapImageRepForCachingDisplay(in: f.row.bounds))
        f.row.cacheDisplay(in: f.row.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: "/tmp/wf-hover-preview-subtask.png")
        try data.write(to: url)
        XCTAssertGreaterThan(data.count, 500, "预览截图应包含真实行渲染：\(url.path)")
    }
}
