import Foundation

/// Inspector-only labels. Task list date metadata retains its own grammar.
enum TaskInspectorSchedulePresentation {
    enum Tone: Equatable { case empty, scheduled, overdue }

    static func tone(date: Date?, hasTime: Bool, now: Date, calendar: Calendar) -> Tone {
        guard let date else { return .empty }
        let overdue = hasTime ? date < now
            : calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
        return overdue ? .overdue : .scheduled
    }

    static func label(date: Date?, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        guard let date else { return "设置日期" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? "M月d日" : "yyyy年M月d日"
        var parts: [String] = []
        let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: calendar.startOfDay(for: date)).day
        if distance == 0 { parts.append("今天") }
        else if distance == 1 { parts.append("明天") }
        else if distance == -1 { parts.append("昨天") }
        else if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            let relativeWeek = date < week.start ? -1 : date >= week.end ? 1 : 0
            if let adjacent = calendar.date(byAdding: .weekOfYear, value: relativeWeek, to: now),
               let interval = calendar.dateInterval(of: .weekOfYear, for: adjacent),
               interval.contains(date) {
                let prefix = relativeWeek < 0 ? "上" : relativeWeek > 0 ? "下" : ""
                let weekday = ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
                parts.append("\(prefix)周\(weekday)")
            }
        }
        parts.append(formatter.string(from: date))
        if hasTime {
            formatter.dateFormat = "HH:mm"
            parts.append(formatter.string(from: date))
        }
        return parts.joined(separator: ", ")
    }
}
