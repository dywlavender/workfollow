import Combine
import Foundation

/// Store for saved smart filters (Wave 1 F5): persisted as `filters.json`
/// through `JSONFileStore`, following the SummaryStore pattern.
/// `filters` is always sorted by name. add/update/rename reject empty names
/// and case-insensitive duplicates by returning `false` without mutating.
/// Clearing `TaskWorkspaceModel.activeFilterID` after a deletion is handled on
/// the workspace side via this store's `$filters` publisher.
@MainActor
final class FilterStore: ObservableObject, ModuleStoreFlushable {
    @Published private(set) var filters: [SavedFilter] = []
    private let persistence: JSONFileStore<[SavedFilter]>
    private let clock: () -> Date
    var organizationResolver: (([String], [String]) -> ([UUID], [UUID]))?

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

    func resolveOrganizationReferences() {
        guard let resolver = organizationResolver else { return }
        let resolved = filters.map { filter -> SavedFilter in
            resolvingReferences(in: filter, using: resolver)
        }
        if filters != resolved { filters = resolved; persist() }
    }

    func renameReference(_ change: TaskOrganizationRename) {
        let resolved = filters.map { filter -> SavedFilter in
            var value = filter
            if change.kind == .list {
                if value.listIDs?.isEmpty != false || value.listIDs?.contains(change.id) == true {
                    value.listNames = value.listNames.map { $0 == change.oldName ? change.newName : $0 }
                }
            } else {
                if value.tagIDs?.isEmpty != false || value.tagIDs?.contains(change.id) == true {
                    value.tags = value.tags.map { $0 == change.oldName ? change.newName : $0 }
                }
            }
            value.expression = value.expression?.mapConditions { condition in
                guard (change.kind == .list && condition.kind == .lists)
                    || (change.kind == .tag && condition.kind == .tags) else { return condition }
                var updated = condition
                if let ids = condition.legacyOrganizationIDs, !ids.isEmpty {
                    guard ids.contains(change.id) else { return condition }
                    updated.organizationSelections = condition.organizationSelections.map { selection in
                        var selection = selection
                        if selection.name == change.oldName { selection.name = change.newName }
                        return selection
                    }
                } else {
                    updated.organizationSelections = condition.organizationSelections.map { selection in
                        var selection = selection
                        if selection.id == change.id || (selection.id == nil && selection.name == change.oldName) {
                            selection.name = change.newName
                        }
                        return selection
                    }
                }
                return updated
            }
            return value
        }
        if filters != resolved { filters = resolved; persist() }
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
        if let resolver = organizationResolver {
            value = resolvingReferences(in: value, using: resolver)
        }
        return value
    }

    private func resolvingReferences(in filter: SavedFilter,
                                     using resolver: ([String], [String]) -> ([UUID], [UUID])) -> SavedFilter {
        var value = filter
        if value.listIDs?.isEmpty != false, !value.listNames.isEmpty {
            let ids = resolver(value.listNames, []).0
            value.listIDs = ids.isEmpty ? nil : ids
        }
        if value.tagIDs?.isEmpty != false, !value.tags.isEmpty {
            let ids = resolver([], value.tags).1
            value.tagIDs = ids.isEmpty ? nil : ids
        }
        value.expression = value.expression?.mapConditions { condition in
            guard condition.kind == .lists || condition.kind == .tags,
                  condition.legacyOrganizationIDs?.isEmpty != false else { return condition }
            var updated = condition
            updated.organizationSelections = condition.organizationSelections.map { selection in
                guard selection.id == nil else { return selection }
                var selection = selection
                // Resolve one name at a time: an old pair of arrays never
                // establishes which ID belongs to which name.
                selection.id = condition.kind == .lists
                    ? resolver([selection.name], []).0.first
                    : resolver([], [selection.name]).1.first
                return selection
            }
            return updated
        }
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
