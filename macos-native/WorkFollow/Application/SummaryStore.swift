import Combine
import Foundation

/// Store for the summary module (Wave 1 F3): one short essay per calendar
/// day, persisted as `summary.json` through `JSONFileStore`. `entries` is
/// always sorted by `dayKey`, newest day first. Autosave is driven by the
/// workspace view (debounced `save` + `flush`); the store keeps no timers.
@MainActor
final class SummaryStore: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var entries: [DailySummary] = []
    /// Last flush failure for inline display; cleared by the next successful flush.
    @Published private(set) var lastError: String?
    private let persistence: JSONFileStore<[DailySummary]>
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init, directory: URL? = nil) {
        self.clock = clock
        let store: JSONFileStore<[DailySummary]>
        if let directory {
            store = JSONFileStore(filename: "summary.json", directory: directory)
        } else {
            store = JSONFileStore(filename: "summary.json")
        }
        persistence = store
        entries = (store.load() ?? []).sorted { $0.dayKey > $1.dayKey }
    }

    func entry(for dayKey: String) -> DailySummary? {
        entries.first { $0.dayKey == dayKey }
    }

    /// Creates or updates the entry for `dayKey`; the new or changed content
    /// refreshes `updatedAt`. Empty (or whitespace-only) content deletes the
    /// entry for that day instead.
    func save(content: String, dayKey: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            guard entry(for: dayKey) != nil else { return }
            entries.removeAll { $0.dayKey == dayKey }
            persistence.schedule(entries)
            return
        }
        if let index = entries.firstIndex(where: { $0.dayKey == dayKey }) {
            entries[index].content = trimmed
            entries[index].updatedAt = clock()
        } else {
            entries.append(DailySummary(dayKey: dayKey, content: trimmed, updatedAt: clock()))
        }
        sortEntries()
        persistence.schedule(entries)
    }

    /// Days of the month containing `month` that have a summary, newest first.
    func entries(inMonth month: Date, calendar: Calendar) -> [DailySummary] {
        let parts = calendar.dateComponents([.year, .month], from: month)
        let prefix = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        return entries.filter { $0.dayKey.hasPrefix(prefix) }
    }

    // MARK: Day keys

    /// Formats a date as the `yyyy-MM-dd` key used by entries.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parses a `yyyy-MM-dd` key back to the start of that calendar day.
    static func date(fromDayKey dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func sortEntries() {
        entries.sort { $0.dayKey > $1.dayKey }
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush { [weak self] error in
            // `Task` names the domain entity in this module; qualify the
            // concurrency type explicitly.
            _Concurrency.Task { @MainActor in
                self?.lastError = error.map { "摘要保存失败：\($0.localizedDescription)" }
            }
            completion(error)
        }
    }
}
