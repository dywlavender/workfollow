import Foundation

/// Coalesce snapshot construction on the model's owning actor, before encoding.
/// The provider reads the latest committed workspace rather than capturing one
/// full snapshot per keystroke. Disk encoding/writes still belong to persistence.
@MainActor
final class WorkspaceSnapshotDebouncer {
    private let persistence: PersistenceCoordinator
    private let delay: TimeInterval
    private var provider: (() -> NativeWorkspaceSnapshot?)?
    private var work: DispatchWorkItem?

    init(persistence: PersistenceCoordinator, delay: TimeInterval = 0.4) {
        self.persistence = persistence
        self.delay = delay
    }

    func schedule(_ provider: @escaping () -> NativeWorkspaceSnapshot?) {
        self.provider = provider
        work?.cancel()
        let next = DispatchWorkItem { [weak self] in self?.flushPendingSnapshot() }
        work = next
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
    }

    /// Call before persistence.flush: its serial queue then receives the newest
    /// snapshot before the flush barrier. A cancelled timer cannot save later.
    func flushPendingSnapshot() {
        work?.cancel()
        work = nil
        guard let provider else { return }
        self.provider = nil
        if let snapshot = provider() { persistence.schedule(snapshot) }
    }
}
