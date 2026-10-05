import XCTest
import SwiftUI
@testable import WorkFollow

/// TaskListViewDefaults 的纯展示规则回归：快速添加占位、日期徽标归类、
/// 子任务预览、空状态文案与分组尾注。全部注入固定 Calendar，无 UI 依赖。
final class TaskListViewDefaultsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private var now: Date { date(9, 26, hour: 12) }

    func testQuickAddTargetNameUsesCreationListRatherThanViewOrTag() {
        // Flutter 的 creationTargetLabel 取清单名；标签过滤不改变创建清单。
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            activeList: "工作", inboxName: "收集箱"), "工作")
        // Today、最近 7 天、所有任务以及标签过滤均默认创建到收集箱。
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            activeList: nil, inboxName: "收集箱"), "收集箱")
        XCTAssertEqual(TaskListViewDefaults.quickAddTargetName(
            activeList: nil, inboxName: TaskList.inbox.name), TaskList.inbox.name)
    }

    func testDateBadgeStyleClassifiesOverdueTodayFutureAndClosed() {
        // 过期 → 红。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 25), isClosed: false, now: now, calendar: calendar), .overdue)
        // 当天（含带时间）→ 强调色。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 26, hour: 23), isClosed: false, now: now, calendar: calendar), .today)
        // 未来 → 未逾期（蓝）。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 30), isClosed: false, now: now, calendar: calendar), .scheduled)
        // 无日期 → 无徽标色。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: nil, isClosed: false, now: now, calendar: calendar), .none)
        // 已关闭的任务不给日期上色。
        XCTAssertEqual(TaskListViewDefaults.dateBadgeStyle(
            dueAt: date(9, 25), isClosed: true, now: now, calendar: calendar), .none)
    }

    func testRowDateColorsAreBlueUntilOverdueAndNeutralWhenClosed() {
        XCTAssertEqual(TaskListViewDefaults.rowDateColor(for: .today), WFColors.accent)
        XCTAssertEqual(TaskListViewDefaults.rowDateColor(for: .scheduled), WFColors.accent)
        XCTAssertEqual(TaskListViewDefaults.rowDateColor(for: .overdue), Color.red)
        XCTAssertEqual(TaskListViewDefaults.rowDateColor(for: .none), WFColors.taskCompletedMetadata)
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

    func testReminderMetadataIncludesRelativeAndLegacyReminders() {
        XCTAssertTrue(TaskListViewDefaults.hasReminder(reminderAt: nil, reminderOffsets: [-30, 0]))
        XCTAssertTrue(TaskListViewDefaults.hasReminder(reminderAt: date(9, 26), reminderOffsets: nil))
        XCTAssertFalse(TaskListViewDefaults.hasReminder(reminderAt: nil, reminderOffsets: []))
    }

    func testHeaderSymbolMatchesDestinationAndCustomFilters() {
        XCTAssertEqual(TaskListViewDefaults.headerSymbol(destination: .today, activeList: nil, activeTag: nil), "sun.max")
        XCTAssertEqual(TaskListViewDefaults.headerSymbol(destination: .nextSevenDays, activeList: nil, activeTag: nil), "line.3.horizontal")
        XCTAssertEqual(TaskListViewDefaults.headerSymbol(destination: .today, activeList: "工作", activeTag: nil), "list.bullet")
        XCTAssertEqual(TaskListViewDefaults.headerSymbol(destination: .today, activeList: nil, activeTag: "阅读"), "tag")
    }

    func testTimedScheduleShowsTimeWhileAllDayUsesDateLabel() {
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: date(9, 30, hour: 10, minute: 30), hasTime: true,
            now: now, calendar: calendar), "10:30")
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: date(9, 26), hasTime: false, now: now, calendar: calendar), "今天")
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: date(9, 27), hasTime: false, now: now, calendar: calendar), "明天")
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: date(9, 30), hasTime: false, now: now, calendar: calendar), "9月30日")
    }

    func testSubtaskProgressCountsCompletedAndActiveChildrenOnly() {
        let parentID = UUID()
        let children = [
            makeTask("完成 1", parentID: parentID, status: .completed),
            makeTask("完成 2", parentID: parentID, status: .completed),
            makeTask("待办 1", parentID: parentID),
            makeTask("待办 2", parentID: parentID),
            makeTask("已删除", parentID: parentID, deletedAt: now)
        ]
        XCTAssertEqual(TaskListViewDefaults.subtaskProgress(parentID: parentID, tasks: children), "2/4")
        XCTAssertNil(TaskListViewDefaults.subtaskProgress(parentID: UUID(), tasks: children))
    }

    func testTaskRowHeightContractIs50PointsWithExistingVerticalPadding() {
        XCTAssertEqual(WFMetrics.rowHeight, 50)
        XCTAssertEqual(WFMetrics.rowVerticalPadding, 11)
        XCTAssertEqual(WFMetrics.rowContentMinHeight, 28)
    }

    private func makeTask(_ title: String, parentID: UUID?, status: TaskStatus = .active,
                          deletedAt: Date? = nil) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none, schedule: TaskSchedule(),
             status: status, parentID: parentID, childOrder: 0,
             createdAt: now, updatedAt: now,
             completedAt: status == .completed ? now : nil, deletedAt: deletedAt)
    }
}
