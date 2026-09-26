import Foundation

/// Published mainland-China holiday schedules, kept separate from recurrence.
/// Ported from Flutter's ChineseWorkCalendar: State Council notices for 2025
/// and 2026. Years without an official table fall back to the ordinary
/// Monday–Friday calendar and the UI discloses that degradation.
enum ChineseWorkCalendar {
    private struct DayKey: Hashable {
        let year: Int, month: Int, day: Int
    }

    static func hasYear(_ year: Int) -> Bool { year == 2025 || year == 2026 }

    /// Holiday periods as (start year, start month, start day, length in days).
    private static let holidayPeriods: [(year: Int, month: Int, day: Int, length: Int)] = [
        (2025, 1, 1, 1), (2025, 1, 28, 8), (2025, 4, 4, 3), (2025, 5, 1, 5),
        (2025, 5, 31, 3), (2025, 10, 1, 8),
        (2026, 1, 1, 3), (2026, 2, 15, 9), (2026, 4, 4, 3), (2026, 5, 1, 5),
        (2026, 6, 19, 3), (2026, 9, 25, 3), (2026, 10, 1, 7),
    ]

    /// Makeup working days (调休上班, ordinary weekends that become workdays).
    private static let makeupWorkdays: [DayKey] = [
        DayKey(year: 2025, month: 1, day: 26), DayKey(year: 2025, month: 2, day: 8),
        DayKey(year: 2025, month: 4, day: 27), DayKey(year: 2025, month: 9, day: 28),
        DayKey(year: 2025, month: 10, day: 11),
        DayKey(year: 2026, month: 1, day: 4), DayKey(year: 2026, month: 2, day: 14),
        DayKey(year: 2026, month: 2, day: 28), DayKey(year: 2026, month: 5, day: 9),
        DayKey(year: 2026, month: 9, day: 20), DayKey(year: 2026, month: 10, day: 10),
    ]

    private static func key(_ date: Date, calendar: Calendar) -> DayKey {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// The published adjustment for the day, if any: `true` = makeup workday
    /// (班), `false` = official rest day inside a holiday period (休).
    static func `override`(for date: Date, calendar: Calendar = .current) -> Bool? {
        let day = key(date, calendar: calendar)
        if makeupWorkdays.contains(day) { return true }
        for period in holidayPeriods where period.year == day.year {
            guard let start = calendar.date(from: DateComponents(year: period.year, month: period.month, day: period.day)),
                  let end = calendar.date(byAdding: .day, value: period.length, to: start),
                  date >= start, date < end else { continue }
            return false
        }
        return nil
    }

    /// Years without an official table use the ordinary Monday–Friday calendar.
    static func isWorkday(date: Date, calendar: Calendar = .current) -> Bool {
        if let adjusted = override(for: date, calendar: calendar) { return adjusted }
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    /// 法定休息日: the inverse of `isWorkday` — rest days inside holiday
    /// periods plus ordinary weekends, minus makeup working weekends.
    static func isHoliday(date: Date, calendar: Calendar = .current) -> Bool {
        !isWorkday(date: date, calendar: calendar)
    }

    private static let fixedFestivals = [
        "1-1": "元旦", "5-1": "劳动节", "9-10": "教师节", "10-1": "国庆节",
    ]

    /// Statutory festival names that move with the lunar calendar are anchored
    /// to their published year (source of the holiday table above).
    private static let annualFestivals: [Int: [String: String]] = [
        2025: ["1-28": "除夕", "1-29": "春节", "4-4": "清明节", "5-31": "端午节", "10-6": "中秋节"],
        2026: ["2-16": "除夕", "2-17": "春节", "4-5": "清明节", "6-19": "端午节", "9-25": "中秋节"],
    ]

    static func festivalName(date: Date, calendar: Calendar = .current) -> String? {
        let day = key(date, calendar: calendar)
        let key = "\(day.month)-\(day.day)"
        return annualFestivals[day.year]?[key] ?? fixedFestivals[key]
    }
}
