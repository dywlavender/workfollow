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
        // 文案实现只有一处：`ScheduleDisplay.dateText(..., style: .full)`。
        // 这里只保留"未设置"的空态文案（视图口径）。
        return ScheduleDisplay.dateText(date, hasTime: hasTime, now: now,
                                        calendar: calendar, style: .full)
    }

    static func label(schedule: TaskSchedule, now: Date, calendar: Calendar) -> String {
        let start = label(date: schedule.dueAt, hasTime: schedule.hasTime, now: now, calendar: calendar)
        guard let date = schedule.dueAt, let end = schedule.dueEndAt else { return start }
        if calendar.isDate(date, inSameDayAs: end) {
            guard schedule.hasTime else { return start }
            return start + " - " + ScheduleDisplay.clockText(end, calendar: calendar)
        }
        return start + " - " + label(date: end, hasTime: schedule.hasTime, now: now, calendar: calendar)
    }
}
