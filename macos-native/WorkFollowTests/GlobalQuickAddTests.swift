import XCTest
@testable import WorkFollow

/// 全局快速添加的"解析 → 建任务"管线测试：只测 GlobalQuickAddComposer，
/// 不触碰真实热键注册与面板。
final class GlobalQuickAddTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testPlainTextCreatesInboxTask() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let id = composer.submit(text: "买牛奶")
            XCTAssertNotNil(id)
            let task = workspace.task(for: id!)
            XCTAssertEqual(task?.title, "买牛奶")
            XCTAssertEqual(task?.list, .inbox)
            XCTAssertEqual(task?.priority, TaskPriority.none)
            XCTAssertNil(task?.schedule.dueAt)
            XCTAssertEqual(task?.schedule.hasTime, false)
        }
    }

    func testParsedDateSchedulesTask() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let id = composer.submit(text: "明天 交周报")
            XCTAssertNotNil(id)
            let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            XCTAssertEqual(workspace.task(for: id!)?.schedule.dueAt, expected)
            XCTAssertEqual(workspace.task(for: id!)?.schedule.hasTime, false)
        }
    }

    func testParsedPriorityAppliesToTask() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let id = composer.submit(text: "准备评审材料 !!")
            XCTAssertNotNil(id)
            XCTAssertEqual(workspace.task(for: id!)?.priority, .medium)
            XCTAssertEqual(workspace.task(for: id!)?.title, "准备评审材料")
        }
    }

    func testEmptyOrTokenOnlyTextReturnsNilWithoutCreatingTasks() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            XCTAssertNil(composer.submit(text: ""))
            XCTAssertNil(composer.submit(text: "   "))
            // 只有解析 token（明天）而无标题文本：不建任务。
            XCTAssertNil(composer.submit(text: "明天"))
            XCTAssertTrue(workspace.allTasks.isEmpty)
        }
    }

    func testKnownListRoutingAndInboxFallback() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false, initialLists: ["工作"])
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let routed = composer.submit(text: "@工作 写季度总结")
            XCTAssertNotNil(routed)
            XCTAssertEqual(workspace.task(for: routed!)?.list, TaskList(name: "工作"))
            // 解析不到清单时进收集箱。
            let fallback = composer.submit(text: "随手记一条")
            XCTAssertNotNil(fallback)
            XCTAssertEqual(workspace.task(for: fallback!)?.list, .inbox)
        }
    }
}
