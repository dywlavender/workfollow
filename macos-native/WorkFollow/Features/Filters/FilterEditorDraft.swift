import Foundation

enum FilterEditorMode: String, CaseIterable, Identifiable {
    case basic, advanced
    var id: String { rawValue }
    var title: String { self == .basic ? "普通筛选" : "高级筛选" }
}

enum FilterRuleConnector: String, CaseIterable, Identifiable {
    case and, or
    var id: String { rawValue }
    var title: String { self == .and ? "且" : "或" }
}

typealias FilterEditorRuleKind = FilterConditionKind

struct FilterEditorRule: Identifiable, Equatable {
    let id: UUID
    var connector: FilterRuleConnector
    var kind: FilterEditorRuleKind {
        didSet {
            if kind != oldValue {
                organizationSelections = []
                legacyOrganizationIDs = nil
            }
        }
    }
    var organizationSelections: [FilterOrganizationSelection] = [] {
        didSet {
            if organizationSelections != oldValue { legacyOrganizationIDs = nil }
        }
    }
    var tagMatch: FilterTagMatch = .any {
        didSet {
            if tagMatch != oldValue { legacyOrganizationIDs = nil }
        }
    }
    var selectedPriorities: Set<TaskPriority> = []
    var dateRange: SavedFilterDateRange = .any
    var keywordText = ""
    private var legacyOrganizationIDs: [UUID]?

    init(id: UUID = UUID(), connector: FilterRuleConnector = .and,
         kind: FilterEditorRuleKind = .tags) {
        self.id = id
        self.connector = connector
        self.kind = kind
    }

    init(condition: FilterCondition, connector: FilterRuleConnector = .and) {
        self.init(connector: connector, kind: condition.kind)
        organizationSelections = condition.organizationSelections
        tagMatch = condition.tagMatch
        selectedPriorities = Set(condition.priorities)
        dateRange = condition.dateRange
        keywordText = condition.keywords.joined(separator: " ")
        legacyOrganizationIDs = condition.legacyOrganizationIDs
    }

    /// Chip bindings retain the identities of items that remain selected.
    var organizationNames: Set<String> {
        get { Set(organizationSelections.map(\.name)) }
        set {
            guard newValue != organizationNames else { return }
            let existing = Dictionary(organizationSelections.map { ($0.name, $0) },
                                      uniquingKeysWith: { current, _ in current })
            organizationSelections = newValue.sorted().map {
                existing[$0] ?? FilterOrganizationSelection(name: $0)
            }
        }
    }

    var condition: FilterCondition {
        FilterCondition(kind: kind, organizationSelections: organizationSelections,
                        tagMatch: tagMatch,
                        priorities: TaskPriority.menuOrder.filter { selectedPriorities.contains($0) },
                        dateRange: dateRange, keywords: SavedFilter.parseKeywords(keywordText),
                        legacyOrganizationIDs: legacyOrganizationIDs)
    }

    var summary: String { condition.summary }
}

/// Unsaved conditions shared by preview and save. A mode change commits no data.
struct FilterEditorDraft {
    let id: UUID
    var name: String
    var selectedLists: Set<String>
    var selectedTags: Set<String>
    var selectedPriorities: Set<TaskPriority>
    var dateRange: SavedFilterDateRange
    var keywordText: String
    private(set) var mode: FilterEditorMode
    var rules: [FilterEditorRule]
    private var sourceFilter: SavedFilter
    private var retainedExpression: FilterExpression?

