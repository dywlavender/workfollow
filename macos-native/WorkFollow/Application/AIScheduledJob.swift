import Foundation

struct AIJobSchedule: Codable, Equatable, Sendable {
    enum Frequency: String, Codable, CaseIterable, Identifiable, Sendable {
        case once, daily, weekdays, weekly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .once: "单次"
            case .daily: "每天"
            case .weekdays: "周一至周五"
            case .weekly: "每周"
            }
        }
    }
    var frequency: Frequency
    var firstRunAt: Date
    var timeZoneID: String

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return value
    }

    func next(after date: Date) -> Date? {
        if frequency == .once { return firstRunAt > date ? firstRunAt : nil }
        return matching(after: max(date, firstRunAt.addingTimeInterval(-1)), direction: .forward)
    }

    func latest(notBefore lowerBound: Date, through date: Date) -> Date? {
        if frequency == .once { return firstRunAt >= lowerBound && firstRunAt <= date ? firstRunAt : nil }
        guard let value = matching(after: date.addingTimeInterval(1), direction: .backward),
              value >= lowerBound, value >= firstRunAt, value <= date else { return nil }
        return value
    }

    private func matching(after date: Date, direction: Calendar.SearchDirection) -> Date? {
        let cal = calendar
        let time = cal.dateComponents([.hour, .minute, .second], from: firstRunAt)
        let days: [Int?]
        switch frequency {
        case .once, .daily: days = [nil]
        case .weekdays: days = (2...6).map(Optional.some)
        case .weekly: days = [cal.component(.weekday, from: firstRunAt)]
        }
        let values = days.compactMap { day -> Date? in
            var components = time; components.weekday = day
            return cal.nextDate(after: date, matching: components, matchingPolicy: .nextTime,
                repeatedTimePolicy: .first, direction: direction)
        }
        return direction == .forward ? values.min() : values.max()
    }

    var summary: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = calendar.timeZone
        formatter.dateFormat = frequency == .once ? "M月d日 HH:mm" : "HH:mm"
        let time = formatter.string(from: firstRunAt)
        let result: String
        if frequency == .weekly {
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            result = "每" + names[calendar.component(.weekday, from: firstRunAt) - 1] + " " + time
        } else { result = frequency == .once ? time : frequency.title + " " + time }
        return timeZoneID == TimeZone.current.identifier ? result : result + "（" + (calendar.timeZone.abbreviation() ?? timeZoneID) + "）"
    }
}

struct AIScheduledRun: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case running, complete, failed, interrupted }
    var id = UUID()
    var scheduledFor: Date
    var startedAt: Date
    var finishedAt: Date?
    var conversationID: UUID
    var state: State = .running
    var error: String?
}

struct AIScheduledJob: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var instruction: String
    var schedule: AIJobSchedule
    var isEnabled: Bool
    var nextRunAt: Date?
    var lastRun: AIScheduledRun?
    var version = 1
}
