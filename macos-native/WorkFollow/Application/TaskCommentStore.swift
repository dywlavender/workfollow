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
    func add(taskID: UUID, text: String, parentID: UUID? = nil) -> TaskComment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = TaskComment(taskID: taskID, text: trimmed, createdAt: clock(), parentID: parentID)
        persistence.schedule(upserts: [comment])
        revision += 1
        return comment
    }

    /// 编辑正文：`createdAt` 不动（列表仍按创建时间排），只记 `editedAt`。
    /// 空文本拒绝（与 `add` 的裁剪口径一致）。
    @discardableResult
    func update(_ commentID: UUID, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var comment = comment(commentID) else { return false }
        guard comment.text != trimmed else { return true }
        comment.text = trimmed
        comment.editedAt = clock()
        persistence.schedule(upserts: [comment])
        revision += 1
        return true
    }

    func comment(_ commentID: UUID) -> TaskComment? {
        allComments.first { $0.id == commentID }
    }

    /// 全量读取（编辑/回复要按 id 找，不能只看某条任务）。
    private var allComments: [TaskComment] {
        (try? persistence.history(taskID: nil, limit: Int.max, insertionOrder: true)) ?? []
    }

    /// 删除一条评论连同它的回复（滴答删除父评论时回复一起消失，否则会留下
    /// 没有上下文的孤儿）。
    func delete(_ commentID: UUID) {
        let doomed = replies(to: commentID, in: comments(containing: commentID)).map(\.id)
        persistence.schedule(deleted: [commentID] + doomed)
        revision += 1
    }

    /// 某条评论的直接回复，按创建时间正序。
    func replies(to commentID: UUID, in comments: [TaskComment]) -> [TaskComment] {
        comments.filter { $0.parentID == commentID }
    }

    private func comments(containing commentID: UUID) -> [TaskComment] {
        guard let comment = comment(commentID) else { return [] }
        return comments(for: comment.taskID)
    }

    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush(completion)
    }
}
