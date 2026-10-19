import Foundation

/// Timeline rows are actual matches, including children whose parent only
/// appears as context in a tree list. Unscheduled matches use the same scope.
enum TaskTimelineProjection {
    static func tasks(in scope: TaskListScope, source: [Task], now: Date, calendar: Calendar,
                      query: TaskListQuery = TaskListQuery(), archivedLists: Set<String> = [],
                      filter: SavedFilter? = nil, hidesCompleted: Bool = false,
                      sortMode: TaskListSortMode = .manual, descending: Bool = false) -> [Task] {
        let matched = TaskListProjection.matches(in: scope, tasks: source, now: now, calendar: calendar,
            query: query, archivedLists: archivedLists).filter { task in
                (!hidesCompleted || !task.isClosed)
                    && (filter.map { FilterEvaluator.matches(task, filter: $0, now: now, calendar: calendar) } ?? true)
            }
        return TaskListGroup(kind: .plain, day: nil, tasks: matched)
            .orderedTasks(using: sortMode, descending: descending, calendar: calendar)
    }
}
