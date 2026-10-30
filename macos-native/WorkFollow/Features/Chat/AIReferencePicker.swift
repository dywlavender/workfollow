import SwiftUI

struct AIReferencePicker: View {
    let select: (AIConversationReference) -> Void
    @EnvironmentObject private var environment: AppEnvironment
    @State private var query = ""
    private var choices: [AIConversationReference] {
        let notes = environment.notesWorkspace.notes.filter { $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
            .map { AIConversationReference(id: $0.id, kind: "note", title: $0.title.isEmpty ? "未命名笔记" : $0.title) }
        let tasks = environment.taskWorkspace.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil && !$0.isClosed }
            .sorted { $0.updatedAt > $1.updatedAt }.map { AIConversationReference(id: $0.id, kind: "task", title: $0.title) }
        return (notes + tasks).filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("查找笔记或待办", text: $query).textFieldStyle(.roundedBorder)
            if let note = environment.notesWorkspace.selected, note.deletedAt == nil {
                Button("引用当前笔记：\(note.title.isEmpty ? "未命名笔记" : note.title)") {
                    select(.init(id: note.id, kind: "note", title: note.title.isEmpty ? "未命名笔记" : note.title))
                }.buttonStyle(.plain)
            }
            if let task = environment.taskWorkspace.selectedTask {
                Button("引用当前任务：\(task.title)") { select(.init(id: task.id, kind: "task", title: task.title)) }.buttonStyle(.plain)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(choices.prefix(40))) { reference in
                        Button { select(reference) } label: {
                            Label(reference.title, systemImage: reference.kind == "note" ? "text.document" : "checkmark.square")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain).workflowActionAnchor("ai.reference.\(reference.id)")
                    }
                    if choices.isEmpty { Text("没有匹配的资料").foregroundStyle(WFColors.secondaryText) }
                }
            }
            .compactScrollbars()
        }.font(WFType.body).padding(16).frame(width: 340, height: 390)
    }
}
