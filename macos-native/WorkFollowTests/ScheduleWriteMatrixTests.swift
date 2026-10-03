import XCTest
@testable import WorkFollow

/// 日程写入矩阵：**每个通道都必须带全字段**。
///
/// "功能做一半"在结构上就是这张表里有空格子。此前没有这层锁，缺口只能靠人肉 review 撞见
/// ——批量丢 `dueEndAt`、快速添加丢 `reminderOffsets`、新建对话框丢 `rule.month` 都是这么漏的。
/// 这里按通道逐格断言：直写（单任务）、批量（多任务）、创建、以及创建通道的宿主投影。
@MainActor
final class ScheduleWriteMatrixTests: XCTestCase {

    private func makeWorkspace() -> TaskWorkspaceModel {
        TaskWorkspaceModel(seedDemoData: false)
    }

    /// 一条"字段全开"的计划：时间段（带结束）+ 截止 + 多级提醒 + 带 month/monthDay 的规则。
    private func makePlan(reference: Date) -> SchedulePlan {
        var rule = RecurrenceRule()
        rule.monthDay = 15
        rule.month = 3
        return SchedulePlan(
            schedule: TaskSchedule(dueAt: reference, hasTime: true,
                                   dueEndAt: reference.addingTimeInterval(3600),
                                   deadlineAt: reference.addingTimeInterval(86_400)),
            reminder: reference.addingTimeInterval(-1800),
            reminderOffsets: [-30, 0],
            frequency: .yearly,
            recurrenceRule: rule)
    }

    private func assertPlanLanded(_ plan: SchedulePlan, on task: Task,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(task.schedule, plan.schedule,
                       "日程必须整块落地（dueAt / hasTime / dueEndAt / deadlineAt）", file: file, line: line)
        XCTAssertEqual(task.reminderAt, plan.reminder, file: file, line: line)
        XCTAssertEqual(task.reminderOffsets, plan.reminderOffsets, file: file, line: line)
        XCTAssertEqual(task.recurrence, plan.frequency, file: file, line: line)
        XCTAssertEqual(task.recurrenceRule, plan.recurrenceRule,
                       "规则整块落地（month / monthDay 不许丢）", file: file, line: line)
    }

    // MARK: - 通道 1：详情 / 任务行 / 四象限（面板直写）

    func testDirectTargetLandsEveryField() throws {
        let workspace = makeWorkspace()
        let id = try XCTUnwrap(workspace.createTask(title: "直写", in: .inbox).taskID)
        let plan = makePlan(reference: Date(timeIntervalSince1970: 1_790_000_000))
        workspace.saveSchedule(plan, to: .task(id))
        assertPlanLanded(plan, on: try XCTUnwrap(workspace.task(for: id)))
    }

    // MARK: - 通道 2：批量（同一份 plan 应用到每个任务）

    func testBatchTargetLandsEveryFieldOnEveryTask() throws {
        let workspace = makeWorkspace()
        let first = try XCTUnwrap(workspace.createTask(title: "批量A", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "批量B", in: .inbox).taskID)
        let plan = makePlan(reference: Date(timeIntervalSince1970: 1_790_000_000))
        workspace.saveSchedule(plan, to: .tasks([first, second]))
        assertPlanLanded(plan, on: try XCTUnwrap(workspace.task(for: first)))
        assertPlanLanded(plan, on: try XCTUnwrap(workspace.task(for: second)))
        workspace.undo()
        XCTAssertNil(workspace.task(for: first)?.schedule.dueEndAt, "整批算一步撤销")
        XCTAssertNil(workspace.task(for: second)?.schedule.dueEndAt, "整批算一步撤销")
    }

    func testBatchSkipsMissingTaskAndWritesTheRest() throws {
        let workspace = makeWorkspace()
        let id = try XCTUnwrap(workspace.createTask(title: "批量C", in: .inbox).taskID)
        let plan = makePlan(reference: Date(timeIntervalSince1970: 1_790_000_000))
        workspace.saveSchedule(plan, to: .tasks([UUID(), id]))
        assertPlanLanded(plan, on: try XCTUnwrap(workspace.task(for: id)))
    }

    // MARK: - 通道 3：创建（快速添加条 / 全局快速添加 / 新建对话框）

    func testCreationPathLandsEveryField() throws {
        let workspace = makeWorkspace()
        let plan = makePlan(reference: Date(timeIntervalSince1970: 1_790_000_000))
        let result = workspace.createDraft(title: "创建通道", list: TaskList.inbox.name,
                                           schedule: plan.schedule, priority: .none,
                                           tags: [], reminder: plan.reminder,
                                           reminderOffsets: plan.reminderOffsets,
                                           repeatFrequency: plan.frequency,
                                           recurrenceRule: plan.recurrenceRule)
        let id = try XCTUnwrap(result.taskID)
        assertPlanLanded(plan, on: try XCTUnwrap(workspace.task(for: id)))
    }

    /// 创建通道的**宿主侧投影**：面板产物 → 快速添加草稿，一个字段都不许漏。
    func testQuickAddDraftProjectionKeepsEveryField() {
        let plan = makePlan(reference: Date(timeIntervalSince1970: 1_790_000_000))
        let draft = QuickAddScheduleDraft(plan)
        XCTAssertEqual(draft.schedule.dueAt, plan.schedule.dueAt)
        XCTAssertEqual(draft.schedule.dueEndAt, plan.schedule.dueEndAt)
        XCTAssertEqual(draft.schedule.hasTime, plan.schedule.hasTime)
        XCTAssertEqual(draft.reminderAt, plan.reminder)
        XCTAssertEqual(draft.reminderOffsets, plan.reminderOffsets)
        XCTAssertEqual(draft.repeatFrequency, plan.frequency)
        XCTAssertEqual(draft.recurrenceRule, plan.recurrenceRule)
    }
}
