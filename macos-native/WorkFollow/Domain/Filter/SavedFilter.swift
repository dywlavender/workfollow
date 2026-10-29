import Foundation

/// Date dimension of a saved filter. The predicates reuse TaskListProjection's
/// existing start-of-day math (with the caller's calendar) instead of a second
/// day-window definition:
/// - `today` matches the `.today` scope predicate (due day <= today, or a
///   deadline no later than today), so 已过期 tasks still show under 今天 views.
/// - `nextSevenDays` matches the `.nextSevenDays` scope predicate
///   (due day < today + 7, includes today and 已过期, excludes the boundary day).
/// - `overdue` / `noDate` match the 所有任务 date buckets. Overdue follows
///   `ScheduleOverdue`: a time range is judged by its end (`dueEndAt`), so an
///   ongoing range is not overdue; `noDate` is dueAt == nil. Deadlines alone do
///   not create buckets.
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

struct FilterOrganizationSelection: Codable, Equatable {
    var id: UUID?
    var name: String

    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

enum FilterTagMatch: String, Codable, CaseIterable, Identifiable {
    case any, all
    var id: String { rawValue }
    var title: String { self == .any ? "任一" : "全部" }
}

enum FilterConditionKind: String, Codable, CaseIterable, Identifiable {
    case lists, tags, priorities, date, keywords
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lists: "清单"
        case .tags: "标签"
        case .priorities: "优先级"
        case .date: "日期范围"
        case .keywords: "关键词"
        }
    }
}

struct FilterCondition: Codable, Equatable {
    var kind: FilterConditionKind
    var organizationSelections: [FilterOrganizationSelection] = []
    var tagMatch: FilterTagMatch = .any
    var priorities: [TaskPriority] = []
    var dateRange: SavedFilterDateRange = .any
    var keywords: [String] = []
    /// Old name and ID arrays were independent sets. Keep that predicate intact
    /// when changing editor modes instead of guessing name-to-ID pairs.
    var legacyOrganizationIDs: [UUID]?

    init(kind: FilterConditionKind, organizationSelections: [FilterOrganizationSelection] = [],
         tagMatch: FilterTagMatch = .any, priorities: [TaskPriority] = [],
         dateRange: SavedFilterDateRange = .any, keywords: [String] = [],
         legacyOrganizationIDs: [UUID]? = nil) {
        self.kind = kind
        self.organizationSelections = organizationSelections
        self.tagMatch = tagMatch
        self.priorities = priorities
        self.dateRange = dateRange
        self.keywords = keywords
        self.legacyOrganizationIDs = legacyOrganizationIDs
    }

    private enum CodingKeys: String, CodingKey {
        case kind, organizationSelections, tagMatch, priorities, dateRange, keywords, legacyOrganizationIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(FilterConditionKind.self, forKey: .kind)
        organizationSelections = try values.decodeIfPresent([FilterOrganizationSelection].self, forKey: .organizationSelections) ?? []
        tagMatch = try values.decodeIfPresent(FilterTagMatch.self, forKey: .tagMatch) ?? .any
        priorities = try values.decodeIfPresent([TaskPriority].self, forKey: .priorities) ?? []
        dateRange = try values.decodeIfPresent(SavedFilterDateRange.self, forKey: .dateRange) ?? .any
        keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
        legacyOrganizationIDs = try values.decodeIfPresent([UUID].self, forKey: .legacyOrganizationIDs)
    }

    var isEnabled: Bool {
        switch kind {
        case .lists, .tags: !organizationSelections.isEmpty || !(legacyOrganizationIDs ?? []).isEmpty
        case .priorities: !priorities.isEmpty
        case .date: dateRange != .any
        case .keywords: !keywords.isEmpty
        }
    }

    var summary: String {
        let detail: String
        switch kind {
        case .lists:
            detail = organizationSelections.map(\.name).joined(separator: "、")
        case .tags:
            let names = organizationSelections.map(\.name).joined(separator: "、")
            return "标签（\(tagMatch.title)）：" + (names.isEmpty ? "未设置" : names)
        case .priorities:
            detail = priorities.map { priority in
                switch priority {
                case .none: "无"
                case .low: "低"
                case .medium: "中"
                case .high: "高"
                }
            }.joined(separator: "、")
        case .date: detail = dateRange.title
        case .keywords: detail = keywords.joined(separator: " 且 ")
        }
        return kind.title + "：" + (detail.isEmpty ? "未设置" : detail)
    }
}

