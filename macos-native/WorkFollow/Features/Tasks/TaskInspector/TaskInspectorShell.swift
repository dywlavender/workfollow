import SwiftUI

struct TaskInspectorShell: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let showBack: Bool
    @FocusState private var titleFocused: Bool
    @State private var presentation = TaskInspectorPresentationState()
    @State private var newListName = ""
    @State private var showNewList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let task = workspace.selectedTask {
                HStack(spacing: WFSpace.md) {
                    if showBack {
                        Button { workspace.select(nil) } label: {
                            Label("返回", systemImage: "chevron.left")
                        }.buttonStyle(.plain)
                    }
                    Button {
                        _ = workspace.changeStatus(task)
                    } label: {
                        Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                            .foregroundStyle(task.status == .completed ? WFColors.tertiaryText : WFColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(task.status == .completed ? "恢复任务" : "完成任务")
                    .accessibilityLabel(task.status == .completed ? "恢复任务" : "完成任务")
                    Divider().frame(height: WFMetrics.icon)
                    scheduleButton(task: task, field: .due)
                    scheduleButton(task: task, field: .deadline)
                    Spacer()
                    priorityMenu(task)
                }
                .font(WFType.body).padding(WFSpace.xl)
                Divider()
                TaskTitleField(task: task, workspace: workspace,
                               focused: $titleFocused, draft: $presentation.titleDraft)
                    .id(task.id)
                    .padding(WFSpace.page)
                documentEditor(task)
                TaskAttributesView(task: task, workspace: workspace).id(task.id)
                if task.parentID == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("子任务").font(WFType.section)
                            Spacer()
                            Button {
                                if let id = workspace.createChild(task.id).taskID { workspace.select(id) }
                            } label: { Image(systemName: "plus") }
                        }
                        ForEach(workspace.allTasks.filter { $0.parentID == task.id && $0.deletedAt == nil }.sorted { $0.childOrder < $1.childOrder }) { child in
                            HStack {
                                Button { _ = workspace.changeStatus(child) } label: {
                                    Image(systemName: child.status == .completed ? "checkmark.square.fill" : "square")
                                }
                                Button(child.title.isEmpty ? "未命名子任务" : child.title) { workspace.select(child.id) }
                                Spacer()
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, WFSpace.page).padding(.vertical, 12)
                } else if let parentID = task.parentID {
                    Button("返回父任务") { workspace.select(parentID) }.padding(.horizontal, WFSpace.page).padding(.bottom, 12)
                }
                Divider()
                HStack {
                    listMenu(task)
                    Spacer()
                    Menu {
                        Button("删除任务", role: .destructive) {
                            _ = workspace.delete(task.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .help("更多操作")
                    .accessibilityLabel("更多任务操作")
                }
                .font(WFType.body)
                .padding(.horizontal, WFSpace.xl)
                .padding(.vertical, WFSpace.md)
            } else {
                Spacer()
                VStack(spacing: WFSpace.md) {
                    Image(systemName: "hand.point.up.left").font(.title2)
                    Text("选择一个任务").font(WFType.body)
                }
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .onChange(of: titleFocused) { _, focused in
            if focused {
                presentation.editingTarget = .title
            } else if presentation.editingTarget == .title {
                presentation.editingTarget = .none
            }
        }
        .onChange(of: workspace.selectedTaskID) { _, _ in
            presentation.synchronizeTitle(taskID: workspace.selectedTask?.id,
                                          title: workspace.selectedTask?.title ?? "")
            titleFocused = false
            presentation.editingTarget = .none
            presentation.activePopover = nil
        }
        .onExitCommand { _ = handleEscape() }
        .onAppear {
            presentation.synchronizeTitle(taskID: workspace.selectedTask?.id,
                                          title: workspace.selectedTask?.title ?? "")
        }
        .alert("移动到新清单", isPresented: $showNewList) {
            TextField("清单名称", text: $newListName)
            Button("取消", role: .cancel) {}
            Button("移动") {
                if let id = workspace.selectedTaskID { _ = workspace.moveToList(id, TaskList(name: newListName)) }
            }.disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @discardableResult
    private func handleEscape() -> InspectorEscapeEffect {
        let previousTarget = presentation.editingTarget
        let effect = presentation.handleEscape(isNarrow: showBack)
        switch effect {
        case .dismissPopover:
            break
        case .endEditing:
            if previousTarget == .title { titleFocused = false }
        case .returnToList:
            workspace.select(nil)
        case .keepInspector:
            break
        }
        return effect
    }

    private func documentEditor(_ task: Task) -> some View {
        ZStack(alignment: .topLeading) {
            DocumentEditor(
                documentID: task.id,
                document: task.document,
                onDocumentChange: { _ = workspace.setDocument(task.id, $0) },
                onEscape: handleEscape,
                onEditingChanged: { isEditing in
                    if isEditing {
                        presentation.editingTarget = .body
                    } else if presentation.editingTarget == .body {
                        presentation.editingTarget = .none
                    }
                },
                profile: DocumentProfile(commands: [
                    DocumentCommand(id: "task.child", title: "创建子任务", group: "任务", keywords: "subtask child") { _ in
                        if let id = workspace.createChild(task.id).taskID { workspace.select(id) }
                    }
                ].filter { _ in task.parentID == nil })
            )
            .id(task.id)

            if task.document.isEmpty {
                Text("添加描述…")
                    .font(WFType.body)
                    .foregroundStyle(WFColors.tertiaryText)
                    .padding(.top, WFSpace.md)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, WFSpace.page)
    }

    private func scheduleButton(task: Task, field: ScheduleField) -> some View {
        Button {
            presentation.activePopover = field.popover
        } label: {
            Label(field.date(in: task).map(dateLabel) ?? field.emptyLabel,
                  systemImage: field.symbol)
                .foregroundStyle(field.date(in: task) == nil ? WFColors.secondaryText : WFColors.accent)
        }
        .buttonStyle(.plain)
        .help(field.emptyLabel)
        .accessibilityLabel(field.date(in: task).map { "\(field.emptyLabel)：\(dateLabel($0))" } ?? field.emptyLabel)
        .popover(isPresented: popoverBinding(field.popover), arrowEdge: .bottom) {
            TaskDatePopover(task: task, workspace: workspace, deadline: field == .deadline) {
                presentation.activePopover = nil
            }
        }
    }

    private func priorityMenu(_ task: Task) -> some View {
        Menu {
            priorityItem(.none, task: task)
            priorityItem(.low, task: task)
            priorityItem(.medium, task: task)
            priorityItem(.high, task: task)
        } label: {
            Label(priorityTitle(task.priority), systemImage: task.priority == .none ? "flag" : "flag.fill")
                .foregroundStyle(task.priority == .none ? WFColors.secondaryText : .orange)
        }
        .menuStyle(.borderlessButton)
        .help("优先级")
        .accessibilityLabel("优先级：\(priorityTitle(task.priority))")
    }

    private func priorityItem(_ priority: TaskPriority, task: Task) -> some View {
        Button {
            _ = workspace.setPriority(task.id, priority)
        } label: {
            if task.priority == priority {
                Label(priorityTitle(priority), systemImage: "checkmark")
            } else {
                Text(priorityTitle(priority))
            }
        }
    }

    private func listMenu(_ task: Task) -> some View {
        Menu {
            ForEach(Array(Set(TaskWorkspaceModel.inspectorLists.map(\.name) + workspace.allTasks.map { $0.list.name })).sorted(), id: \.self) { name in
                let list = TaskList(name: name)
                Button {
                    _ = workspace.moveToList(task.id, list)
                } label: {
                    if task.list == list {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
            Divider()
            Button("新清单…") { newListName = ""; showNewList = true }
        } label: {
            Label(task.list.name, systemImage: "tray")
                .foregroundStyle(WFColors.secondaryText)
        }
        .menuStyle(.borderlessButton)
        .disabled(!workspace.canMoveToList(task.id))
        .help(task.parentID == nil ? "移动到清单" : "子任务跟随父任务清单")
        .accessibilityLabel(task.parentID == nil ? "清单：\(task.list.name)" : "清单：\(task.list.name)，子任务跟随父任务")
    }

    private func popoverBinding(_ popover: InspectorPopover) -> Binding<Bool> {
        Binding(
            get: { presentation.activePopover == popover },
            set: { presented in
                if presented {
                    presentation.activePopover = popover
                } else if presentation.activePopover == popover {
                    presentation.activePopover = nil
                }
            }
        )
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无优先级"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

private enum ScheduleField: Equatable {
    case due
    case deadline

    var popover: InspectorPopover { self == .due ? .schedule : .deadline }
    var emptyLabel: String { self == .due ? "安排日期" : "截止日期" }
    var title: String { self == .due ? "安排日期" : "截止日期" }
    var symbol: String { self == .due ? "calendar" : "calendar.badge.exclamationmark" }

    func date(in task: Task) -> Date? {
        self == .due ? task.schedule.dueAt : task.schedule.deadlineAt
    }
}

private struct TaskTitleField: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    @FocusState.Binding var focused: Bool
    @Binding var draft: String

    init(task: Task, workspace: TaskWorkspaceModel, focused: FocusState<Bool>.Binding,
         draft: Binding<String>) {
        self.task = task
        self.workspace = workspace
        self._focused = focused
        self._draft = draft
    }

    var body: some View {
        TextField("任务名称", text: $draft)
            .textFieldStyle(.plain)
            .font(WFType.detailTitle)
            .focused($focused)
            .onChange(of: draft) { _, value in
                _ = workspace.setTitle(task.id, value)
            }
            .onChange(of: task.title) { _, value in
                if !focused { draft = value }
            }
            .onSubmit { focused = false }
            .accessibilityLabel("任务标题")
    }
}
