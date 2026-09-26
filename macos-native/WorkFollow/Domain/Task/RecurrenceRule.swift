import Foundation

/// Optional alongside the original frequency, so existing preview JSON remains readable.
struct RecurrenceRule: Equatable, Codable {
    var interval: Int = 1
    var endDate: Date?
    /// Includes the current occurrence, matching Flutter's count contract.
    var remainingCount: Int?
    var monthDay: Int?
    var weekday: Int?
    var month: Int?
}

enum RecurrenceEngine {
    static func next(for task: Task, now: Date, calendar: Calendar) -> Date? {
        guard task.recurrence != .never else { return nil }
        let rule = task.recurrenceRule ?? RecurrenceRule()
        guard rule.remainingCount.map({ $0 > 1 }) ?? true else { return nil }
        let base = task.schedule.dueAt ?? calendar.startOfDay(for: now)
        let interval = max(1, rule.interval)
        var next: Date?
        if task.recurrence == .monthly || task.recurrence == .yearly {
            // Advance from the first day, then clamp the original target day.
            // Jan 31 → Feb 28 → Mar 31, not Mar 28.
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base)
            let target = rule.monthDay ?? parts.day ?? 1
            parts.day = 1
            if task.recurrence == .yearly, let month = rule.month { parts.month = min(12, max(1, month)) }
            if let first = calendar.date(from: parts),
               let month = calendar.date(byAdding: task.recurrence.component, value: interval, to: first),
               let days = calendar.range(of: .day, in: .month, for: month) {
                next = calendar.date(byAdding: .day, value: min(max(1, target), days.count) - 1, to: month)
            }
        } else if task.recurrence == .weekly, let weekday = rule.weekday {
            let current = calendar.component(.weekday, from: base)
            let distance = (weekday - current + 7) % 7
            next = calendar.date(byAdding: .day, value: (distance == 0 ? 7 : distance) + 7 * (interval - 1), to: base)
        } else if [.weekdays, .weekends, .workdays, .holidays].contains(task.recurrence) {
            var candidate = base
            var remaining = interval
            while remaining > 0 {
                guard let day = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = day
                let weekday = calendar.component(.weekday, from: candidate)
                let isWeekday = weekday != 1 && weekday != 7
                let matches: Bool
                switch task.recurrence {
                case .weekdays: matches = isWeekday
                case .weekends: matches = !isWeekday
                case .workdays: matches = NativeWorkCalendar.isWorkday(candidate, calendar: calendar)
                default: matches = !NativeWorkCalendar.isWorkday(candidate, calendar: calendar)
                }
                if matches { remaining -= 1 }
            }
            next = candidate
        } else {
            next = calendar.date(byAdding: task.recurrence.component, value: interval, to: base)
        }
        if let next, let end = rule.endDate,
           calendar.startOfDay(for: next) > calendar.startOfDay(for: end) { return nil }
        return next
    }
}

/// Same bundled 2025/2026 table as Flutter's ChineseWorkCalendar. Outside that
/// table the product falls back to Monday–Friday and discloses this in the UI.
enum NativeWorkCalendar {
    static func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        let working = ["2025-01-26", "2025-02-08", "2025-04-27", "2025-09-28", "2025-10-11", "2026-01-04", "2026-02-14", "2026-02-28", "2026-05-09", "2026-09-20", "2026-10-10"]
        if working.contains(key) { return true }
        let periods = [(2025,1,1,1),(2025,1,28,8),(2025,4,4,3),(2025,5,1,5),(2025,5,31,3),(2025,10,1,8),
                       (2026,1,1,3),(2026,2,15,9),(2026,4,4,3),(2026,5,1,5),(2026,6,19,3),(2026,9,25,3),(2026,10,1,7)]
        for (year, month, day, length) in periods {
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  let end = calendar.date(byAdding: .day, value: length, to: start) else { continue }
            if date >= start && date < end { return false }
        }
        return parts.weekday != 1 && parts.weekday != 7
    }
}
