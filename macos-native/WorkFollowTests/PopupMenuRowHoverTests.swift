import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class PopupMenuRowHoverTests: XCTestCase {
    func testSharedRowShowsHoverOnlyWhenEnabled() throws {
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            PopupMenuRow(action: {}) { Text("可用行") }
            PopupMenuRow(action: {}) { Text("禁用行") }.disabled(true)
        }.padding(8).background(WFColors.content))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 240, height: 100)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let rows = hoverRows(in: host)
        XCTAssertEqual(rows.count, 1, "禁用行不应挂 hover 追踪")
        try assertHover(rows[0], in: window)
    }

    func testTaskContextMenuIconTilesAndSkipRowUseSharedHover() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "右键菜单悬浮", in: .inbox).taskID)
        workspace.setRepeat(id, .daily)
        _ = workspace.setDueDate(id, Date())
        let task = try XCTUnwrap(workspace.task(for: id))
        let host = NSHostingView(rootView: TaskContextMenuPopover(
            workspace: workspace, isPresented: .constant(true), task: task,
            onCustomDate: {}, onChooseParent: {})
            .environmentObject(AppEnvironment())
            .frame(width: TaskContextMenuPopover.menuWidth))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 240, height: 700)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let rows = hoverRows(in: host)
        // 5 个日期快选 + 4 个优先级旗标 + 1 行「跳过此周期」。
        XCTAssertEqual(rows.count, 10, "日期与优先级图标、跳过行都应带 hover 背景")
        try assertHover(rows[0], in: window)
        try assertHover(rows[8], in: window)
        try assertHover(rows[9], in: window)
    }

    func testQuickAddPropertiesRowsUseSharedHover() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let host = NSHostingView(rootView: QuickAddPropertiesPopover(
            workspace: workspace, selectedPriority: .none,
            selectedList: TaskList.inbox.name, selectedTags: [],
            onPriority: { _ in }, onList: { _ in }, onTags: { _ in },
            onTemplate: {}, onDismiss: {})
            .frame(width: PopupMetrics.quickAddPropertiesWidth))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 280, height: 360)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let rows = hoverRows(in: host)
        XCTAssertGreaterThanOrEqual(rows.count, 6, "快速添加属性行都应带 hover 背景")
        try assertHover(rows[0], in: window)
    }

    func testQuickComposerChipsUseSharedHover() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let host = NSHostingView(rootView: TaskQuickComposer(
            workspace: workspace, fallbackSchedule: TaskSchedule(),
            presetSchedule: nil, presetPriority: .none, requestClose: {})
            .frame(width: 320, height: 212))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 380, height: 280)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let rows = hoverRows(in: host)
        // 日期胶囊、优先级旗标、清单胶囊、更多（省略号）。
        XCTAssertEqual(rows.count, 4, "新建卡上的图标胶囊都应带 hover 背景")
        for row in rows { try assertHover(row, in: window) }
    }

    func testFocusScopeRowsUseSharedHover() throws {
        let host = NSHostingView(rootView: FocusTaskScopePopover(
            selectedScope: .today, listNames: ["工作"], listColor: { _ in .blue },
            onSelect: { _ in }, onDismiss: {})
            .frame(width: FocusTaskPickerMetrics.scopeWidth, height: 280))
        let window = InspectorPanelTestSupport.ownerWindow(
            for: host, width: FocusTaskPickerMetrics.scopeWidth, height: 280)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        let rows = hoverRows(in: host)
        XCTAssertEqual(rows.count, 5, "今天/明天/最近七天/收集箱/工作都应带 hover")
        try assertHover(rows[1], in: window)
    }

    private func hoverRows(in host: NSView) -> [RowHoverView] {
        descendants(host).compactMap { $0 as? RowHoverView }
    }

    private func assertHover(_ row: RowHoverView, in window: NSWindow) throws {
        XCTAssertTrue(row.trackingAreas.contains { $0.options.contains(.activeInActiveApp) },
                      "菜单子窗口不是 key window，仍须接收 app 级 hover")
        XCTAssertEqual(row.layer?.backgroundColor?.alpha, 0)
        row.mouseEntered(with: try trackingEvent(.mouseEntered, window: window))
        XCTAssertTrue(row.hovered)
        XCTAssertGreaterThan(row.layer?.backgroundColor?.alpha ?? 0, 0)
        row.mouseExited(with: try trackingEvent(.mouseExited, window: window))
        XCTAssertFalse(row.hovered)
        XCTAssertEqual(row.layer?.backgroundColor?.alpha, 0)
    }

    private func trackingEvent(_ type: NSEvent.EventType, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
