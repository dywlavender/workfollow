import Combine
import Foundation

/// Notes are `Task(kind: .note)` now. This model is the Notes-page projection:
/// it keeps the folder/favorite/linked-task API used by the view, while every
/// read and write goes through the same task store and history as the task page.
@MainActor
final class NotesWorkspaceModel: ObservableObject {
    @Published private(set) var revealRequest: UUID?

    func reveal(_ id: UUID) {
        folderFilter = nil; favoritesOnly = false; selectedID = id
        revealRequest = UUID()
    }
    private let taskWorkspace: TaskWorkspaceModel
    private let clock: () -> Date
    private var savedFolders: [String]
    private var folderRecords: [NoteFolderMeta]
    private var taskSubscription: AnyCancellable?

    /// Standalone initializer used by notes-only tests and previews. The app
    /// injects its shared `TaskWorkspaceModel` through the initializer below.
    init(initialNotes: [Note] = [], folders: [String] = [],
         folderMetadata: [NoteFolderMeta] = [], clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        taskWorkspace = TaskWorkspaceModel(clock: clock, seedDemoData: false,
                                          initialTasks: initialNotes.map { $0.migratedTask() })
        savedFolders = folders
        folderRecords = folderMetadata
        bootstrapFolders(initialNotes: initialNotes)
        bindTaskWorkspace()
    }

    init(taskWorkspace: TaskWorkspaceModel, folders: [String] = [],
         folderMetadata: [NoteFolderMeta] = [], clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        self.taskWorkspace = taskWorkspace
        savedFolders = folders
        folderRecords = folderMetadata
        bootstrapFolders(initialNotes: taskWorkspace.noteTasks.map(Note.init(task:)))
        bindTaskWorkspace()
    }

    private func bootstrapFolders(initialNotes: [Note]) {
        let allNames = savedFolders + folderRecords.map(\.name) + initialNotes.map(\.folder)
        var knownNames = Set(folderRecords.map(\.name))
        for name in allNames where name != "未归档" && knownNames.insert(name).inserted {
            folderRecords.append(NoteFolderMeta(id: UUID().uuidString, parentID: nil,
                                                name: name, sortOrder: folderRecords.count,
                                                createdAt: nil, updatedAt: nil))
        }
    }

    private func bindTaskWorkspace() {
        taskSubscription = taskWorkspace.$revision.dropFirst().sink { [weak self] _ in
            self?.revision += 1
        }
    }

    @Published var selectedID: UUID?
    @Published var folderFilter: String?
    @Published var favoritesOnly = false
    var folders: [String] {
        let names = Array(Set(savedFolders + folderRecords.map(\.name)
                              + notes.filter { $0.deletedAt == nil }.map(\.folder)))
            .filter { $0 != "未归档" }
        let orderByName = Dictionary(folderRecords.map { ($0.name, $0.sortOrder) },
                                     uniquingKeysWith: { current, _ in current })
        return names.sorted { lhs, rhs in
            let left = orderByName[lhs] ?? Int.max
            let right = orderByName[rhs] ?? Int.max
            if left != right { return left < right }
            return lhs.localizedCompare(rhs) == .orderedAscending
        }
    }
    var folderMetadataForPersistence: [NoteFolderMeta] {
        let recordsByName = Dictionary(folderRecords.map { ($0.name, $0) },
                                       uniquingKeysWith: { current, _ in current })
        return folders.enumerated().map { index, name in
            var record = recordsByName[name]
                ?? NoteFolderMeta(id: UUID().uuidString, parentID: nil, name: name,
                                  sortOrder: index, createdAt: nil, updatedAt: nil)
            record.sortOrder = index
            return record
        }
    }

    func folderID(named name: String) -> String? {
        folderRecords.first { $0.name == name }?.id
    }

    @discardableResult func addFolder(_ rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "未归档", !folders.contains(name) else { return false }
        savedFolders = folders + [name]
        folderRecords.append(NoteFolderMeta(id: UUID().uuidString, parentID: nil,
                                            name: name, sortOrder: folderRecords.count,
                                            createdAt: nil, updatedAt: nil))
        revision += 1
        return true
    }

