import Foundation

enum FocusTaskPickerScope: Equatable {
    case today
    case tomorrow
    case nextSevenDays
    case inbox
    case list(String)

    var title: String {
        switch self {
        case .today: "今天"
        case .tomorrow: "明天"
        case .nextSevenDays: "最近 7 天"
        case .inbox: TaskList.inbox.name
        case let .list(name): name
        }
    }

    var id: String {
        switch self {
        case .today: "today"
        case .tomorrow: "tomorrow"
        case .nextSevenDays: "next-seven-days"
        case .inbox: "inbox"
        case let .list(name): "list:\(name)"
        }
    }
}

struct FocusTaskPickerGroup: Identifiable {
    let id: String
    let title: String?
    let tasks: [Task]
}

/// Picker-only grouping layered on TaskListProjection membership. Today and
/// Recent 7 Days therefore share the same inclusion boundaries as task lists.
enum FocusTaskPickerProjection {
    static func groups(tasks: [Task], scope: FocusTaskPickerScope, query: String,
                       now: Date, calendar: Calendar) -> [FocusTaskPickerGroup] {
        let taskScope: TaskListScope
        let listFilter: String?
        switch scope {
        case .today:
            taskScope = .today
            listFilter = nil
        case .tomorrow:
            taskScope = .allTasks
            listFilter = nil
        case .nextSevenDays:
            taskScope = .nextSevenDays
            listFilter = nil
        case .inbox:
            taskScope = .inbox
            listFilter = nil
        case let .list(name):
            taskScope = .allTasks
            listFilter = name
        }

        let matches = TaskListProjection.matches(
            in: taskScope,
            tasks: tasks,
            now: now,
            calendar: calendar,
            query: TaskListQuery(search: query, list: listFilter)
        ).filter(isPickable)

        let today = calendar.startOfDay(for: now)
        switch scope {
        case .today:
            let overdue = matches.filter {
                $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false
            }
            let overdueIDs = Set(overdue.map(\.id))
            let dueToday = matches.filter { !overdueIDs.contains($0.id) }
            return [
                group("overdue", title: "已过期", tasks: overdue),
                group("today", title: "今天", tasks: dueToday)
            ].filter { !$0.tasks.isEmpty }

        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
            let tasks = matches.filter {
                $0.schedule.dueAt.map { calendar.startOfDay(for: $0) == tomorrow } ?? false
            }
            return [group("tomorrow", title: "明天", tasks: tasks)].filter { !$0.tasks.isEmpty }

        case .nextSevenDays:
            let overdue = matches.filter {
                $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false
            }
            let upcoming = matches.filter {
                $0.schedule.dueAt.map { calendar.startOfDay(for: $0) >= today } ?? false
            }
            let byDay = Dictionary(grouping: upcoming) {
                calendar.startOfDay(for: $0.schedule.dueAt!)
            }
            var result = [group("overdue", title: "已过期", tasks: overdue)]
            result += byDay.keys.sorted().map { day in
                let title = calendar.isDate(day, inSameDayAs: today)
                    ? "今天"
                    : day.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)
                        .locale(.appDate))
                return group("day:\(Int64(day.timeIntervalSince1970))", title: title,
                             tasks: byDay[day] ?? [])
            }
            return result.filter { !$0.tasks.isEmpty }

        case .inbox, .list(_):
            return [group("plain", title: nil, tasks: matches)].filter { !$0.tasks.isEmpty }
        }
    }

    static func displayTitle(for task: Task) -> String {
        task.title.isEmpty ? "未命名任务" : task.title
    }

    static func date(for task: Task) -> Date? {
        task.schedule.dueAt ?? task.schedule.deadlineAt
    }

    private static func isPickable(_ task: Task) -> Bool {
        task.status == .active && task.deletedAt == nil && !task.isAbandoned
            && task.skippedAt == nil && !task.isConverted
    }

    private static func group(_ id: String, title: String?, tasks: [Task]) -> FocusTaskPickerGroup {
        FocusTaskPickerGroup(id: id, title: title, tasks: tasks)
    }
}
