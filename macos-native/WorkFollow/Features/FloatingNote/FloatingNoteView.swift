import SwiftUI

/// Note adapter: persistence and note actions stay in the note module.
struct FloatingNoteView: View {
    let noteID: UUID
    @ObservedObject var notes: NotesWorkspaceModel
    let tasks: TaskWorkspaceModel
    let editorHandle: DocumentEditorHandle
    let focusAtEnd: Bool
    let onClose: () -> Void

    var body: some View {
        if let note = notes.notes.first(where: { $0.id == noteID && $0.deletedAt == nil }) {
            FloatingEditorView(documentID: noteID,
                title: Binding(get: { notes.notes.first(where: { $0.id == noteID })?.title ?? "" },
                               set: { value in notes.edit(noteID) { $0.title = value } }),
                titlePlaceholder: "未命名笔记",
                titleAccessibilityLabel: "笔记标题",
                document: note.document,
                onDocumentChange: { document in notes.edit(noteID) { $0.document = document } },
                profile: NoteDocumentProfile.make(host: NoteEditorHostActions.make(
                    noteID: noteID, tasks: tasks, notes: notes)),
                editorHandle: editorHandle, focusAtEnd: focusAtEnd,
                onClose: onClose, actions: EmptyView(),
                topBar: {
                    HStack {
                        Text(NoteDateLabel.tickStyle(note.updatedAt))
                            .font(WFType.body.weight(.medium))
                            .foregroundStyle(WFColors.accent)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, FloatingEditorMetrics.contentHorizontalPadding)
                    .frame(height: FloatingEditorMetrics.topBarHeight)
                })
        }
    }
}
