import Foundation

/// One day's summary: the short essay the user writes for a calendar day.
/// The JSON keys (`dayKey`, `content`, `updatedAt`) are part of the on-disk
/// `summary.json` format introduced by the Wave 1 F3 stub and must stay stable.
struct DailySummary: Identifiable, Codable, Equatable {
    var id: String { dayKey }
    let dayKey: String  // yyyy-MM-dd in the user's calendar.
    var content: String
    var updatedAt: Date
}