indirect enum FilterExpression: Codable, Equatable {
    case all([FilterExpression])
    case any([FilterExpression])
    case condition(FilterCondition)

    private enum CodingKeys: String, CodingKey { case operation, children, condition }
    private enum Operation: String, Codable { case all, any, condition }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Operation.self, forKey: .operation) {
        case .all: self = .all(try values.decode([FilterExpression].self, forKey: .children))
        case .any: self = .any(try values.decode([FilterExpression].self, forKey: .children))
        case .condition: self = .condition(try values.decode(FilterCondition.self, forKey: .condition))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all(let children):
            try values.encode(Operation.all, forKey: .operation)
            try values.encode(children, forKey: .children)
        case .any(let children):
            try values.encode(Operation.any, forKey: .operation)
            try values.encode(children, forKey: .children)
        case .condition(let condition):
            try values.encode(Operation.condition, forKey: .operation)
            try values.encode(condition, forKey: .condition)
        }
    }

    func mapConditions(_ transform: (FilterCondition) -> FilterCondition) -> Self {
        switch self {
        case .all(let children): .all(children.map { $0.mapConditions(transform) })
        case .any(let children): .any(children.map { $0.mapConditions(transform) })
        case .condition(let condition): .condition(transform(condition))
        }
    }

    var summary: String {
        switch self {
        case .condition(let condition): condition.summary
        case .all(let children): Self.summary(children, separator: " 且 ", empty: "所有任务")
        case .any(let children): Self.summary(children, separator: " 或 ", empty: "没有匹配条件")
        }
    }

    private static func summary(_ children: [Self], separator: String, empty: String) -> String {
        guard !children.isEmpty else { return empty }
        if children.count == 1 { return children[0].summary }
        return "（" + children.map(\.summary).joined(separator: separator) + "）"
    }
}

/// One saved smart filter (Wave 1 F5, aligned with TickTick's 过滤器).
/// Without an expression, enabled dimensions retain their original AND rules;
/// empty arrays and `.any` mean the dimension is off.
struct SavedFilter: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var listNames: [String] = []
    var tags: [String] = []
    var listIDs: [UUID]?
    var tagIDs: [UUID]?
    var priorities: [TaskPriority] = []
    var dateRange: SavedFilterDateRange = .any
    /// 关键词（滴答「普通筛选」的"按关键词做内容筛选"）：**全部包含**才算命中，
    /// 匹配范围是标题 + 正文纯文本，大小写不敏感。空数组 = 该维度关闭。
    var keywords: [String] = []
    var expression: FilterExpression?

    init(id: UUID = UUID(), name: String, listNames: [String] = [], tags: [String] = [],
         priorities: [TaskPriority] = [], dateRange: SavedFilterDateRange = .any,
         keywords: [String] = [], expression: FilterExpression? = nil) {
        self.id = id
        self.name = name
        self.listNames = listNames
        self.tags = tags
        self.priorities = priorities
        self.dateRange = dateRange
        self.keywords = keywords
        self.expression = expression
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, listNames, tags, listIDs, tagIDs, priorities, dateRange, keywords, expression
    }

    /// additive Codable：旧 `filters.json` 缺 `keywords` / `expression` 时仍能读取
    /// （属性默认值不会让合成解码器宽容缺键，所以显式写出来）。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        listNames = try values.decodeIfPresent([String].self, forKey: .listNames) ?? []
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        listIDs = try values.decodeIfPresent([UUID].self, forKey: .listIDs)
        tagIDs = try values.decodeIfPresent([UUID].self, forKey: .tagIDs)
        priorities = try values.decodeIfPresent([TaskPriority].self, forKey: .priorities) ?? []
        dateRange = try values.decodeIfPresent(SavedFilterDateRange.self, forKey: .dateRange) ?? .any
        keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
        expression = try values.decodeIfPresent(FilterExpression.self, forKey: .expression)
    }

    var legacyConditions: [FilterCondition] {
        [FilterCondition(kind: .lists,
                         organizationSelections: listNames.map { FilterOrganizationSelection(name: $0) },
                         legacyOrganizationIDs: listIDs),
         FilterCondition(kind: .tags,
                         organizationSelections: tags.map { FilterOrganizationSelection(name: $0) },
                         legacyOrganizationIDs: tagIDs),
         FilterCondition(kind: .priorities, priorities: priorities),
         FilterCondition(kind: .date, dateRange: dateRange),
         FilterCondition(kind: .keywords, keywords: keywords)].filter(\.isEnabled)
    }

    /// 关键词原文 → token 列表：空格 / 半角逗号 / 中文逗号 / 顿号 / 换行分隔，
    /// 去重且保持输入顺序。编辑器与测试共用这一处解析。
    static func parseKeywords(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: " ,，、\t\n")
        var seen = Set<String>()
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Pure predicate: does `task` pass every enabled dimension of `filter`?
/// Closed (completed/abandoned) tasks are deliberately not excluded here —
/// matching them follows `TaskListQuery.matches`, which also ignores `isClosed`
/// and lets matching closed tasks stay in the view's 已完成 group.
enum FilterEvaluator {
    static func matches(_ task: Task, filter: SavedFilter,
                        now: Date, calendar: Calendar) -> Bool {
        if let expression = filter.expression {
            return matches(task, expression: expression, now: now, calendar: calendar)
        }
        if let ids = filter.listIDs, !ids.isEmpty, let taskID = task.listID {
            if !ids.contains(taskID) { return false }
        } else if !filter.listNames.isEmpty && !filter.listNames.contains(task.list.name) { return false }
        if let ids = filter.tagIDs, !ids.isEmpty, let references = task.tagReferences {
            if !references.contains(where: { ids.contains($0.id) }) { return false }
        } else if !filter.tags.isEmpty && !filter.tags.contains(where: { task.tags.contains($0) }) { return false }
        if !filter.priorities.isEmpty && !filter.priorities.contains(task.priority) {
            return false
        }
        if !filter.keywords.isEmpty {
            // 只在真有关键词时才拼正文，避免没有该维度时每个任务都拼一次。
            guard filter.keywords.allSatisfy({ task.document.matches($0, prefix: task.title + "\n") }) else {
                return false
            }
        }
        return matchesDate(task, range: filter.dateRange, now: now, calendar: calendar)
    }

