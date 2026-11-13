import Foundation

struct ProjectFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

struct ProjectFolders: Codable, Equatable {
    static let unfiledName = "未归档"

    private(set) var folders: [ProjectFolder] = []
    private var assignments: [UUID: UUID] = [:]

    func folderID(for recordID: UUID) -> UUID? { assignments[recordID] }

    mutating func create(_ rawName: String) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != Self.unfiledName,
              !folders.contains(where: { $0.name == name }) else { return nil }
        let folder = ProjectFolder(name: name)
        folders.append(folder)
        return folder.id
    }

    mutating func rename(_ id: UUID, to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != Self.unfiledName, let index = folders.firstIndex(where: { $0.id == id }),
              !folders.contains(where: { $0.id != id && $0.name == name }) else { return false }
        folders[index].name = name
        return true
    }

    mutating func remove(_ id: UUID) {
        folders.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
    }

    mutating func move(_ recordID: UUID, to folderID: UUID?) {
        if let folderID, !folders.contains(where: { $0.id == folderID }) { return }
        assignments[recordID] = folderID
    }
}
