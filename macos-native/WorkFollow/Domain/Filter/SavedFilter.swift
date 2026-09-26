import Foundation

/// Date dimension of a saved filter. The predicates reuse TaskListProjection's
/// existing start-of-day math (with the caller's calendar) instead of a second
/// day-window definition:
/// - `today` matches the `.today` scope predicate (due day <= today, or a
///   deadline no later than today), so 已过期 tasks still show under 今天 views.
/// - `nextSevenDays` matches the `.nextSevenDays` scope predicate
///   (due day < today + 7, includes today and 已过期, excludes the boundary day).
/// - `overdue` / `noDate` match the 所有任务 date buckets (due day < today,
///   respectively dueAt == nil; deadlines alone do not create buckets).
enum SavedFilterDateRange: String, Codable, CaseIterable {
    case any
    case today
    case nextSevenDays
    case noDate
    case overdue

    var title: String {
        switch self {
        case .any: "任意"
        case .today: "今天"
        case .nextSevenDays: "最近 7 天"
        case .noDate: "无日期"
        case .overdue: "已逾期"
        }
    }
}

/// One saved smart filter (Wave 1 F5, aligned with TickTick's 过滤器).
/// Every enabled dimension is AND-combined; empty arrays and `.any` mean the
/// dimension is off and never rejects a task.
struct SavedFilter: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var listNames: [String] = []
    var tags: [String] = []
    var priorities: [TaskPriority] = []
    var dateRange: SavedFilterDateRange = .any
}

/// Pure predicate: does `task` pass every enabled dimension of `filter`?
/// Closed (completed/abandoned) tasks are deliberately not excluded here —
/// matching them follows `TaskListQuery.matches`, which also ignores `isClosed`
/// and lets matching closed tasks stay in the view's 已完成 group.
enum FilterEvaluator {
    static func matches(_ task: Task, filter: SavedFilter,
                        now: Date, calendar: Calendar) -> Bool {
        if !filter.listNames.isEmpty && !filter.listNames.contains(task.list.name) {
            return false
        }
        if !filter.tags.isEmpty && !filter.tags.contains(where: { task.tags.contains($0) }) {
            return false
        }
        if !filter.priorities.isEmpty && !filter.priorities.contains(task.priority) {
            return false
        }
        let today = calendar.startOfDay(for: now)
        switch filter.dateRange {
        case .any:
            return true
        case .today:
            let due = task.schedule.dueAt.map { calendar.startOfDay(for: $0) <= today } ?? false
            let deadline = task.schedule.deadlineAt.map { $0 <= today } ?? false
            return due || deadline
        case .nextSevenDays:
            guard let dueAt = task.schedule.dueAt else { return false }
            let end = calendar.date(byAdding: .day, value: 7, to: today)!
            return calendar.startOfDay(for: dueAt) < end
        case .noDate:
            return task.schedule.dueAt == nil
        case .overdue:
            guard let dueAt = task.schedule.dueAt else { return false }
            return calendar.startOfDay(for: dueAt) < today
        }
    }
}
