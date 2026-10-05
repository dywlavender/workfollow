import Foundation

/// Single in-memory authority for Phase 2. UI integration and Repository come later.
final class WorkspaceStore {
    enum UndoPolicy { case record, skip }
    private(set) var tasks: [Task] = [] {
        didSet {
            readRevision += 1
            taskOffsets = nil
            childOffsets = nil
        }
    }
    private(set) var readRevision = 0
    private(set) var readIndexBuildCount = 0
    private(set) var fullDiffBuildCount = 0
    private var taskOffsets: [UUID: Int]?
    private var childOffsets: [UUID: [Int]]?
    private(set) var lists: [String] = []
    /// 侧栏清单元数据（Round B1）：与 lists 一一对应、顺序一致，sortOrder 即数组下标。
    /// 只覆盖 store 注册过的清单；随 commit/undo/transaction 与 lists 同步进退。
    private(set) var listMetas: [TaskListMeta] = []
    /// 清单文件夹（滴答层级第一级）。**独立于 lists**：允许空文件夹，
    /// 随 commit/undo/transaction 与清单同进同退。
    private(set) var listFolders: [TaskListFolder] = []
    private var undoLists: [[String]] = []
    private var undoListMetas: [[TaskListMeta]] = []
    private var undoListFolders: [[TaskListFolder]] = []
    /// 清单内自定义分组（滴答第三级）。与清单/文件夹一样随 commit/undo 同步进退。
    private(set) var listSections: [TaskListSection] = []
    private var undoListSections: [[TaskListSection]] = []
    private var undoCompensations: [(() -> Void)?] = []
    private var transactionDepth = 0
    private var undoSnapshots: [[Task]] = []
    private struct TextRebase {
        var title: String
        var document: NativeDocument
        var updatedAt: Date
        var rebasesText = false
        var rebasesSourceNote = false
        var sourceNoteID: UUID?

        init(_ task: Task) {
            title = task.title
            document = task.document
            updatedAt = task.updatedAt
        }

        func applying(to task: Task) -> Task {
            var value = task
            if rebasesText {
                value.title = title
                value.document = document
            }
            value.updatedAt = updatedAt
            if rebasesSourceNote { value.sourceNoteID = sourceNoteID }
            return value
        }
    }
    /// Per-step overlays preserve text without copying every historical array
    /// on each keystroke. New business steps start with an empty overlay.
    private var undoTextRebases: [[UUID: TextRebase]] = []
    var canUndo: Bool { !undoSnapshots.isEmpty }
    /// Compatibility callback for consumers that still need full snapshots.
    var onTasksChanged: (([Task], [Task]) -> Void)?
    /// Emits the task-level diff once per commit, undo, or outer transaction.
    var onTaskChanges: ((TaskChangeSet) -> Void)?

    private func prepareReadIndex() {
        guard taskOffsets == nil else { return }
        readIndexBuildCount += 1
        var byID: [UUID: Int] = [:]
        var byParent: [UUID: [Int]] = [:]
        for (offset, task) in tasks.enumerated() {
            if byID[task.id] == nil { byID[task.id] = offset }
            if let parent = task.parentID { byParent[parent, default: []].append(offset) }
        }
        taskOffsets = byID
        childOffsets = byParent
    }

    func task(_ id: UUID) -> Task? {
        prepareReadIndex()
        return taskOffsets?[id].map { tasks[$0] }
    }

    func children(of id: UUID, includingDeleted: Bool = false) -> [Task] {
        prepareReadIndex()
        return (childOffsets?[id] ?? []).map { tasks[$0] }
            .filter { $0.skippedAt == nil && (includingDeleted || $0.deletedAt == nil) }
            .sorted { $0.childOrder < $1.childOrder }
    }

    func listMeta(for name: String) -> TaskListMeta? {
        listMetas.first { $0.name == name }
    }

    func listFolder(named name: String) -> TaskListFolder? {
        listFolders.first { $0.name == name }
    }

    func listSection(_ id: String) -> TaskListSection? {
        listSections.first { $0.id == id }
    }

