import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 任务行里的标签胶囊（2026-10-19，对齐滴答）：有标签时标题下方多一行，
/// 行高必须跟着涨，否则 `NSOutlineView` 会把胶囊裁掉。
@MainActor
final class TaskRowTagLayoutTests: XCTestCase {

    func testRowHeightGrowsForPreviewAndTags() {
        let base = TaskListMetrics.taskRowHeight(hasPreview: false, hasTags: false)
        let preview = TaskListMetrics.taskRowHeight(hasPreview: true, hasTags: false)
        let tags = TaskListMetrics.taskRowHeight(hasPreview: false, hasTags: true)
        let both = TaskListMetrics.taskRowHeight(hasPreview: true, hasTags: true)

        XCTAssertEqual(base, WFMetrics.rowHeight, accuracy: 0.5, "无预览无标签时保持基础行高")
        XCTAssertGreaterThan(preview, base, "预览行要多占高度")
        XCTAssertGreaterThan(tags, base, "标签行要多占高度")
        XCTAssertGreaterThan(both, preview)
        XCTAssertGreaterThan(both, tags)
    }

    func testNativeRowResizesWhenTagsAreAddedAndUndoRestoresHeight() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let environment = AppEnvironment()
        let taskID = try XCTUnwrap(workspace.createTask(title: "标签行布局", in: .inbox).taskID)
        let root = TaskListView(workspace: workspace,
            navigation: AppNavigation(destination: .allTasks), navigationVisible: false)
            .environmentObject(environment)
            .frame(width: 760, height: 640)
        let host = NSHostingView(rootView: root)
        let owner = InspectorPanelTestSupport.ownerWindow(for: host, width: 760, height: 640)
        defer { owner.contentView = nil; owner.close() }
        func outline(in view: NSView) -> NSOutlineView? {
            if let outline = view as? NSOutlineView { return outline }
            return view.subviews.lazy.compactMap { outline(in: $0) }.first
        }
        let list = try XCTUnwrap(outline(in: host))
        func rowHeight() throws -> CGFloat {
            InspectorPanelTestSupport.settle(owner)
            let row = try XCTUnwrap((0..<list.numberOfRows).first {
                (list.item(atRow: $0) as? NativeTaskOutline.Item)?.id.contains(taskID.uuidString) == true
            })
            return list.rect(ofRow: row).height
        }
        let original = try rowHeight()
        workspace.setTags(taskID, ["本周", "验收"])
        let tagged = try rowHeight()
        XCTAssertGreaterThan(tagged, original, "真实列表行必须为标签胶囊腾出高度")
        let key = TaskViewScopeKey.key(destination: .allTasks, activeList: nil, activeTag: nil)
        environment.viewPreferences.setDetailField(.tags, hidden: true, for: key)
        XCTAssertEqual(try rowHeight(), original, accuracy: 0.5, "隐藏标签后不能留下胶囊行的空位")
        environment.viewPreferences.setDetailField(.tags, hidden: false, for: key)
        XCTAssertEqual(try rowHeight(), tagged, accuracy: 0.5)
        environment.viewPreferences.setHidesDetails(true, for: key)
        XCTAssertEqual(try rowHeight(), original, accuracy: 0.5)
        environment.viewPreferences.setHidesDetails(false, for: key)
        XCTAssertEqual(try rowHeight(), tagged, accuracy: 0.5)
        if let directory = ProcessInfo.processInfo.environment["WF_ROW_TAG_ARTIFACTS"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("task-row-tags.png"))
        }
        workspace.undo()
        XCTAssertEqual(try rowHeight(), original, accuracy: 0.5)
    }
}
