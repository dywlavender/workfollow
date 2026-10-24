import Foundation

/// 任务级纯文本评论（滴答详情底栏 💬 出口的单机版最小语义）。
/// 一条评论属于一个任务，按创建时间正序呈现（最早在上）。
struct TaskComment: Identifiable, Codable, Equatable {
    let id: UUID
    let taskID: UUID
    var text: String
    let createdAt: Date
    /// 回复的父评论（TI2-09 剩余项）。nil = 顶层评论。
    /// 滴答的 `TTTaskDetailCommentCell` 有 `replyOrRemoveButton`，回复按一级缩进呈现。
    var parentID: UUID?
    /// 编辑过的时间（`editButton` / `TTCommentEditViewController`）。nil = 未编辑。
    var editedAt: Date?

    init(id: UUID = UUID(), taskID: UUID, text: String, createdAt: Date,
         parentID: UUID? = nil, editedAt: Date? = nil) {
        self.id = id
        self.taskID = taskID
        self.text = text
        self.createdAt = createdAt
        self.parentID = parentID
        self.editedAt = editedAt
    }
}

extension TaskComment {
    // 旧存档没有 parentID / editedAt：解码回落 nil（additive，不改既有记录）。
    private enum CodingKeys: String, CodingKey {
        case id, taskID, text, createdAt, parentID, editedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        taskID = try values.decode(UUID.self, forKey: .taskID)
        text = try values.decode(String.self, forKey: .text)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        parentID = try values.decodeIfPresent(UUID.self, forKey: .parentID)
        editedAt = try values.decodeIfPresent(Date.self, forKey: .editedAt)
    }
}
