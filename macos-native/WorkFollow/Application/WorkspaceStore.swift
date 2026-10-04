import Foundation

/// Single in-memory authority for Phase 2. UI integration and Repository come later.
final class WorkspaceStore {
    enum UndoPolicy { case record, skip }
    private(set) var tasks: [Task] = []
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
    private var undoCompensations: [(() -> Void)?] = []
    private var transactionDepth = 0
    private var undoSnapshots: [[Task]] = []
    var canUndo: Bool { !undoSnapshots.isEmpty }
    /// Compatibility callback for consumers that still need full snapshots.
    var onTasksChanged: (([Task], [Task]) -> Void)?
    /// Emits the task-level diff once per commit, undo, or outer transaction.
    var onTaskChanges: ((TaskChangeSet) -> Void)?

    func task(_ id: UUID) -> Task? { tasks.first { $0.id == id } }

    func children(of id: UUID, includingDeleted: Bool = false) -> [Task] {
        tasks.filter { $0.parentID == id && $0.skippedAt == nil && (includingDeleted || $0.deletedAt == nil) }
            .sorted { $0.childOrder < $1.childOrder }
    }

    func listMeta(for name: String) -> TaskListMeta? {
        listMetas.first { $0.name == name }
    }

    func listFolder(named name: String) -> TaskListFolder? {
        listFolders.first { $0.name == name }
    }

    // Only application commands commit snapshots; readers receive value copies.
    func commit(_ snapshot: [Task], undoPolicy: UndoPolicy = .record,
                lists: [String]? = nil, listMetas: [TaskListMeta]? = nil,
                listFolders: [TaskListFolder]? = nil,
                undoCompensation: (() -> Void)? = nil) {
        let listsChanged = lists != nil && lists != self.lists
        let metasChanged = listMetas != nil && listMetas != self.listMetas
        let foldersChanged = listFolders != nil && listFolders != self.listFolders
        guard snapshot != tasks || listsChanged || metasChanged || foldersChanged else { return }
        if undoPolicy == .record && transactionDepth == 0 {
            undoSnapshots.append(tasks)
            undoLists.append(self.lists)
            undoListMetas.append(self.listMetas)
            undoListFolders.append(self.listFolders)
            undoCompensations.append(undoCompensation)
            if undoSnapshots.count > 50 {
                undoSnapshots.removeFirst()
                undoLists.removeFirst()
                undoListMetas.removeFirst()
                undoListFolders.removeFirst()
                undoCompensations.removeFirst()
            }
        } else if undoPolicy == .skip {
            // Rebase text-only edits through history so undoing a business
            // command cannot revert later text input (including another task).
            let old = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let changed = Dictionary(uniqueKeysWithValues: snapshot.filter {
                old[$0.id]?.title != $0.title || old[$0.id]?.document != $0.document
            }.map { ($0.id, $0) })
            undoSnapshots = undoSnapshots.map { previous in
                previous.map { task in
                    guard let latest = changed[task.id] else { return task }
                    var value = task
                    value.title = latest.title
                    value.document = latest.document
                    value.updatedAt = latest.updatedAt
                    return value
                }
            }
        }
        let previousTasks = tasks
        tasks = snapshot
        if let lists { self.lists = lists }
        if let listFolders { self.listFolders = listFolders }
        reconcileListMetas(committed: listMetas, listsCommitted: lists != nil)
        if transactionDepth == 0 {
            publishTaskChanges(from: previousTasks)
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
        undoSnapshots = undoSnapshots.map { previous in
            previous.map { task in
                guard task.id == id else { return task }
                var rebased = task
                rebased.sourceNoteID = sourceNoteID
                rebased.updatedAt = updatedAt
                return rebased
            }
        }
    }

    func undo() {
        guard let previous = undoSnapshots.popLast() else { return }
        let before = tasks
        tasks = previous
        lists = undoLists.removeLast()
        listMetas = undoListMetas.removeLast()
        listFolders = undoListFolders.removeLast()
        if let compensation = undoCompensations.popLast() ?? nil { compensation() }
        if transactionDepth == 0 {
            publishTaskChanges(from: before)
        }
    }
    func clearUndo() {
        undoSnapshots.removeAll()
        undoLists.removeAll()
        undoListMetas.removeAll()
        undoListFolders.removeAll()
        undoCompensations.removeAll()
    }

    func transaction(_ body: () -> Void) {
        let before = tasks
        let beforeLists = lists
        let beforeMetas = listMetas
        let beforeFolders = listFolders
        transactionDepth += 1
        body()
        transactionDepth -= 1
        if transactionDepth == 0 && (before != tasks || beforeLists != lists || beforeMetas != listMetas
                                     || beforeFolders != listFolders) {
            undoSnapshots.append(before); undoLists.append(beforeLists); undoListMetas.append(beforeMetas)
            undoListFolders.append(beforeFolders)
            undoCompensations.append(nil)
            if undoSnapshots.count > 50 {
                undoSnapshots.removeFirst()
                undoLists.removeFirst()
                undoListMetas.removeFirst()
                undoListFolders.removeFirst()
                undoCompensations.removeFirst()
            }
            publishTaskChanges(from: before)
        }
    }

    /// One publication boundary for commands, outer transactions and undo.
    /// Hydration without consumers needs no diff; list metadata alone is not
    /// a task domain event. Keep the legacy snapshot observer compatible.
    private func publishTaskChanges(from before: [Task]) {
        let changes = onTaskChanges.map { _ in TaskChangeSet(before: before, after: tasks) }
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
