import Foundation

struct NotePersistenceChange {
    var upserts: [Note] = []
    var deleted: [UUID] = []
    var order: [UUID]? = nil
    /// nil means all upserts carry new bodies (inserts); an empty set is a
    /// metadata-only edit and must not encode/rewrite the document.
    var documentIDs: Set<UUID>? = nil
}
