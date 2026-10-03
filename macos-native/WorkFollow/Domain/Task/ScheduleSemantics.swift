import Foundation

/// 日程的领域语义 —— **只此一份**。
///
/// 这些规则此前散在三个层里，靠注释声明"两边一致"：
/// - `TaskDateDraftModel.allDayAnchorHour`（表现层草稿）
/// - `ReminderSchedule.allDayAnchorHour`（通知排期）
/// - `TaskActions.makeNextOccurrence` 里局部的日平移闭包
///
/// 只要有一处改动不同步，就会出现"面板按 09:00 显示、通知在别的时间响"这类漂移。
/// 现在锚点、区间校验、日归一、重复平移都走这里，UI 预览 / 提交 / 通知排期 / 重复生成
/// 共用同一实现。
enum ScheduleSemantics {

    /// 全天任务的锚点小时（09:00）：面板预设、提醒偏移、通知排期共用。
    static let allDayAnchorHour = 9

    /// 某一天的 09:00（全天任务的锚点时刻）。
    static func allDayAnchor(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: allDayAnchorHour, minute: 0, second: 0,
                      of: calendar.startOfDay(for: day))
    }

    /// 偏移锚点：定时任务取到期时刻本身；全天任务取当天 09:00；无日期则无锚点。
    static func anchor(due: Date?, hasTime: Bool, calendar: Calendar) -> Date? {
        guard let due else { return nil }
        return hasTime ? due : allDayAnchor(on: due, calendar: calendar)
    }

    /// 无时间的日程落在当天 0 点；有时间的原样保留；空值仍是空值。
    static func normalized(_ date: Date?, hasTime: Bool, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        return hasTime ? date : calendar.startOfDay(for: date)
    }

    /// 区间校验：结束**严格早于**开始才非法。
    /// 判据照抄 Flutter `apply()` 的 `to.isBefore(from)`——相等合法（09:00 → 09:00 可提交），
    /// 不要自行改成 `<=`。
    static func rangeError(start: Date?, end: Date?) -> String? {
        guard let start, let end else { return nil }
        return end < start ? "结束时间不能早于开始时间" : nil
    }

    /// 重复生成时的整体平移：按天数平移、保留时刻。
    /// `due` / `dueEnd` / `deadline` / `reminder` 必须用同一条平移，
    /// 否则新实例的截止与提醒会各自落在不同天。
    static func shifted(_ date: Date?, byDays days: Int, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        return calendar.date(byAdding: .day, value: days, to: date)
    }
}
