import XCTest
@testable import WorkFollow

/// 日期面板「时间」行占位（2026-10-18，对齐滴答）：
/// 没有具体时刻时这一行只显示占位「时间」，不再露出默认 09:00
/// （否则用户会以为设过了时间，却找不到清除入口）。
///
/// 视图层的占位/输入框切换由真机核验；这里锁住驱动它的判据 `hasTime`。
@MainActor
final class ScheduleTimeRowPlaceholderTests: XCTestCase {

    func testHasTimeDistinguishesPlaceholderFromValue() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "时间占位用例", in: .inbox).taskID)

        var task = try XCTUnwrap(workspace.task(for: id))
        XCTAssertFalse(task.schedule.hasTime, "默认全天：行显示占位「时间」")

        let day = workspace.calendar.startOfDay(for: workspace.clock())
        let timed = workspace.calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day) ?? day
        workspace.saveSchedule(SchedulePlan(schedule: TaskSchedule(dueAt: timed, hasTime: true),
                                            reminder: nil, reminderOffsets: [],
                                            frequency: .never, recurrenceRule: nil),
                               to: .task(id))

        task = try XCTUnwrap(workspace.task(for: id))
        XCTAssertTrue(task.schedule.hasTime, "设了时刻：行显示输入框，可清除")
    }
}
