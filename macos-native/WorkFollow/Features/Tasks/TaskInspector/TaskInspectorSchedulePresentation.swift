import Foundation

/// Shared due-state and delay rules; the inspector retains its full date labels.
enum TaskInspectorSchedulePresentation {
    enum Tone: Equatable { case empty, scheduled, overdue }

    static func tone(date: Date?, hasTime: Bool, now: Date, calendar: Calendar) -> Tone {
        guard let date else { return .empty }
        let overdue = hasTime ? date < now
            : calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
        return overdue ? .overdue : .scheduled
    }

    static func tone(schedule: TaskSchedule, now: Date, calendar: Calendar) -> Tone {
        guard schedule.dueAt != nil else { return .empty }
        return ScheduleOverdue.isOverdue(schedule: schedule, now: now, calendar: calendar)
            ? .overdue : .scheduled
    }

    static func overdueDescription(schedule: TaskSchedule, isClosed: Bool = false,
                                   now: Date, calendar: Calendar) -> String? {
        ScheduleOverdue.delayText(schedule: schedule, isClosed: isClosed, now: now, calendar: calendar)
    }

    static func label(date: Date?, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        guard let date else { return "设置日期" }
        // 文案实现只有一处：`ScheduleDisplay.dateText(..., style: .full)`。
        // 这里只保留"未设置"的空态文案（视图口径）。
        return ScheduleDisplay.dateText(date, hasTime: hasTime, now: now,
                                        calendar: calendar, style: .full)
    }

    static func label(schedule: TaskSchedule, now: Date, calendar: Calendar,
                      isClosed: Bool = false) -> String {
        let overdue = !isClosed && tone(schedule: schedule, now: now, calendar: calendar) == .overdue
        func dateLabel(_ date: Date?) -> String {
            guard overdue, let date else {
                return label(date: date, hasTime: schedule.hasTime, now: now, calendar: calendar)
            }
            let day = ScheduleDisplay.absoluteDateText(date, now: now, calendar: calendar)
            return schedule.hasTime ? day + ", " + ScheduleDisplay.clockText(date, calendar: calendar) : day
        }
        var title = dateLabel(schedule.dueAt)
        if let date = schedule.dueAt, let end = schedule.dueEndAt {
            if calendar.isDate(date, inSameDayAs: end) {
                if schedule.hasTime { title += " - " + ScheduleDisplay.clockText(end, calendar: calendar) }
            } else {
                title += " - " + dateLabel(end)
            }
        }
        guard let delay = overdueDescription(schedule: schedule, isClosed: isClosed, now: now, calendar: calendar) else { return title }
        return title + ", " + delay
    }
}
