import Foundation

/// 列表行 / 子任务行的日期文案（紧凑风格）。
/// 实现只有一处：`ScheduleDisplay.dateText(_:hasTime:now:calendar:style:)` 的 `.compact`。
enum TaskDateLabel {
    static func text(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar,
                     display: TaskDateDisplayMode = .taskTime) -> String {
        switch display {
        case .taskTime:
            return ScheduleDisplay.dateText(date, hasTime: hasTime, now: now,
                                            calendar: calendar, style: .compact)
        case .countdown:
            return ScheduleDisplay.countdownText(date, hasTime: hasTime, now: now,
                                                 calendar: calendar)
        }
    }
}
