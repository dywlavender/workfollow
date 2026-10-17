import Foundation

/// 任务级纯文本评论（滴答详情底栏 💬 出口的单机版最小语义）。
/// 一条评论属于一个任务，按创建时间正序呈现（最早在上）。
struct TaskComment: Identifiable, Codable, Equatable {
    let id: UUID
    let taskID: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), taskID: UUID, text: String, createdAt: Date) {
        self.id = id
        self.taskID = taskID
        self.text = text
        self.createdAt = createdAt
    }
}
