import SwiftUI

/// Task actions wrap the same floating editor used by notes.
struct FloatingTaskView: View {
    let taskID: UUID
    @ObservedObject var workspace: TaskWorkspaceModel
    let environment: AppEnvironment?
    let editorHandle: DocumentEditorHandle
    let onClose: () -> Void
    let onOpenInMain: () -> Void
    private enum Picker { case tags, relation }
    @State private var picker: Picker?

    var body: some View {
        if let task = workspace.task(for: taskID), task.deletedAt == nil {
            FloatingEditorView(documentID: taskID,
                title: Binding(get: { workspace.task(for: taskID)?.title ?? "" },
                               set: { _ = workspace.setTitle(taskID, $0) }),
                titlePlaceholder: "未命名任务",
                titleAccessibilityLabel: "任务标题",
                document: task.document,
                onDocumentChange: { _ = workspace.setDocument(taskID, $0) },
                profile: profile(task), editorHandle: editorHandle,
                onClose: onClose, actions: actions(task),
                topBar: {
                    FloatingTaskTopBar(taskID: taskID, workspace: workspace)
                })
        }
    }

    private func profile(_ task: Task) -> DocumentProfile {
        TaskDocumentProfile.make(task: task, host: TaskEditorHostActions(
            createChild: {
                onOpenInMain()
                workspace.requestChildTitleEditor(for: taskID)
            },
            openTags: { picker = .tags }, openRelation: { picker = .relation },
            openLink: { link in
                guard let url = URL(string: link) else { return false }
                return environment?.openResourceLink(url) ?? false
            },
            availableTags: { workspace.tagNames },
            addTag: { tag in
                guard let current = workspace.task(for: taskID), !current.tags.contains(tag) else { return }
                workspace.setTags(taskID, current.tags + [tag])
            },
            availableLists: { workspace.availableListNames.filter { $0 != task.list.name } },
            moveToList: { _ = workspace.moveToList(taskID, TaskList(name: $0)) },
            pasteFiles: { urls in
                guard let imported = try? NativeAttachmentFiles.importFiles(urls), !imported.isEmpty,
                      let current = workspace.task(for: taskID) else { return }
                workspace.setAttachments(taskID, current.attachments + imported)
            },
            checklistItem: { line in
                workspace.checklistItemMeta(taskID, line: line)
            },
            setChecklistReminder: { line, date in
                _ = workspace.setChecklistItemReminder(taskID, line: line, at: date)
            },
            checklistReminderNotice: { environment?.reminders.checklistReminderNotice }))
    }

    private func actions(_ task: Task) -> some View {
        HStack(spacing: 10) {
            Button { picker = picker == .tags ? nil : .tags } label: {
                Image(systemName: "tag").frame(width: 24, height: 24)
            }
            .hoverTip("标签")
            .background(AnchoredPropertyPanel(isPresented: binding(.tags),
                width: PopupMetrics.tagPickerWidth, prefersAbove: true,
                placement: .verticalInOwner, title: "任务标签") {
                    TaskTagPickerPopover(initialTags: task.tags, workspace: workspace,
                        onCancel: { picker = nil }, onApply: { tags in
                            workspace.setTags(taskID, tags)
                            picker = nil
                        })
                })
            Button { picker = picker == .relation ? nil : .relation } label: {
                Image(systemName: "link").frame(width: 24, height: 24)
            }
            .hoverTip("关联任务或笔记")
            .background(AnchoredPropertyPanel(isPresented: binding(.relation),
                width: PopupMetrics.relationPickerWidth, prefersAbove: true,
                placement: .verticalInOwner, title: "任务关联") {
                    TaskRelationPicker(sourceTaskID: taskID, tasks: workspace.allTasks,
                        notes: environment?.notesWorkspace.notes ?? [], sourceNoteID: task.sourceNoteID,
                        onSelect: { target in
                            guard TaskRelationSelection.apply(target, sourceTaskID: taskID,
                                workspace: workspace, notes: environment?.notesWorkspace.notes ?? [],
                                handle: editorHandle) else { return false }
                            picker = nil
                            return true
                        }, onCancel: { picker = nil })
                })
        }
        .buttonStyle(.plain).foregroundStyle(WFColors.secondaryText)
    }

    private func binding(_ value: Picker) -> Binding<Bool> {
        Binding(get: { picker == value }, set: { if !$0, picker == value { picker = nil } })
    }
}
