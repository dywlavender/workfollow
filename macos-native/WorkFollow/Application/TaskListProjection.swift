import Foundation

enum TaskListScope { case today, inbox, allTasks, nextSevenDays, completed }
enum TaskGroupKind: Equatable { case pinned, overdue, today, day, upcoming, later, undated, plain, completed }
enum TaskListSortMode: String, CaseIterable {
    case manual, due, priority

    var title: String {
        switch self {
        case .manual: "手动排序"
        case .due: "按日期排序"
        case .priority: "按优先级排序"
        }
    }
}
struct TaskListQuery: Equatable {
    var search = ""
    var list: String?
    var tag: String?
    var isFiltering: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || list != nil || tag != nil }
    func matches(_ task: Task) -> Bool {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (list == nil || task.list.name == list) &&
            (tag == nil || task.tags.contains(tag!)) &&
            (text.isEmpty || (task.title + "\n" + task.document.plainText).localizedCaseInsensitiveContains(text))
    }
}
struct TaskListGroup {
    let kind: TaskGroupKind
    let day: Date?
    let tasks: [Task]
    let label: String?

    /// Stable across sorting and heading changes so a folded group does not
    /// accidentally transfer to another group or reopen after its label shifts.
    var id: String {
        switch kind {
        case .pinned: "pinned"
        case .overdue: "overdue"
        case .today: "today"
        case .upcoming: "upcoming"
        case .later: "later"
        case .undated: "undated"
        case .plain: "plain"
        case .day:
            if let day { Self.dayGroupID(day) }
            else { "day-undated" }
        case .completed:
            if let day { Self.closedDayGroupID(day) }
            else if label == "无日期" { "closed-undated" }
            else { "closed" }
        }
    }

    static func dayGroupID(_ day: Date) -> String {
        "day:\(Int64(day.timeIntervalSince1970))"
    }

    static func closedDayGroupID(_ day: Date) -> String {
        "closed:\(Int64(day.timeIntervalSince1970))"
    }

    init(kind: TaskGroupKind, day: Date?, tasks: [Task], label: String? = nil) {
        self.kind = kind
        self.day = day
        self.tasks = tasks
        self.label = label
    }

