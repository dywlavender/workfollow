import Foundation

enum TaskListScope { case today, inbox, allTasks, nextSevenDays, overdue, completed }
enum TaskGroupKind: Equatable { case overdue, today, plain, completed }
struct TaskListGroup {
    let kind: TaskGroupKind
    let day: Date?
    let tasks: [Task]
}

enum TaskListProjection {
    /// Flutter keeps matching completed tasks in Today/Inbox, while their badge counts open tasks.
    static func matches(in scope: TaskListScope, store: WorkspaceStore,
                        now: Date, calendar: Calendar) -> [Task] {
        store.tasks.filter { task in
            guard task.deletedAt == nil else { return false }
            switch scope {
            case .allTasks: return true
            case .nextSevenDays:
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 7, to: start)!
                return [task.schedule.dueAt, task.schedule.deadlineAt].compactMap { $0 }.contains { $0 >= start && $0 < end }
            case .overdue:
                return task.status == .active && [task.schedule.dueAt, task.schedule.deadlineAt].compactMap { $0 }.contains { calendar.startOfDay(for: $0) < calendar.startOfDay(for: now) }
            case .inbox: return task.list == .inbox
            case .completed: return task.status == .completed
            case .today:
                let today = calendar.startOfDay(for: now)
                let due = task.schedule.dueAt.map { calendar.startOfDay(for: $0) <= today } ?? false
                let deadline = task.schedule.deadlineAt.map { $0 <= today } ?? false
                return due || deadline
            }
        }
    }

    static func rows(in scope: TaskListScope, store: WorkspaceStore,
                     now: Date, calendar: Calendar) -> [Task] {
        let tasks = matches(in: scope, store: store, now: now, calendar: calendar)
        let ids = Set(tasks.map(\.id))
        return tasks.filter { $0.parentID.map { !ids.contains($0) } ?? true }
    }

    static func count(in scope: TaskListScope, store: WorkspaceStore,
                      now: Date, calendar: Calendar) -> Int {
        matches(in: scope, store: store, now: now, calendar: calendar)
            .filter { scope == .completed || $0.status == .active }.count
    }

    static func groups(in scope: TaskListScope, store: WorkspaceStore,
                       now: Date, calendar: Calendar) -> [TaskListGroup] {
        let rows = rows(in: scope, store: store, now: now, calendar: calendar)
        let closed = rows.filter { $0.status == .completed }.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
        if scope == .completed {
            let days = Dictionary(grouping: closed) {
                $0.completedAt.map { calendar.startOfDay(for: $0) } ?? .distantPast
            }
            return days.keys.sorted(by: >).map {
                TaskListGroup(kind: .completed, day: $0 == .distantPast ? nil : $0, tasks: days[$0]!)
            }
        }
        let open = rows.filter { $0.status == .active }
        var groups: [TaskListGroup] = []
        if scope == .today {
            let today = calendar.startOfDay(for: now)
            let overdue = open.filter { $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false }
            let overdueIDs = Set(overdue.map(\.id))
            let remaining = open.filter { !overdueIDs.contains($0.id) }
            if !overdue.isEmpty { groups.append(TaskListGroup(kind: .overdue, day: nil, tasks: overdue)) }
            if !remaining.isEmpty { groups.append(TaskListGroup(kind: .today, day: today, tasks: remaining)) }
        } else if !open.isEmpty {
            groups.append(TaskListGroup(kind: .plain, day: nil, tasks: open))
        }
        if !closed.isEmpty { groups.append(TaskListGroup(kind: .completed, day: nil, tasks: closed)) }
        return groups
    }
}
