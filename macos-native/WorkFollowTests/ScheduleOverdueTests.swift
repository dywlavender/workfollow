import XCTest
@testable import WorkFollow

/// 逾期口径（对齐滴答）：时间段以结束为准，进行中不算逾期；
/// 全天按自然日、带时刻按实际时长，延迟分天/小时/分钟三档。
final class ScheduleOverdueTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }()

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    func testAllDayRangeStaysScheduledThroughItsEndDay() {
        let ongoing = TaskSchedule(dueAt: date(13), hasTime: false, dueEndAt: date(30))
        let beforeEnd = date(29, 10)
        XCTAssertFalse(ScheduleOverdue.isOverdue(schedule: ongoing, now: beforeEnd, calendar: calendar))
        XCTAssertNil(ScheduleOverdue.delayText(schedule: ongoing, now: beforeEnd, calendar: calendar),
                     "进行中的区间不能出「延迟」文案，更不能兜成「不足1天」")
        XCTAssertFalse(ScheduleOverdue.isOverdue(schedule: ongoing, now: date(30, 23, 59),
                                                 calendar: calendar),
                       "结束日当天仍可做")
        XCTAssertTrue(ScheduleOverdue.isOverdue(schedule: ongoing, now: date(31, 0, 1),
                                                calendar: calendar))
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: ongoing, now: date(31, 0, 1),
                                                 calendar: calendar), "延迟1天")
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: ongoing, now: date(33, 12),
                                                 calendar: calendar), "延迟3天")
    }

    func testTimedRangeUsesEndInstantAndSubDayUnits() {
        let range = TaskSchedule(dueAt: date(13, 9), hasTime: true, dueEndAt: date(30, 9))
        XCTAssertFalse(ScheduleOverdue.isOverdue(schedule: range, now: date(30, 8, 59), calendar: calendar),
                       "结束时刻之前仍不算逾期")
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: range, now: date(30, 9, 17), calendar: calendar),
                       "延迟17分钟")
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: range, now: date(30, 14), calendar: calendar),
                       "延迟5小时")
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: range, now: date(31, 10), calendar: calendar),
                       "延迟1天", "满 24 小时才进位到「天」")
    }

    func testSingleDaySchedulesKeepTheirGranularity() {
        let allDay = TaskSchedule(dueAt: date(29))
        XCTAssertFalse(ScheduleOverdue.isOverdue(schedule: allDay, now: date(29, 23), calendar: calendar))
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: allDay, now: date(30, 8), calendar: calendar),
                       "延迟1天")
        let timed = TaskSchedule(dueAt: date(29, 9), hasTime: true)
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: timed, now: date(29, 10), calendar: calendar),
                       "延迟1小时")
        XCTAssertEqual(ScheduleOverdue.delayText(schedule: timed, now: date(29, 9, 5), calendar: calendar),
                       "延迟5分钟")
    }

    func testClosedOrUndatedTasksNeverShowDelay() {
        let ended = TaskSchedule(dueAt: date(20), hasTime: false, dueEndAt: date(25))
        XCTAssertNil(ScheduleOverdue.delayText(schedule: ended, isClosed: true,
                                               now: date(29), calendar: calendar))
        XCTAssertFalse(ScheduleOverdue.isOverdue(schedule: ended, isClosed: true,
                                                 now: date(29), calendar: calendar))
        XCTAssertNil(ScheduleOverdue.delayText(schedule: TaskSchedule(), now: date(29),
                                               calendar: calendar))
    }

    func testFutureEndNeverProducesASubDayFallback() {
        // 旧实现把 days <= 0 一律写成「不足1天」，结束日在未来也会出文案。
        let future = TaskSchedule(dueAt: date(13), hasTime: true, dueEndAt: date(30, 18))
        XCTAssertNil(ScheduleOverdue.delayText(schedule: future, now: date(29, 12), calendar: calendar))
    }
}