    func orderedTasks(using mode: TaskListSortMode, calendar: Calendar) -> [Task] {
        guard kind != .completed, mode != .manual else { return tasks }
        return tasks.enumerated().sorted { lhs, rhs in
            if mode == .priority, lhs.element.priority != rhs.element.priority {
                return lhs.element.priority.rawValue > rhs.element.priority.rawValue
            }
            switch (lhs.element.schedule.dueAt, rhs.element.schedule.dueAt) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

/// View-only folding state for task group headings.
struct TaskGroupExpansionState: Equatable {
    private(set) var collapsedIDs: Set<String> = []

    func isCollapsed(_ group: TaskListGroup) -> Bool {
        collapsedIDs.contains(group.id)
    }

    mutating func toggle(_ group: TaskListGroup) {
        if !collapsedIDs.insert(group.id).inserted {
            collapsedIDs.remove(group.id)
        }
    }

    mutating func toggleClosedGroups(in groups: [TaskListGroup]) {
        let ids = groups
            .filter { $0.kind == .completed && !$0.tasks.isEmpty }
            .map(\.id)
        guard !ids.isEmpty else { return }
        if ids.allSatisfy(collapsedIDs.contains) {
            collapsedIDs.subtract(ids)
        } else {
            collapsedIDs.formUnion(ids)
        }
    }

    mutating func reveal(_ task: Task, in scope: TaskListScope, calendar: Calendar) {
        guard task.isClosed else { return }
        if scope == .completed {
            let id = task.closedAt.map {
                TaskListGroup.closedDayGroupID(calendar.startOfDay(for: $0))
            } ?? "closed-undated"
            collapsedIDs.remove(id)
        } else {
            collapsedIDs.remove("closed")
        }
    }
}

enum TaskListProjection {
    /// Flutter keeps matching completed tasks in Today/Inbox, while their badge counts open tasks.
    static func matches(in scope: TaskListScope, store: WorkspaceStore,
                        now: Date, calendar: Calendar, query: TaskListQuery = TaskListQuery()) -> [Task] {
        store.tasks.filter { task in
            guard task.deletedAt == nil && task.skippedAt == nil && !task.isConverted else { return false }
            guard query.matches(task) else { return false }
            switch scope {
            case .allTasks: return true
            case .nextSevenDays:
                let start = calendar.startOfDay(for: now)
                let end = calendar.date(byAdding: .day, value: 7, to: start)!
                return task.schedule.dueAt.map { calendar.startOfDay(for: $0) < end } ?? false
            case .inbox: return task.list == .inbox
            case .completed: return task.isClosed
            case .today:
                guard !task.isAbandoned else { return false }
                let today = calendar.startOfDay(for: now)
                let due = task.schedule.dueAt.map { calendar.startOfDay(for: $0) <= today } ?? false
                let deadline = task.schedule.deadlineAt.map { $0 <= today } ?? false
                return due || deadline
            }
        }
    }

    static func rows(in scope: TaskListScope, store: WorkspaceStore,
                     now: Date, calendar: Calendar, query: TaskListQuery = TaskListQuery()) -> [Task] {
        let tasks = matches(in: scope, store: store, now: now, calendar: calendar, query: query)
        let ids = Set(tasks.map(\.id))
        return tasks.filter { $0.parentID.map { !ids.contains($0) } ?? true }
    }

    static func count(in scope: TaskListScope, store: WorkspaceStore,
                      now: Date, calendar: Calendar) -> Int {
        matches(in: scope, store: store, now: now, calendar: calendar)
            .filter { scope == .completed || !$0.isClosed }.count
    }

    static func groups(in scope: TaskListScope, store: WorkspaceStore,
                       now: Date, calendar: Calendar, query: TaskListQuery = TaskListQuery()) -> [TaskListGroup] {
        let rows = rows(in: scope, store: store, now: now, calendar: calendar, query: query)
        let closed = rows.filter(\.isClosed).sorted {
            ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast)
        }
        if scope == .completed {
            let dated = closed.filter { $0.closedAt != nil }
            let undated = closed.filter { $0.closedAt == nil }
            let days = Dictionary(grouping: dated) {
                calendar.startOfDay(for: $0.closedAt!)
            }
            var groups = days.keys.sorted(by: >).map { day in
                TaskListGroup(kind: .completed, day: day,
                              tasks: days[day]!.sorted { $0.closedAt! > $1.closedAt! })
            }
            if !undated.isEmpty {
                groups.append(TaskListGroup(kind: .completed, day: nil, tasks: undated,
                                            label: "无日期"))
            }
            return groups
        }
        let open = rows.filter { !$0.isClosed }
        let pinned = open.filter(\.isPinned)
        let ordinary = open.filter { !$0.isPinned }
        var groups: [TaskListGroup] = []
        if !pinned.isEmpty {
            groups.append(TaskListGroup(kind: .pinned, day: nil, tasks: pinned))
        }
        if scope == .allTasks {
            if query.list == nil && query.tag == nil {
                groups += allTaskDateGroups(ordinary, now: now, calendar: calendar)
            } else if !ordinary.isEmpty {
                groups.append(TaskListGroup(kind: .plain, day: nil, tasks: ordinary))
            }
        } else if scope == .today {
            let today = calendar.startOfDay(for: now)
            let overdue = ordinary.filter { $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false }
            let overdueIDs = Set(overdue.map(\.id))
            let remaining = ordinary.filter { !overdueIDs.contains($0.id) }
            if !overdue.isEmpty { groups.append(TaskListGroup(kind: .overdue, day: nil, tasks: overdue)) }
            if !remaining.isEmpty { groups.append(TaskListGroup(kind: .today, day: today, tasks: remaining)) }
        } else if scope == .nextSevenDays {
            let today = calendar.startOfDay(for: now)
            let overdue = ordinary.filter { $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false }
            if !overdue.isEmpty { groups.append(TaskListGroup(kind: .overdue, day: nil, tasks: overdue)) }

            let upcoming = ordinary.filter { $0.schedule.dueAt.map { calendar.startOfDay(for: $0) >= today } ?? false }
            let byDay = Dictionary(grouping: upcoming) {
                calendar.startOfDay(for: $0.schedule.dueAt!)
            }
            for day in byDay.keys.sorted() {
                groups.append(TaskListGroup(kind: day == today ? .today : .day,
                                            day: day, tasks: byDay[day]!))
            }
        } else if !ordinary.isEmpty {
            groups.append(TaskListGroup(kind: .plain, day: nil, tasks: ordinary))
        }
        if !closed.isEmpty {
            let hasCompleted = closed.contains { $0.status == .completed }
            let hasAbandoned = closed.contains { $0.isAbandoned }
            let label = hasCompleted && hasAbandoned ? "已完成&已放弃"
                : hasAbandoned ? "已放弃" : "已完成"
            groups.append(TaskListGroup(kind: .completed, day: nil, tasks: closed, label: label))
        }
        return groups
    }

    private static func allTaskDateGroups(_ tasks: [Task], now: Date,
                                          calendar: Calendar) -> [TaskListGroup] {
        let today = calendar.startOfDay(for: now)
        let recentEnd = calendar.date(byAdding: .day, value: 7, to: today)!
        let overdue = tasks.filter {
            $0.schedule.dueAt.map { calendar.startOfDay(for: $0) < today } ?? false
        }
        let onToday = tasks.filter {
            $0.schedule.dueAt.map { calendar.startOfDay(for: $0) == today } ?? false
        }
        let upcoming = tasks.filter {
            guard let dueAt = $0.schedule.dueAt else { return false }
            let day = calendar.startOfDay(for: dueAt)
            return day > today && day < recentEnd
        }
        let later = tasks.filter {
            $0.schedule.dueAt.map { calendar.startOfDay(for: $0) >= recentEnd } ?? false
        }
        let undated = tasks.filter { $0.schedule.dueAt == nil }

        func sortedByDueDay(_ values: [Task]) -> [Task] {
            values.enumerated().sorted { lhs, rhs in
                let lhsDay = calendar.startOfDay(for: lhs.element.schedule.dueAt!)
                let rhsDay = calendar.startOfDay(for: rhs.element.schedule.dueAt!)
                return lhsDay == rhsDay ? lhs.offset < rhs.offset : lhsDay < rhsDay
            }.map(\.element)
        }

        var groups: [TaskListGroup] = []
        if !overdue.isEmpty { groups.append(TaskListGroup(kind: .overdue, day: nil, tasks: overdue)) }
        if !onToday.isEmpty { groups.append(TaskListGroup(kind: .today, day: today, tasks: onToday)) }
        if !upcoming.isEmpty {
            groups.append(TaskListGroup(kind: .upcoming, day: nil, tasks: sortedByDueDay(upcoming)))
        }
        if !later.isEmpty {
            groups.append(TaskListGroup(kind: .later, day: nil, tasks: sortedByDueDay(later)))
        }
        if !undated.isEmpty { groups.append(TaskListGroup(kind: .undated, day: nil, tasks: undated)) }
        return groups
    }
}

/// 清单 14 色板（照搬 Flutter list_color.dart 的 ARGB 值），加清单色的
/// 稳定推导与侧栏排序两条纯规则，保持可单测、不依赖 SwiftUI。
enum WFListPalette {
    static let argb: [UInt32] = [
        0xFFE35D6A, // red
        0xFFE8793F, // orange
        0xFFD7A62B, // yellow
        0xFF9AA63A, // olive
        0xFF42A66A, // green
        0xFF38A89D, // mint
        0xFF2F9FB5, // cyan
        0xFF4285D4, // blue
        0xFF5865C8, // indigo
        0xFF8056C7, // purple
        0xFFC04D9A, // magenta
        0xFF9A756A, // warm grey
        0xFF66758A, // slate
        0xFF8A909B, // grey
    ]

    /// 清单最终落在色板上的下标：显式 meta 优先（越界回退），未选色时按清单名
    /// 做稳定字符折叠（Flutter listColorValueForName 同款），等名永远同色。
    static func colorIndex(for name: String, explicit: Int?) -> Int {
        if let explicit, explicit >= 0, explicit < argb.count { return explicit }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let score = name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) & 0x7FFF_FFFF }
        return score % argb.count
    }
}

/// 侧栏清单显示顺序（对齐 Flutter WorkspaceController.orderedLists）：
/// 置顶在前，其余按 meta sortOrder，再按名字；无 meta 的清单排在有 meta
/// 之后、按字典序。纯函数，便于对排序语义做单测。
enum TaskListOrdering {
    static func ordered(_ names: [String], metas: [TaskListMeta]) -> [String] {
        let byName = Dictionary(metas.map { ($0.name, $0) },
                                uniquingKeysWith: { current, _ in current })
        return names.sorted { lhs, rhs in
            let left = byName[lhs], right = byName[rhs]
            if (left?.isPinned ?? false) != (right?.isPinned ?? false) {
                return left?.isPinned ?? false
            }
            let leftOrder = left?.sortOrder ?? Int.max
            let rightOrder = right?.sortOrder ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.localizedCompare(rhs) == .orderedAscending
        }
    }
}
