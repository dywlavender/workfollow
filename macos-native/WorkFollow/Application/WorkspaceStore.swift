import Foundation

/// Single in-memory authority for Phase 2. UI integration and Repository come later.
final class WorkspaceStore {
    enum UndoPolicy { case record, skip }
    private(set) var tasks: [Task] = []
    private var undoSnapshots: [[Task]] = []
    var canUndo: Bool { !undoSnapshots.isEmpty }

    func task(_ id: UUID) -> Task? { tasks.first { $0.id == id } }

    func children(of id: UUID, includingDeleted: Bool = false) -> [Task] {
        tasks.filter { $0.parentID == id && (includingDeleted || $0.deletedAt == nil) }
            .sorted { $0.childOrder < $1.childOrder }
    }

    // Only application commands commit snapshots; readers receive value copies.
    func commit(_ snapshot: [Task], undoPolicy: UndoPolicy = .record) {
        guard snapshot != tasks else { return }
        if undoPolicy == .record {
            undoSnapshots.append(tasks)
            if undoSnapshots.count > 50 { undoSnapshots.removeFirst() }
        } else {
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
    }
    func undo() {
        guard let previous = undoSnapshots.popLast() else { return }
        tasks = previous
    }
    func clearUndo() { undoSnapshots.removeAll() }
}
