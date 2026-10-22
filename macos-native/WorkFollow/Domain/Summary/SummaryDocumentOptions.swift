import Foundation

/// The recipe applied to a saved summary. Pending inspector changes are kept
/// separately by the editor until the user adopts a preview.
struct SummaryDocumentOptions: Codable, Equatable {
    var filter = SummaryFilter(showsDate: true, showsList: true, showsTags: true)
    var grouping: SummaryGrouping = .completion
    var includesNextWeek = false
    var content: Set<SummaryContentField> = SummaryContentField.standard

    static let standard = SummaryDocumentOptions()

    init() {}

    private enum CodingKeys: String, CodingKey { case filter, grouping, includesNextWeek, content }

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
    }
}
