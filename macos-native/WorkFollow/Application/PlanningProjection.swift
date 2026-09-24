import Foundation

enum PlanningProjection {
    /// Flutter baseline: medium/high are important; scheduled within three days
    /// (including overdue) is urgent. Deadline does not define matrix urgency.
    static func quadrant(_ task: Task, now: Date, calendar: Calendar = .current) -> Int {
        let important = task.priority == .high || task.priority == .medium
        let horizon = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        let urgent = task.schedule.dueAt.map { calendar.startOfDay(for: $0) <= horizon } ?? false
        return important ? (urgent ? 0 : 1) : (urgent ? 2 : 3)
    }

    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first)!
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func tasks(on day: Date, from tasks: [Task], calendar: Calendar = .current) -> [Task] {
        tasks.filter { task in
            task.deletedAt == nil && task.schedule.dueAt.map { calendar.isDate($0, inSameDayAs: day) } == true
        }.sorted { ($0.schedule.dueAt ?? .distantPast) < ($1.schedule.dueAt ?? .distantPast) }
    }
}
