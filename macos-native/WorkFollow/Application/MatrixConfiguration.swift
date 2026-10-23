import Foundation

enum MatrixPreset: String, CaseIterable, Codable {
    case priority, timeAndPriority, legacyThreeDays, custom
    var title: String { switch self {
    case .priority: "按优先级"; case .timeAndPriority: "时间与优先级";
    case .legacyThreeDays: "旧版三天规则"; case .custom: "自定义规则"
    } }
}
enum MatrixSort: String, CaseIterable, Codable {
    /// `manual` 保留给「拖拽顺序」这一旧口径；菜单里只在需要时出现。
    case date, created, modified, title, tag, priority, manual
    var title: String { switch self {
    case .date: "时间"; case .created: "创建时间"; case .modified: "修改时间"
    case .title: "标题"; case .tag: "标签"; case .priority: "优先级"
    case .manual: "手动"
    } }
}
/// 排序方向（滴答「顺序」一栏）。
enum MatrixOrderDirection: String, CaseIterable, Codable {
    case ascending, descending
    var title: String { self == .ascending ? "从旧到新" : "从新到旧" }
}

enum MatrixGrouping: String, CaseIterable, Codable {
    /// 顺序与滴答的「分组」子菜单一致。
    case list, date, created, tag, priority, none
    var title: String {
        switch self {
        case .list: "清单"
        case .date: "时间"
        case .created: "创建时间"
        case .tag: "标签"
        case .priority: "优先级"
        case .none: "无"
        }
    }
}
enum MatrixDateBasis: String, CaseIterable, Codable {
    case schedule, deadline
    var title: String { self == .schedule ? "安排日期" : "截止日期" }
}
enum MatrixDateKind: String, CaseIterable, Codable {
    case any, unscheduled, todayOrEarlier, nextDays, afterDays, dateRange
    var title: String { switch self {
    case .any: "不限日期"; case .unscheduled: "无日期"; case .todayOrEarlier: "今天及以前";
    case .nextDays: "未来几天内"; case .afterDays: "几天以后或无日期"; case .dateRange: "指定日期范围"
    } }
}
struct MatrixDatePredicate: Equatable, Codable {
    var basis: MatrixDateBasis = .schedule
    var kind: MatrixDateKind = .any
    var days = 3
    var includeOverdue = true
    var rangeStart: Date?
    var rangeEnd: Date?