    static func matches(_ task: Task, expression: FilterExpression,
                        now: Date, calendar: Calendar) -> Bool {
        switch expression {
        case .all(let children):
            children.allSatisfy { matches(task, expression: $0, now: now, calendar: calendar) }
        case .any(let children):
            children.contains { matches(task, expression: $0, now: now, calendar: calendar) }
        case .condition(let condition):
            matches(task, condition: condition, now: now, calendar: calendar)
        }
    }

    private static func matches(_ task: Task, condition: FilterCondition,
                                now: Date, calendar: Calendar) -> Bool {
        guard condition.isEnabled else { return true }
        switch condition.kind {
        case .lists:
            if let ids = condition.legacyOrganizationIDs, !ids.isEmpty, let id = task.listID {
                return ids.contains(id)
            }
            return condition.organizationSelections.isEmpty || condition.organizationSelections.contains { selection in
                if let id = selection.id, let taskID = task.listID { return id == taskID }
                return selection.name == task.list.name
            }
        case .tags:
            if let ids = condition.legacyOrganizationIDs, !ids.isEmpty, let references = task.tagReferences {
                return references.contains { ids.contains($0.id) }
            }
            let matchesSelection: (FilterOrganizationSelection) -> Bool = { selection in
                if let id = selection.id, let references = task.tagReferences {
                    return references.contains { $0.id == id }
                }
                return task.tags.contains(selection.name)
            }
            if condition.organizationSelections.isEmpty { return true }
            return condition.tagMatch == .all
                ? condition.organizationSelections.allSatisfy(matchesSelection)
                : condition.organizationSelections.contains(where: matchesSelection)
        case .priorities: return condition.priorities.contains(task.priority)
        case .date: return matchesDate(task, range: condition.dateRange, now: now, calendar: calendar)
        case .keywords:
            return condition.keywords.allSatisfy { task.document.matches($0, prefix: task.title + "\n") }
        }
    }

    private static func matchesDate(_ task: Task, range: SavedFilterDateRange,
                                    now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        switch range {
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
            // 时间段以结束为准：进行中的区间不算逾期。
            return ScheduleOverdue.isOverdue(schedule: task.schedule, now: now, calendar: calendar)
        }
    }
}
