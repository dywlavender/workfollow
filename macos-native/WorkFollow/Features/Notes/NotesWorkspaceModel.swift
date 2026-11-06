import Combine
import Foundation

/// Notes are `Task(kind: .note)` now. This model is the Notes-page projection:
/// it keeps the folder/favorite/linked-task API used by the view, while every
/// read and write goes through the same task store and history as the task page.
@MainActor
final class NotesWorkspaceModel: ObservableObject {
    @Published private(set) var revealRequest: UUID?
    /// 搜索面板打开笔记后的一次性定位请求；消费后清空。
    @Published private(set) var searchRevealRequest: SearchRevealRequest?

    func reveal(_ id: UUID) {
        folderFilter = nil; favoritesOnly = false; selectedID = id
        revealRequest = UUID()
    }

    func requestSearchReveal(noteID: UUID, query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchRevealRequest = SearchRevealRequest(targetID: noteID, query: trimmed)
    }

    func consumeSearchReveal(for noteID: UUID) -> SearchRevealRequest? {
        guard let request = searchRevealRequest, request.targetID == noteID else { return nil }
        searchRevealRequest = nil
        return request
    }
    private let taskWorkspace: TaskWorkspaceModel
    private let clock: () -> Date
    private let layoutDefaults: UserDefaults?
    private static let aiPaneVisibleDefaultsKey = "notes.ai.paneVisible"
    private static let expandedFoldersDefaultsKey = "notes.expandedFolders"
    private var savedFolders: [String]
    private var folderRecords: [NoteFolderMeta]
    private var taskSubscription: AnyCancellable?

    /// 笔记页右侧 AI 栏的展开状态：纯界面状态，随布局偏好一起保存。
    @Published var aiPaneVisible = false {
        didSet {
            layoutDefaults?.set(aiPaneVisible, forKey: Self.aiPaneVisibleDefaultsKey)
        }
    }

    /// 树里展开的文件夹 ID。纯界面状态，单独持久化，绝不复用 `revision`：
    /// AppEnvironment 订阅 `$revision` 写盘，折叠一次触发一次 SQLite 写太重。
    @Published var expandedFolderIDs: Set<String> = [] {
        didSet {
            layoutDefaults?.set(Array(expandedFolderIDs).sorted(),
                                forKey: Self.expandedFoldersDefaultsKey)
        }
    }

    func isFolderExpanded(_ id: String) -> Bool { expandedFolderIDs.contains(id) }

    func setFolderExpanded(_ id: String, _ expanded: Bool) {
        if expanded { expandedFolderIDs.insert(id) } else { expandedFolderIDs.remove(id) }
    }

    /// 打开某一篇笔记时，把它的父文件夹链全部展开（单击文件夹本身不改正文）。
    func expandAncestors(ofFolderNamed name: String) {
        guard let record = folderRecords.first(where: { $0.name == name }) else { return }
        var seen = Set<String>()
        var cursor = record.parentID
        while let current = cursor, seen.insert(current).inserted {
            expandedFolderIDs.insert(current)
            cursor = folderRecords.first(where: { $0.id == current })?.parentID
        }
        expandedFolderIDs.insert(record.id)
    }

    /// Standalone initializer used by notes-only tests and previews. The app
    /// injects its shared `TaskWorkspaceModel` through the initializer below.
    init(initialNotes: [Note] = [], folders: [String] = [],
         folderMetadata: [NoteFolderMeta] = [], clock: @escaping () -> Date = Date.init,
         layoutDefaults: UserDefaults? = nil) {
        self.clock = clock
        self.layoutDefaults = layoutDefaults
        taskWorkspace = TaskWorkspaceModel(clock: clock, seedDemoData: false,
                                          initialTasks: initialNotes.map { $0.migratedTask() })
        savedFolders = folders
        folderRecords = folderMetadata
        bootstrapFolders(initialNotes: initialNotes)
        bindTaskWorkspace()
        aiPaneVisible = layoutDefaults?.object(forKey: Self.aiPaneVisibleDefaultsKey) as? Bool ?? false
        if let stored = layoutDefaults?.stringArray(forKey: Self.expandedFoldersDefaultsKey) {
            expandedFolderIDs = Set(stored)
        } else {
            // 新笔记默认落在「未归档」，首次进入必须展开，否则刚建的笔记看不见。
            expandedFolderIDs = [NoteFolderTree.unfiledNodeID]
        }
    }

    init(taskWorkspace: TaskWorkspaceModel, folders: [String] = [],
         folderMetadata: [NoteFolderMeta] = [], clock: @escaping () -> Date = Date.init,
         layoutDefaults: UserDefaults? = nil) {
        self.clock = clock
        self.taskWorkspace = taskWorkspace
        self.layoutDefaults = layoutDefaults
        savedFolders = folders
        folderRecords = folderMetadata
        bootstrapFolders(initialNotes: taskWorkspace.noteTasks.map(Note.init(task:)))
        bindTaskWorkspace()
        aiPaneVisible = layoutDefaults?.object(forKey: Self.aiPaneVisibleDefaultsKey) as? Bool ?? false
        if let stored = layoutDefaults?.stringArray(forKey: Self.expandedFoldersDefaultsKey) {
            expandedFolderIDs = Set(stored)
        } else {
            // 新笔记默认落在「未归档」，首次进入必须展开，否则刚建的笔记看不见。
            expandedFolderIDs = [NoteFolderTree.unfiledNodeID]
        }
    }

