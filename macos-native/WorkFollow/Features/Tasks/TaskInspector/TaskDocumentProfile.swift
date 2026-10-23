import Foundation

/// Narrow callbacks supplied by the task host. The shared editor never owns a workspace.
struct TaskEditorHostActions {
    let createChild: () -> Void
    let openTags: () -> Void
    let openRelation: () -> Void
    let openLink: (String) -> Bool
    /// `#` 标签补全：候选来自工作区已有标签，选中后把标签挂到任务上。
    var availableTags: () -> [String] = { [] }
    var addTag: (String) -> Void = { _ in }
    /// 粘贴文件成附件（TI2-03 剩余项）。
    var pasteFiles: ([URL]) -> Void = { _ in }
}

enum TaskDocumentProfile {
    static let slashFormatIDs = ["format.heading1", "format.heading2", "format.heading3",
                                 "format.bullet", "format.ordered", "format.checklist", "format.quote"]
    static func make(task: Task, host: TaskEditorHostActions) -> DocumentProfile {
        var commands: [DocumentCommand] = []
        // 放开嵌套（2026-10-17）：子任务正文同样可插入"子任务"（孙任务）。
        commands.append(DocumentCommand(id: "task.child", title: "子任务", group: "插入",
                                         keywords: "subtask child") { _ in host.createChild() })
        commands.append(DocumentCommand(id: "task.tags", title: "标签", group: "插入") { _ in host.openTags() })
        commands.append(DocumentCommand(id: "task.relation", title: "关联任务/笔记", group: "插入") { _ in host.openRelation() })
        var profile = DocumentProfile(commands: commands, taskSlash: true, onOpenLink: host.openLink,
                                      selectionToolbarEnabled: false,
                                      slashCommandOverride: DocumentProfile.compactDocumentCommands(formatIDs: slashFormatIDs) + commands,
                                      blockMenuCommands: DocumentProfile.standardBlockMenuCommands)
        profile.tagCandidates = host.availableTags
        profile.onTagInserted = host.addTag
        profile.onPasteFiles = host.pasteFiles
        return profile
    }

    static func reference(to note: Note) -> EditorReference {
        EditorReference(title: "📄 " + (note.title.isEmpty ? "未命名笔记" : note.title),
                        target: "workfollow://note/" + note.id.uuidString)
    }
}
