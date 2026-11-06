import Foundation

struct NoteEditorHostActions {
    let createTaskFromSelection: (String) -> Void
    /// 粘贴文件成附件。任务详情走 `TaskEditorHostActions.pasteFiles`，
    /// 笔记此前完全没接这条，所以 Finder 复制图片文件粘进正文没有任何反应。
    var pasteFiles: ([URL]) -> Void = { _ in }
    /// 斜杠 AI 命令（提取待办/总结/润色）：与右侧 AI 栏同一条管线
    /// （prepare → context → ask），结果也展示在 AI 栏里。默认空 = 未接线。
    var runAIAction: (NoteAIAction) -> Void = { _ in }
    /// 选中文字的 AI 动作：宿主接管后走右侧 AI 栏（输出 + 替换/插入回写）。
    /// 返回 false = 沿用独立选区浮窗。默认不接管，任务详情与测试宿主行为不变。
    var runSelectionAI: (AISelectionTarget, AIConversationPreset) -> Bool = { _, _ in false }
    /// `@` 提及候选（任务/笔记）；空 = 正文里 `@` 不弹补全。
    var mentionCandidates: () -> [DocumentMention] = { [] }
    /// 正文链接的应用内直达路由（`workfollow://`）；返回 false 走系统打开。
    /// 默认空 = 系统兜底（App 的 URL 事件同样能路由到目标）。
    var openLink: ((String) -> Bool)? = nil
    /// 行内日期/清单提醒的写入。默认由 make 接到笔记自己的任务存储；
    /// 直接构造（预览/测试宿主）不接则为空操作。
    var setChecklistReminder: (Int, Date?) -> Void = { _, _ in }
    /// 未授权通知时提醒面板底部的说明；nil 不显示。
    var checklistReminderNotice: () -> String? = { nil }

    @MainActor
    static func make(noteID: UUID, tasks: TaskWorkspaceModel, notes: NotesWorkspaceModel,
                     runAIAction: @escaping (NoteAIAction) -> Void = { _ in },
                     runSelectionAI: @escaping (AISelectionTarget, AIConversationPreset) -> Bool = { _, _ in false },
                     openLink: ((String) -> Bool)? = nil,
                     checklistReminderNotice: @escaping () -> String? = { nil }) -> Self {
        Self(createTaskFromSelection: { text in
            // 多行选区每行一条；任务侧回链 sourceNoteID，不再写 linkedTaskIDs
            // （关联任务区两侧都是 union 显示，AI 提取待办同一条回链语义）。
            _ = tasks.createTasksFromSelection(text, noteID: noteID)
        }, pasteFiles: { urls in
            guard let imported = try? NativeAttachmentFiles.importFiles(urls),
                  !imported.isEmpty else { return }
            notes.edit(noteID) { $0.attachments.append(contentsOf: imported) }
        }, runAIAction: runAIAction, runSelectionAI: runSelectionAI, mentionCandidates: {
            // `@` 提及候选：最近更新的任务在前，笔记按用户排序；排除本笔记与空标题。
            let taskMentions = tasks.allTasks.filter { task in
                task.deletedAt == nil && !task.isNoteTask && !task.title.trimmingCharacters(in: .whitespaces).isEmpty
            }.sorted { $0.updatedAt > $1.updatedAt }.prefix(50)
                .map { DocumentMention(id: $0.id, kind: .task, title: $0.title) }
            let noteMentions = notes.notes.filter { note in
                note.id != noteID && !note.title.trimmingCharacters(in: .whitespaces).isEmpty
            }.prefix(50).map { DocumentMention(id: $0.id, kind: .note, title: $0.title) }
            return Array(taskMentions) + Array(noteMentions)
        }, openLink: openLink,
           setChecklistReminder: { line, date in
               // 笔记即任务实体：提醒写入走笔记自己的任务存储，通知排程由
               // 提醒服务按正文扫描（检查项与带提醒的普通段落都覆盖）。
               _ = notes.setChecklistItemReminder(noteID, line: line, at: date)
           }, checklistReminderNotice: checklistReminderNotice)
    }
}

enum NoteDocumentProfile {
    static let slashFormatIDs = ["format.heading1", "format.heading2", "format.heading3",
                                 "format.bullet", "format.ordered", "format.checklist", "format.quote"]
    static func make(host: NoteEditorHostActions) -> DocumentProfile {
        var slashCommands = DocumentProfile.compactDocumentCommands(formatIDs: slashFormatIDs)
        slashCommands.append(contentsOf: aiSlashCommands(host: host))
        var profile = DocumentProfile(selectionActions: [
            DocumentSelectionAction(id: "note.createTask", title: "用所选文字创建任务",
                                    toolbarTitle: "创建任务", perform: host.createTaskFromSelection)
        ], noteSlash: true, selectionToolbarEnabled: true,
           slashCommandOverride: slashCommands,
           blockMenuCommands: DocumentProfile.standardBlockMenuCommands)
        // 与任务详情同一条粘贴链路：文件 → 宿主落盘成附件。
        profile.onPasteFiles = host.pasteFiles
        profile.mentionCandidates = host.mentionCandidates
        profile.onOpenLink = host.openLink
        profile.onSelectionAI = host.runSelectionAI
        profile.setChecklistReminder = host.setChecklistReminder
        profile.checklistReminderNotice = host.checklistReminderNotice
        return profile
    }

    /// 斜杠 AI 三动作：作用域是整篇笔记，与 AI 栏的三个按钮同语义同管线。
    /// 选中级 AI（改写选中文字）走选区浮条/右键菜单，由 `onSelectionAI` 接管，
    /// 宿主接进右侧 AI 栏；未接管的宿主仍回退到独立选区浮窗。
    private static func aiSlashCommands(host: NoteEditorHostActions) -> [DocumentCommand] {
        [("note.ai.tasks", "提取待办", .extract, "待办 任务 action ai"),
         ("note.ai.organize", "AI 总结", .organize, "总结 要点 summary ai"),
         ("note.ai.polish", "AI 润色", .polish, "润色 改写 polish ai")].map { id, title, action, keywords in
            DocumentCommand(id: id, title: title, group: "AI 助手", keywords: keywords,
                            web: { host.runAIAction(action) },
                            perform: { _ in host.runAIAction(action) })
        }
    }
}
