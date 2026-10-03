import Foundation

/// 列表行 / 子任务行的日期文案（紧凑风格）。
/// 实现只有一处：`ScheduleDisplay.dateText(_:hasTime:now:calendar:style:)` 的 `.compact`。
enum TaskDateLabel {
    static func text(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        ScheduleDisplay.dateText(date, hasTime: hasTime, now: now, calendar: calendar, style: .compact)
    }
}
