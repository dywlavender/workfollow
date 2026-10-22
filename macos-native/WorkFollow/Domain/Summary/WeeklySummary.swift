import Foundation

struct WeeklySummary: Codable, Equatable, Identifiable {
    let weekKey: String
    let scopeID: String
    var listName: String?
    var document: NativeDocument
    var updatedAt: Date
    var options: SummaryDocumentOptions? = nil
    var range: SummaryDateRange? = nil
    var listNames: [String]? = nil
    var id: String { weekKey + "/" + scopeID }
}
