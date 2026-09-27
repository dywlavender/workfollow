import Combine
import Foundation

@MainActor
final class NotesWorkspaceModel: ObservableObject {
    private let store: NoteStore
    private let clock: () -> Date
    private var savedFolders: [String]
    init(initialNotes: [Note] = [], folders: [String] = [], clock: @escaping () -> Date = Date.init) {
        store = NoteStore(notes: initialNotes, clock: clock)
        savedFolders = folders
        self.clock = clock
    }
    @Published var selectedID: UUID?
    @Published var folderFilter: String?
    @Published var favoritesOnly = false
    var folders: [String] { Array(Set(savedFolders + notes.filter { $0.deletedAt == nil }.map(\.folder))).filter { $0 != "未归档" }.sorted() }
    @discardableResult func addFolder(_ rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "未归档", !folders.contains(name) else { return false }
        savedFolders = folders + [name]
        revision += 1
        return true
    }
    @discardableResult func renameFolder(_ old: String, to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "未归档", name != old, !folders.contains(name) else { return false }
        savedFolders = folders.map { $0 == old ? name : $0 }
        for note in notes where note.folder == old { store.edit(note.id) { $0.folder = name } }
        if folderFilter == old { folderFilter = name }
        revision += 1
        return true
    }
    func removeFolder(_ name: String) {
        savedFolders = folders.filter { $0 != name }
        for note in notes where note.folder == name { store.edit(note.id) { $0.folder = "未归档" } }
        if folderFilter == name { folderFilter = nil }
        revision += 1
    }
    @Published private(set) var revision = 0
    var notes: [Note] { _ = revision; return store.notes }
    var selected: Note? { notes.first { $0.id == selectedID } }
    func rows(trash: Bool, query: String, folder: String?, favorites: Bool, newestFirst: Bool = true) -> [Note] {
        notes.filter {
            ($0.deletedAt != nil) == trash &&
            (trash || folder == nil || $0.folder == folder) &&
            (trash || !favorites || $0.favorite) &&
            (query.isEmpty || ($0.title + $0.document.plainText).localizedCaseInsensitiveContains(query))
        }.sorted {
            if trash { return $0.deletedAt! > $1.deletedAt! }
            if !newestFirst { return $0.title < $1.title }
            return $0.updatedAt > $1.updatedAt
        }
    }
    func create(folder: String? = nil) {
        let id = store.create()
        if let folder { store.edit(id) { $0.folder = folder } }
        selectedID = id
        revision += 1
    }
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

    // MARK: - 任务数据接缝（Round B2 迁移）

    /// NoteStore 拿不到任务数据；由主线在 AppEnvironment 注入：
    /// `notesWorkspace.taskProvider = { [weak taskWorkspace] in taskWorkspace?.allTasks ?? [] }`。
    /// 未接线时关联任务区只显示 linkedTaskIDs 命中的任务。
    var taskProvider: (() -> [Task])?

    /// 打开关联任务的回调；由主线接 `taskWorkspace.select(id)`（必要时切换 destination）。
    var openTask: ((UUID) -> Void)?

    /// Flutter tasksLinkedToNote 语义：sourceNoteID 指向本笔记的未删除任务。
    func tasksLinkedToNote(_ note: Note) -> [Task] {
        guard let taskProvider else { return [] }
        return taskProvider().filter { $0.sourceNoteID == note.id && $0.deletedAt == nil }
    }

    /// 导入/迁移侧写入原始富文本 JSON；写入后该笔记进入受保护状态
    /// （MigrationSnapshot 属禁改文件，未来接入时调用这里）。
    func preserveOriginalContent(_ id: UUID, json: String) {
        edit(id) { $0.originalContentJson = json }
    }

    /// Flutter convertNoteToPlainText：显式创建可独立编辑的纯文本副本。
    /// 原导入笔记与其富文本源保持不动，副本成为当前选中笔记。
    /// 仅受保护（hasPreservedRichContent）的笔记可转换。
    @discardableResult
    func createPlainTextCopy(_ id: UUID) -> UUID? {
        guard let source = notes.first(where: { $0.id == id }),
              source.hasPreservedRichContent else { return nil }
        let copy = Note(id: UUID(),
                        title: notePlainTextCopyTitle(source.title),
                        document: NativeDocument(plainText: notePlainTextBody(source.document)),
                        folder: source.folder,
                        favorite: source.favorite,
                        updatedAt: clock())
        store.insert(copy)
        selectedID = copy.id
        revision += 1
        return copy.id
    }
}

/// 页脚字数统计（对齐 Flutter：去掉全部空白后按 Unicode 码点/rune 计数）。
func noteWordCount(_ text: String) -> Int {
    text.filter { !$0.isWhitespace }.unicodeScalars.count
}

/// 纯文本副本标题（Flutter：“标题（纯文本副本）”；无标题时即“（纯文本副本）”）。
func notePlainTextCopyTitle(_ title: String) -> String {
    title.isEmpty ? "（纯文本副本）" : title + "（纯文本副本）"
}

/// 纯文本副本正文：只保留文字与换行，剥离附件占位符（对象替换符 U+FFFC）。
func notePlainTextBody(_ document: NativeDocument) -> String {
    document.plainText.replacingOccurrences(of: "\u{FFFC}", with: "")
}
