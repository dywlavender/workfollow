import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 创建完成后的落点契约。
///
/// 用户反馈的原症状：在页面上新建一条待办，新行**看着**被选中（涂了选中灰），
/// 但右侧编辑栏仍是上一条待办的内容。根因有两层，这里各钉一条：
///
/// 1. 列表快速添加条传 `selectCreatedTask: false`，所以 `selectedTaskID` 压根没变；
/// 2. 「刚创建」的 2 秒标识被画成了选中底色（`selected || recentlyCreated`），
///    于是"看起来选中"和"实际选中"分叉。
@MainActor
final class TaskCreationOpensCreatedTaskTests: XCTestCase {
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let value = view as? T { return value }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    private func workspace(_ tasks: [Task] = [], now: Date = Date()) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { now }, seedDemoData: false, initialTasks: tasks)
    }

    // MARK: - 模型层：范围内外两种落点

    func testOpenCreatedTaskSelectsItWhenItLandsInTheCurrentView() throws {
        let model = workspace()
        let id = try XCTUnwrap(model.submitCapture(
            QuickCaptureSession(text: "今天要做的事"), defaultDueAt: model.dateFromToday(0),
            selectCreatedTask: false).last)
        XCTAssertNil(model.selectedTaskID, "创建本身不抢选中（列表条传 false 时）")

        XCTAssertTrue(model.openCreatedTask(id, in: .today),
                      "落在当前视图里的新任务应该被打开")
        XCTAssertEqual(model.selectedTaskID, id, "编辑栏必须跟到新任务")
    }

    func testOpenCreatedTaskRefusesTaskOutsideTheCurrentView() throws {
        let model = workspace()
        // 没有日期 → 不属于「今天」。打开它只会得到一份空详情，不如保留去向提示。
        let id = try XCTUnwrap(model.submitCapture(
            QuickCaptureSession(text: "没有日期的收集箱任务"), selectCreatedTask: false).last)

        XCTAssertFalse(model.openCreatedTask(id, in: .today),
                       "范围外的任务不该抢选中")
        XCTAssertNil(model.selectedTaskID)
    }

    func testOpenCreatedTaskRefusesTaskHiddenByActiveListQuery() throws {
        let model = workspace()
        let id = try XCTUnwrap(model.submitCapture(
            QuickCaptureSession(text: "清单筛选外的任务", listOverride: "工作"),
            selectCreatedTask: false).last)

        XCTAssertFalse(model.openCreatedTask(id, in: .allTasks, query: TaskListQuery(list: "学习")),
                       "被当前清单筛选掉的任务不该被打开")
        XCTAssertNil(model.selectedTaskID)
    }

    func testOpenCreatedTaskSelectsSubtaskThroughItsVisibleParent() throws {
        let parent = Task(id: UUID(), title: "父任务", list: .inbox, priority: .none,
                          schedule: TaskSchedule(dueAt: Date()), childOrder: 0,
                          createdAt: Date(), updatedAt: Date())
        let model = workspace([parent])
        let childID = try XCTUnwrap(model.createChild(parent.id, title: "子任务").taskID)

        // 子任务在列表里只跟着父任务出现；父任务可见即视为可见。
        XCTAssertTrue(model.openCreatedTask(childID, in: .today))
        XCTAssertEqual(model.selectedTaskID, childID)
    }

    func testOpenCreatedTaskClearsBulkSelectionSoDetailIsReachable() throws {
        let existing = Task(id: UUID(), title: "已有任务", list: .inbox, priority: .none,
                            schedule: TaskSchedule(dueAt: Date()), childOrder: 0,
                            createdAt: Date(), updatedAt: Date())
        let model = workspace([existing])
        model.toggleBulkSelection(existing.id)
        XCTAssertFalse(model.bulkSelection.isEmpty)

        let id = try XCTUnwrap(model.submitCapture(
            QuickCaptureSession(text: "新任务"), defaultDueAt: model.dateFromToday(0),
            selectCreatedTask: false).last)
        XCTAssertTrue(model.openCreatedTask(id, in: .today))
        // 批量态下右栏是批量面板，详情看不见；打开新任务必须先退出批量态。
        XCTAssertTrue(model.bulkSelection.isEmpty, "打开新任务时应退出批量选中")
        XCTAssertEqual(model.selectedTaskID, id)
    }

    // MARK: - 渲染层：新建标识不等于选中

    func testNewlyCreatedRowIsHighlightedButNotPaintedAsSelected() throws {
        let now = Date()
        let task = Task(id: UUID(), title: "刚建的任务", list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: now), childOrder: 0,
                        createdAt: now, updatedAt: now)
        let model = workspace([task], now: now)
        let environment = AppEnvironment(clock: { now },
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        let row = NativeTaskRowView()
        row.configure(NativeTaskRowConfiguration(task: task, workspace: model, environment: environment,
            depth: 0, hasChildren: false, expanded: false, bulkSelected: false,
            recentlyCreated: true, showsListBadge: false, hidesDetails: true, hiddenFields: [],
            allowsReordering: false, dateDisplay: .taskTime, feedback: TaskDropFeedback(),
            onEditingRequested: {}, onEditingBegan: {}, onEditingEnded: {}, onSelect: {},
            onBulkToggle: {}, onRangeSelect: {}, onComplete: {}, onRestore: {}, onToggleExpanded: {}),
            selectedTaskID: nil, values: EnvironmentValues())

        let hover = try XCTUnwrap(find(RowHoverView.self, in: row))
        XCTAssertTrue(hover.highlighted, "新建行要有 2 秒标识")
        XCTAssertFalse(hover.selected, "新建标识不能同时算作选中，否则行看着被打开、详情却是上一条")
    }

    func testSelectedRowWinsOverCreationHighlight() throws {
        let now = Date()
        let task = Task(id: UUID(), title: "刚建又打开的任务", list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: now), childOrder: 0,
                        createdAt: now, updatedAt: now)
        let model = workspace([task], now: now)
        let environment = AppEnvironment(clock: { now },
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        let row = NativeTaskRowView()
        row.configure(NativeTaskRowConfiguration(task: task, workspace: model, environment: environment,
            depth: 0, hasChildren: false, expanded: false, bulkSelected: false,
            recentlyCreated: true, showsListBadge: false, hidesDetails: true, hiddenFields: [],
            allowsReordering: false, dateDisplay: .taskTime, feedback: TaskDropFeedback(),
            onEditingRequested: {}, onEditingBegan: {}, onEditingEnded: {}, onSelect: {},
            onBulkToggle: {}, onRangeSelect: {}, onComplete: {}, onRestore: {}, onToggleExpanded: {}),
            selectedTaskID: task.id, values: EnvironmentValues())

        let hover = try XCTUnwrap(find(RowHoverView.self, in: row))
        XCTAssertTrue(hover.selected)
        // 同一行既刚建又被打开时，显示的是"正被编辑"，不该退回"刚建出来"。
        XCTAssertFalse(hover.highlighted, "选中必须压过新建标识")
    }
}
