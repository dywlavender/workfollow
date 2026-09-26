import XCTest
@testable import WorkFollow

/// TaskListViewDefaults 的纯展示规则回归：快速添加占位、日期徽标归类、
/// 子任务预览、空状态文案与分组尾注。全部注入固定 Calendar，无 UI 依赖。
final class TaskListViewDefaultsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private var now: Date { date(9, 26, hour: 12) }

    func testQuickAddTargetNamePrefersListThenTagThenViewScope() {
        // 已按清单过滤时占位跟随清单（最高优先）。
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            scope: .today, activeList: "工作", activeTag: "验收", inboxName: "收集箱"), "工作")
        // 只有标签过滤时显示标签。
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            scope: .allTasks, activeList: nil, activeTag: "验收", inboxName: "收集箱"), "#验收")
        // 无清单/标签时跟随视图语义。
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            scope: .today, activeList: nil, activeTag: nil, inboxName: "收集箱"), "今天")
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            scope: .nextSevenDays, activeList: nil, activeTag: nil, inboxName: "收集箱"), "最近 7 天")
        // 其余（收集箱/所有任务/空）回落到收集箱。
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            scope: .inbox, activeList: nil, activeTag: nil, inboxName: "收集箱"), "收集箱")
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            scope: .allTasks, activeList: nil, activeTag: nil, inboxName: "收集箱"), "收集箱")
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            scope: nil, activeList: nil, activeTag: nil, inboxName: "收集箱"), "收集箱")
    }

    func testDateBadgeStyleClassifiesOverdueTodayFutureAndClosed() {
        // 过期 → 红。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 25), isClosed: false, now: now, calendar: calendar), .overdue)
        // 当天（含带时间）→ 强调色。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 26, hour: 23), isClosed: false, now: now, calendar: calendar), .today)
        // 未来 → 灰。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 30), isClosed: false, now: now, calendar: calendar), .scheduled)
        // 无日期 → 无徽标色。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: nil, isClosed: false, now: now, calendar: calendar), .none)
        // 已关闭的任务不给日期上色。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 25), isClosed: true, now: now, calendar: calendar), .none)
    }

    func testSubtaskPreviewJoinsChecklistPrefixLimitsAndFallsBack() {
        XCTAssertNil(TaskListViewDefaults.subtaskPreview(titles: []))
        XCTAssertEqual(TaskListViewDefaults.subtaskPreview(titles: ["甲"]), "- [ ] 甲")
        XCTAssertEqual(
            TaskListViewDefaults.subtaskPreview(titles: ["甲", "", "乙", "丙"]),
            "- [ ] 甲 - [ ] 无标题 - [ ] 乙")
    }

    func testEmptyStateMessageFollowsDestination() {
        XCTAssertEqual(TaskListViewDefaults.emptyStateMessage(destination: .today), "今天的事情都做完了")
        XCTAssertEqual(TaskListViewDefaults.emptyStateMessage(destination: .inbox),
                       "没想好把任务安排在哪？可以先放这里")
        XCTAssertEqual(TaskListViewDefaults.emptyStateMessage(destination: .trash), "垃圾桶是空的")
        XCTAssertEqual(TaskListViewDefaults.emptyStateMessage(destination: .allTasks), "这里还没有任务")
        XCTAssertEqual(TaskListViewDefaults.emptyStateMessage(destination: .completed), "这里还没有任务")
    }

    func testOnlyOverdueGroupCarriesPostponeNote() {
        XCTAssertEqual(TaskListViewDefaults.groupTrailingNote(for: .overdue), "顺延")
        for kind in [TaskGroupKind.pinned, .today, .upcoming, .later, .undated, .day, .plain, .completed] {
            XCTAssertNil(TaskListViewDefaults.groupTrailingNote(for: kind))
        }
    }
}
