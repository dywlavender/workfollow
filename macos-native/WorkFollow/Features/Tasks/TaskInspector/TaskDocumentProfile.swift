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
    /// `~` 清单补全：候选是未归档清单，选中后把任务移进该清单。
    var availableLists: () -> [String] = { [] }
    var moveToList: (String) -> Void = { _ in }
    /// 粘贴文件成附件（TI2-03 剩余项）。
    var pasteFiles: ([URL]) -> Void = { _ in }
    /// 检查项行内控件：行号按换行切分，与任务文档的块顺序一致。
    var checklistItem: (Int) -> ChecklistItemMeta? = { _ in nil }
    var setChecklistReminder: (Int, Date?) -> Void = { _, _ in }
    var checklistReminderNotice: () -> String? = { nil }
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
        profile.listCandidates = host.availableLists
        profile.onListInserted = host.moveToList
        profile.onPasteFiles = host.pasteFiles
        profile.checklistItem = host.checklistItem
        profile.setChecklistReminder = host.setChecklistReminder
        profile.checklistReminderNotice = host.checklistReminderNotice
        profile.checklistRemindersEnabled = task.kind == .checklist
        // 滴答任务正文的 Enter 就是一个 22pt 行盒（2026-10-30 AX 实测），
        // 没有笔记那种 10pt 段距。
        profile.paragraphSpacing = 0
        return profile
    }

    static func reference(to note: Note) -> EditorReference {
        EditorReference(title: "📄 " + (note.title.isEmpty ? "未命名笔记" : note.title),
                        target: "workfollow://note/" + note.id.uuidString)
    }
}
