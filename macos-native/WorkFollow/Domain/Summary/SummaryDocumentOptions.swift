import Foundation

/// The recipe applied to a saved summary. Pending inspector changes are kept
/// separately by the editor until the user adopts a preview.
struct SummaryDocumentOptions: Codable, Equatable {
    var filter = SummaryFilter(showsDate: true, showsList: true, showsTags: true)
    var grouping: SummaryGrouping = .completion
    var includesNextWeek = false
    var content: Set<SummaryContentField> = SummaryContentField.standard
    var contentOrder: [SummaryContentField] = SummaryContentField.inlineOrder
    var contentStyles = SummaryContentStyles()

    static let standard = SummaryDocumentOptions()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case filter, grouping, includesNextWeek, content, contentOrder, contentStyles
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        filter = try values.decodeIfPresent(SummaryFilter.self, forKey: .filter) ?? .all
        grouping = try values.decodeIfPresent(SummaryGrouping.self, forKey: .grouping) ?? .completion
        includesNextWeek = try values.decodeIfPresent(Bool.self, forKey: .includesNextWeek) ?? false
        if let saved = try values.decodeIfPresent(Set<SummaryContentField>.self, forKey: .content) {
            content = saved
        } else {
            // Translate the previous three switches without changing stored text.
            content = [.taskName, .progress]
            if filter.showsDate { content.formUnion([.completedTime, .taskTime]) }
            if filter.showsList { content.insert(.list) }
            if filter.showsTags { content.insert(.tags) }
        }
        // 顺序按字符串解码，未知字段直接丢弃；整个摘要不应该因为一个新字段打不开。
        let savedOrder = (try values.decodeIfPresent([String].self, forKey: .contentOrder) ?? [])
            .compactMap(SummaryContentField.init(rawValue:))
        contentOrder = Self.normalizedOrder(savedOrder)
        contentStyles = try values.decodeIfPresent(SummaryContentStyles.self, forKey: .contentStyles)
            ?? .standard
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(filter, forKey: .filter)
        try values.encode(grouping, forKey: .grouping)
        try values.encode(includesNextWeek, forKey: .includesNextWeek)
        try values.encode(content, forKey: .content)
        try values.encode(contentOrder, forKey: .contentOrder)
        try values.encode(contentStyles, forKey: .contentStyles)
    }

    /// 旧档案没有顺序字段，或遇到重复/固定槽位时，补成完整的行内顺序。
    static func normalizedOrder(_ order: [SummaryContentField]) -> [SummaryContentField] {
        var result: [SummaryContentField] = []
        for field in order where field.isInline && !result.contains(field) {
            result.append(field)
        }
        for field in SummaryContentField.inlineOrder where !result.contains(field) {
            result.append(field)
        }
        return result
    }

    mutating func moveContentField(_ field: SummaryContentField, by offset: Int) {
        guard let from = contentOrder.firstIndex(of: field) else { return }
        let destination = min(max(0, from + offset), contentOrder.count - 1)
        guard destination != from else { return }
        contentOrder.remove(at: from)
        contentOrder.insert(field, at: destination)
    }
}
