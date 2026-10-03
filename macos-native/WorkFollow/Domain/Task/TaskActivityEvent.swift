import Foundation

struct TaskActivityEvent: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, Hashable {
        case created
        case titleChanged
        case dateChanged
        case listChanged
        case priorityChanged
        case tagsChanged
        case completed
        case restored
        case abandoned
        case childCreated
        case focusStarted
    }

    let id: UUID
    let taskID: UUID
    let occurredAt: Date
    let kind: Kind
    let beforeValue: String?
    let afterValue: String?

    init(id: UUID = UUID(), taskID: UUID, occurredAt: Date, kind: Kind,
         beforeValue: String? = nil, afterValue: String? = nil) {
        self.id = id
        self.taskID = taskID
        self.occurredAt = occurredAt
        self.kind = kind
        self.beforeValue = beforeValue
        self.afterValue = afterValue
    }

    var title: String {
        switch kind {
        case .created: "创建任务"
        case .titleChanged: "修改标题"
        case .dateChanged: "调整日期"
        case .listChanged: "移动清单"
        case .priorityChanged: "调整优先级"
        case .tagsChanged: "修改标签"
        case .completed: "完成任务"
        case .restored: "恢复任务"
        case .abandoned: "放弃任务"
        case .childCreated: "添加子任务"
        case .focusStarted: "开始专注"
        }
    }

    var detail: String? {
        switch kind {
        case .created, .childCreated, .focusStarted:
            return afterValue
        case .titleChanged, .dateChanged, .listChanged, .priorityChanged, .tagsChanged:
            guard beforeValue != nil || afterValue != nil else { return nil }
            return "\(beforeValue ?? "—") → \(afterValue ?? "—")"
        case .completed, .restored, .abandoned:
            return nil
        }
    }
}
