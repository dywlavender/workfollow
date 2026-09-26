import Foundation

/// Human label for a task date: 今天/明天/昨天 within one day's distance,
/// otherwise "M月d日" (with year when different from now's year), plus "HH:mm"
/// when the task carries a time.
enum TaskDateLabel {
    static func text(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN"); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "M月d日" : "yyyy年M月d日"
        let day = distance == 0 ? "今天" : distance == 1 ? "明天" : distance == -1 ? "昨天" : formatter.string(from: date)
        formatter.dateFormat = "HH:mm"
        return day + (hasTime ? " " + formatter.string(from: date) : "")
    }
}
