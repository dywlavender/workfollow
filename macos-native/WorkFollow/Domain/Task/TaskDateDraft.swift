import Foundation

enum TaskDateDraft {
    static func movingDay(_ date: Date, to day: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    static func applying(date: Date?, hasTime: Bool, deadline: Bool,
                         to current: TaskSchedule, calendar: Calendar) -> TaskSchedule {
        var result = current
        if deadline {
            result.deadlineAt = date.map { calendar.startOfDay(for: $0) }
        } else {
            result.dueAt = date.map { hasTime ? $0 : calendar.startOfDay(for: $0) }
            result.hasTime = date != nil && hasTime
        }
        return result
    }
}
