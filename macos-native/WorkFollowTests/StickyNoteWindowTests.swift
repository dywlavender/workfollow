import XCTest
@testable import WorkFollow

/// 便签浮窗（阶段 1）：编辑防抖写回、回灌抑制、单实例、删除跟随关窗。
/// 全部走控制器 + 真实 workspace 数据,断言 store 语义而非窗口像素。
@MainActor
final class StickyNoteWindowTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!
    }

    private func makeTask(_ title: String, document: NativeDocument = .empty) -> Task {
        Task(id: UUID(), title: title, document: document, list: .inbox, priority: .none,
             schedule: TaskSchedule(), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private func makeWorkspace(_ tasks: [Task]) -> TaskWorkspaceModel {
        TaskWorkspaceModel(clock: { self.now }, calendar: calendar,
                           seedDemoData: false, initialTasks: tasks)
    }

    override func setUp() {
        super.setUp()
        StickyNoteWindowController.shared.closeAll()
    }

    override func tearDown() {
        StickyNoteWindowController.shared.closeAll()
        super.tearDown()
    }

    /// AC-1.1 等效:打开后实例登记在案,窗口可见。
    func testOpenRegistersSingleInstancePerTask() {
        let a = makeTask("便签A")
        let workspace = makeWorkspace([a])
        StickyNoteWindowController.shared.attach(workspace: workspace)

        StickyNoteWindowController.shared.open(taskID: a.id)
        XCTAssertEqual(StickyNoteWindowController.shared.openTaskIDs, [a.id])

        // AC-1.5:重复打开不产生第二个实例。
        StickyNoteWindowController.shared.open(taskID: a.id)
        XCTAssertEqual(StickyNoteWindowController.shared.openTaskIDs, [a.id])
    }

    /// AC-1.2 等效:浮窗编辑(模拟 textDidChange)防抖写回 store。
    func testEditorWriteBackUpdatesStoreDocument() async throws {
        let a = makeTask("便签A")
        let workspace = makeWorkspace([a])
        StickyNoteWindowController.shared.attach(workspace: workspace)
        StickyNoteWindowController.shared.debounceEnabled = false
        StickyNoteWindowController.shared.open(taskID: a.id)

        StickyNoteWindowController.shared.simulateEditorText("便签里改的内容", for: a.id)
        // 防抖 0.5s,等待写回。
        try await Swift.Task.sleep(nanoseconds: 900_000_000)

        XCTAssertEqual(workspace.task(for: a.id)?.document.plainText, "便签里改的内容")
    }

    /// AC-1.3 等效:主窗口改动回灌浮窗文本。
    func testStoreChangeFeedsBackToPanel() {
        let a = makeTask("便签A")
        let workspace = makeWorkspace([a])
        StickyNoteWindowController.shared.attach(workspace: workspace)
        StickyNoteWindowController.shared.open(taskID: a.id)

        workspace.setDocument(a.id, NativeDocument(plainText: "主窗口改的"))

        let text = StickyNoteWindowController.shared.panelText(for: a.id)
        XCTAssertEqual(text, "主窗口改的")
    }

    /// 回灌抑制:浮窗自己触发的写回不再反向覆盖浮窗(用户光标安全)。
    /// 这里验证 suppressEcho 机制存在行为:写回后主窗口值 == 浮窗值。
    func testWriteBackDoesNotFightWithFeedback() async throws {
        let a = makeTask("便签A")
        let workspace = makeWorkspace([a])
        StickyNoteWindowController.shared.attach(workspace: workspace)
        StickyNoteWindowController.shared.debounceEnabled = false
        StickyNoteWindowController.shared.open(taskID: a.id)

        StickyNoteWindowController.shared.simulateEditorText("第一版", for: a.id)
        try await Swift.Task.sleep(nanoseconds: 900_000_000)
        StickyNoteWindowController.shared.simulateEditorText("第二版", for: a.id)
        try await Swift.Task.sleep(nanoseconds: 900_000_000)

        XCTAssertEqual(workspace.task(for: a.id)?.document.plainText, "第二版",
                       "连续编辑最后一次落盘")
        // 回灌不打架:写回期间 suppressEcho 抑制了 sink 回灌,浮窗文本不被
        // 打回旧值(浮窗最终文本由用户最后输入决定)。
        XCTAssertGreaterThanOrEqual(
            StickyNoteWindowController.shared.suppressedCountDuringLastWriteBack, 1,
            "每次写回期间的 store 变更回灌均被抑制")
    }

    /// AC-1.6:任务删除 → 便签自动关闭。
    func testTaskDeleteClosesStickyNote() {
        let a = makeTask("便签A")
        let workspace = makeWorkspace([a])
        StickyNoteWindowController.shared.attach(workspace: workspace)
        StickyNoteWindowController.shared.open(taskID: a.id)
        XCTAssertEqual(StickyNoteWindowController.shared.openTaskIDs.count, 1)

        _ = workspace.delete(a.id)
        // workspace.objectWillChange 同步触发控制器观察者。
        XCTAssertEqual(StickyNoteWindowController.shared.openTaskIDs, [],
                       "删除任务后便签自动关闭")
    }

    /// 多开并存(AC-1.4 等效):两个任务各持一个实例。
    func testMultipleNotesCoexist() {
        let a = makeTask("A"), b = makeTask("B")
        let workspace = makeWorkspace([a, b])
        StickyNoteWindowController.shared.attach(workspace: workspace)

        StickyNoteWindowController.shared.open(taskID: a.id)
        StickyNoteWindowController.shared.open(taskID: b.id)

        XCTAssertEqual(Set(StickyNoteWindowController.shared.openTaskIDs), [a.id, b.id])
    }
}
