import Foundation

/// Planning a week does not require inventing a due date. The history travels
/// with the task, so persistence, undo and cross-week moves retain one identity.
struct TaskWeeklyPlanning: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let weekKey: String
        let enteredAt: Date
        let title: String
        let listName: String
        let schedule: TaskSchedule
        var movedToWeek: String?
        var movedAt: Date?
    }

    var currentWeek: String?
    var history: [Entry] = []

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: SummaryReviewBuilder.weekStart(of: date, calendar: calendar))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    mutating func enter(_ week: String, task: Task, at date: Date) {
        if let currentWeek, currentWeek != week,
           let index = history.firstIndex(where: { $0.weekKey == currentWeek }) {
            history[index].movedToWeek = week
            history[index].movedAt = date
        }
        if let index = history.firstIndex(where: { $0.weekKey == week }) {
            history[index].movedToWeek = nil
            history[index].movedAt = nil
        } else {
            history.append(Entry(weekKey: week, enteredAt: date, title: task.title,
                                 listName: task.list.name, schedule: task.schedule))
        }
        currentWeek = week
    }

    /// Called only for domain commits, never while replaying undo/redo or
    /// loading a snapshot. Old dates are captured when first observed, rather
    /// than presenting reconstructed history as an original planning baseline.
    static func recording(before: Task?, after: Task, at date: Date, calendar: Calendar) -> Task {
        var value = after
        if before == nil { value.weeklyPlanning = nil } // Copies/recurrences start their own history.
        var planning = value.weeklyPlanning ?? TaskWeeklyPlanning()
        if let before, planning.history.isEmpty, let due = before.schedule.dueAt {
            planning.enter(key(for: due, calendar: calendar), task: before, at: date)
        }
        let explicitlyChanged = before != nil && before?.weeklyPlanning?.currentWeek != after.weeklyPlanning?.currentWeek
        if explicitlyChanged, let week = after.weeklyPlanning?.currentWeek {
            planning.enter(week, task: after, at: date)
        } else if let due = after.schedule.dueAt,
                  before == nil || before?.schedule != after.schedule || planning.currentWeek == nil {
            planning.enter(key(for: due, calendar: calendar), task: after, at: date)
        }
        if !planning.history.isEmpty { value.weeklyPlanning = planning }
        return value
    }
}

struct WeeklyPlanProjection {
    let weekStart: Date
    let calendar: Calendar
    var weekKey: String { TaskWeeklyPlanning.key(for: weekStart, calendar: calendar) }
    var weekEnd: Date { SummaryReviewBuilder.weekEnd(of: weekStart, calendar: calendar) }

    func includes(_ task: Task) -> Bool {
        guard task.deletedAt == nil, task.skippedAt == nil, !task.isConverted else { return false }
        if task.weeklyPlanning?.currentWeek == weekKey { return true }
        guard let due = task.schedule.dueAt else { return false }
        return due < weekEnd && (task.schedule.dueEndAt ?? due) >= weekStart
    }

    func tasks(from tasks: [Task], listName: String? = nil) -> [Task] {
        let matching = tasks.filter { includes($0) && (listName == nil || $0.list.name == listName) }
        let ids = Set(matching.map(\.id))
        return matching.filter { $0.parentID.map { !ids.contains($0) } ?? true }
            .sorted {
                if $0.isClosed != $1.isClosed { return !$0.isClosed }
                if $0.schedule.dueAt != $1.schedule.dueAt {
                    return ($0.schedule.dueAt ?? .distantFuture) < ($1.schedule.dueAt ?? .distantFuture)
                }
                if $0.priority != $1.priority { return $0.priority.rawValue > $1.priority.rawValue }
                return ($0.childOrder, $0.createdAt) < ($1.childOrder, $1.createdAt)
            }
    }
}