    private func bootstrapFolders(initialNotes: [Note]) {
        let allNames = savedFolders + folderRecords.map(\.name) + initialNotes.map(\.folder)
        var knownNames = Set(folderRecords.map(\.name))
        for name in allNames where name != "未归档" && knownNames.insert(name).inserted {
            folderRecords.append(NoteFolderMeta(id: UUID().uuidString, parentID: nil,
                                                name: name, sortOrder: folderRecords.count,
                                                createdAt: nil, updatedAt: nil))
        }
        // 迁移快照里的 parentId 可能悬空或成环；读档后统一清洗一次，
        // 后面所有树遍历与展开操作都能假定父链无环。
        folderRecords = NoteFolderTree.sanitized(folderRecords)
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
        let ordered = folders.enumerated().map { index, name in
            var record = recordsByName[name]
                ?? NoteFolderMeta(id: UUID().uuidString, parentID: nil, name: name,
                                  sortOrder: index, createdAt: nil, updatedAt: nil)
            record.sortOrder = index
            return record
        }
        return NoteFolderTree.sanitized(ordered)
    }

    func folderID(named name: String) -> String? {
        folderRecords.first { $0.name == name }?.id
    }

    // MARK: - 文件夹层级

    /// 树视图用的深度优先节点序列。
    var folderNodes: [NoteFolderNode] { NoteFolderTree.nodes(from: folderRecords) }

    var folderRecordsForTree: [NoteFolderMeta] { folderRecords }

    func folderName(forNodeID id: String) -> String? {
        folderRecords.first { $0.id == id }?.name
    }

    /// 正文面包屑：从根到当前文件夹的完整路径（含自己）。
    func folderPath(named name: String) -> [String] {
        guard name != NoteFolderTree.unfiledName,
              let record = folderRecords.first(where: { $0.name == name }) else { return [name] }
        return NoteFolderTree.path(toID: record.id, in: folderRecords) + [name]
    }

    /// 树里某个文件夹直属的笔记；搜索与收藏作用域沿用 `rows` 的口径。
    func notes(inFolderNamed name: String, query: String, favorites: Bool) -> [Note] {
        rows(trash: false, query: query, folder: name, favorites: favorites)
    }

    /// 把文件夹挂到另一个文件夹下（nil = 根目录）。禁止挂到自己或自己的后代。
    @discardableResult
    func moveFolder(id: String, under parentID: String?) -> Bool {
        guard let index = folderRecords.firstIndex(where: { $0.id == id }),
              NoteFolderTree.canMove(folderID: id, under: parentID, in: folderRecords) else { return false }
        let resolved = folderRecords.contains { $0.id == parentID } ? parentID : nil
        folderRecords[index].parentID = resolved
        revision += 1
        return true
    }

    /// 在指定父节点下新建子文件夹，返回新 ID；名字仍要求全局唯一。
    @discardableResult func addFolder(_ rawName: String, parentID: String?) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != NoteFolderTree.unfiledName, !folders.contains(name) else { return nil }
        let resolved = folderRecords.contains { $0.id == parentID } ? parentID : nil
        let record = NoteFolderMeta(id: UUID().uuidString, parentID: resolved,
                                    name: name, sortOrder: folderRecords.count,
                                    createdAt: nil, updatedAt: nil)
        savedFolders = folders + [name]
        folderRecords.append(record)
        if let resolved { expandedFolderIDs.insert(resolved) }
        revision += 1
        return record.id
    }

    @discardableResult func addFolder(_ rawName: String) -> Bool {
        addFolder(rawName, parentID: nil) != nil
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
        let removedID = folderRecords.first { $0.name == name }?.id
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
        // 子文件夹提升为根：笔记仍留在子文件夹里，不跟着回落到未归档。
        if let removedID {
            for index in folderRecords.indices where folderRecords[index].parentID == removedID {
                folderRecords[index].parentID = nil
            }
        }
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
    func create(folder: String? = nil, title: String = "", document: NativeDocument = .empty,
                select: Bool = true) -> UUID {
        let name = folder ?? "未归档"
        let id = taskWorkspace.createNote(title: title, document: document,
                                          folder: name, folderID: folderID(named: name)) ?? UUID()
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

    /// 笔记正文的检查项/行内日期提醒写入。笔记即任务实体，落盘与通知排程
    /// 复用任务存储的同一条事务路径（`TaskReminderPlan` 扫描正文里带提醒的
    /// 检查项与普通段落，笔记任务同样在扫描范围内）。
    @discardableResult
    func setChecklistItemReminder(_ id: UUID, line: Int, at date: Date?) -> TaskActionResult {
        taskWorkspace.setChecklistItemReminder(id, line: line, at: date)
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
