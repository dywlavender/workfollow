import SwiftUI

struct TaskInspectorShell: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @EnvironmentObject private var environment: AppEnvironment
    let showBack: Bool
    @FocusState private var titleFocused: Bool
    @FocusState private var childTitleFocused: Bool
    @State private var presentation = TaskInspectorPresentationState()
    @State private var newListName = ""
    @State private var inlineChildEditorID: UUID?
    @State private var inlineChildTitleDraft = ""
    @State private var showNewList = false
    @State private var showTagsPopover = false
    @State private var showAttributesPopover = false
    @State private var showFormattingToolbar = false
    @State private var showRelationsPopover = false
    @State private var relationQuery = ""
    @StateObject private var editorHandle = DocumentEditorHandle()

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
                        Image(systemName: task.isAbandoned ? "circle.slash"
                                         : task.isClosed ? "checkmark.square.fill" : "square")
                            .foregroundStyle(task.isClosed ? WFColors.tertiaryText : WFColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(task.isClosed ? "恢复任务" : "完成任务")
                    .accessibilityLabel(task.isClosed ? "恢复任务" : "完成任务")
                    Divider().frame(height: WFMetrics.icon)
                    scheduleButton(task: task, field: .due)
                    Spacer()
                    priorityMenu(task)
                }
                .font(WFType.body)
                .padding(.horizontal, 24)
                .frame(height: 56)
                Divider()
                ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                TaskTitleField(task: task, workspace: workspace,
                               focused: $titleFocused, draft: $presentation.titleDraft)
                    .id(task.id)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                documentEditor(task)
                if task.parentID == nil {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(editorChildren(task.id)) { child in
                            childRow(child)
                            Divider().padding(.leading, 27)
                        }
                        Button {
                            workspace.requestChildTitleEditor(for: task.id)
                        } label: {
                            Label("添加子任务", systemImage: "plus")
                                .frame(minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain).foregroundStyle(WFColors.accent)
                    }.padding(.horizontal, 24).padding(.top, 12)
                } else if let parentID = task.parentID {
                    Button("返回父任务") { workspace.select(parentID) }.padding(.horizontal, WFSpace.page).padding(.bottom, 12)
                }
                }.padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    listMenu(task)
                    Spacer()
                    Button { showFormattingToolbar.toggle() } label: {
                        Image(systemName: "textformat").font(.system(size: 18))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(showFormattingToolbar ? WFColors.accent : WFColors.text)
                    .help("正文格式").accessibilityLabel("正文格式")
                    Menu {
                        if task.parentID == nil {
                            Button("添加子任务") { workspace.requestChildTitleEditor(for: task.id) }
                        }
                        Button(task.isPinned ? "取消置顶" : "置顶") { _ = workspace.setPinned(task.id, !task.isPinned) }
                        Button("标签…") { showTagsPopover = true }
                        Button("更多属性…") { showAttributesPopover = true }
                        Button("添加附件…") { addAttachments(to: task.id) }
                        Button("截止日期…") { presentation.activePopover = .deadline }
                        Button("转换为笔记") { _ = environment.convertTaskToNote(task.id) }
                        if !task.isClosed && task.recurrence != .never {
                            Button("跳过本周期") { workspace.skip(task.id) }
                                .disabled(RecurrenceEngine.next(for: task, now: workspace.clock(), calendar: workspace.calendar) == nil)
                        }
                        Button(task.isAbandoned ? "恢复任务" : "放弃任务") {
                            if task.isAbandoned { _ = workspace.restore(task.id) }
                            else { _ = workspace.abandon(task.id) }
                        }
                        .disabled(task.status == .completed)
                        Button("删除任务", role: .destructive) {
                            _ = workspace.delete(task.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden).fixedSize()
                    .help("更多操作")
                    .accessibilityLabel("更多任务操作")
                    .popover(isPresented: $showTagsPopover, arrowEdge: .top) {
                        TaskTagPickerPopover(initialTags: task.tags, workspace: workspace,
                            onCancel: { showTagsPopover = false },
                            onApply: { tags in
                                workspace.setTags(task.id, tags)
                                showTagsPopover = false
                            })
                    }
                    .popover(isPresented: $showAttributesPopover, arrowEdge: .top) {
                        ScrollView {
                            TaskAttributesView(task: workspace.task(for: task.id) ?? task,
                                               workspace: workspace)
                        }.frame(width: 320, height: 360)
                    }
                    .popover(isPresented: $showRelationsPopover, arrowEdge: .top) {
                        relationPicker(task)
                    }
                    .popover(isPresented: popoverBinding(.deadline), arrowEdge: .top) {
                        TaskDatePopoverV2(task: task, workspace: workspace, deadline: true) {
                            presentation.activePopover = nil
                        }
                    }
                }
                .font(WFType.body)
                .padding(.horizontal, 24)
                .frame(height: 48)
                .overlay(alignment: .bottomTrailing) {
                    if showFormattingToolbar {
                        formattingToolbar.padding(.horizontal, 16).padding(.bottom, 48)
                    }
                }
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
            showTagsPopover = false
            showAttributesPopover = false
            showFormattingToolbar = false
            showRelationsPopover = false
        }
        .onChange(of: workspace.pendingChildTitleEditorID) { _, _ in beginPendingChildEditing() }
        .onExitCommand {
            if childTitleFocused { finishInlineChildEditing() }
            else { _ = handleEscape() }
        }
        .onAppear {
            presentation.synchronizeTitle(taskID: workspace.selectedTask?.id,
                                          title: workspace.selectedTask?.title ?? "")
            beginPendingChildEditing()
        }
        .alert("移动到新清单", isPresented: $showNewList) {
            TextField("清单名称", text: $newListName)
            Button("取消", role: .cancel) {}
            Button("移动") {
                if let id = workspace.selectedTaskID {
                    if workspace.saveList(newListName) { _ = workspace.moveToList(id, TaskList(name: newListName)) }
                    else { TaskNamePrompt.invalidName() }
                }
            }.disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Menu {
                    ForEach([0, 1, 2, 14], id: \.self) { index in
                        let command = DocumentFormatCommand.commands[index]
                        Button(command.title) { editorHandle.format(command) }
                    }
                } label: { Image(systemName: "textformat.size").frame(width: 30, height: 30) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("标题").accessibilityLabel("标题格式")
                formatButton("粗体", "bold", 9)
                formatButton("高亮", "highlighter", 13)
                formatButton("检查项", "checklist", 7)
                formatButton("无序列表", "list.bullet", 5)
                formatButton("有序列表", "list.number", 6)
                Divider().frame(height: 18)
                formatButton("斜体", "italic", 10)
                formatButton("下划线", "underline", 11)
                formatButton("删除线", "strikethrough", 12)
                Button { editorHandle.insertDivider() } label: {
                    Image(systemName: "minus").frame(width: 26, height: 30)
                }.help("分割线").accessibilityLabel("分割线")
                Menu {
                    Button("日期") { editorHandle.insertTime(format: "yyyy年M月d日") }
                    Button("日期时间") { editorHandle.insertTime(format: "yyyy年M月d日 HH:mm") }
                    Button("仅时间") { editorHandle.insertTime(format: "HH:mm") }
                } label: {
                    Image(systemName: "clock").frame(width: 26, height: 30)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("插入当前时间").accessibilityLabel("插入当前时间")
                Button { editorHandle.editLink() } label: {
                    Image(systemName: "link").frame(width: 30, height: 30)
                }.help("链接").accessibilityLabel("链接")
                formatButton("行内代码", "chevron.left.forwardslash.chevron.right", 15)
                formatButton("引用", "text.quote", 3)
                Button { editorHandle.insertAttachment() } label: {
                    Image(systemName: "paperclip").frame(width: 30, height: 30)
                }.help("附件").accessibilityLabel("附件")
            }.buttonStyle(.plain).font(.system(size: 14))
                .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .frame(maxWidth: 444).frame(height: 38)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.border))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func formatButton(_ title: String, _ symbol: String, _ index: Int) -> some View {
        Button { editorHandle.format(DocumentFormatCommand.commands[index]) } label: {
            Image(systemName: symbol).frame(width: 26, height: 30)
        }.help(title).accessibilityLabel(title)
    }

    private func editorChildren(_ parentID: UUID) -> [Task] {
        workspace.allTasks.filter {
            $0.parentID == parentID && $0.deletedAt == nil && $0.skippedAt == nil && $0.convertedNoteID == nil
        }.sorted { $0.childOrder < $1.childOrder }
    }

    private func relationPicker(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索笔记", text: $relationQuery).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let notes = environment.notesWorkspace.notes.filter {
                        $0.deletedAt == nil && (relationQuery.isEmpty || ($0.title + $0.folder).localizedCaseInsensitiveContains(relationQuery))
                    }
                    if notes.isEmpty { Text("没有匹配的笔记").foregroundStyle(.secondary).padding() }
                    ForEach(notes) { note in
                        Button {
                            workspace.setSourceNote(task.id, note.id)
                            editorHandle.insertNoteReference(note)
                            showRelationsPopover = false
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                VStack(alignment: .leading) {
                                    Text(note.title.isEmpty ? "未命名笔记" : note.title).lineLimit(1)
                                    Text(note.folder).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if task.sourceNoteID == note.id { Image(systemName: "checkmark") }
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(16).frame(width: 320, height: 300)
    }

    private func openDocumentLink(_ link: String) -> Bool {
        guard let url = URL(string: link), url.scheme == "workfollow", url.host == "note" else { return false }
        if let id = UUID(uuidString: url.lastPathComponent),
           environment.notesWorkspace.notes.contains(where: { $0.id == id && $0.deletedAt == nil }) {
            environment.navigation.destination = .notes
            environment.notesWorkspace.selectedID = id
        }
        return true
    }

    private func childRow(_ child: Task) -> some View {
        HStack(spacing: 10) {
            Button { _ = workspace.changeStatus(child) } label: {
                Image(systemName: child.isAbandoned ? "circle.slash" : child.isClosed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
            }
            .accessibilityLabel(Text((child.isClosed ? "恢复子任务：" : "完成子任务：") + child.title))
            if inlineChildEditorID == child.id {
                TextField("子任务名称", text: $inlineChildTitleDraft)
                    .textFieldStyle(.plain)
                    .focused($childTitleFocused)
                    .onChange(of: inlineChildTitleDraft) { _, value in
                        _ = workspace.setTitle(child.id, value)
                    }
                    .onSubmit { finishInlineChildEditing() }
                    .accessibilityLabel("子任务标题")
            } else {
                Button(child.title.isEmpty ? "未命名子任务" : child.title) { workspace.select(child.id) }
            }
            Spacer(minLength: 8)
            TaskDateButton(task: child, workspace: workspace)
        }.buttonStyle(.plain).font(WFType.body)
            .foregroundStyle(child.isClosed ? WFColors.tertiaryText : WFColors.text)
            .frame(minHeight: 44)
            .contextMenu { Button("删除子任务") { _ = workspace.delete(child.id) } }
    }

    private func beginPendingChildEditing() {
        guard let childID = workspace.consumePendingChildTitleEditor() else { return }
        inlineChildEditorID = childID
        inlineChildTitleDraft = workspace.task(for: childID)?.title ?? ""
        DispatchQueue.main.async { childTitleFocused = true }
    }

    private func finishInlineChildEditing() {
        childTitleFocused = false
        inlineChildEditorID = nil
    }

    @MainActor
    private func addAttachments(to taskID: UUID) {
        NativeAttachmentFiles.choose { result in
            guard case .success(let attachments) = result,
                  let current = workspace.task(for: taskID) else { return }
            workspace.setAttachments(taskID, current.attachments + attachments)
        }
    }

    @discardableResult
    private func handleEscape() -> InspectorEscapeEffect {
        if showFormattingToolbar {
            showFormattingToolbar = false
            return .dismissPopover
        }
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
                    DocumentCommand(id: "task.child", title: "子任务", group: "插入", keywords: "subtask child") { _ in
                        workspace.requestChildTitleEditor(for: task.id)
                    }
                ].filter { _ in task.parentID == nil } + [
                    DocumentCommand(id: "task.tags", title: "标签", group: "插入") { _ in showTagsPopover = true },
                    DocumentCommand(id: "task.relation", title: "关联任务/笔记", group: "插入") { _ in
                        relationQuery = ""
                        showRelationsPopover = true
                    }
                ], taskSlash: true, onOpenLink: openDocumentLink),
                contentSized: true,
                handle: editorHandle
            )
            .id(task.id)

            if task.document.isEmpty {
                Text("添加描述…")
                    .font(WFType.body)
                    .foregroundStyle(WFColors.tertiaryText)
                    .padding(.top, 4)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
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
            TaskDatePopoverV2(task: task, workspace: workspace, deadline: field == .deadline) {
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
            Image(systemName: task.priority == .none ? "flag" : "flag.fill")
                .font(.system(size: 18))
                .foregroundStyle(task.priority == .none ? WFColors.secondaryText : task.priority == .high ? .red : task.priority == .medium ? .orange : WFColors.accent)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden).fixedSize()
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
            ForEach(workspace.allListNames, id: \.self) { name in
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
        .menuIndicator(.hidden).fixedSize()
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
        TaskDateLabel.text(date, hasTime: workspace.selectedTask?.schedule.hasTime == true && workspace.selectedTask?.schedule.dueAt == date,
                           now: workspace.clock(), calendar: workspace.calendar)
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
        TextField(task.parentID == nil ? "任务标题" : "准备做什么？", text: $draft, axis: .vertical)
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
