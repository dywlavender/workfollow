import Foundation

struct TaskTagPickerSession {
    var query: String = ""
    private(set) var selectedTags: Set<String>

    /// Tags owned by this draft stay in its catalog even when deselected.
    private var localCatalog: [String]

    init(initialTags: [String]) {
        let initial = Self.uniqueTags(initialTags)
        selectedTags = Set(initial)
        localCatalog = initial
    }

    func allTags(availableTags: [String]) -> [String] {
        Self.uniqueTags(availableTags + localCatalog).sorted()
    }

    func matchingTags(availableTags: [String]) -> [String] {
        let tags = allTags(availableTags: availableTags)
        guard let needle = Self.normalizedTag(query) else { return tags }
        return tags.filter { $0.localizedCaseInsensitiveContains(needle) }
    }

    func creatableTags(availableTags: [String]) -> [String] {
        let existing = Set(allTags(availableTags: availableTags))
        var seen = Set<String>()

        return query
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .compactMap(Self.normalizedTag)
            .filter { !existing.contains($0) && seen.insert($0).inserted }
    }

    mutating func toggle(_ tag: String) {
        guard let tag = Self.normalizedTag(tag) else { return }
        remember(tag)
        if !selectedTags.insert(tag).inserted {
            selectedTags.remove(tag)
        }
    }

    mutating func createFromQuery(availableTags: [String]) {
        let created = creatableTags(availableTags: availableTags)
        for tag in created {
            remember(tag)
        }
        selectedTags.formUnion(created)
        query = ""
    }

    private mutating func remember(_ tag: String) {
        guard !localCatalog.contains(tag) else { return }
        localCatalog.append(tag)
    }

    private static func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap(Self.normalizedTag).filter { seen.insert($0).inserted }
    }

    /// Picker-local cleanup trims whitespace and surrounding hash markers while
    /// keeping tag identity case-sensitive.
    private static func normalizedTag(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let unmarked = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = unmarked.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
