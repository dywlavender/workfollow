import Foundation

struct Note: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var document: NativeDocument
    var folder: String
    var favorite = false
    var linkedTaskIDs: [UUID] = []
    var attachments: [NativeAttachment] = []
    var updatedAt: Date
    var deletedAt: Date?
}
