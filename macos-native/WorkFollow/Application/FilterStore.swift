import Combine
import Foundation

/// Store for saved smart filters (Wave 1 F5): persisted as `filters.json`
/// through `JSONFileStore`, following the HabitStore/SummaryStore pattern.
/// `filters` is always sorted by name. add/update/rename reject empty names
/// and case-insensitive duplicates by returning `false` without mutating.
/// Clearing `TaskWorkspaceModel.activeFilterID` after a deletion is handled on
/// the workspace side via this store's `$filters` publisher.
@MainActor
final class FilterStore: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var filters: [SavedFilter] = []
    private let persistence: JSONFileStore<[SavedFilter]>
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init, directory: URL? = nil) {
        self.clock = clock
        let store: JSONFileStore<[SavedFilter]>
        if let directory {
            store = JSONFileStore(filename: "filters.json", directory: directory)
        } else {
            store = JSONFileStore(filename: "filters.json")
        }
        persistence = store
        filters = Self.sortedByName(store.load() ?? [])
    }

    func filter(withID id: UUID?) -> SavedFilter? {
        guard let id else { return nil }
        return filters.first { $0.id == id }
    }

    func filter(named rawName: String) -> SavedFilter? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return filters.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    @discardableResult
    func add(_ filter: SavedFilter) -> Bool {
        guard let prepared = prepared(filter, excludingID: nil) else { return false }
        filters.append(prepared)
        sortAndPersist()
        return true
    }

    @discardableResult
    func update(_ filter: SavedFilter) -> Bool {
        guard let index = filters.firstIndex(where: { $0.id == filter.id }),
              let prepared = prepared(filter, excludingID: filter.id) else { return false }
        filters[index] = prepared
        sortAndPersist()
        return true
    }

    @discardableResult
    func rename(_ id: UUID, to rawName: String) -> Bool {
        guard var filter = filter(withID: id) else { return false }
        filter.name = rawName
        return update(filter)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard let index = filters.firstIndex(where: { $0.id == id }) else { return false }
        filters.remove(at: index)
        persist()
        return true
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }

    /// Rejects empty names and case-insensitive duplicates, and trims the name.
    private func prepared(_ filter: SavedFilter, excludingID: UUID?) -> SavedFilter? {
        let name = filter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !filters.contains(where: {
                  $0.id != excludingID && $0.name.caseInsensitiveCompare(name) == .orderedSame
              }) else { return nil }
        var value = filter
        value.name = name
        return value
    }

    private func sortAndPersist() {
        filters = Self.sortedByName(filters)
        persist()
    }

    private func persist() {
        persistence.schedule(filters)
    }

    private static func sortedByName(_ values: [SavedFilter]) -> [SavedFilter] {
        values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
