import Foundation

/// 列表行和看板卡片共用的任务标记；只读取任务及同一工作区的子任务投影。
struct TaskSecondaryMetadata: Identifiable, Equatable {
    let id: String
    var symbol: String? = nil
    var value: String? = nil
    let accessibilityLabel: String

    static func items(for task: Task, subtaskProgress: String?) -> [Self] {
        var items: [Self] = []
        if let progress = subtaskProgress {
            items.append(.init(id: "subtasks", value: progress,
                               accessibilityLabel: "子任务进度：\(progress)"))
        }
        if task.recurrence != .never {
            items.append(.init(id: "repeat", symbol: "repeat", accessibilityLabel: "重复任务"))
        }
        if TaskListViewDefaults.hasReminder(reminderAt: task.reminderAt,
                                            reminderOffsets: task.reminderOffsets) {
            items.append(.init(id: "reminder", symbol: "bell", accessibilityLabel: "有提醒"))
        }
        if !task.tags.isEmpty {
            items.append(.init(id: "tags", symbol: "tag", accessibilityLabel: "有标签"))
        }
        if !task.document.isEmpty {
            items.append(.init(id: "description", symbol: "text.alignleft", accessibilityLabel: "有描述"))
        }
        if !task.attachments.isEmpty {
            items.append(.init(id: "attachments", symbol: "paperclip", accessibilityLabel: "有附件"))
        }
        return items
    }
}

/// 看板保留任务正文预览；隐藏详细只控制元信息，与列表的同一设置一致。
struct TaskKanbanCardDetails: Equatable {
    let preview: String?
    let listName: String?
    let tags: [String]
    let showsDate: Bool
    let showsPriority: Bool
    let showsPinned: Bool
    let showsAbandoned: Bool
    let indicators: [TaskSecondaryMetadata]

    init(task: Task, subtaskProgress: String?, showsListBadge: Bool,
         hidesDetails: Bool, hiddenFields: [TaskRowDetailField]) {
        preview = TaskListViewDefaults.bodyPreview(of: task.document)
        listName = !hidesDetails && showsListBadge && !hiddenFields.contains(.list) ? task.list.name : nil
        tags = !hidesDetails && !hiddenFields.contains(.tags) ? task.tags : []
        showsDate = !hidesDetails && !hiddenFields.contains(.date)
            && (task.schedule.dueAt != nil || task.schedule.deadlineAt != nil)
        showsPriority = !hidesDetails && !hiddenFields.contains(.priority) && task.priority != .none
        showsPinned = !hidesDetails && task.isPinned
        showsAbandoned = !hidesDetails && task.isAbandoned
        indicators = !hidesDetails && !hiddenFields.contains(.indicators)
            ? TaskSecondaryMetadata.items(for: task, subtaskProgress: subtaskProgress).filter { $0.id != "tags" }
            : []
    }
}
