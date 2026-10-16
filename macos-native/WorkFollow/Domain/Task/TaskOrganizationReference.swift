import Foundation

struct TaskTagReference: Equatable, Codable, Identifiable {
    var id: UUID
    var name: String
}

struct TaskOrganizationRename {
    enum Kind: String { case list, tag }
    var kind: Kind
    var id: UUID
    var oldName: String
    var newName: String
}

extension Notification.Name {
    static let workspaceOrganizationRenamed = Notification.Name("workspaceOrganizationRenamed")
}
