import Foundation

enum NoteDateLabel {
    /// 滴答笔记顶栏日期："今天，10月24日" / "昨天，…" / 本周内"周X，…"。
    static func tickStyle(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        let datePart = "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
        if calendar.isDate(date, inSameDayAs: now) { return "今天，\(datePart)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) { return "昨天，\(datePart)" }
        if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: twoDaysAgo) { return "前天，\(datePart)" }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) {
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return "\(names[calendar.component(.weekday, from: date) - 1])，\(datePart)"
        }
        return datePart
    }
}
