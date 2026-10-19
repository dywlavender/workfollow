import XCTest
@testable import WorkFollow

/// 时间段的开始 / 结束日期行及全天开关所使用的草稿语义。
/// 参考端的会员介绍图展示了这组控件；本地提交行为由这些测试验证。
@MainActor
final class SchedulePeriodTabTests: XCTestCase {

    private func makeModel(calendar: Calendar = .current) throws -> (TaskDateDraftModel, Task) {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "时间段用例", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.task(for: id))
        let model = TaskDateDraftModel(task: task, calendar: calendar,
                                       now: { Date(timeIntervalSince1970: 1_760_000_000) },
                                       deadline: false)
        model.setTab(.period)
        return (model, task)
    }

    func testSetPeriodStartAndEndDirectly() throws {
        let calendar = Calendar.current
        let (model, _) = try makeModel(calendar: calendar)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let end = calendar.date(byAdding: .day, value: 3, to: start)!

        model.setPeriodStart(start)
        XCTAssertEqual(model.periodStart, start)
        XCTAssertNil(model.periodEnd, "设置开始后结束仍是空，等待第二个日期")

        model.setPeriodEnd(end)
        XCTAssertEqual(model.periodEnd, end)
        XCTAssertEqual(model.periodRange?.lowerBound, start)
        XCTAssertEqual(model.periodRange?.upperBound, end)
    }

    func testMovingStartPastEndClearsEnd() throws {
        let calendar = Calendar.current
        let (model, _) = try makeModel(calendar: calendar)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let end = calendar.date(byAdding: .day, value: 2, to: start)!

        model.setPeriodStart(start)
        model.setPeriodEnd(end)
        XCTAssertEqual(model.periodEnd, end)

        // 开始挪到结束之后 → 旧结束不再合法，清空等待重选。
        let later = calendar.date(byAdding: .day, value: 5, to: start)!
        model.setPeriodStart(later)
        XCTAssertEqual(model.periodStart, later)
        XCTAssertNil(model.periodEnd)
    }

    func testAllDayToggleDrivesHasTime() throws {
        let (model, _) = try makeModel()
        XCTAssertFalse(model.hasTime, "时间段默认全天（没有具体时刻）")

        model.setHasTime(true)
        XCTAssertTrue(model.hasTime)

        model.setHasTime(false)
        XCTAssertFalse(model.hasTime)
    }

    func testChangingPeriodDatesPreservesTimesAndReminderAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day,
                                               hour: hour, minute: minute))!
        }
        let (model, task) = try makeModel(calendar: calendar)
        model.setPeriodStart(date(19))
        model.setPeriodEnd(date(21))
        model.setHasTime(true)
        model.setStartTime(date(19, 9, 17))
        model.setEndTime(date(21, 11, 43))
        model.setReminderOffsets([-30])

        model.setPeriodStart(date(20))
        model.setPeriodEnd(date(22))

        let plan = model.commitPlan(for: task)
        XCTAssertEqual(plan.schedule.dueAt, date(20, 9, 17))
        XCTAssertEqual(plan.schedule.dueEndAt, date(22, 11, 43))
        XCTAssertEqual(plan.reminder, date(20, 8, 47))
        XCTAssertTrue(model.canCommit)
    }

    func testSwitchingTabsKeepsLatestStartTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day,
                                               hour: hour, minute: minute))!
        }
        let (model, task) = try makeModel(calendar: calendar)
        model.setPeriodStart(date(19, 0, 0))
        model.setHasTime(true)
        model.setStartTime(date(19, 9, 17))

        model.setTab(.date)
        XCTAssertEqual(model.commitPlan(for: task).schedule.dueAt, date(19, 9, 17))
        model.setStartTime(date(19, 10, 43))
        model.setTab(.period)
        XCTAssertEqual(model.commitPlan(for: task).schedule.dueAt, date(19, 10, 43))
    }
}
