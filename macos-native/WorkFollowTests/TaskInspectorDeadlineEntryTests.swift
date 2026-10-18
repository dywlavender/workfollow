import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-01：截止日期入口。
///
/// 结构证据（滴答 8.0.80）：顶栏 `TTTaskDetailTopView.secondaryDateLabel`（412×14）+
/// `dateButton`；本地此前 `deadlineAt` 有字段、`TaskDatePopoverV2(deadline: true)` 有分支，
/// 但没有任何调用点——这两条用例锁住"入口真的接上了"：
/// 1. 安排日期面板只在详情编辑栏（传了 `onRequestDeadline`）里多出「截止日期」行；
/// 2. 顶栏只在有截止日期时渲染次要日期标签，且位于安排日期右侧。
@MainActor
final class TaskInspectorDeadlineEntryTests: XCTestCase {

    // MARK: - 布局契约

    func testDeadlineRowGrowsSchedulePanelByExactlyOneRow() {
        let base = SchedulePopoverLayoutV2.height(availableHeight: 1200)
        let withEntry = SchedulePopoverLayoutV2.height(availableHeight: 1200, deadlineRow: true)
        XCTAssertEqual(withEntry - base, ScheduleMetrics.rowHeight, accuracy: 0.5)
    }

    func testDeadlineRowDefaultsOffForEveryOtherHost() {
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 1200, deadlineRow: false),
                       SchedulePopoverLayoutV2.height(availableHeight: 1200))
        XCTAssertEqual(SchedulePopoverLayoutV2.height(availableHeight: 1200, repeating: true),
                       SchedulePopoverLayoutV2.height(availableHeight: 1200, repeating: true, deadlineRow: false))
    }

    // MARK: - 安排日期面板里的「截止日期」行

    func testSchedulePanelShowsDeadlineEntryOnlyForInspectorHost() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let task = try makeTask(in: workspace, deadline: nil)

        let inspector = try popoverValues(task: task, workspace: workspace, onRequestDeadline: {})
        let row = try XCTUnwrap(inspector[.deadlineRow],
                                "详情编辑栏的安排日期面板必须有截止日期入口")
        XCTAssertEqual(row.label, "截止日期")
        XCTAssertFalse(row.active)

        let otherHost = try popoverValues(task: task, workspace: workspace, onRequestDeadline: nil)
        XCTAssertNil(otherHost[.deadlineRow], "任务行 / 快速添加 / 批量面板不应出现该行")
    }

    func testDeadlineEntryShowsTheExistingDeadlineAsActive() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let deadline = workspace.calendar.startOfDay(
            for: workspace.clock().addingTimeInterval(3 * 86_400))
        let task = try makeTask(in: workspace, deadline: deadline)

        let values = try popoverValues(task: task, workspace: workspace, onRequestDeadline: {})
        let row = try XCTUnwrap(values[.deadlineRow])
        XCTAssertTrue(row.active, "已设截止日期时该行是激活态")
        XCTAssertTrue(row.label.hasPrefix("截止 "), "行文案带上当前截止日期：\(row.label)")
    }

    /// 截止日期面板本身不再重复渲染入口行（否则会出现"截止日期 › 截止日期"的自指）。
    func testDeadlinePanelDoesNotRepeatTheEntryRow() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let deadline = workspace.calendar.startOfDay(for: workspace.clock())
        let task = try makeTask(in: workspace, deadline: deadline)

        let values = try popoverValues(task: task, workspace: workspace,
                                       deadline: true, onRequestDeadline: {})
        XCTAssertNil(values[.deadlineRow])
    }

    // MARK: - 顶栏次要日期标签

    func testHeaderShowsDeadlineLabelOnlyWhenDeadlineExists() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let task = try makeTask(in: workspace, deadline: nil)
        workspace.select(task.id)

        var frames = try renderShell(workspace)
        XCTAssertNil(frames[.deadlineLabel], "没有截止日期时顶栏不占位")

        let deadline = workspace.calendar.startOfDay(
            for: workspace.clock().addingTimeInterval(2 * 86_400))
        workspace.saveSchedule(SchedulePlan(schedule: TaskSchedule(deadlineAt: deadline),
                                            reminder: nil, reminderOffsets: [],
                                            frequency: .never, recurrenceRule: nil),
                               to: .task(task.id))
        frames = try renderShell(workspace)

        let label = try XCTUnwrap(frames[.deadlineLabel], "有截止日期时顶栏出现次要日期")
        let scheduleArea = try XCTUnwrap(frames[.schedule])
        XCTAssertGreaterThan(label.width, 0)
        XCTAssertGreaterThanOrEqual(label.minX, scheduleArea.minX - 0.5)
        XCTAssertLessThanOrEqual(label.maxX, scheduleArea.maxX + 0.5,
                                 "次要日期与安排日期同属顶栏日程区")
        XCTAssertEqual(label.midY, scheduleArea.midY, accuracy: 1,
                       "两个日期在同一行")
    }

    func testDeadlineLabelDisappearsWhenDeadlineIsCleared() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let task = try makeTask(in: workspace, deadline: nil)
        workspace.select(task.id)

        var frames = try renderShell(workspace)
        XCTAssertNil(frames[.deadlineLabel])

        let deadline = workspace.calendar.startOfDay(for: workspace.clock())
        workspace.saveSchedule(SchedulePlan(schedule: TaskSchedule(deadlineAt: deadline),
                                            reminder: nil, reminderOffsets: [],
                                            frequency: .never, recurrenceRule: nil),
                               to: .task(task.id))
        frames = try renderShell(workspace)
        XCTAssertNotNil(frames[.deadlineLabel])

        // 清除走的是同一条 deadline 通道（`TaskDateDraftModel.clearPlan` 只清 deadlineAt）。
        workspace.saveSchedule(SchedulePlan(schedule: TaskSchedule(deadlineAt: nil),
                                            reminder: nil, reminderOffsets: [],
                                            frequency: .never, recurrenceRule: nil),
                               to: .task(task.id))
        frames = try renderShell(workspace)
        XCTAssertNil(frames[.deadlineLabel], "清除后不再占位")
    }

    // MARK: - 真机路径：日期面板里点「截止日期」→ 切到截止日期面板 → 选日期 → 写回

    func testDeadlineRowSwitchesPanelAndWritesDeadlineThroughTheRealInspector() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "截止日期通道", in: .inbox).taskID)
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        XCTAssertNil(workspace.task(for: id)?.schedule.deadlineAt)

        try InspectorPanelTestSupport.clickButton(containing: "设置日期", in: window)
        let schedulePanel = try InspectorPanelTestSupport.panel(
            title: InspectorPanelTestSupport.datePanelTitle, below: window)
        try InspectorPanelTestSupport.clickButton(containing: "截止日期", in: schedulePanel)

        XCTAssertFalse(schedulePanel.isVisible, "点截止日期后安排日期面板收起")
        let deadlinePanel = try InspectorPanelTestSupport.panel(
            title: InspectorPanelTestSupport.datePanelTitle, below: window)
        XCTAssertFalse(deadlinePanel === schedulePanel, "必须是另一块面板（deadline 模式）")

        // 截止日期面板默认选中今天；回车走「确定」（`.keyboardShortcut(.defaultAction)`）。
        try InspectorPanelTestSupport.sendReturn(to: deadlinePanel)

        let deadline = try XCTUnwrap(workspace.task(for: id)?.schedule.deadlineAt,
                                     "确定后必须写回 deadlineAt")
        let expected = workspace.calendar.startOfDay(for: workspace.clock())
        XCTAssertEqual(workspace.calendar.startOfDay(for: deadline), expected)
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
                               deadline: Bool = false,
                               onRequestDeadline: (() -> Void)?)
    throws -> [ScheduleRenderAnchor: ScheduleRenderValue] {
        var values: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
        let root = TaskDatePopoverV2(task: task, workspace: workspace, deadline: deadline,
                                     onRequestDeadline: onRequestDeadline) {}
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
