import XCTest
@testable import WorkFollow

/// 日程字段的「写后读」回归。
///
/// 这三条对应一类真实缺陷：面板里明明设置了，任务里却没有——字段在
/// 批量 / 创建通道里被静默丢弃。每条用例都从 store 读回任务后断言，
/// 而不是只断言传参。
@MainActor
final class ScheduleFieldPersistenceTests: XCTestCase {

    /// 批量改期：面板可以从「时间段」模式提交，`dueEndAt` 必须一起落地；
    /// `deadlineAt` 不属于批量通道，应保留任务原值。
    func testBulkScheduleKeepsPeriodEndAndPreservesDeadline() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "批量时间段", in: .inbox).taskID)
        let calendar = workspace.calendar
        let base = workspace.dateFromToday(0)
        let oldStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: base))
        let oldEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: oldStart))
        let deadline = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: oldStart))
        _ = workspace.setSchedule(id, TaskSchedule(dueAt: oldStart, hasTime: true,
                                                   dueEndAt: oldEnd, deadlineAt: deadline))

        let newStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: base))
        let newEnd = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: newStart))
        workspace.bulkSelection = [id]
        workspace.applyBulk(.schedule(TaskSchedule(dueAt: newStart, hasTime: true, dueEndAt: newEnd)))

        let task = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(task.schedule.dueAt, newStart)
        XCTAssertEqual(task.schedule.dueEndAt, newEnd, "批量改期不能丢掉时间段的结束")
        XCTAssertEqual(task.schedule.deadlineAt, deadline, "截止日期应保留")
    }

    /// 创建通道要写入面板里勾的多级提醒（`reminderOffsets`），
    /// 而不只是旧式的单个 `reminderAt`。
    func testCreateDraftWritesReminderOffsets() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let result = workspace.createDraft(title: "多级提醒",
                                           list: TaskList.inbox.name,
                                           schedule: TaskSchedule(dueAt: workspace.dateFromToday(1),
                                                                  hasTime: true),
                                           priority: .none,
                                           tags: [],
                                           reminder: nil,
                                           reminderOffsets: [0, -1440],
                                           repeatFrequency: .never)
        let id = try XCTUnwrap(result.taskID)
        let task = try XCTUnwrap(workspace.task(for: id))
        XCTAssertEqual(task.reminderOffsets, [-1440, 0],
                       "面板里勾的多级提醒必须写进新任务（升序归一）")
    }

    /// 快速添加草稿的形状：空数组代表"未设提醒"，交出去时是 nil 而不是清空。
    func testQuickAddDraftCarriesReminderOffsets() throws {
        let draft = QuickAddScheduleDraft(dueAt: Date(), hasTime: true,
                                          reminderAt: nil, reminderOffsets: [-30])
        XCTAssertEqual(draft.reminderOffsetsOrNil, [-30])
        XCTAssertEqual(draft.schedule.hasTime, true)
        XCTAssertNil(QuickAddScheduleDraft().reminderOffsetsOrNil,
                     "空数组表示未设提醒，交给动作层应为 nil")
    }
}
