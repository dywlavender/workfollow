import Foundation

/// Stable folder identity and migration ordering, retained independently from
/// the flat folder-name presentation used by the current Native notes UI.
struct NoteFolderMeta: Identifiable, Equatable, Codable {
    var id: String
    var parentID: String?
    var name: String
    var sortOrder: Int
    var createdAt: String?
    var updatedAt: String?
}

struct Note: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var document: NativeDocument
    var folder: String
    var folderID: String? = nil
    var favorite = false
    var linkedTaskIDs: [UUID] = []
    var attachments: [NativeAttachment] = []
    var updatedAt: Date
    var deletedAt: Date?
    /// 导入富文本笔记时保留的原始文档 JSON（对齐 Flutter originalContentJson）。
    /// additive Codable：旧快照没有该键时解码为 nil；写入后原文受保护，
    /// 只有显式“创建纯文本副本”才产生可自由编辑的新笔记。
    private var originalContent: String? = nil
    private var deferredOriginal: DeferredOriginalContent?
    var originalContentJson: String? {
        get { if let deferredOriginal { return try? deferredOriginal.resolve() }; return originalContent }
        set { originalContent = newValue; deferredOriginal = nil }
    }
    mutating func deferOriginalContent(_ reference: DeferredOriginalContent) { deferredOriginal = reference }
    func originalContentValue() throws -> String? { try deferredOriginal?.resolve() ?? originalContent }
    func sameOriginalContent(as other: Note) -> Bool {
        if let reference = deferredOriginal, reference === other.deferredOriginal { return true }
        return originalContentJson == other.originalContentJson
    }
    init(id: UUID, title: String, document: NativeDocument, folder: String, folderID: String? = nil,
         favorite: Bool = false, linkedTaskIDs: [UUID] = [], attachments: [NativeAttachment] = [],
         updatedAt: Date, deletedAt: Date? = nil, originalContentJson: String? = nil) {
        self.id = id; self.title = title; self.document = document; self.folder = folder; self.folderID = folderID
        self.favorite = favorite; self.linkedTaskIDs = linkedTaskIDs; self.attachments = attachments
        self.updatedAt = updatedAt; self.deletedAt = deletedAt; self.originalContent = originalContentJson
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, document, folder, folderID, favorite, linkedTaskIDs, attachments, updatedAt, deletedAt, originalContentJson
    }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        id = try v.decode(UUID.self, forKey: .id); title = try v.decode(String.self, forKey: .title)
        document = try v.decode(NativeDocument.self, forKey: .document); folder = try v.decode(String.self, forKey: .folder)
        folderID = try v.decodeIfPresent(String.self, forKey: .folderID); favorite = try v.decode(Bool.self, forKey: .favorite)
        linkedTaskIDs = try v.decode([UUID].self, forKey: .linkedTaskIDs)
        attachments = try v.decode([NativeAttachment].self, forKey: .attachments)
        updatedAt = try v.decode(Date.self, forKey: .updatedAt); deletedAt = try v.decodeIfPresent(Date.self, forKey: .deletedAt)
        originalContent = try v.decodeIfPresent(String.self, forKey: .originalContentJson)
    }
    func encode(to encoder: Encoder) throws {
        var v = encoder.container(keyedBy: CodingKeys.self)
        try v.encode(id, forKey: .id); try v.encode(title, forKey: .title); try v.encode(document, forKey: .document)
        try v.encode(folder, forKey: .folder); try v.encodeIfPresent(folderID, forKey: .folderID)
        try v.encode(favorite, forKey: .favorite); try v.encode(linkedTaskIDs, forKey: .linkedTaskIDs)
        try v.encode(attachments, forKey: .attachments); try v.encode(updatedAt, forKey: .updatedAt)
        try v.encodeIfPresent(deletedAt, forKey: .deletedAt)
        let original = try originalContentValue()
        try v.encodeIfPresent(original, forKey: .originalContentJson)
    }
    static func == (a: Note, b: Note) -> Bool {
        a.id == b.id && a.title == b.title && a.document == b.document && a.folder == b.folder && a.folderID == b.folderID &&
        a.favorite == b.favorite && a.linkedTaskIDs == b.linkedTaskIDs && a.attachments == b.attachments &&
        a.updatedAt == b.updatedAt && a.deletedAt == b.deletedAt && a.sameOriginalContent(as: b)
    }

    /// Flutter hasPreservedRichContent 语义：存在保留的原始内容即视为受保护。
    var hasPreservedRichContent: Bool { deferredOriginal?.isPresent ?? (originalContentJson != nil) }
}
