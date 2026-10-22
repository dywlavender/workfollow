import Foundation

/// Half-open calendar range. Weekly keys retain their existing archive identity.
struct SummaryDateRange: Codable, Equatable {
    enum Kind: String, Codable { case day, week, month, custom }
    enum Preset: String, CaseIterable {
        case today = "今天", tomorrow = "明天", yesterday = "昨天"
        case thisWeek = "本周", nextWeek = "下周", lastWeek = "上周"
        case thisMonth = "本月", lastMonth = "上月"
    }
    let start: Date
    let end: Date
    let kind: Kind

    static func week(containing date: Date, calendar: Calendar) -> Self {
        let start = SummaryReviewBuilder.weekStart(of: date, calendar: calendar)
        return Self(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!, kind: .week)
    }

    static func preset(_ preset: Preset, now: Date, calendar: Calendar) -> Self {
        let today = calendar.startOfDay(for: now)
        switch preset {
        case .today, .tomorrow, .yesterday:
            let offset = preset == .tomorrow ? 1 : preset == .yesterday ? -1 : 0
            let start = calendar.date(byAdding: .day, value: offset, to: today)!
            return Self(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!, kind: .day)
        case .thisWeek, .nextWeek, .lastWeek:
            let offset = preset == .nextWeek ? 7 : preset == .lastWeek ? -7 : 0
            return week(containing: calendar.date(byAdding: .day, value: offset, to: today)!, calendar: calendar)
        case .thisMonth, .lastMonth:
            let anchor = calendar.date(byAdding: .month, value: preset == .lastMonth ? -1 : 0, to: today)!
            let start = calendar.dateInterval(of: .month, for: anchor)!.start
            return Self(start: start, end: calendar.date(byAdding: .month, value: 1, to: start)!, kind: .month)
        }
    }

    static func custom(start: Date, through lastDay: Date, calendar: Calendar) -> Self? {
        let start = calendar.startOfDay(for: start), last = calendar.startOfDay(for: lastDay)
        guard start <= last else { return nil }
        return Self(start: start, end: calendar.date(byAdding: .day, value: 1, to: last)!, kind: .custom)
    }

    func contains(_ date: Date) -> Bool { start <= date && date < end }
    func lastDay(calendar: Calendar) -> Date { calendar.date(byAdding: .day, value: -1, to: end)! }
    func storageKey(calendar: Calendar) -> String {
        let first = SummaryStore.dayKey(start, calendar: calendar)
        if kind == .week { return first }
        return kind.rawValue + ":" + first + ":" + SummaryStore.dayKey(lastDay(calendar: calendar), calendar: calendar)
    }
    func title(calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let first = formatter.string(from: start)
        return kind == .day ? first : first + "-" + formatter.string(from: lastDay(calendar: calendar))
    }
    func next(calendar: Calendar) -> Self {
        if kind == .month {
            return Self(start: end, end: calendar.date(byAdding: .month, value: 1, to: end)!, kind: .month)
        }
        let days = calendar.dateComponents([.day], from: start, to: end).day!
        return Self(start: end, end: calendar.date(byAdding: .day, value: days, to: end)!, kind: kind)
    }
}