    // Only application commands commit snapshots; readers receive value copies.
    func commit(_ snapshot: [Task], undoPolicy: UndoPolicy = .record,
                lists: [String]? = nil, listMetas: [TaskListMeta]? = nil,
                listFolders: [TaskListFolder]? = nil,
                listSections: [TaskListSection]? = nil,
                undoCompensation: (() -> Void)? = nil) {
        let listsChanged = lists != nil && lists != self.lists
        let metasChanged = listMetas != nil && listMetas != self.listMetas
        let foldersChanged = listFolders != nil && listFolders != self.listFolders
        let sectionsChanged = listSections != nil && listSections != self.listSections
        guard snapshot != tasks || listsChanged || metasChanged || foldersChanged || sectionsChanged else { return }
        if undoPolicy == .record && transactionDepth == 0 {
            undoSnapshots.append(tasks)
            undoTextRebases.append([:])
            undoLists.append(self.lists)
            undoListMetas.append(self.listMetas)
            undoListFolders.append(self.listFolders)
            undoListSections.append(self.listSections)
            undoCompensations.append(undoCompensation)
            if undoSnapshots.count > 50 {
                undoSnapshots.removeFirst()
                undoTextRebases.removeFirst()
                undoLists.removeFirst()
                undoListMetas.removeFirst()
                undoListFolders.removeFirst()
                undoListSections.removeFirst()
                undoCompensations.removeFirst()
            }
        } else if undoPolicy == .skip {

            // Rebase text-only edits through history so undoing a business
            // command cannot revert later text input (including another task).
            let old = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let changed = Dictionary(uniqueKeysWithValues: snapshot.filter {
                old[$0.id]?.title != $0.title || old[$0.id]?.document != $0.document
            }.map { ($0.id, $0) })
            rebaseTextHistory(changed)
        }
        let previousTasks = tasks
        tasks = snapshot
        if let lists { self.lists = lists }
        if let listFolders { self.listFolders = listFolders }
        if let listSections { self.listSections = listSections }
        reconcileListMetas(committed: listMetas, listsCommitted: lists != nil)
        if transactionDepth == 0 {
            publishTaskChanges(from: previousTasks)
        }
    }

    /// Text-only commands preserve task IDs, positions and parent membership.
    /// Publish one exact entry; outer transactions retain their aggregate diff.
    func commitText(_ id: UUID, title: String? = nil, document: NativeDocument? = nil,
                    updatedAt: Date) {
        prepareReadIndex()
        guard let index = taskOffsets?[id] else { return }
        let before = tasks[index]
        var after = before
        if let title { after.title = title }
        if let document { after.document = document }
        guard before.title != after.title || before.document != after.document else { return }
        after.updatedAt = updatedAt
        let previousTasks = transactionDepth == 0 && onTasksChanged != nil ? tasks : nil
        let byID = taskOffsets
        let byParent = childOffsets
        tasks[index] = after
        // Assignment still advances readRevision so value projections refresh;
        // only the structurally unchanged lookup indexes are retained.
        taskOffsets = byID
        childOffsets = byParent
        rebaseTextHistory([id: after])
        if transactionDepth == 0 {
            let changes = onTaskChanges.map { _ in TaskChangeSet(updatedFrom: before, to: after) }
            if let previousTasks { onTasksChanged?(previousTasks, tasks) }
            if let changes { onTaskChanges?(changes) }
        }
    }

    private func rebaseTextHistory(_ changed: [UUID: Task]) {
        for index in undoTextRebases.indices {
            for (id, latest) in changed {
                var rebase = undoTextRebases[index][id] ?? TextRebase(latest)
                rebase.title = latest.title
                rebase.document = latest.document
                rebase.updatedAt = latest.updatedAt
                rebase.rebasesText = true
                undoTextRebases[index][id] = rebase
            }
        }
    }

    /// Commits an editor-owned document/source pair without recording a business undo.
    /// Text keeps the usual `.skip` rebase; only this path rebases sourceNoteID too.
    func commitEditorReference(_ id: UUID, document: NativeDocument, sourceNoteID: UUID?, updatedAt: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var snapshot = tasks
        snapshot[index].document = document
        snapshot[index].sourceNoteID = sourceNoteID
        snapshot[index].updatedAt = updatedAt
        guard snapshot != tasks else { return }

        commit(snapshot, undoPolicy: .skip)
        for historyIndex in undoTextRebases.indices {
            var rebase = undoTextRebases[historyIndex][id] ?? TextRebase(snapshot[index])
            rebase.rebasesSourceNote = true
            rebase.sourceNoteID = sourceNoteID
            rebase.updatedAt = updatedAt
            undoTextRebases[historyIndex][id] = rebase
        }
    }

