import Combine
import Foundation

@MainActor
final class TaskCommentStore: ObservableObject, ModuleStoreFlushable {
    /// 每次增删 +1，驱动评论面板刷新。
    @Published private(set) var revision = 0

    private let persistence: SQLiteRecordStore<TaskComment, EmptyHistoryMetadata>
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init, directory: URL? = nil) {
        self.clock = clock
        let store = SQLiteRecordStore<TaskComment, EmptyHistoryMetadata>(
            filename: "task-comments", directory: directory ?? JSONFileStore<[TaskComment]>.moduleDirectory,
            newestFirst: false,
            timestamp: { $0.createdAt }, taskID: { $0.taskID }, migrate: { data in
                .init(records: try JSONDecoder().decode([TaskComment].self, from: data), metadata: nil)
            })
        persistence = store
        _ = store.load()
    }

    var storageError: Error? { persistence.readError }

    /// 某条任务的评论，按创建时间正序（旧→新）。
    func comments(for taskID: UUID) -> [TaskComment] {
        (try? persistence.history(taskID: taskID, limit: Int.max, insertionOrder: true)) ?? []
    }

    func count(for taskID: UUID) -> Int {
        comments(for: taskID).count
    }

    @discardableResult
    func add(taskID: UUID, text: String) -> TaskComment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = TaskComment(taskID: taskID, text: trimmed, createdAt: clock())
        persistence.schedule(upserts: [comment])
        revision += 1
        return comment
    }

    func delete(_ commentID: UUID) {
        persistence.schedule(deleted: [commentID])
        revision += 1
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }
}