    @discardableResult func renameFolder(_ old: String, to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "未归档", name != old, !folders.contains(name) else { return false }
        let folderID = self.folderID(named: old)
        if let index = folderRecords.firstIndex(where: { $0.name == old }) {
            folderRecords[index].name = name
        }
        savedFolders = folders.map { $0 == old ? name : $0 }
        for note in notes where note.folder == old {
            taskWorkspace.editNote(note.id, allowDeleted: true) { task in
                var meta = task.note ?? TaskNoteMetadata()
                meta.folder = name
                meta.folderID = folderID
                task.note = meta
            }
        }
        if folderFilter == old { folderFilter = name }
        revision += 1
        return true
    }

    func removeFolder(_ name: String) {
        savedFolders = folders.filter { $0 != name }
        for note in notes where note.folder == name {
            taskWorkspace.editNote(note.id, allowDeleted: true) { task in
                var meta = task.note ?? TaskNoteMetadata()
                meta.folder = "未归档"
                meta.folderID = nil
                task.note = meta
            }
        }
        folderRecords.removeAll { $0.name == name }
        if folderFilter == name { folderFilter = "未归档" }
        revision += 1
    }

    @Published private(set) var revision = 0
    var notes: [Note] {
        _ = revision
        return taskWorkspace.noteTasks.map(Note.init(task:))
    }
    var selected: Note? { notes.first { $0.id == selectedID } }

    func rows(trash: Bool, query: String, folder: String?, favorites: Bool) -> [Note] {
        let filtered = notes.filter {
            ($0.deletedAt != nil) == trash &&
            (trash || folder == nil || $0.folder == folder) &&
            (trash || !favorites || $0.favorite) &&
            (query.isEmpty || $0.document.matches(query, prefix: $0.title))
        }
        return trash ? filtered.sorted { $0.deletedAt! > $1.deletedAt! } : filtered
    }

    func sort(_ order: NoteListSort) {
        _ = taskWorkspace.sortNotes(byTitle: order == .title)
        revision += 1
    }

    @discardableResult
    func create(folder: String? = nil, select: Bool = true) -> UUID {
        let name = folder ?? "未归档"
        let id = taskWorkspace.createNote(folder: name, folderID: folderID(named: name)) ?? UUID()
        if select { selectedID = id }
        revision += 1
        return id
    }

    /// 悬浮窗关闭时只丢弃“本次浮窗新建且仍未写任何内容”的笔记，
    /// 不把已有空笔记或已进垃圾桶的笔记一起清掉。
    @discardableResult
    func discardEmptyNote(_ id: UUID) -> Bool {
        guard let note = notes.first(where: { $0.id == id }),
              note.deletedAt == nil,
              note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              note.document.isEmpty else { return false }
        taskWorkspace.discardNoteForCompensation(id)
        if selectedID == id { selectedID = nil }
        revision += 1
        return true
    }

    func moveNoteToFolder(_ id: UUID, named folder: String) {
        let folderID = self.folderID(named: folder)
        taskWorkspace.editNote(id) { task in
            var meta = task.note ?? TaskNoteMetadata()
            meta.folder = folder
            meta.folderID = folderID
            task.note = meta
        }
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
        let noteID = taskWorkspace.createNote(title: task.title,
                                              document: NativeDocument(blocks: blocks),
                                              folder: "未归档") ?? UUID()
        taskWorkspace.editNote(noteID) { noteTask in
            noteTask.attachments = task.attachments
            var meta = noteTask.note ?? TaskNoteMetadata()
            meta.linkedTaskIDs = [task.id]
            noteTask.note = meta
        }
        selectedID = noteID
        revision += 1
        return noteID
    }

    func discardCreatedNoteForUndo(_ id: UUID) {
        taskWorkspace.discardNoteForCompensation(id)
        if selectedID == id { selectedID = nil }
        revision += 1
    }

    func restoreCreatedNoteForRedo(_ note: Note) {
        guard !notes.contains(where: { $0.id == note.id }) else { return }
        taskWorkspace.restoreNoteForCompensation(note)
        selectedID = note.id
        revision += 1
    }

