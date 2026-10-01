import Foundation

struct NoteEditorHostActions {
    let createTaskFromSelection: (String) -> Void

    @MainActor
    static func make(noteID: UUID, tasks: TaskWorkspaceModel, notes: NotesWorkspaceModel) -> Self {
        Self(createTaskFromSelection: { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let id = tasks.createTask(title: trimmed, in: .inbox).taskID else { return }
            notes.edit(noteID) { $0.linkedTaskIDs.append(id) }
        })
    }
}

enum NoteDocumentProfile {
    static let slashFormatIDs = ["format.heading1", "format.heading2", "format.heading3",
                                 "format.bullet", "format.ordered", "format.checklist", "format.quote"]
    static func make(host: NoteEditorHostActions) -> DocumentProfile {
        DocumentProfile(selectionActions: [
            DocumentSelectionAction(id: "note.createTask", title: "用所选文字创建任务",
                                    toolbarTitle: "创建任务", perform: host.createTaskFromSelection)
        ], noteSlash: true, selectionToolbarEnabled: true,
           slashCommandOverride: DocumentProfile.compactDocumentCommands(formatIDs: slashFormatIDs))
    }
}
