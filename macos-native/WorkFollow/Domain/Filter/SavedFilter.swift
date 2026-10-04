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
    /// 关键词（滴答「普通筛选」的"按关键词做内容筛选"）：**全部包含**才算命中，
    /// 匹配范围是标题 + 正文纯文本，大小写不敏感。空数组 = 该维度关闭。
    var keywords: [String] = []

    init(id: UUID = UUID(), name: String, listNames: [String] = [], tags: [String] = [],
         priorities: [TaskPriority] = [], dateRange: SavedFilterDateRange = .any,
         keywords: [String] = []) {
        self.id = id
        self.name = name
        self.listNames = listNames
        self.tags = tags
        self.priorities = priorities
        self.dateRange = dateRange
        self.keywords = keywords
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, listNames, tags, priorities, dateRange, keywords
    }

    /// additive Codable：旧 `filters.json` 缺 `keywords` 键时解码为空数组
    /// （属性默认值不会让合成解码器宽容缺键，所以显式写出来）。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        listNames = try values.decodeIfPresent([String].self, forKey: .listNames) ?? []
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        priorities = try values.decodeIfPresent([TaskPriority].self, forKey: .priorities) ?? []
        dateRange = try values.decodeIfPresent(SavedFilterDateRange.self, forKey: .dateRange) ?? .any
        keywords = try values.decodeIfPresent([String].self, forKey: .keywords) ?? []
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
        if !filter.listNames.isEmpty && !filter.listNames.contains(task.list.name) {
            return false
        }
        if !filter.tags.isEmpty && !filter.tags.contains(where: { task.tags.contains($0) }) {
            return false
        }
        if !filter.priorities.isEmpty && !filter.priorities.contains(task.priority) {
            return false
        }
        if !filter.keywords.isEmpty {
            // 只在真有关键词时才拼正文，避免没有该维度时每个任务都拼一次。
            let haystack = task.title + "\n" + task.document.plainText
            guard filter.keywords.allSatisfy({ haystack.localizedCaseInsensitiveContains($0) }) else {
                return false
            }
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
