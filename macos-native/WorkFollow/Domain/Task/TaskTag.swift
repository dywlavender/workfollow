import Foundation

/// The directory owns tag identity and presentation, including unused tags.
/// TaskTagReference uses this same ID when a task is assigned to the tag.
struct TaskTag: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var colorARGB: UInt32?
    var sortOrder: Int
    var parentID: UUID?

    init(id: UUID = UUID(), name: String, colorARGB: UInt32? = nil,
         sortOrder: Int = 0, parentID: UUID? = nil) {
        self.id = id
        self.name = Self.normalizedName(name) ?? ""
        self.colorARGB = colorARGB
        self.sortOrder = sortOrder
        self.parentID = parentID
    }

    private enum CodingKeys: String, CodingKey { case id, name, colorARGB, sortOrder, parentID }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        colorARGB = try values.decodeIfPresent(UInt32.self, forKey: .colorARGB)
        sortOrder = try values.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        parentID = try values.decodeIfPresent(UUID.self, forKey: .parentID)
    }

    static func normalizedName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Depth-first display order; sortOrder is local to each parent.
    static func ordered(_ tags: [TaskTag]) -> [TaskTag] {
        let sorted = tags.enumerated().sorted {
            $0.element.sortOrder == $1.element.sortOrder
                ? $0.offset < $1.offset
                : $0.element.sortOrder < $1.element.sortOrder
        }.map(\.element)
        let children = Dictionary(grouping: sorted, by: \.parentID)
        var result: [TaskTag] = []
        var visited = Set<UUID>()
        func append(_ tag: TaskTag) {
            guard visited.insert(tag.id).inserted else { return }
            result.append(tag)
            for child in children[tag.id] ?? [] { append(child) }
        }
        for tag in children[nil] ?? [] { append(tag) }
        for tag in sorted where !visited.contains(tag.id) { append(tag) }
        return result
    }

    /// Add legacy task labels without replacing explicit records or existing IDs.
    /// References are examined before names so migration can adopt their identity.
    static func reconciled(_ directory: [TaskTag], tasks: [Task]) -> [TaskTag] {
        var result = directory
        var names = Set(directory.map(\.name))
        var ids = Set(directory.map(\.id))
        var nextOrder = (directory.filter { $0.parentID == nil }.map(\.sortOrder).max() ?? -1) + 1
        let references = tasks.flatMap { ($0.tagReferences ?? []) + ($0.series?.template.tagReferences ?? []) }
        var referenceIDs: [String: UUID] = [:]
        for reference in references {
            guard let name = normalizedName(reference.name) else { continue }
            referenceIDs[name] = referenceIDs[name] ?? reference.id
            guard !ids.contains(reference.id), names.insert(name).inserted else { continue }
            result.append(TaskTag(id: reference.id, name: name, sortOrder: nextOrder))
            ids.insert(reference.id)
            nextOrder += 1
        }
        for raw in tasks.flatMap({ $0.tags + ($0.series?.template.tags ?? []) }) {
            guard let name = normalizedName(raw), !names.contains(name) else { continue }
            if let referenceID = referenceIDs[name], ids.contains(referenceID) { continue }
            let tag = TaskTag(name: name, sortOrder: nextOrder)
            result.append(tag)
            names.insert(name); ids.insert(tag.id)
            nextOrder += 1
        }
        let startOrder = (directory.filter { $0.parentID == nil }.map(\.sortOrder).max() ?? -1) + 1
        let additions = result.dropFirst(directory.count).sorted { $0.name < $1.name }
            .enumerated().map { index, tag in
                var value = tag
                value.sortOrder = startOrder + index
                return value
            }
        return directory + additions
    }
}
