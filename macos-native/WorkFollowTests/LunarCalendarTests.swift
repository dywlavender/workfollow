import XCTest
@testable import WorkFollow

final class LunarCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    func testSolarFestivals() {
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(8, 1), calendar: calendar), "建军节")
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(10, 1), calendar: calendar), "国庆节")
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(1, 1), calendar: calendar), "元旦")
    }

    func testLunarFestivalsMatchChineseCalendar() {
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(8, 19), calendar: calendar), "七夕")
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(8, 27), calendar: calendar), "中元节")
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(2, 17), calendar: calendar), "春节")
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(9, 25), calendar: calendar), "中秋节")
    }

    func testEveIsLastDayOfLunarYear() {
        // 2026's 腊月 has only 29 days, so 除夕 falls on 2026-02-16.
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(2, 16), calendar: calendar), "除夕")
    }

    func testOrdinaryDaysHaveNoLabel() {
        XCTAssertNil(LunarCalendarService.festivalLabel(for: date(8, 22), calendar: calendar))
        XCTAssertNil(LunarCalendarService.festivalLabel(for: date(8, 2), calendar: calendar))
    }

    func testSolarFestivalWinsOverLunarLabel() {
        // 2026-08-01 is both 建军节 (solar) and lunar 六月十九.
        XCTAssertEqual(LunarCalendarService.festivalLabel(for: date(8, 1), calendar: calendar), "建军节")
    }

    func testGridPadsAdjacentMonthsAndStartsOnFirstWeekday() {
        var calendar = self.calendar
        calendar.firstWeekday = 1 // Sunday, matching the design's 日一二三四五六 row
        // 2026-08 opens on a Saturday, so the grid starts on Sunday 7-26.
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let cells = MonthGridCalculator.cells(displayedMonth: august, calendar: calendar)

        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(calendar.component(.day, from: cells[0].date), 26)
        XCTAssertEqual(calendar.component(.month, from: cells[0].date), 7)
        XCTAssertFalse(cells[0].inMonth)
        XCTAssertTrue(cells[6].inMonth) // 8-1
        XCTAssertTrue(cells[36].inMonth) // 8-31
        XCTAssertFalse(cells[37].inMonth) // 9-1
        XCTAssertTrue(calendar.isDate(cells[0].date, inSameDayAs: calendar.date(from: DateComponents(year: 2026, month: 7, day: 26))!))
    }
}
