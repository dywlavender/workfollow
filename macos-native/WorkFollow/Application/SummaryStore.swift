import Combine
import Foundation

/// Journals keep their own file; the live summary only persists its display
/// recipe, never a snapshot of the generated text.
@MainActor
final class SummaryStore: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var entries: [DailySummary] = []
    @Published private(set) var options: SummaryDocumentOptions
    /// Last flush failure for inline display; cleared by the next successful flush.
    @Published private(set) var lastError: String?
    private let persistence: JSONFileStore<[DailySummary]>
    private let optionsPersistence: JSONFileStore<SummaryDocumentOptions>
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
        let optionsStore = JSONFileStore<SummaryDocumentOptions>(
            filename: "summary-options.json", directory: directory ?? JSONFileStore<[DailySummary]>.moduleDirectory)
        optionsPersistence = optionsStore
        var loaded = optionsStore.load() ?? .standard
        // List scope follows the shared week/context selection, not the saved recipe.
        loaded.filter.listName = nil
        options = loaded
        entries = (store.load() ?? []).sorted { $0.dayKey > $1.dayKey }
    }

    func entry(for dayKey: String) -> DailySummary? {
        entries.first { $0.dayKey == dayKey }
    }

    func updateOptions(_ value: SummaryDocumentOptions) {
        var normalized = value
        normalized.filter.listName = nil
        guard options != normalized else { return }
        options = normalized
        optionsPersistence.schedule(normalized)
    }

    /// 保存富文本正文（P0 起摘要正文走 document）。`content` 同步一份纯文本，
    /// 供旧预览/搜索使用；空文档等同删除该条目。
    func save(document: NativeDocument, dayKey: String) {
        let plain = document.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else {
            guard entry(for: dayKey) != nil else { return }
            entries.removeAll { $0.dayKey == dayKey }
            persistence.schedule(entries)
            return
        }
        if let index = entries.firstIndex(where: { $0.dayKey == dayKey }) {
            entries[index].document = document
            entries[index].content = plain
            entries[index].updatedAt = clock()
        } else {
            entries.append(DailySummary(dayKey: dayKey, content: plain,
                                        document: document, updatedAt: clock()))
        }
        sortEntries()
        persistence.schedule(entries)
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
            entries[index].document = nil
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
    nonisolated static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parses a `yyyy-MM-dd` key back to the start of that calendar day.
    nonisolated static func date(fromDayKey dayKey: String, calendar: Calendar) -> Date? {
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
        persistence.flush { [weak self, optionsPersistence] dailyError in
            optionsPersistence.flush { optionsError in
            let error = dailyError ?? optionsError
            // `Task` names the domain entity in this module; qualify the
            // concurrency type explicitly.
            _Concurrency.Task { @MainActor in
                self?.lastError = error.map { "摘要保存失败：\($0.localizedDescription)" }
            }
            completion(error)
            }
        }
    }
}