    func edit(_ id: UUID, _ mutation: (inout Note) -> Void) {
        taskWorkspace.editNote(id) { task in
            var note = Note(task: task)
            mutation(&note)
            Self.apply(note: note, to: &task)
        }
    }

    private static func apply(note: Note, to task: inout Task) {
        task.title = note.title
        task.document = note.document
        task.attachments = note.attachments
        task.deletedAt = note.deletedAt
        var meta = task.note ?? TaskNoteMetadata()
        meta.folder = note.folder.isEmpty ? "未归档" : note.folder
        meta.folderID = note.folderID
        meta.isFavorite = note.favorite
        meta.linkedTaskIDs = note.linkedTaskIDs
        let storedChanged = note.storedOriginalContentForMigration != meta.storedOriginalContentForMigration
        let referenceChanged = note.deferredOriginalReference !== meta.deferredOriginalReference
        if storedChanged || referenceChanged {
            if let stored = note.storedOriginalContentForMigration {
                meta.adoptStoredOriginalContent(stored)
            } else if let reference = note.deferredOriginalReference {
                meta.deferOriginalContent(reference)
            } else {
                meta.adoptStoredOriginalContent(nil)
            }
        }
        task.note = meta
    }

    /// Note → task keeps the same id and body; the task page projection picks
    /// the row up again in its original list (or the inbox for `.notes`).
    @discardableResult
    func convertToTask(_ id: UUID) -> TaskActionResult {
        guard taskWorkspace.task(for: id)?.isNoteTask == true else { return .failure(.missingTask) }
        let result = taskWorkspace.setKind(id, .text)
        if result.taskID != nil, selectedID == id { selectedID = nil }
        revision += 1
        return result
    }

    func delete(_ id: UUID) { _ = taskWorkspace.deleteNote(id); selectedID = nil }
    func restore(_ id: UUID) { _ = taskWorkspace.restoreNote(id); selectedID = nil }
    func purge(_ id: UUID) { _ = taskWorkspace.purgeNote(id); selectedID = nil }
    func emptyTrash() { _ = taskWorkspace.emptyNoteTrash(); selectedID = nil }

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
        taskWorkspace.editNote(id) { task in
            var meta = task.note ?? TaskNoteMetadata()
            meta.originalContentJson = json
            task.note = meta
        }
    }

    /// Flutter convertNoteToPlainText：显式创建可独立编辑的纯文本副本。
    /// 原导入笔记与其富文本源保持不动，副本成为当前选中笔记。
    /// 仅受保护（hasPreservedRichContent）的笔记可转换。
    @discardableResult
    func createPlainTextCopy(_ id: UUID) -> UUID? {
        guard let source = notes.first(where: { $0.id == id }),
              source.hasPreservedRichContent, (try? source.document.materialized()) != nil else { return nil }
        guard let copyID = taskWorkspace.createNote(
            title: notePlainTextCopyTitle(source.title),
            document: NativeDocument(plainText: notePlainTextBody(source.document)),
            folder: source.folder, folderID: source.folderID) else { return nil }
        if source.favorite {
            taskWorkspace.editNote(copyID) { task in
                var meta = task.note ?? TaskNoteMetadata()
                meta.isFavorite = true
                task.note = meta
            }
        }
        selectedID = copyID
        revision += 1
        return copyID
    }

    func createAIRewrite(_ text: String, request: NoteRewriteRequest, select: Bool = true) throws -> UUID {
        guard let source = notes.first(where: { $0.id == request.noteID && $0.deletedAt == nil }) else {
            throw AITaskError.sourceMissing
        }
        let body = DocumentExternalClipboardCodec.fragment(fromMarkdown: text)?.document ?? NativeDocument(plainText: text)
        let link = DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "来源："),
            DocumentRun(text: request.title, marks: [.link(NativeResourceLink.note(source.id).url.absoluteString)])])
        guard let id = taskWorkspace.createNote(title: request.title + "（\(request.action.suffix)）",
            document: NativeDocument(blocks: [link] + body.blocks), folder: source.folder, folderID: source.folderID) else {
            throw AITaskError.sourceMissing
        }
        if select { selectedID = id }
        revision += 1
        return id
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
