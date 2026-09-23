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
                Text("添加描述…")
                    .font(WFType.body).foregroundStyle(WFColors.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .padding(.horizontal, WFSpace.page)
                Spacer(minLength: 0)
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
            presentation.editingTarget = focused ? .title : .none
        }
        .onChange(of: workspace.selectedTaskID) { _, _ in
            presentation.synchronizeTitle(taskID: workspace.selectedTask?.id,
                                          title: workspace.selectedTask?.title ?? "")
            titleFocused = false
            presentation.editingTarget = .none
            presentation.activePopover = nil
        }
        .onExitCommand(perform: handleEscape)
        .onAppear {
            presentation.synchronizeTitle(taskID: workspace.selectedTask?.id,
                                          title: workspace.selectedTask?.title ?? "")
        }
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
            SchedulePopoverView(
                title: field.title,
                selectedDate: field.date(in: task),
                today: workspace.dateFromToday(0),
                tomorrow: workspace.dateFromToday(1),
                nextWeek: workspace.dateFromToday(7)
            ) { date in
                if field == .due {
                    _ = workspace.setDueDate(task.id, date)
                } else {
                    _ = workspace.setDeadline(task.id, date)
                }
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
            ForEach(TaskWorkspaceModel.inspectorLists, id: \.name) { list in
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

private struct SchedulePopoverView: View {
    let title: String
    let today: Date
    let tomorrow: Date
    let nextWeek: Date
    let onSelect: (Date?) -> Void
    @State private var customDate: Date

    init(title: String, selectedDate: Date?, today: Date, tomorrow: Date,
         nextWeek: Date, onSelect: @escaping (Date?) -> Void) {
        self.title = title
        self.today = today
        self.tomorrow = tomorrow
        self.nextWeek = nextWeek
        self.onSelect = onSelect
        self._customDate = State(initialValue: selectedDate ?? today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            Text(title).font(WFType.section)
            HStack {
                quickDate("今天", date: today)
                quickDate("明天", date: tomorrow)
                quickDate("下周", date: nextWeek)
            }
            Divider()
            DatePicker("自选日期", selection: $customDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: customDate) { _, date in onSelect(date) }
            Button("无日期") { onSelect(nil) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WFSpace.lg)
        .frame(width: 300)
    }

    private func quickDate(_ title: String, date: Date) -> some View {
        Button(title) { onSelect(date) }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
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