    init(initial: SavedFilter?) {
        let source = initial ?? SavedFilter(name: "")
        id = source.id
        name = source.name
        selectedLists = Set(source.listNames)
        selectedTags = Set(source.tags)
        selectedPriorities = Set(source.priorities)
        dateRange = source.dateRange
        keywordText = source.keywords.joined(separator: " ")
        sourceFilter = source
        mode = source.expression == nil ? .basic : .advanced
        if let expression = source.expression {
            let editable = Self.linearized(expression)
            rules = editable ?? []
            retainedExpression = editable == nil ? expression : nil
        } else {
            rules = []
            retainedExpression = nil
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var filter: SavedFilter {
        guard mode == .advanced else { return basicFilter }
        var value = sourceFilter
        value.name = trimmedName
        value.expression = advancedExpression
        return value
    }

    private var basicFilter: SavedFilter {
        let sameLists = selectedLists == Set(sourceFilter.listNames)
        let sameTags = selectedTags == Set(sourceFilter.tags)
        var value = SavedFilter(id: id, name: trimmedName,
                                listNames: sameLists ? sourceFilter.listNames : selectedLists.sorted(),
                                tags: sameTags ? sourceFilter.tags : selectedTags.sorted(),
                                priorities: TaskPriority.menuOrder.filter { selectedPriorities.contains($0) },
                                dateRange: dateRange, keywords: SavedFilter.parseKeywords(keywordText))
        if sameLists { value.listIDs = sourceFilter.listIDs }
        if sameTags { value.tagIDs = sourceFilter.tagIDs }
        return value
    }

    private var advancedExpression: FilterExpression {
        if let retainedExpression { return retainedExpression }
        let enabled = rules.filter { $0.condition.isEnabled }
        guard let first = enabled.first else { return .all([]) }
        return enabled.dropFirst().reduce(FilterExpression.condition(first.condition)) { expression, rule in
            switch rule.connector {
            case .and: .all([expression, .condition(rule.condition)])
            case .or: .any([expression, .condition(rule.condition)])
            }
        }
    }

    var expressionSummary: String {
        (mode == .advanced ? advancedExpression : .all(basicFilter.legacyConditions.map(FilterExpression.condition))).summary
    }

    var canEditAdvancedRules: Bool { retainedExpression == nil }
    var advancedEditingIssue: String? {
        canEditAdvancedRules ? nil : "此过滤器包含分组条件，逐行编辑会改变组合关系。当前条件仍会保留。"
    }
    var basicConversionIssue: String? {
        mode == .advanced && Self.basicConditions(advancedExpression) == nil
            ? "当前组合不能无损转换为普通筛选，请保留高级筛选。" : nil
    }

    @discardableResult
    mutating func switchMode(to mode: FilterEditorMode) -> Bool {
        guard mode != self.mode else { return true }
        if mode == .advanced {
            sourceFilter = basicFilter
            rules = sourceFilter.legacyConditions.map { FilterEditorRule(condition: $0) }
            retainedExpression = nil
        } else {
            guard let conditions = Self.basicConditions(advancedExpression) else { return false }
            var value = SavedFilter(id: id, name: trimmedName)
            for condition in conditions {
                switch condition.kind {
                case .lists:
                    value.listNames = condition.organizationSelections.map(\.name)
                    value.listIDs = Self.ordinaryIDs(condition)
                case .tags:
                    value.tags = condition.organizationSelections.map(\.name)
                    value.tagIDs = Self.ordinaryIDs(condition)
                case .priorities: value.priorities = condition.priorities
                case .date: value.dateRange = condition.dateRange
                case .keywords: value.keywords = condition.keywords
                }
            }
            sourceFilter = value
            selectedLists = Set(value.listNames)
            selectedTags = Set(value.tags)
            selectedPriorities = Set(value.priorities)
            dateRange = value.dateRange
            keywordText = value.keywords.joined(separator: " ")
            retainedExpression = nil
        }
        self.mode = mode
        return true
    }

    mutating func addRule(kind: FilterEditorRuleKind = .tags) {
        if mode == .basic { switchMode(to: .advanced) }
        guard canEditAdvancedRules else { return }
        rules.append(FilterEditorRule(kind: kind))
    }

    mutating func removeRule(id: UUID) {
        guard canEditAdvancedRules else { return }
        rules.removeAll { $0.id == id }
    }

    func listOptions(allListNames: [String]) -> [String] {
        let inbox = TaskList.inbox.name
        let chosen = rules.filter { $0.kind == .lists }.flatMap { $0.organizationSelections.map(\.name) }
        let others = Set(allListNames).union(selectedLists).union(chosen).subtracting([inbox]).sorted()
        return [inbox] + others
    }

    func tagOptions(tagNames: [String]) -> [String] {
        let chosen = rules.filter { $0.kind == .tags }.flatMap { $0.organizationSelections.map(\.name) }
        var seen = Set<String>()
        let ordered = tagNames.filter { seen.insert($0).inserted }
        return ordered + Set(chosen).union(selectedTags).subtracting(seen).sorted()
    }

    private static func ordinaryIDs(_ condition: FilterCondition) -> [UUID]? {
        if let ids = condition.legacyOrganizationIDs { return ids }
        let ids = condition.organizationSelections.compactMap(\.id)
        return !ids.isEmpty && ids.count == condition.organizationSelections.count ? ids : nil
    }

    private static func basicConditions(_ expression: FilterExpression) -> [FilterCondition]? {
        let conditions: [FilterCondition]
        switch expression {
        case .condition(let condition): conditions = condition.isEnabled ? [condition] : []
        case .all(let children):
            var combined: [FilterCondition] = []
            for child in children {
                guard let values = basicConditions(child) else { return nil }
                combined += values
            }
            conditions = combined
        case .any(let children):
            guard children.count == 1 else { return nil }
            return basicConditions(children[0])
        }
        var result: [FilterCondition] = []
        for condition in conditions {
            if condition.kind == .tags, condition.tagMatch == .all,
               condition.organizationSelections.count > 1 { return nil }
            if condition.kind == .lists || condition.kind == .tags {
                let count = condition.organizationSelections.compactMap(\.id).count
                if condition.legacyOrganizationIDs == nil && count > 0
                    && count < condition.organizationSelections.count { return nil }
            }
            if let existing = result.first(where: { $0.kind == condition.kind }) {
                if existing == condition { continue }
                return nil
            }
            result.append(condition)
        }
        return result
    }

    private static func linearized(_ expression: FilterExpression) -> [FilterEditorRule]? {
        switch expression {
        case .condition(let condition):
            return condition.isEnabled ? [FilterEditorRule(condition: condition)] : []
        case .all(let children): return linearized(children, connector: .and)
        case .any(let children):
            guard !children.isEmpty else { return nil }
            return linearized(children, connector: .or)
        }
    }

    private static func linearized(_ children: [FilterExpression], connector: FilterRuleConnector)
        -> [FilterEditorRule]? {
        guard let first = children.first else { return [] }
        guard var result = linearized(first) else { return nil }
        if connector == .or && result.isEmpty && children.count > 1 { return nil }
        for child in children.dropFirst() {
            guard let trailing = homogeneousConditions(child, connector: connector) else { return nil }
            result += trailing.map { FilterEditorRule(condition: $0, connector: connector) }
        }
        return result
    }

    private static func homogeneousConditions(_ expression: FilterExpression, connector: FilterRuleConnector)
        -> [FilterCondition]? {
        switch expression {
        case .condition(let condition):
            if !condition.isEnabled { return connector == .and ? [] : nil }
            return [condition]
        case .all(let children) where connector == .and:
            var result: [FilterCondition] = []
            for child in children {
                guard let values = homogeneousConditions(child, connector: connector) else { return nil }
                result += values
            }
            return result
        case .any(let children) where connector == .or && !children.isEmpty:
            var result: [FilterCondition] = []
            for child in children {
                guard let values = homogeneousConditions(child, connector: connector) else { return nil }
                result += values
            }
            return result
        default: return nil
        }
    }
}

/// Counts real unfinished matches without changing the active filter or store.
/// Parent rows retained for navigation by the task list are not extra matches.
struct FilterEditorPreview {
    let matchingCount: Int
    let tasks: [Task]

    static func project(tasks: [Task], filter: SavedFilter,
                        now: Date, calendar: Calendar, limit: Int = 3) -> Self {
        let matching = tasks.filter {
            $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted && !$0.isClosed
                && FilterEvaluator.matches($0, filter: filter, now: now, calendar: calendar)
        }
        return Self(matchingCount: matching.count, tasks: Array(matching.prefix(max(0, limit))))
    }
}
