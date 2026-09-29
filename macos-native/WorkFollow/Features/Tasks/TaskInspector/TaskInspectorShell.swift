import SwiftUI

/// 任务详情：顶部状态/日期/优先级，标题与正文连续编辑，一级子任务跟在正文后；
/// 底部清单入口与正文格式、更多操作入口固定显示。
struct TaskInspectorShell: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @EnvironmentObject private var environment: AppEnvironment
    let showBack: Bool
    /// 浮层里的详情（日历/四象限点任务条打开的那个）：Esc 要关掉浮层，而不是
    /// 把选中项清掉后留在原地不动——对齐 Flutter `TaskInspector._escape()` 的
    /// `_isPopup` 分支（它排在"退回列表"之前）。
    var onRequestClose: (() -> Void)? = nil
    @FocusState private var titleFocused: Bool
    @FocusState private var childTitleFocused: Bool
    @State private var presentation = TaskInspectorPresentationState()
    @State private var newListName = ""
    @State private var inlineChildEditorID: UUID?
    @State private var inlineChildTitleDraft = ""
    @State private var showNewList = false
    @State private var showTagsPopover = false
    @State private var showAttributesPopover = false
    @State private var showMoreActionsPopover = false
    @State private var showFormattingToolbar = false
    @State private var showRelationsPopover = false
    @State private var relationQuery = ""
    /// 「添加子任务」整行的悬停态（原版 `InkWell.hoverColor`）。
    @State private var hoveringAddChild = false
    @StateObject private var editorHandle = DocumentEditorHandle()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let task = workspace.selectedTask {
                headerBar(task)
                Divider()
                GeometryReader { viewport in
                    ScrollView {
                        inspectorContent(task)
                            .frame(minWidth: viewport.size.width,
                                   minHeight: viewport.size.height,
                                   alignment: .topLeading)
                            .background {
                                // 点击编辑栏空白处：光标送到最近的输入行（文末），
                                // 与笔记页的空白点按行为一致；文字行上的点击仍由
                                // 文本视图自己按就近字符定位。
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture { editorHandle.focusEnd() }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                bottomBar(task)
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
        .overlay {
            if let task = workspace.selectedTask, hasFooterPopover {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismissFooterPopover)
                    footerPopover(task)
                        .padding(.trailing, WFSpace.xl)
                        .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(20)
            }
        }
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
            showMoreActionsPopover = false
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

    // MARK: - 顶部：状态框 + 日期 + 优先级

    private func headerBar(_ task: Task) -> some View {
        HStack(spacing: WFSpace.sm) {
            if showBack {
                Button { workspace.select(nil) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("返回列表")
                .accessibilityLabel("返回列表")
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
            scheduleChip(task, field: .due)
            priorityMenu(task)
            Spacer(minLength: 0)
            // 滴答式：右上角专注与置顶常驻入口。
            Button {
                environment.startFocus(for: task.id)
            } label: {
                Image(systemName: "timer")
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: 24, height: WFMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("开始专注")
            .accessibilityLabel("开始专注")
            Button {
                _ = workspace.setPinned(task.id, !task.isPinned)
            } label: {
                Image(systemName: task.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(task.isPinned ? WFColors.accent : WFColors.secondaryText)
                    .frame(width: 24, height: WFMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isPinned ? "取消置顶" : "置顶")
            .accessibilityLabel(task.isPinned ? "取消置顶" : "置顶任务")
        }
        .padding(.horizontal, WFSpace.xl)
        .frame(height: 48)
    }

    private func moreMenu(_ task: Task) -> some View {
        Button { showMoreActionsPopover = true } label: {
            Image(systemName: "ellipsis")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("更多操作")
        .accessibilityLabel("更多任务操作")
    }

    private var hasFooterPopover: Bool {
        showMoreActionsPopover || showTagsPopover || showAttributesPopover ||
            showRelationsPopover || presentation.activePopover == .deadline
    }

    @ViewBuilder
    private func footerPopover(_ task: Task) -> some View {
        Group {
            if showMoreActionsPopover {
                moreActionsPopover(task)
            } else if showTagsPopover {
                TaskTagPickerPopover(initialTags: task.tags, workspace: workspace,
                    onCancel: { showTagsPopover = false },
                    onApply: { tags in
                        workspace.setTags(task.id, tags)
                        showTagsPopover = false
                    })
            } else if showAttributesPopover {
                ScrollView {
                    TaskAttributesView(task: workspace.task(for: task.id) ?? task,
                                       onEscape: dismissFooterPopover,
                                       workspace: workspace)
                }
                .frame(width: 320, height: 300)
            } else if showRelationsPopover {
                relationPicker(task)
            } else if presentation.activePopover == .deadline {
                TaskDatePopoverV2(task: task, workspace: workspace, deadline: true) {
                    presentation.activePopover = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WFColors.border))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private func dismissFooterPopover() {
        showMoreActionsPopover = false
        showTagsPopover = false
        showAttributesPopover = false
        showRelationsPopover = false
        if presentation.activePopover == .deadline {
            presentation.activePopover = nil
        }
    }

    private func moreActionsPopover(_ task: Task) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                if task.parentID == nil {
                    moreAction("添加子任务", symbol: "list.bullet.indent") {
                        workspace.requestChildTitleEditor(for: task.id)
                    }
                }
                moreAction(task.isPinned ? "取消置顶" : "置顶", symbol: "pin") {
                    _ = workspace.setPinned(task.id, !task.isPinned)
                }
                moreAction("标签…", symbol: "tag") { showTagsPopover = true }
                moreAction("更多属性…", symbol: "slider.horizontal.3") { showAttributesPopover = true }
                moreAction("添加附件…", symbol: "paperclip") { addAttachments(to: task.id) }
                moreAction("截止日期…", symbol: "calendar.badge.exclamationmark") {
                    presentation.activePopover = .deadline
                }
                moreAction("转换为笔记", symbol: "doc.text") {
                    _ = environment.convertTaskToNote(task.id)
                }
                moreAction("保存为模板…", symbol: "doc.badge.plus") { saveAsTemplate() }
                if !task.isClosed && task.recurrence != .never {
                    moreAction("跳过本周期", symbol: "arrow.forward.end") {
                        workspace.skip(task.id)
                    }
                    .disabled(RecurrenceEngine.next(for: task, now: workspace.clock(), calendar: workspace.calendar) == nil)
                }
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                moreAction(task.isAbandoned ? "恢复任务" : "放弃任务", symbol: "arrow.uturn.backward") {
                    if task.isAbandoned { _ = workspace.restore(task.id) }
                    else { _ = workspace.abandon(task.id) }
                }
                .disabled(task.status == .completed)
                moreAction("删除任务", symbol: "trash", destructive: true) {
                    _ = workspace.delete(task.id)
                }
            }
            .padding(8)
        }
        .frame(width: 208, height: 368)
    }

    private func moreAction(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            showMoreActionsPopover = false
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(WFType.menu)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? Color.red : WFColors.text)
        .padding(.horizontal, 8)
    }

    // MARK: - 主体：标题 → 正文 → 一级子任务

    private func inspectorContent(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskTitleField(task: task, workspace: workspace,
                           focused: $titleFocused, draft: $presentation.titleDraft)
                .id(task.id)
                .padding(.horizontal, WFSpace.xl)
                .padding(.top, WFSpace.lg)
                .padding(.bottom, WFSpace.md)
            documentEditor(task)
                .padding(.top, WFSpace.sm)
            // 子任务区只在**已经有子任务**时出现——新建的空任务不自动带上它。
            // 原版 `task_editor_profile.dart:149-153` 就是这么挂的：
            // `if (!task.isChildTask && childrenOf(task.id).isNotEmpty)`，注释写着
            // "空父任务保持整屏正文；第一个子任务从更多菜单、行右键菜单或 / 面板来"。
            if task.parentID == nil, !editorChildren(task.id).isEmpty {
                subtaskSection(task)
                    .padding(.top, WFSpace.xl)
            } else if let parentID = task.parentID {
                Button("返回父任务") { workspace.select(parentID) }
                    .buttonStyle(.plain)
                    .foregroundStyle(WFColors.accent)
                    .font(WFType.control)
                    .padding(.horizontal, WFSpace.xl)
                    .padding(.top, WFSpace.md)
            }
        }
        .padding(.bottom, WFSpace.xl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func chipLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) { content() }
            .font(WFType.control)
            .lineLimit(1)
            .padding(.horizontal, WFSpace.sm)
            .frame(height: 26)
            .background(WFColors.secondarySurface, in: Capsule())
    }

    /// 顶部日期入口；点击仍使用现有日期 popover。
    private func scheduleChip(_ task: Task, field: ScheduleField) -> some View {
            Button {
                presentation.activePopover = field.popover
            } label: {
                chipLabel {
                    Image(systemName: field.symbol)
                    Text(scheduleChipLabel(task, field: field))
                }
                .foregroundStyle(scheduleChipColor(task, field: field))
            }
            .buttonStyle(.plain)
            .help(field.emptyLabel)
            .accessibilityLabel(field.date(in: task).map { "\(field.emptyLabel)：\(dateLabel($0))" } ?? field.emptyLabel)
        .schedulePopover(isPresented: popoverBinding(field.popover)) {
            TaskDatePopoverV2(task: task, workspace: workspace, deadline: field == .deadline) {
                presentation.activePopover = nil
            }
        }
    }

    private func scheduleChipColor(_ task: Task, field: ScheduleField) -> Color {
        guard field == .due, !task.isClosed else { return WFColors.secondaryText }
        switch TaskListViewDefaults.dateBadgeStyle(dueAt: task.schedule.dueAt, isClosed: task.isClosed,
                                                   now: workspace.clock(), calendar: workspace.calendar) {
        case .overdue: return .red
        case .today, .scheduled: return WFColors.accent
        case .none: return WFColors.secondaryText
        }
    }

    private func subtaskSection(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(editorChildren(task.id)) { child in
                childRow(child)
                Divider().padding(.leading, 27)
            }
            // 一级子任务不再给这个入口：原版 `_addChildTask` 对子任务直接 return，
            // 动作层也会以"子任务不能再建子任务"失败，留着它只是个点了没反应的入口。
            if task.parentID == nil { addChildRow(task) }
        }
        .padding(.horizontal, WFSpace.xl)
        .padding(.top, WFSpace.md)
    }

    /// 「添加子任务」整行。
    ///
    /// 与原版的 add row（`task_children_panel.dart` 里 `task-add-child` 那一段）
    /// 逐项对齐：`＋` 图标 18、文字 14 medium、两者都用强调色，行高 42，悬停时整行
    /// 染强调色最浅的一档（`accentFaint`）并收 `control` 圆角；文字与上面子任务行的
    /// 标题列同一条竖线（原版注释：inset like the child rows above it）。
    ///
    /// 原先这里是一个 12pt 的 `Label`、行高 36、没有悬停反馈，点起来像一句静态说明。
    private func addChildRow(_ task: Task) -> some View {
        Button {
            workspace.requestChildTitleEditor(for: task.id)
        } label: {
            HStack(spacing: WFSpace.dense) {
                Image(systemName: "plus").font(.system(size: WFMetrics.icon))
                Text("添加子任务").font(WFType.listTitleMedium)
                Spacer(minLength: 0)
            }
            .foregroundStyle(WFColors.accent)
            .padding(.horizontal, WFSpace.sm)
            .frame(minHeight: 42, alignment: .leading)
            .contentShape(Rectangle())
            .background(hoveringAddChild ? WFColors.accentFaint : .clear,
                        in: RoundedRectangle(cornerRadius: WFSpace.compact))
        }
        .buttonStyle(.plain)
        // 悬停底色比内容再宽 8：图标仍落在子任务行勾选框那条竖线上，底色却像原版那
        // 样比文字内容宽一圈。
        .padding(.horizontal, -WFSpace.sm)
        .onHover { hoveringAddChild = $0 }
        .help("添加子任务")
        .accessibilityLabel("添加子任务")
    }

    // MARK: - 底部工具行：左清单选择，右正文格式与更多操作

    private func bottomBar(_ task: Task) -> some View {
        HStack(spacing: WFSpace.xs) {
            listMenu(task)
            Spacer(minLength: 0)
            Button {
                let isOpening = !showFormattingToolbar
                showFormattingToolbar.toggle()
                if isOpening { editorHandle.focusEditor() }
            } label: {
                Image(systemName: "textformat")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showFormattingToolbar ? WFColors.accent : WFColors.secondaryText)
            .help("正文格式").accessibilityLabel("正文格式")
            moreMenu(task)
        }
        .font(WFType.body)
        .padding(.horizontal, WFSpace.xl)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            if showFormattingToolbar {
                formattingToolbar.padding(.horizontal, 16).padding(.bottom, 48)
            }
        }
    }

    private var formattingToolbar: some View {
        // 宽度与提示文案都取原版默认值（444 / 「上传附件」），不再在调用点上改写。
        DocumentFormatToolbarView(handle: editorHandle)
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
                    .font(.system(size: 15))
                    .foregroundStyle(child.isClosed ? WFColors.tertiaryText : WFColors.secondaryText)
            }
            .help(child.isClosed ? "恢复任务" : "完成任务")
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
                    // 滴答式：未完成子任务标题灰显，与正文区分层级。
                    .foregroundStyle(child.isClosed ? WFColors.tertiaryText : WFColors.secondaryText)
            }
            Spacer(minLength: 8)
            TaskDateButton(task: child, workspace: workspace)
        }.buttonStyle(.plain).font(WFType.listTitleMedium)
            .frame(minHeight: 40)
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

    @MainActor
    private func saveAsTemplate() {
        guard let task = workspace.selectedTask else { return }
        guard let name = TaskNamePrompt.ask("保存为模板", value: task.title, confirm: "保存"),
              !name.isEmpty else { return }
        let children = workspace.allTasks.filter {
            $0.parentID == task.id && $0.deletedAt == nil && $0.skippedAt == nil &&
                !$0.isAbandoned && !$0.isConverted
        }.sorted { $0.childOrder < $1.childOrder }
        if TemplateStore.shared.contains(name: name) {
            guard TaskNamePrompt.confirm("模板“\(name)”已存在",
                                         message: "是否用当前任务替换这个模板？") else { return }
        }
        _ = TemplateStore.shared.save(name: name, from: task,
                                      includingChildren: children, forceReplace: true)
    }

    @discardableResult
    private func handleEscape() -> InspectorEscapeEffect {
        if hasFooterPopover {
            dismissFooterPopover()
            return .dismissPopover
        }
        if showFormattingToolbar {
            showFormattingToolbar = false
            return .dismissPopover
        }
        // 浮层优先于"退回列表"：原版里 popup 的 Esc 就是把浮层关掉。
        if let onRequestClose {
            onRequestClose()
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
        .padding(.horizontal, WFSpace.xl)
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

    private func priorityMenu(_ task: Task) -> some View {
        Menu {
            priorityItem(.none, task: task)
            priorityItem(.low, task: task)
            priorityItem(.medium, task: task)
            priorityItem(.high, task: task)
        } label: {
            Image(systemName: task.priority == .none ? "flag" : "flag.fill")
                .foregroundStyle(priorityColor(task.priority))
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden).fixedSize()
        .help("优先级")
        .accessibilityLabel("优先级：\(priorityTitle(task.priority))")
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
                .font(WFType.control)
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

    /// 滴答式逾期上下文：日期 chip 里附带"延期 N 天"。
    private func scheduleChipLabel(_ task: Task, field: ScheduleField) -> String {
        guard let date = field.date(in: task) else { return field.emptyLabel }
        var label = dateLabel(date)
        if field == .due, let dueAt = task.schedule.dueAt, !task.isClosed {
            let days = workspace.calendar.dateComponents([.day],
                from: workspace.calendar.startOfDay(for: dueAt),
                to: workspace.calendar.startOfDay(for: workspace.clock())).day ?? 0
            if days > 0 { label += "，逾期 \(days) 天" }
        }
        return label
    }

    private func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无优先级"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none: WFColors.secondaryText
        case .low: WFColors.accent
        case .medium: .orange
        case .high: .red
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
            // 与文档标题同一个角色：原版这里是 `detailTitle`（18 semibold）配
            // `lineControl`。曾经的 22 bold 是照参考图放大过的，比原版重两档。
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
