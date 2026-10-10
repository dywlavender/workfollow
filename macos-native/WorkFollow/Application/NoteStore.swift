import Foundation

enum NoteListSort {
    case title, recentlyEdited
}

/// Notes have their own mutation boundary; trash operations never touch tasks.
final class NoteStore {
    private(set) var notes: [Note] = []
    private let clock: () -> Date
    var onChange: ((NotePersistenceChange) -> Void)?
    init(notes: [Note] = [], clock: @escaping () -> Date = Date.init) { self.notes = notes; self.clock = clock }
    func create() -> UUID {
        let note = Note(id: UUID(), title: "", document: .empty,
                        folder: "未归档", updatedAt: clock())
        notes.insert(note, at: 0)
        onChange?(NotePersistenceChange(upserts: [note], order: notes.map(\.id)))
        return note.id
    }
    func insert(_ note: Note) {
        notes.insert(note, at: 0)
        onChange?(NotePersistenceChange(upserts: [note], order: notes.map(\.id)))
    }
    func sort(_ order: NoteListSort) {
        // Sort only on an explicit command. The array itself is persisted, so
        // later edits and reopening the app keep the resulting order.
        notes = notes.enumerated().sorted { lhs, rhs in
            switch order {
            case .title:
                if lhs.element.title != rhs.element.title { return lhs.element.title < rhs.element.title }
            case .recentlyEdited:
                if lhs.element.updatedAt != rhs.element.updatedAt { return lhs.element.updatedAt > rhs.element.updatedAt }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        onChange?(NotePersistenceChange(order: notes.map(\.id)))
    }
    func removeCreatedNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        onChange?(NotePersistenceChange(deleted: [id], order: notes.map(\.id)))
    }
    func edit(_ id: UUID, _ mutation: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        let before = notes[index]
        var after = before
        mutation(&after)
        after.updatedAt = clock()
        let documentChanged = before.document != after.document || !before.sameOriginalContent(as: after)
        if documentChanged {
            do { _ = try before.document.materialized(); _ = try before.originalContentValue() }
            catch { return }
        }
        notes[index] = after
        onChange?(NotePersistenceChange(upserts: [notes[index]], documentIDs: documentChanged ? [id] : []))
    }
    func delete(_ id: UUID) { edit(id) { $0.deletedAt = clock() } }
    func restore(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].deletedAt = nil
        notes[index].updatedAt = clock()
        onChange?(NotePersistenceChange(upserts: [notes[index]], documentIDs: []))
    }
    func purge(_ id: UUID) {
        guard notes.contains(where: { $0.id == id && $0.deletedAt != nil }) else { return }
        notes.removeAll { $0.id == id }
        onChange?(NotePersistenceChange(deleted: [id], order: notes.map(\.id)))
    }
    func emptyTrash() {
        let deleted = notes.filter { $0.deletedAt != nil }.map(\.id)
        notes.removeAll { $0.deletedAt != nil }
        onChange?(NotePersistenceChange(deleted: deleted, order: notes.map(\.id)))
    }

    // Folder operations apply to deleted notes too, so restoring one cannot
    // resurrect a removed folder. They do not count as editing the document.
    func moveFolder(_ folder: String, to destination: String, destinationID: String?) {
        var changed: [Note] = []
        for index in notes.indices where notes[index].folder == folder {
            notes[index].folder = destination
            notes[index].folderID = destinationID
            changed.append(notes[index])
        }
        onChange?(NotePersistenceChange(upserts: changed, documentIDs: []))
    }
}
