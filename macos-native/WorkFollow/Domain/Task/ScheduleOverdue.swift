import Foundation

/// 逾期判定与延迟文案的唯一口径（对齐滴答）：
/// - 时间段以**结束**（`dueEndAt ?? dueAt`）为准，进行中的区间不算逾期；
/// - 全天任务按自然日比较：结束日当天仍可做，次日才算逾期；
/// - 带时刻的任务按结束时刻比较；
/// - 延迟文案分 天 / 小时 / 分钟 三档，不再用「不足1天」兜底。
enum ScheduleOverdue {
    static func reference(_ schedule: TaskSchedule) -> Date? {
        schedule.dueEndAt ?? schedule.dueAt
    }

    static func isOverdue(schedule: TaskSchedule, isClosed: Bool = false,
                          now: Date, calendar: Calendar) -> Bool {
        guard !isClosed, let date = reference(schedule) else { return false }
        return isOverdue(date: date, hasTime: schedule.hasTime, now: now, calendar: calendar)
    }

    static func isOverdue(date: Date, hasTime: Bool, now: Date, calendar: Calendar) -> Bool {
        hasTime ? date < now : calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    /// 逾期时长（不含前缀）：`3天` / `5小时` / `12分钟`。
    /// 全天按自然日；带时刻按实际经过时长，跨满 24 小时才进位到「天」。
    static func durationText(schedule: TaskSchedule, now: Date, calendar: Calendar) -> String {
        guard let date = reference(schedule) else { return "" }
        return durationText(date: date, hasTime: schedule.hasTime, now: now, calendar: calendar)
    }

    static func durationText(date: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        if !hasTime {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            return "\(max(1, days))天"
        }
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed >= 86_400 { return "\(Int(elapsed / 86_400))天" }
        if elapsed >= 3_600 { return "\(Int(elapsed / 3_600))小时" }
        return "\(max(1, Int(elapsed / 60)))分钟"
    }

    static func delayText(schedule: TaskSchedule, isClosed: Bool = false,
                          now: Date, calendar: Calendar) -> String? {
        guard isOverdue(schedule: schedule, isClosed: isClosed, now: now, calendar: calendar) else { return nil }
        return "延迟" + durationText(schedule: schedule, now: now, calendar: calendar)
    }
}
