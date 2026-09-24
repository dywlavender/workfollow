import Foundation

/// Optional alongside the original frequency, so existing preview JSON remains readable.
struct RecurrenceRule: Equatable, Codable {
    var interval: Int = 1
    var endDate: Date?
    /// Includes the current occurrence, matching Flutter's count contract.
    var remainingCount: Int?
    var monthDay: Int?
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
            if let first = calendar.date(from: parts),
               let month = calendar.date(byAdding: task.recurrence.component, value: interval, to: first),
               let days = calendar.range(of: .day, in: .month, for: month) {
                next = calendar.date(byAdding: .day, value: min(max(1, target), days.count) - 1, to: month)
            }
        } else {
            next = calendar.date(byAdding: task.recurrence.component, value: interval, to: base)
        }
        if let next, let end = rule.endDate,
           calendar.startOfDay(for: next) > calendar.startOfDay(for: end) { return nil }
        return next
    }
}
