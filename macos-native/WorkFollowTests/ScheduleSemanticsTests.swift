import XCTest
@testable import WorkFollow

/// 日程领域语义（`ScheduleSemantics`）的回归。
///
/// 这组规则以前在三个层各写一份（草稿模型、通知排期、重复生成），只能靠注释维持一致。
/// 用例分两部分：① 语义本身；② **各层共用同一实现**——后者是防止再次漂移的关键。
final class ScheduleSemanticsTests: XCTestCase {

    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }()

    private func makeDate(_ year: Int, _ month: Int, _ day: Int,
                          _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private func makeTask(dueAt: Date?, hasTime: Bool, offsets: [Int]? = nil) -> Task {
        let stamp = Date(timeIntervalSince1970: 0)
        var task = Task(id: UUID(), title: "全天任务", list: .inbox, priority: .none,
                        schedule: TaskSchedule(dueAt: dueAt, dueEndAt: nil,
                                               deadlineAt: nil),
                        status: .active, parentID: nil, childOrder: 0,
                        createdAt: stamp, updatedAt: stamp)
        task.schedule.hasTime = hasTime
        task.reminderOffsets = offsets
        return task
    }

    // MARK: - 锚点

    func testAllDayAnchorIsNineOnThatDay() throws {
        let anchor = try XCTUnwrap(ScheduleSemantics.allDayAnchor(on: makeDate(2026, 10, 3, 23, 30),
                                                                 calendar: calendar))
        XCTAssertEqual(anchor, makeDate(2026, 10, 3, 9, 0), "全天锚点是当天 09:00")
    }

    func testAnchorKeepsClockForTimedAndAnchorsAllDay() {
        let timed = makeDate(2026, 10, 3, 7, 45)
        XCTAssertEqual(ScheduleSemantics.anchor(due: timed, hasTime: true, calendar: calendar), timed)
        XCTAssertEqual(ScheduleSemantics.anchor(due: timed, hasTime: false, calendar: calendar),
                       makeDate(2026, 10, 3, 9, 0))
        XCTAssertNil(ScheduleSemantics.anchor(due: nil, hasTime: false, calendar: calendar))
    }

    func testNormalizedFloorsToDayWhenNoTime() {
        let value = makeDate(2026, 10, 3, 21, 30)
        XCTAssertEqual(ScheduleSemantics.normalized(value, hasTime: true, calendar: calendar), value)
        XCTAssertEqual(ScheduleSemantics.normalized(value, hasTime: false, calendar: calendar),
                       makeDate(2026, 10, 3))
        XCTAssertNil(ScheduleSemantics.normalized(nil, hasTime: true, calendar: calendar))
    }

    // MARK: - 区间校验

    func testRangeErrorOnlyWhenEndIsStrictlyBeforeStart() {
        let start = makeDate(2026, 10, 3, 9, 0)
        XCTAssertNil(ScheduleSemantics.rangeError(start: start, end: makeDate(2026, 10, 3, 9, 0)),
                     "相等合法，照 Flutter 的 to.isBefore(from)")
        XCTAssertNil(ScheduleSemantics.rangeError(start: start, end: makeDate(2026, 10, 3, 10, 0)))
        XCTAssertNotNil(ScheduleSemantics.rangeError(start: start, end: makeDate(2026, 10, 3, 8, 59)))
        XCTAssertNil(ScheduleSemantics.rangeError(start: nil, end: makeDate(2026, 10, 3)))
    }

    // MARK: - 平移

    func testShiftedKeepsClockAcrossDays() throws {
        let due = makeDate(2026, 10, 3, 21, 30)
        let moved = try XCTUnwrap(ScheduleSemantics.shifted(due, byDays: 7, calendar: calendar))
        XCTAssertEqual(moved, makeDate(2026, 10, 10, 21, 30), "平移保留时刻")
        XCTAssertNil(ScheduleSemantics.shifted(nil, byDays: 3, calendar: calendar))
    }

    // MARK: - 各层共用同一实现（防漂移）

    func testReminderServiceAnchorsAllDayTasksAtNineLikeThePanel() throws {
        let task = makeTask(dueAt: makeDate(2026, 10, 3, 15, 0), hasTime: false)
        let service = try XCTUnwrap(ReminderSchedule.reminderBase(for: task, calendar: calendar))
        XCTAssertEqual(service, makeDate(2026, 10, 3, 9, 0))
        XCTAssertEqual(service,
                       ScheduleSemantics.anchor(due: task.schedule.dueAt,
                                                hasTime: task.schedule.hasTime,
                                                calendar: calendar),
                       "通知排期的锚点必须与领域（面板预览/提交）同一实现")
    }

    func testAllDayOffsetsFireRelativeToNine() {
        let task = makeTask(dueAt: makeDate(2026, 10, 3, 15, 0), hasTime: false,
                            offsets: [-30, 0])
        XCTAssertEqual(ReminderSchedule.fireDates(for: task, calendar: calendar),
                       [makeDate(2026, 10, 3, 8, 30), makeDate(2026, 10, 3, 9, 0)],
                       "提前 30 分钟 = 09:00 前半小时；准时 = 09:00")
    }

    func testTimedTaskOffsetsFireRelativeToItsOwnClock() {
        let task = makeTask(dueAt: makeDate(2026, 10, 3, 20, 0), hasTime: true,
                            offsets: [-5])
        XCTAssertEqual(ReminderSchedule.fireDates(for: task, calendar: calendar),
                       [makeDate(2026, 10, 3, 19, 55)])
    }
}
