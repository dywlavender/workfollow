import SwiftUI

struct TaskInspectorShell: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let showBack: Bool
    @FocusState private var titleFocused: Bool
    @State private var presentation = TaskInspectorPresentationState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let task = workspace.selectedTask {
                HStack(spacing: WFSpace.md) {
                    if showBack {
                        Button { workspace.select(nil) } label: {
                            Label("返回", systemImage: "chevron.left")
                        }.buttonStyle(.plain)
                    }
                    Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                        .foregroundStyle(WFColors.secondaryText)
                    if let date = task.schedule.dueAt {
                        Label(date.formatted(date: .abbreviated, time: task.schedule.hasTime ? .shortened : .omitted),
                              systemImage: "calendar").foregroundStyle(WFColors.accent)
                    }
                    if let deadline = task.schedule.deadlineAt {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(WFColors.secondaryText)
                    }
                    Spacer()
                    Image(systemName: task.priority == .none ? "flag" : "flag.fill")
                        .foregroundStyle(task.priority == .none ? WFColors.secondaryText : .orange)
                }
                .font(WFType.body).padding(WFSpace.xl)
                Divider()
                TaskTitleField(task: task, workspace: workspace, focused: $titleFocused)
                    .id(task.id)
                    .padding(WFSpace.page)
                Text("添加描述…")
                    .font(WFType.body).foregroundStyle(WFColors.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .padding(.horizontal, WFSpace.page)
                Spacer(minLength: 0)
                Divider()
                Label(task.list.name, systemImage: "tray")
                    .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                    .padding(WFSpace.xl)
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
            presentation.editingTarget = focused ? .title : .none
        }
        .onChange(of: workspace.selectedTaskID) { _, _ in
            titleFocused = false
            presentation.editingTarget = .none
            presentation.activePopover = nil
        }
        .onExitCommand(perform: handleEscape)
    }

    private func handleEscape() {
        switch presentation.handleEscape(isNarrow: showBack) {
        case .dismissPopover:
            break
        case .endEditing:
            titleFocused = false
        case .returnToList:
            workspace.select(nil)
        case .keepInspector:
            break
        }
    }
}

private struct TaskTitleField: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    @FocusState.Binding var focused: Bool
    @State private var draft: String

    init(task: Task, workspace: TaskWorkspaceModel, focused: FocusState<Bool>.Binding) {
        self.task = task
        self.workspace = workspace
        self._focused = focused
        self._draft = State(initialValue: task.title)
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
