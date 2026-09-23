import Foundation

/// Single in-memory authority for Phase 2. UI integration and Repository come later.
final class WorkspaceStore {
    private(set) var tasks: [Task] = []

    func task(_ id: UUID) -> Task? { tasks.first { $0.id == id } }

    func children(of id: UUID, includingDeleted: Bool = false) -> [Task] {
        tasks.filter { $0.parentID == id && (includingDeleted || $0.deletedAt == nil) }
            .sorted { $0.childOrder < $1.childOrder }
    }

    // Only application commands commit snapshots; readers receive value copies.
    func commit(_ snapshot: [Task]) { tasks = snapshot }
}
