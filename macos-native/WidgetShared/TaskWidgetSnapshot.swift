import Foundation

/// A widget receives task metadata, never document bodies or a writable workspace.
struct TaskWidgetItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var parentID: UUID?
    var title: String
    var listName: String
    var priority: Int
    var dueAt: Date?
    var dueEndAt: Date?
    var deadlineAt: Date?
    var hasTime: Bool
    var completedAt: Date?
    var isCompleted: Bool
    var weekKey: String?
    var updatedAt: Date

    var url: URL { URL(string: "workfollow://task/\(id.uuidString)")! }
    func isOverdue(on day: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        return (dueEndAt ?? dueAt).map { calendar.startOfDay(for: $0) < start } == true
            || deadlineAt.map { calendar.startOfDay(for: $0) < start } == true
    }
}

/// The host resolves countdown rules for each prepared timeline day. The widget
/// only renders these entries; countdowns never become completion commands.
struct TaskWidgetCountdownItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var symbol: String
    var displayDate: Date
    var relativeLabel: String
}

struct TaskWidgetSnapshot: Codable, Equatable, Sendable {
    var version = 1
    var updatedAt: Date
    var tasks: [TaskWidgetItem]
    // Optional so snapshots from the installed task-only widget remain readable.
    var countdowns: [TaskWidgetCountdownItem]? = nil

    static let empty = Self(updatedAt: .distantPast, tasks: [])

    func today(at date: Date, calendar: Calendar = .current) -> TaskWidgetDay {
        let day = calendar.startOfDay(for: date)
        let matching = tasks.filter { task in
            guard !task.isCompleted else { return false }
            return task.dueAt.map { calendar.startOfDay(for: $0) <= day } == true
                || task.deadlineAt.map { calendar.startOfDay(for: $0) <= day } == true
        }
        let ids = Set(matching.map(\.id))
        let remaining = matching.filter { $0.parentID.map { !ids.contains($0) } ?? true }.sorted { a, b in
            let leftOverdue = a.isOverdue(on: day, calendar: calendar), rightOverdue = b.isOverdue(on: day, calendar: calendar)
            if leftOverdue != rightOverdue { return leftOverdue }
            if a.priority != b.priority { return a.priority > b.priority }
            if a.dueAt != b.dueAt { return (a.dueAt ?? .distantFuture) < (b.dueAt ?? .distantFuture) }
            return a.id.uuidString < b.id.uuidString
        }
        let completed = tasks.filter { $0.isCompleted && $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } == true }
        let completedIDs = Set(completed.map(\.id))
        let completedCount = completed.filter { $0.parentID.map { !completedIDs.contains($0) } ?? true }.count
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -offset, to: day)!
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let parts = calendar.dateComponents([.year, .month, .day], from: weekStart)
        let weekKey = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        let weekTasks = tasks.filter { task in
            guard !task.isCompleted else { return false }
            return task.weekKey == weekKey || task.dueAt.map { $0 < weekEnd && (task.dueEndAt ?? $0) >= weekStart } == true
        }
        let weekIDs = Set(weekTasks.map(\.id))
        return TaskWidgetDay(date: day, remaining: remaining, completedCount: completedCount,
            overdueCount: remaining.filter { $0.isOverdue(on: day, calendar: calendar) }.count,
            weekRemainingCount: weekTasks.filter { $0.parentID.map { !weekIDs.contains($0) } ?? true }.count,
            countdowns: (countdowns ?? []).filter { calendar.isDate($0.displayDate, inSameDayAs: day) })
    }
}

struct TaskWidgetDay: Equatable, Sendable {
    let date: Date
    let remaining: [TaskWidgetItem]
    let completedCount: Int
    let overdueCount: Int
    let weekRemainingCount: Int
    let countdowns: [TaskWidgetCountdownItem]

    var entryCount: Int { remaining.count + countdowns.count }
}

enum TaskWidgetLink {
    enum Destination { case today, quickAdd, weekPlan, countdowns }
    static let today = URL(string: "workfollow://widget/today")!
    static let quickAdd = URL(string: "workfollow://widget/add")!
    static let weekPlan = URL(string: "workfollow://widget/week")!
    static let countdowns = URL(string: "workfollow://widget/countdowns")!
    static func destination(for url: URL) -> Destination? {
        guard url.scheme == "workfollow", url.host == "widget", url.query == nil,
              url.fragment == nil else { return nil }
        switch url.path {
        case "/today": return .today
        case "/add": return .quickAdd
        case "/week": return .weekPlan
        case "/countdowns": return .countdowns
        default: return nil
        }
    }
}
