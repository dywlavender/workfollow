import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-01（2026-10-18 调整）：截止日期入口统一收在顶栏。
///
/// 滴答的日期面板没有「截止日期」行（用户确认）；安排日期面板只负责
/// 日期/时间段/时间/提醒/重复，截止日期由顶栏 `deadlineLabel` 单独设置：
/// 1. 日期面板（安排 / 截止）都不渲染 `.deadlineRow`；
/// 2. 顶栏只在任务已有截止日期时显示次要日期；
/// 3. 次要日期入口打开独立的截止日期面板。
@MainActor
final class TaskInspectorDeadlineEntryTests: XCTestCase {

    // MARK: - 日期面板不再有「截止日期」行

    func testSchedulePanelHasNoDeadlineRow() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let task = try makeTask(in: workspace, deadline: nil)

        for isDeadline in [false, true] {
            let values = try popoverValues(task: task, workspace: workspace, deadline: isDeadline)
            XCTAssertNil(values[.deadlineRow],
                         "日期面板（deadline=\(isDeadline)）不渲染截止日期入口行")
        }
    }

    // MARK: - 顶栏次要日期（只在有截止日期时显示，对齐滴答 secondaryDateLabel）

    func testHeaderHidesDeadlineWithoutDeadline() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let task = try makeTask(in: workspace, deadline: nil)
        workspace.select(task.id)

        let frames = try renderShell(workspace)
        XCTAssertNil(frames[.deadlineLabel], "未设置截止日期时顶栏不占位")
    }

    func testHeaderShowsDeadlineAfterSetting() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let task = try makeTask(in: workspace, deadline: nil)
        workspace.select(task.id)

        let deadline = workspace.calendar.startOfDay(
            for: workspace.clock().addingTimeInterval(2 * 86_400))
        workspace.saveSchedule(SchedulePlan(schedule: TaskSchedule(deadlineAt: deadline),
                                            reminder: nil, reminderOffsets: [],
                                            frequency: .never, recurrenceRule: nil),
                               to: .task(task.id))

        let frames = try renderShell(workspace)
        let label = try XCTUnwrap(frames[.deadlineLabel], "设置后顶栏出现次要日期")
        let scheduleArea = try XCTUnwrap(frames[.schedule])
        XCTAssertGreaterThan(label.width, 0)
        XCTAssertGreaterThanOrEqual(label.minX, scheduleArea.minX - 0.5)
        XCTAssertLessThanOrEqual(label.maxX, scheduleArea.maxX + 0.5,
                                 "次要日期与安排日期同属顶栏日程区")
        XCTAssertEqual(label.midY, scheduleArea.midY, accuracy: 1,
                       "两个日期在同一行")
    }

    // MARK: - 真机路径：顶栏次要日期 → 截止日期面板

    func testDeadlineLabelOpensDeadlinePanel() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "截止日期通道", in: .inbox).taskID)
        // 顶栏入口只在已有截止日期时出现，先写入一个。
        let deadline = workspace.calendar.startOfDay(for: workspace.clock())
        workspace.saveSchedule(SchedulePlan(schedule: TaskSchedule(deadlineAt: deadline),
                                            reminder: nil, reminderOffsets: [],
                                            frequency: .never, recurrenceRule: nil),
                               to: .task(id))
        workspace.select(id)

        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, width: 880,
                                                           environment: environment,
                                                           onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }

        // 按渲染锚点坐标点击（顶栏入口在 AX 树里可能被合并，不依赖文案）。
        let label = try XCTUnwrap(frames[.deadlineLabel], "顶栏必须有截止日期入口")
        try InspectorPanelTestSupport.click(label, in: host, window: window)
        let deadlinePanel = try InspectorPanelTestSupport.panel(
            title: InspectorPanelTestSupport.datePanelTitle, below: window)

        XCTAssertTrue(deadlinePanel.isVisible, "顶栏次要日期应打开截止日期面板")
        try InspectorPanelTestSupport.sendEscape(to: deadlinePanel)
    }

    func testUnsetScheduleChipOpensDatePanelAndReturnSavesShortcut() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "无日期任务入口", in: .inbox).taskID)
        workspace.select(id)
        let original = try XCTUnwrap(workspace.task(for: id))
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, width: 880,
                                                           onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 880)
        defer { window.close() }
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.scheduleChip]), in: host, window: window)
        let datePanel = try InspectorPanelTestSupport.panel(
            title: InspectorPanelTestSupport.datePanelTitle, below: window)
        let dateHost = try XCTUnwrap(datePanel.contentView as? NSHostingView<AnyView>)
        var scheduleFrames: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        dateHost.rootView = AnyView(dateHost.rootView.coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { scheduleFrames = $0 })
        InspectorPanelTestSupport.settle(datePanel)
        try InspectorPanelTestSupport.click(try XCTUnwrap(scheduleFrames[.shortcut("明天")]).frame,
                                             in: dateHost, window: datePanel)
        XCTAssertEqual(workspace.task(for: id), original)
        try InspectorPanelTestSupport.sendReturn(to: datePanel)
        XCTAssertFalse(datePanel.isVisible)
        XCTAssertEqual(workspace.task(for: id)?.schedule.dueAt, workspace.dateFromToday(1))
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id), original)
    }

    // MARK: - Helpers

    private func makeTask(in workspace: TaskWorkspaceModel, deadline: Date?) throws -> Task {
        let id = try XCTUnwrap(workspace.createTask(title: "截止日期用例", in: .inbox).taskID)
        if let deadline {
            workspace.saveSchedule(SchedulePlan(schedule: TaskSchedule(deadlineAt: deadline),
                                                reminder: nil, reminderOffsets: [],
                                                frequency: .never, recurrenceRule: nil),
                                   to: .task(id))
        }
        return try XCTUnwrap(workspace.task(for: id))
    }

    private func popoverValues(task: Task, workspace: TaskWorkspaceModel,
                               deadline: Bool = false)
    throws -> [ScheduleRenderAnchor: ScheduleRenderValue] {
        var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        let root = TaskDatePopoverV2(task: task, workspace: workspace, deadline: deadline) {}
            .background(WFColors.content)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "schedule-render")
            .onPreferenceChange(ScheduleFramesKey.self) { values = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let size = NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: 260, height: 900))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return values
    }

    private func renderShell(_ workspace: TaskWorkspaceModel) throws -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = TaskInspectorShell(workspace: workspace, showBack: false)
            .environmentObject(AppEnvironment())
            .frame(width: 880, height: 900)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return frames
    }
}