    func anchor(of task: Task) -> Date? { basis == .schedule ? task.schedule.dueAt : task.schedule.deadlineAt }
    func matches(_ task: Task, now: Date, calendar: Calendar) -> Bool {
        let anchor = anchor(of: task).map { calendar.startOfDay(for: $0) }
        let today = calendar.startOfDay(for: now)
        let high = calendar.date(byAdding: .day, value: max(0, days), to: today)!
        switch kind {
        case .any: return true
        case .unscheduled: return anchor == nil
        case .todayOrEarlier: return anchor.map { $0 <= today } ?? false
        case .nextDays: return anchor.map { $0 <= high && (includeOverdue || $0 >= today) } ?? false
        case .afterDays: return anchor.map { $0 > high } ?? true
        case .dateRange:
            guard let anchor, let rangeStart, let rangeEnd else { return false }
            return anchor >= calendar.startOfDay(for: rangeStart) && anchor <= calendar.startOfDay(for: rangeEnd)
        }
    }
    /// Nearest valid day. nil means that this rule explicitly requests no date.
    func proposedDay(for task: Task, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let current = anchor(of: task).map { calendar.startOfDay(for: $0) } ?? today
        switch kind {
        case .any: return anchor(of: task)
        case .unscheduled: return nil
        case .todayOrEarlier: return min(current, today)
        case .nextDays:
            let high = calendar.date(byAdding: .day, value: max(0, days), to: today)!
            return includeOverdue ? min(current, high) : min(max(current, today), high)
        case .afterDays:
            let first = calendar.date(byAdding: .day, value: max(0, days) + 1, to: today)!
            return max(current, first)
        case .dateRange:
            guard let rangeStart, let rangeEnd, rangeEnd >= rangeStart else { return nil }
            return min(max(current, calendar.startOfDay(for: rangeStart)), calendar.startOfDay(for: rangeEnd))
        }
    }
}
struct MatrixRule: Equatable, Codable {
    var priorities: [TaskPriority] = []
    var listNames: [String] = []
    var tagNames: [String] = []
    var requiresAllTags = false
    var date = MatrixDatePredicate()
    func matches(_ task: Task, now: Date, calendar: Calendar) -> Bool {
        (priorities.isEmpty || priorities.contains(task.priority))
            && (listNames.isEmpty || listNames.contains(task.list.name))
            && (tagNames.isEmpty || (requiresAllTags ? tagNames.allSatisfy(task.tags.contains) : tagNames.contains(where: task.tags.contains)))
            && date.matches(task, now: now, calendar: calendar)
    }
}
struct MatrixQuadrantConfiguration: Equatable, Codable, Identifiable {
    var quadrant: MatrixQuadrant
    var title: String
    var colorIndex: Int
    var rule: MatrixRule
    var sort: MatrixSort = .manual
    var grouping: MatrixGrouping = .list
    /// 排序方向；`.manual` 时反转拖拽顺序。
    var direction: MatrixOrderDirection = .ascending
    var manualOrder: [UUID] = []
    var id: Int { quadrant.rawValue }
}
struct MatrixConfiguration: Equatable, Codable {
    var preset: MatrixPreset
    var quadrants: [MatrixQuadrantConfiguration]
    var displayOrder: [MatrixQuadrant] = MatrixQuadrant.allCases
    /// Classification order is independent of screen position.
    var precedence: [MatrixQuadrant] = MatrixQuadrant.allCases
    var showCompleted = true

    static let legacy = makePreset(.legacyThreeDays)
    static func makePreset(_ preset: MatrixPreset) -> MatrixConfiguration {
        let values = MatrixQuadrant.allCases.map { quadrant in
            var rule = MatrixRule()
            if preset == .priority {
                let priority: TaskPriority = switch quadrant { case .doNow: .high; case .schedule: .medium; case .delegate: .low; case .later: .none }
                rule.priorities = [priority]
            } else {
                let important = quadrant == .doNow || quadrant == .schedule
                let urgent = quadrant == .doNow || quadrant == .delegate
                rule.priorities = important ? [.high, .medium] : [.low, .none]
                rule.date.kind = urgent ? .nextDays : .afterDays
                rule.date.days = preset == .legacyThreeDays ? 3 : 0
            }
            return MatrixQuadrantConfiguration(quadrant: quadrant, title: quadrant.title,
                                                colorIndex: quadrant.rawValue, rule: rule)
        }
        return MatrixConfiguration(preset: preset, quadrants: values)
    }
    func configuration(for quadrant: MatrixQuadrant) -> MatrixQuadrantConfiguration {
        quadrants.first { $0.quadrant == quadrant } ?? Self.legacy.quadrants[quadrant.rawValue]
    }
    func matches(_ task: Task, now: Date, calendar: Calendar) -> [MatrixQuadrant] {
        precedence.filter { configuration(for: $0).rule.matches(task, now: now, calendar: calendar) }
    }
    func quadrant(for task: Task, now: Date, calendar: Calendar) -> MatrixQuadrant? {
        matches(task, now: now, calendar: calendar).first
    }
    mutating func update(_ value: MatrixQuadrantConfiguration) {
        if let index = quadrants.firstIndex(where: { $0.quadrant == value.quadrant }) { quadrants[index] = value }
        preset = .custom
    }
    mutating func move(_ quadrant: MatrixQuadrant, before target: MatrixQuadrant) {
        guard quadrant != target else { return }
        displayOrder.removeAll { $0 == quadrant }
        displayOrder.insert(quadrant, at: displayOrder.firstIndex(of: target) ?? displayOrder.count)
    }
    mutating func reorder(_ id: UUID, before target: UUID?, in quadrant: MatrixQuadrant) {
        guard let index = quadrants.firstIndex(where: { $0.quadrant == quadrant }), id != target else { return }
        quadrants[index].manualOrder.removeAll { $0 == id }
        let position = target.flatMap { quadrants[index].manualOrder.firstIndex(of: $0) } ?? quadrants[index].manualOrder.count
        quadrants[index].manualOrder.insert(id, at: position)
    }
}

