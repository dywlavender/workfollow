import Combine
import Foundation

@MainActor
final class NotesWorkspaceModel: ObservableObject {
    private let store: NoteStore
    init(initialNotes: [Note] = [], clock: @escaping () -> Date = Date.init) { store = NoteStore(notes: initialNotes, clock: clock) }
    @Published var selectedID: UUID?
    @Published private(set) var revision = 0
    var notes: [Note] { _ = revision; return store.notes }
    var selected: Note? { notes.first { $0.id == selectedID } }
    func rows(trash: Bool, query: String, folder: String?, favorites: Bool) -> [Note] {
        notes.filter {
            ($0.deletedAt != nil) == trash &&
            (trash || folder == nil || $0.folder == folder) &&
            (trash || !favorites || $0.favorite) &&
            (query.isEmpty || ($0.title + $0.document.plainText).localizedCaseInsensitiveContains(query))
        }.sorted {
            if trash { return $0.deletedAt! > $1.deletedAt! }
            return $0.updatedAt > $1.updatedAt
        }
    }
    func create() { selectedID = store.create(); revision += 1 }
    @discardableResult
    func createFromTask(_ task: Task, children: [Task], clock: () -> Date) -> UUID {
        var blocks = task.document.blocks
        if !children.isEmpty {
            blocks.append(contentsOf: children.map {
                DocumentBlock(kind: .checklist($0.isClosed),
                              runs: [DocumentRun(text: $0.title.isEmpty ? "无标题" : $0.title)])
            })
        }
        if !task.tags.isEmpty {
            blocks.append(DocumentBlock(kind: .paragraph,
                                        runs: [DocumentRun(text: task.tags.map { "#" + $0 }.joined(separator: " "))]))
        }
        let note = Note(id: UUID(), title: task.title, document: NativeDocument(blocks: blocks),
                        folder: "未归档", linkedTaskIDs: [task.id], attachments: task.attachments,
                        updatedAt: clock())
        store.insert(note)
        selectedID = note.id
        revision += 1
        return note.id
    }
    func discardCreatedNoteForUndo(_ id: UUID) {
        store.removeCreatedNote(id)
        if selectedID == id { selectedID = nil }
        revision += 1
    }
    func edit(_ id: UUID, _ mutation: (inout Note) -> Void) { store.edit(id, mutation); revision += 1 }
    func delete(_ id: UUID) { store.delete(id); selectedID = nil; revision += 1 }
    func restore(_ id: UUID) { store.restore(id); selectedID = nil; revision += 1 }
    func purge(_ id: UUID) { store.purge(id); selectedID = nil; revision += 1 }
    func emptyTrash() { store.emptyTrash(); selectedID = nil; revision += 1 }
}
