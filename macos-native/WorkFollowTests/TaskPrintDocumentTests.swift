import XCTest
@testable import WorkFollow

/// 打印文本的纯函数（与 AppKit 解耦）：分组头 + 每行任务的元信息。
final class TaskPrintDocumentTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func task(_ title: String, status: TaskStatus = .active, dueAt: Date? = nil,
                      priority: TaskPriority = .none, tags: [String] = []) -> Task {
        var task = Task(id: UUID(), title: title, list: TaskList(name: "工作"), priority: priority,
                        schedule: TaskSchedule(dueAt: dueAt, hasTime: true), parentID: nil,
                        childOrder: 0, createdAt: now, updatedAt: now)
        task.status = status
        task.tags = tags
        return task
    }

    func testPrintTextCarriesGroupHeaderAndTaskMeta() {
        let group = TaskListGroup(kind: .plain, day: nil,
                                  tasks: [task("写周报", dueAt: now, priority: .high, tags: ["报告"]),
                                          task("旧任务", status: .completed)],
                                  label: "进行中")
        let text = TaskPrintDocument.text(title: "工作", groups: [group], now: now, calendar: calendar)
        XCTAssertTrue(text.hasPrefix("工作\n──"), "标题 + 分隔线")
        XCTAssertTrue(text.contains("进行中（2）"), "分组头带计数（与列表/看板同一份文案来源）")
        XCTAssertTrue(text.contains("• 写周报"), "未完成用 • 前缀")
        XCTAssertTrue(text.contains("#报告"), "标签进打印文本")
        XCTAssertTrue(text.contains("高"), "优先级进打印文本")
        XCTAssertTrue(text.contains("✓ 旧任务"), "已完成用 ✓ 前缀")
    }

    func testPrintTextFallsBackForUntitledTaskAndEmptyGroups() {
        let group = TaskListGroup(kind: .plain, day: nil, tasks: [task("")], label: "未分组")
        let text = TaskPrintDocument.text(title: "收集箱", groups: [group], now: now, calendar: calendar)
        XCTAssertTrue(text.contains("• 无标题"), "空标题有兜底文案")

        let empty = TaskPrintDocument.text(title: "空清单", groups: [], now: now, calendar: calendar)
        XCTAssertTrue(empty.hasPrefix("空清单\n──"), "没有分组时只留标题（不补造内容）")
        XCTAssertFalse(empty.contains("（"), "空视图不补造分组")
    }
}