struct MatrixDropProposal: Identifiable, Equatable {
    let taskID: UUID
    let target: MatrixQuadrant
    var id: String { "\(taskID.uuidString):\(target.rawValue)" }
    var priority: TaskPriority?
    var schedule: TaskSchedule?
    var list: TaskList?
    var tags: [String]?
    var listChoices: [String] = []
    var tagChoices: [String] = []
    var changes: [String] = []
    var conflict: String?
    var isNoOp: Bool { priority == nil && schedule == nil && list == nil && tags == nil }
    var canCommit: Bool { conflict == nil }
}

enum MatrixDropPlanner {
    static func propose(task: Task, target: MatrixQuadrant, configuration: MatrixConfiguration,
                        now: Date, calendar: Calendar, chosenList: String? = nil,
                        chosenTag: String? = nil) -> MatrixDropProposal {
        var proposal = MatrixDropProposal(taskID: task.id, target: target)
        if configuration.quadrant(for: task, now: now, calendar: calendar) == target { return proposal }
        let rule = configuration.configuration(for: target).rule
        var candidate = task
        if !rule.priorities.isEmpty && !rule.priorities.contains(task.priority),
           let priority = TaskPriority.menuOrder.first(where: rule.priorities.contains) {
            candidate.priority = priority; proposal.priority = priority
            proposal.changes.append("优先级改为\(priority.title)")
        }
        if !rule.date.matches(task, now: now, calendar: calendar) {
            var schedule = task.schedule
            let day = rule.date.proposedDay(for: task, now: now, calendar: calendar)
            if rule.date.basis == .deadline { schedule.deadlineAt = day }
            else if let day {
                let start: Date
                if task.schedule.hasTime, let old = task.schedule.dueAt {
                    let parts = calendar.dateComponents([.hour, .minute, .second], from: old)
                    start = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0,
                                          second: parts.second ?? 0, of: day)!
                } else { start = day }
                schedule = CalendarGestureDraft.moved(schedule, to: start, hasTime: task.schedule.hasTime, calendar: calendar)
            } else { schedule.dueAt = nil; schedule.dueEndAt = nil; schedule.hasTime = false }
            candidate.schedule = schedule; proposal.schedule = schedule
            proposal.changes.append(day.map { "\(rule.date.basis.title)改为\($0.formatted(.dateTime.month().day()))" }
                                   ?? "取消\(rule.date.basis.title)")
        }
        if !rule.listNames.isEmpty && !rule.listNames.contains(task.list.name) {
            proposal.listChoices = rule.listNames
            let chosen = chosenList.flatMap { rule.listNames.contains($0) ? $0 : nil } ?? rule.listNames[0]
            candidate.list = TaskList(name: chosen); proposal.list = candidate.list
            proposal.changes.append("移至清单“\(chosen)”")
        }
        if !rule.tagNames.isEmpty && !(rule.requiresAllTags ? rule.tagNames.allSatisfy(task.tags.contains) : rule.tagNames.contains(where: task.tags.contains)) {
            proposal.tagChoices = rule.requiresAllTags ? [] : rule.tagNames
            let selected = chosenTag.flatMap { rule.tagNames.contains($0) ? $0 : nil } ?? rule.tagNames[0]
            let additions = rule.requiresAllTags ? rule.tagNames : [selected]
            candidate.tags = Array(Set(task.tags + additions)).sorted(); proposal.tags = candidate.tags
            proposal.changes.append("添加标签：\(additions.joined(separator: "、"))")
        }
        if configuration.quadrant(for: candidate, now: now, calendar: calendar) != target {
            proposal.conflict = "候选属性仍先命中其他象限，请调整规则或匹配顺序。"
        }
        return proposal
    }
}
