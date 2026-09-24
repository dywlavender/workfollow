import Foundation

/// Notes have their own mutation boundary; trash operations never touch tasks.
final class NoteStore {
    private(set) var notes: [Note] = []
    private let clock: () -> Date
    init(notes: [Note] = [], clock: @escaping () -> Date = Date.init) { self.notes = notes; self.clock = clock }
    func create() -> UUID {
        let note = Note(id: UUID(), title: "", document: .empty,
                        folder: "未归档", updatedAt: clock())
        notes.insert(note, at: 0)
        return note.id
    }
    func edit(_ id: UUID, _ mutation: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        mutation(&notes[index])
        notes[index].updatedAt = clock()
    }
    func delete(_ id: UUID) { edit(id) { $0.deletedAt = clock() } }
    func restore(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].deletedAt = nil
        notes[index].updatedAt = clock()
    }
    func purge(_ id: UUID) { notes.removeAll { $0.id == id && $0.deletedAt != nil } }
    func emptyTrash() { notes.removeAll { $0.deletedAt != nil } }
}