    func undo() {
        guard let previous = undoSnapshots.popLast() else { return }
        let textRebases = undoTextRebases.removeLast()
        let before = tasks
        tasks = textRebases.isEmpty ? previous : previous.map { task in
            textRebases[task.id]?.applying(to: task) ?? task
        }
        lists = undoLists.removeLast()
        listMetas = undoListMetas.removeLast()
        listFolders = undoListFolders.removeLast()
        listSections = undoListSections.removeLast()
        if let compensation = undoCompensations.popLast() ?? nil { compensation() }
        if transactionDepth == 0 {
            publishTaskChanges(from: before)
        }
    }
    func clearUndo() {
        undoSnapshots.removeAll()
        undoTextRebases.removeAll()
        undoLists.removeAll()
        undoListMetas.removeAll()
        undoListFolders.removeAll()
        undoListSections.removeAll()
        undoCompensations.removeAll()
    }

    func transaction(_ body: () -> Void) {
        let before = tasks
        let beforeLists = lists
        let beforeMetas = listMetas
        let beforeFolders = listFolders
        let beforeSections = listSections
        transactionDepth += 1
        body()
        transactionDepth -= 1
        if transactionDepth == 0 && (before != tasks || beforeLists != lists || beforeMetas != listMetas
                                     || beforeFolders != listFolders
                                     || beforeSections != listSections) {
            undoSnapshots.append(before); undoLists.append(beforeLists); undoListMetas.append(beforeMetas)
            undoTextRebases.append([:])
            undoListFolders.append(beforeFolders)
            undoListSections.append(beforeSections)
            undoCompensations.append(nil)
            if undoSnapshots.count > 50 {
                undoSnapshots.removeFirst()
                undoTextRebases.removeFirst()
                undoLists.removeFirst()
                undoListMetas.removeFirst()
                undoListFolders.removeFirst()
                undoListSections.removeFirst()
                undoCompensations.removeFirst()
            }
            publishTaskChanges(from: before)
        }
    }

    /// One publication boundary for commands, outer transactions and undo.
    /// Hydration without consumers needs no diff; list metadata alone is not
    /// a task domain event. Keep the legacy snapshot observer compatible.
    private func publishTaskChanges(from before: [Task]) {
        let changes = onTaskChanges.map { _ in
            fullDiffBuildCount += 1
            return TaskChangeSet(before: before, after: tasks)
        }
        onTasksChanged?(before, tasks)
        if let changes, !changes.entries.isEmpty { onTaskChanges?(changes) }
    }

    // MARK: - 清单元数据对账（Round B1）

    /// 始终让 listMetas 与 lists 一一对应（sortOrder 归一化为数组下标）：
    /// - 显式传入 meta：按名字继承，缺失的名字补默认 meta；
    /// - 只有 lists 变化（renameList/removeList 的形态）：同名清单继承原 meta；
    ///   若恰好"一消失、一出现"，视为重命名，消失者的颜色/置顶继承给新名字
    ///   （对齐 Flutter renameList 保留 color/pinned 的行为）；
    /// - 两者都没给：meta 不动。
    private func reconcileListMetas(committed: [TaskListMeta]?, listsCommitted: Bool) {
        if !listsCommitted {
            guard let committed else { return }
            listMetas = aligned(committed, to: lists)
            return
        }
        var carry: [String: TaskListMeta] = [:]
        if committed == nil {
            let previousNames = Set(listMetas.map(\.name))
            let disappeared = listMetas.filter { !lists.contains($0.name) }
            let appeared = lists.filter { !previousNames.contains($0) }
            if disappeared.count == 1, appeared.count == 1 {
                carry[appeared[0]] = disappeared[0]
            }
        }
        var byName = Dictionary((committed ?? listMetas).map { ($0.name, $0) },
                                uniquingKeysWith: { current, _ in current })
        listMetas = lists.enumerated().map { index, name in
            var meta = carry[name] ?? byName.removeValue(forKey: name) ?? TaskListMeta(name: name)
            meta.name = name
            meta.sortOrder = index
            return meta
        }
    }

    private func aligned(_ metas: [TaskListMeta], to names: [String]) -> [TaskListMeta] {
        var byName = Dictionary(metas.map { ($0.name, $0) },
                                uniquingKeysWith: { current, _ in current })
        return names.enumerated().map { index, name in
            var meta = byName.removeValue(forKey: name) ?? TaskListMeta(name: name)
            meta.name = name
            meta.sortOrder = index
            return meta
        }
    }
}
