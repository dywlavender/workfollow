import Combine
import Foundation

extension Publisher where Output == TaskChangeSet, Failure == Never {
    /// Field-aware side-effect boundary. Coalescing happens before the consumer
    /// computes signatures; no task/document snapshots are retained by debounce.
    func reminderInvalidations(
        delay: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(250),
        scheduler: DispatchQueue = .main
    ) -> AnyPublisher<Void, Never> {
        filter { $0.affectsReminders }
            .map { _ in () }
            .debounce(for: delay, scheduler: scheduler)
            .eraseToAnyPublisher()
    }
}
