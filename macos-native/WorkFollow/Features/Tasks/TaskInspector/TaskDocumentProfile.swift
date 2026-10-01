import Foundation

/// Narrow callbacks supplied by the task host. The shared editor never owns a workspace.
struct TaskEditorHostActions {
    let createChild: () -> Void
    let openTags: () -> Void
    let openRelation: () -> Void
    let openLink: (String) -> Bool
}

enum TaskDocumentProfile {
    static let slashFormatIDs = ["format.heading1", "format.heading2", "format.heading3",
                                 "format.bullet", "format.ordered", "format.checklist", "format.quote"]
    static func make(task: Task, host: TaskEditorHostActions) -> DocumentProfile {
        var commands: [DocumentCommand] = []
        if task.parentID == nil {
            commands.append(DocumentCommand(id: "task.child", title: "子任务", group: "插入",
                                             keywords: "subtask child") { _ in host.createChild() })
        }
        commands.append(DocumentCommand(id: "task.tags", title: "标签", group: "插入") { _ in host.openTags() })
        commands.append(DocumentCommand(id: "task.relation", title: "关联任务/笔记", group: "插入") { _ in host.openRelation() })
        return DocumentProfile(commands: commands, taskSlash: true, onOpenLink: host.openLink,
                               selectionToolbarEnabled: false,
                               slashCommandOverride: DocumentProfile.compactDocumentCommands(formatIDs: slashFormatIDs) + commands)
    }

    static func reference(to note: Note) -> EditorReference {
        EditorReference(title: "📄 " + (note.title.isEmpty ? "未命名笔记" : note.title),
                        target: "workfollow://note/" + note.id.uuidString)
    }
}
