import Foundation

/// Note-specific fields carried by a `Task` whose kind is `.note`.
///
/// The note library is a projection over tasks, so identity, title, body,
/// attachments, trash state and timestamps stay on `Task`; only the fields the
/// task model has no equivalent for live here.
struct TaskNoteMetadata: Equatable, Codable {
    var folder: String = "未归档"
    var folderID: String? = nil
    var isFavorite: Bool = false
    var linkedTaskIDs: [UUID] = []

    /// New notes keep their protected source in the task metadata. Migrated
    /// notes keep it in the legacy `note_documents` row lazily, so opening the
    /// app must not resolve every note body.
    private var storedOriginalContent: String? = nil
    private var originalPresence: Bool? = nil
    private var deferredOriginal: DeferredOriginalContent? = nil

    init(folder: String = "未归档", folderID: String? = nil, isFavorite: Bool = false,
         linkedTaskIDs: [UUID] = [], originalContentJson: String? = nil) {
        self.folder = folder.isEmpty ? "未归档" : folder
        self.folderID = folderID
        self.isFavorite = isFavorite
        self.linkedTaskIDs = linkedTaskIDs
        storedOriginalContent = originalContentJson
        originalPresence = originalContentJson == nil ? nil : true
    }

    var originalContentJson: String? {
        get {
            if let deferredOriginal { return try? deferredOriginal.resolve() }
            return storedOriginalContent
        }
        set {
            storedOriginalContent = newValue
            originalPresence = newValue == nil ? nil : true
            deferredOriginal = nil
        }
    }

    var storedOriginalContentForMigration: String? { storedOriginalContent }
    var deferredOriginalReference: DeferredOriginalContent? { deferredOriginal }

    /// The protected source lives in the legacy note document table and is
    /// resolved on demand.
    var needsDeferredOriginal: Bool {
        storedOriginalContent == nil && (originalPresence == true || deferredOriginal?.isPresent == true)
    }

    var hasPreservedRichContent: Bool {
        deferredOriginal?.isPresent ?? (originalPresence ?? (storedOriginalContent != nil))
    }

    func originalContentValue() throws -> String? {
        try deferredOriginal?.resolve() ?? storedOriginalContent
    }

    mutating func deferOriginalContent(_ reference: DeferredOriginalContent) {
        deferredOriginal = reference
        if reference.isPresent == true { originalPresence = true }
    }

    mutating func adoptStoredOriginalContent(_ value: String?) {
        storedOriginalContent = value
        originalPresence = value == nil ? nil : true
        deferredOriginal = nil
    }

    func sameOriginalContent(as other: TaskNoteMetadata) -> Bool {
        if let reference = deferredOriginal, reference === other.deferredOriginal { return true }
        return originalContentJson == other.originalContentJson
    }

    private enum CodingKeys: String, CodingKey {
        case folder, folderID, isFavorite, linkedTaskIDs, originalContentJson, hasOriginalContent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        folder = try values.decodeIfPresent(String.self, forKey: .folder) ?? "未归档"
        if folder.isEmpty { folder = "未归档" }
        folderID = try values.decodeIfPresent(String.self, forKey: .folderID)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        linkedTaskIDs = try values.decodeIfPresent([UUID].self, forKey: .linkedTaskIDs) ?? []
        storedOriginalContent = try values.decodeIfPresent(String.self, forKey: .originalContentJson)
        let presence = try values.decodeIfPresent(Bool.self, forKey: .hasOriginalContent)
        originalPresence = storedOriginalContent == nil ? presence : true
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(folder, forKey: .folder)
        try values.encodeIfPresent(folderID, forKey: .folderID)
        try values.encode(isFavorite, forKey: .isFavorite)
        try values.encode(linkedTaskIDs, forKey: .linkedTaskIDs)
        try values.encodeIfPresent(storedOriginalContent, forKey: .originalContentJson)
        if storedOriginalContent == nil, hasPreservedRichContent {
            try values.encode(true, forKey: .hasOriginalContent)
        }
    }

    static func == (lhs: TaskNoteMetadata, rhs: TaskNoteMetadata) -> Bool {
        lhs.folder == rhs.folder && lhs.folderID == rhs.folderID
            && lhs.isFavorite == rhs.isFavorite && lhs.linkedTaskIDs == rhs.linkedTaskIDs
            && lhs.sameOriginalContent(as: rhs)
    }
}
