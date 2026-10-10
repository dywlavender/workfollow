import Foundation

/// One serial queue owns debounce, encoding and atomic writes. Flush is a queue
/// barrier: older writes can never finish after the final snapshot. The first
/// successful write of each day also leaves a daily backup copy behind.
final class PersistenceCoordinator {
    private let queue = DispatchQueue(label: "WorkFollow.preview.persistence", qos: .utility)
    private let repository: NativePreviewRepository
    private let delay: TimeInterval
    private var pending: NativeWorkspaceSnapshot?
    private var batch = SQLiteWorkspaceRepository.Batch()
    private var work: DispatchWorkItem?
    /// 当天已尝试过每日备份后不再重复扫描（队列内私有状态）。
    private var lastDailyBackupDay: String?
    var onResult: ((Error?) -> Void)?

    init(repository: NativePreviewRepository = NativePreviewRepository(), delay: TimeInterval = 0.4) {
        self.repository = repository
        self.delay = delay
    }

    func schedule(_ snapshot: NativeWorkspaceSnapshot) {
        queue.async { [self] in
            pending = snapshot
            batch = SQLiteWorkspaceRepository.Batch()
            work?.cancel()
            let next = DispatchWorkItem { [weak self] in self?.writePending() }
            work = next
            queue.asyncAfter(deadline: .now() + delay, execute: next)
        }
    }

    func schedule(changes: TaskChangeSet, order: [UUID]? = nil) {
        queue.async { [self] in
            for entry in changes.entries {
                if let previous = batch.tasks[entry.taskID] {
                    batch.tasks[entry.taskID] = TaskChangeSet.Entry(
                        operation: entry.after == nil ? .delete : previous.operation == .insert ? .insert : entry.operation,
                        before: previous.before, after: entry.after,
                        changedFields: previous.changedFields.union(entry.changedFields))
                } else { batch.tasks[entry.taskID] = entry }
            }
            if let order = order ?? changes.order { batch.taskOrder = order }
            scheduleBatchWrite()
        }
    }

    /// Metadata contains no tasks or notes. Entity mutations use exact deltas.
    func schedule(metadata: NativeWorkspaceSnapshot) {
        queue.async { [self] in
            batch.metadata = metadata
            scheduleBatchWrite()
        }
    }

    private func scheduleBatchWrite() {
        work?.cancel()
        let next = DispatchWorkItem { [weak self] in self?.writePending() }
        work = next
        queue.asyncAfter(deadline: .now() + delay, execute: next)
    }

    func schedule(notes change: NotePersistenceChange) {
        queue.async { [self] in
            for id in change.deleted {
                batch.noteUpserts.removeValue(forKey: id); batch.noteDeleted.insert(id); batch.noteDocuments.remove(id)
            }
            for note in change.upserts {
                batch.noteDeleted.remove(note.id); batch.noteUpserts[note.id] = note
                if change.documentIDs == nil || change.documentIDs!.contains(note.id) { batch.noteDocuments.insert(note.id) }
            }
            if let order = change.order { batch.noteOrder = order }
            scheduleBatchWrite()
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
        guard pending != nil || !batch.isEmpty else { return nil }
        do {
            if let snapshot = pending {
                try repository.save(snapshot)
                pending = nil
            }
            if !batch.isEmpty { try repository.apply(batch) }
            pending = nil
            batch = SQLiteWorkspaceRepository.Batch()
            maintainDailyBackupIfNeeded()
            onResult?(nil)
            return nil
        } catch {
            // Keep the latest snapshot available for a retry/termination flush.
            onResult?(error)
            return error
        }
    }

    /// 当天首次写入成功后留一份每日快照（maintainDailyBackup 内部吞掉所有错误）。
    private func maintainDailyBackupIfNeeded() {
        let day = NativePreviewRepository.dayStamp(for: Date())
        guard day != lastDailyBackupDay else { return }
        lastDailyBackupDay = day
        repository.maintainDailyBackup()
    }
}
