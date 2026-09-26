import Foundation

/// Festival labels for the date grid: solar festivals by Gregorian month/day,
/// lunar festivals (and 除夕) via Calendar(identifier: .chinese). The grid only
/// decorates festival days, so the lookup returns nil for ordinary days.
enum LunarCalendarService {
    private static let solarFestivals = [
        "1-1": "元旦", "2-14": "情人节", "3-8": "妇女节", "3-12": "植树节",
        "4-1": "愚人节", "5-1": "劳动节", "5-4": "青年节", "6-1": "儿童节",
        "7-1": "建党节", "8-1": "建军节", "9-10": "教师节", "10-1": "国庆节",
        "12-25": "圣诞节",
    ]
    private static let lunarFestivals = [
        "1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头", "5-5": "端午节",
        "7-7": "七夕", "7-15": "中元节", "8-15": "中秋节", "9-9": "重阳节",
        "12-8": "腊八节", "12-23": "小年",
    ]

    private static let lock = NSLock()
    private static var cachedChinese: (timeZoneID: String, calendar: Calendar)?

    static func festivalLabel(for date: Date, calendar: Calendar) -> String? {
        solarFestival(date, calendar: calendar) ?? lunarFestival(date, calendar: calendar)
    }

    private static func solarFestival(_ date: Date, calendar: Calendar) -> String? {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return solarFestivals["\(month)-\(day)"]
    }

    private static func lunarFestival(_ date: Date, calendar: Calendar) -> String? {
        let chinese = chineseCalendar(timeZone: calendar.timeZone)
        let components = chinese.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day, components.isLeapMonth != true else { return nil }
        // 除夕 is the last day of the lunar year: the day before 正月初一.
        if month == 12, day >= 29,
           let next = chinese.date(byAdding: .day, value: 1, to: date),
           chinese.dateComponents([.month, .day], from: next).day == 1,
           chinese.dateComponents([.month], from: next).month == 1 {
            return "除夕"
        }
        return lunarFestivals["\(month)-\(day)"]
    }

    /// Opening Calendar(identifier: .chinese) allocates ICU data, so reuse one
    /// per time zone; lunar day boundaries follow the given zone.
    private static func chineseCalendar(timeZone: TimeZone) -> Calendar {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedChinese, cached.timeZoneID == timeZone.identifier { return cached.calendar }
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        cachedChinese = (timeZone.identifier, calendar)
        return calendar
    }
}

/// Fixed 6×7 grid of start-of-day dates covering the displayed month, padded
/// with adjacent-month days. Split from the view so the padding math is testable.
enum MonthGridCalculator {
    struct Cell: Identifiable, Equatable {
        let date: Date
        let inMonth: Bool
        var id: Date { date }
    }

    static let weeks = 6

    static func cells(displayedMonth: Date, calendar: Calendar) -> [Cell] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -leading, to: first) ?? first
        return (0..<weeks * 7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? first
            return Cell(date: calendar.startOfDay(for: date),
                        inMonth: calendar.isDate(date, equalTo: first, toGranularity: .month))
        }
    }
}
