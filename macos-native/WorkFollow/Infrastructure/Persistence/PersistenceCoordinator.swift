import Foundation

/// One serial queue owns debounce, encoding and atomic writes. Flush is a queue
/// barrier: older writes can never finish after the final snapshot.
final class PersistenceCoordinator {
    private let queue = DispatchQueue(label: "WorkFollow.preview.persistence", qos: .utility)
    private let repository: NativePreviewRepository
    private let delay: TimeInterval
    private var pending: NativeWorkspaceSnapshot?
    private var work: DispatchWorkItem?
    var onResult: ((Error?) -> Void)?

    init(repository: NativePreviewRepository = NativePreviewRepository(), delay: TimeInterval = 0.4) {
        self.repository = repository
        self.delay = delay
    }

    func schedule(_ snapshot: NativeWorkspaceSnapshot) {
        queue.async { [self] in
            pending = snapshot
            work?.cancel()
            let next = DispatchWorkItem { [weak self] in self?.writePending() }
            work = next
            queue.asyncAfter(deadline: .now() + delay, execute: next)
        }
    }

    func flush(completion: @escaping (Error?) -> Void) {
        queue.async { [self] in
            work?.cancel()
            let error = writePending()
            DispatchQueue.main.async { completion(error) }
        }
    }

    @discardableResult
    private func writePending() -> Error? {
        guard let snapshot = pending else { return nil }
        do {
            try repository.save(snapshot)
            pending = nil
            onResult?(nil)
            return nil
        } catch {
            // Keep the latest snapshot available for a retry/termination flush.
            onResult?(error)
            return error
        }
    }
}
