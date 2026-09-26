import Foundation

/// Single in-memory authority for Phase 2. UI integration and Repository come later.
final class WorkspaceStore {
    enum UndoPolicy { case record, skip }
    private(set) var tasks: [Task] = []
    private(set) var lists: [String] = []
    private var undoLists: [[String]] = []
    private var undoCompensations: [(() -> Void)?] = []
    private var transactionDepth = 0
    private var undoSnapshots: [[Task]] = []
    var canUndo: Bool { !undoSnapshots.isEmpty }

    func task(_ id: UUID) -> Task? { tasks.first { $0.id == id } }

    func children(of id: UUID, includingDeleted: Bool = false) -> [Task] {
        tasks.filter { $0.parentID == id && $0.skippedAt == nil && (includingDeleted || $0.deletedAt == nil) }
            .sorted { $0.childOrder < $1.childOrder }
    }

    // Only application commands commit snapshots; readers receive value copies.
    func commit(_ snapshot: [Task], undoPolicy: UndoPolicy = .record,
                lists: [String]? = nil, undoCompensation: (() -> Void)? = nil) {
        guard snapshot != tasks || lists != nil && lists != self.lists else { return }
        if undoPolicy == .record && transactionDepth == 0 {
            undoSnapshots.append(tasks)
            undoLists.append(self.lists)
            undoCompensations.append(undoCompensation)
            if undoSnapshots.count > 50 {
                undoSnapshots.removeFirst()
                undoLists.removeFirst()
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
        tasks = snapshot
        if let lists { self.lists = lists }
    }
    func undo() {
        guard let previous = undoSnapshots.popLast() else { return }
        tasks = previous
        lists = undoLists.removeLast()
        if let compensation = undoCompensations.popLast() ?? nil { compensation() }
    }
    func clearUndo() {
        undoSnapshots.removeAll()
        undoLists.removeAll()
        undoCompensations.removeAll()
    }

    func transaction(_ body: () -> Void) {
        let before = tasks
        let beforeLists = lists
        transactionDepth += 1
        body()
        transactionDepth -= 1
        if transactionDepth == 0 && (before != tasks || beforeLists != lists) {
            undoSnapshots.append(before); undoLists.append(beforeLists)
            undoCompensations.append(nil)
            if undoSnapshots.count > 50 {
                undoSnapshots.removeFirst()
                undoLists.removeFirst()
                undoCompensations.removeFirst()
            }
        }
    }
}
