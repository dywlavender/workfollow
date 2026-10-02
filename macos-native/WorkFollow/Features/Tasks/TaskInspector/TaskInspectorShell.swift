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
    @State private var actionPresentation = TaskInspectorActionPresentationState()
    @State private var showFormattingToolbar = false
    @State private var focusStartFailed = false
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
                TaskEmptyInspectorView()
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
                        .padding(.bottom, TaskInspectorMetrics.footerOverlayInset)
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
            actionPresentation.dismiss()
            showFormattingToolbar = false
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
        .alert("无法开始专注", isPresented: $focusStartFailed) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("请先结束当前专注会话，再尝试开始新的专注。")
        }
    }

    // MARK: - 顶部：状态框 + 日期 + 优先级

    private func headerBar(_ task: Task) -> some View {
        TaskInspectorHeader(task: task, showBack: showBack,
                            onBack: { workspace.select(nil) },
                            onComplete: { _ = workspace.changeStatus(task) },
                            onRepeat: { presentation.activePopover = .recurrence },
                            schedule: { scheduleChip(task, field: .due) },
                            priority: { priorityMenu(task) })
        .schedulePopover(isPresented: popoverBinding(.recurrence)) {
            TaskDatePopoverV2(task: task, workspace: workspace, initialPage: .recurrence) {
                presentation.activePopover = nil
            }
        }
    }

    private func moreMenu(_ task: Task) -> some View {
        Button { actionPresentation.open(.more) } label: {
            Image(systemName: "ellipsis")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("更多操作")
        .accessibilityLabel("更多任务操作")
    }

    private var hasFooterPopover: Bool {
        actionPresentation.panel != nil || presentation.activePopover == .deadline
    }

    @ViewBuilder
    private func footerPopover(_ task: Task) -> some View {
        Group {
            if actionPresentation.panel == .more {
                moreActionsPopover(task)
            } else if actionPresentation.panel == .tags {
                TaskTagPickerPopover(initialTags: task.tags, workspace: workspace,
                    onCancel: { actionPresentation.dismiss(.tags) },
                    onApply: { tags in
                        workspace.setTags(task.id, tags)
                        actionPresentation.dismiss(.tags)
                    })
                    .inspectorRenderAnchor(.tagPicker)
            } else if actionPresentation.panel == .attributes {
                ScrollView {
                    TaskAttributesView(task: workspace.task(for: task.id) ?? task,
                                       onEscape: dismissFooterPopover,
                                       workspace: workspace)
                }
                .frame(width: 320, height: 300)
            } else if actionPresentation.panel == .relation {
                relationPicker(task)
            } else if actionPresentation.panel == .parent {
                TaskParentPicker(taskID: task.id, workspace: workspace) {
                    actionPresentation.dismiss(.parent)
                }
                .inspectorRenderAnchor(.parentPicker)
            } else if presentation.activePopover == .deadline {
                TaskDatePopoverV2(task: task, workspace: workspace, deadline: true) {
                    presentation.activePopover = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WFColors.border))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .background(PopupEscapeRouter(depth: 2) {
            if !actionPresentation.handleEscape() { dismissFooterPopover() }
        })
    }

    private func dismissFooterPopover() {
        actionPresentation.dismiss()
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
                moreAction("关联主任务", symbol: "rectangle.3.group") {
                    actionPresentation.open(.parent)
                }
                .disabled(task.isClosed || task.skippedAt != nil || task.convertedNoteID != nil ||
                          workspace.allTasks.contains { $0.parentID == task.id })
                .inspectorRenderAnchor(.parentMenuRow)
                moreAction(task.isPinned ? "取消置顶" : "置顶", symbol: "pin") {
                    _ = workspace.setPinned(task.id, !task.isPinned)
                }
                moreAction(task.isAbandoned ? "恢复任务" : "放弃", symbol: "xmark.square") {
                    if task.isAbandoned { _ = workspace.restore(task.id) }
                    else { _ = workspace.abandon(task.id) }
                }
                .disabled(task.status == .completed)
                moreAction("标签", symbol: "tag") { actionPresentation.open(.tags) }
                    .inspectorRenderAnchor(.tagsMenuRow)
                moreAction("上传附件", symbol: "paperclip") { addAttachments(to: task.id) }
                focusSubmenuRow(task)
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                moreAction("保存为模板", symbol: "doc.badge.plus") { saveAsTemplate() }
                moreAction("创建副本", symbol: "square.on.square") { workspace.duplicate(task.id) }
                    .inspectorRenderAnchor(.duplicateMenuRow)
                moreAction("复制链接", symbol: "link") {
                    let copied = TaskLinkClipboard.copy(task)
                    environment.feedback.show(FeedbackEvent(kind: copied ? .success : .error,
                        message: copied ? "已复制任务链接" : "无法复制任务链接"))
                }
                moreAction("转换为笔记", symbol: "doc.text") { _ = environment.convertTaskToNote(task.id) }
                moreAction("删除", symbol: "trash", destructive: true) { _ = workspace.delete(task.id) }
                // Retain existing secondary capabilities until their product
                // location is verified; do not silently drop them during parity.
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                Text("其他操作").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                moreAction("更多属性…", symbol: "slider.horizontal.3") { actionPresentation.open(.attributes) }
                moreAction("截止日期…", symbol: "calendar.badge.exclamationmark") {
                    presentation.activePopover = .deadline
                }
                if !task.isClosed && task.recurrence != .never {
                    moreAction("跳过本周期", symbol: "arrow.forward.end") {
                        workspace.skip(task.id)
                    }
                    .disabled(RecurrenceEngine.next(for: task, now: workspace.clock(), calendar: workspace.calendar) == nil)
                }
            }
            .padding(8)
        }
        .frame(width: 208, height: 456)
        .inspectorRenderAnchor(.moreMenu)
    }

    private func focusSubmenuRow(_ task: Task) -> some View {
        Button {
            // A click after hover must keep the already-open submenu visible.
            actionPresentation.openSubmenu(.focus)
        } label: {
            HStack {
                Label("开始专注", systemImage: "circle.inset.filled")
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .font(WFType.menu)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(WFColors.text).padding(.horizontal, 8)
        .inspectorRenderAnchor(.focusMenuRow)
        // Leaving this row does NOT dismiss: the pointer can cross the gap.
        // Entering another actionable row dismisses the submenu instead.
        .onHover { if $0 { actionPresentation.openSubmenu(.focus) } }
        .background(AnchoredPropertyPanel(
            isPresented: Binding(get: { actionPresentation.submenu == .focus },
                                 set: { if !$0 { actionPresentation.dismissSubmenu() } }),
            width: 176, placement: .submenu) {
                TaskFocusSubmenu { stopwatch in
                    if !TaskInspectorFocusAction.start(taskID: task.id, stopwatch: stopwatch,
                        store: environment.focusStore, presentation: &actionPresentation) {
                        actionPresentation.dismiss()
                        focusStartFailed = true
                    }
                }
            })
    }

    private func moreAction(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            actionPresentation.dismiss(.more)
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
        .onHover { if $0 { actionPresentation.dismissSubmenu() } }
    }

    // MARK: - 主体：标题 → 正文 → 一级子任务

    private func inspectorContent(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let parentID = task.parentID, let parent = workspace.task(for: parentID) {
                TaskParentBreadcrumbView(title: parent.title) { workspace.select(parentID) }
                    .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                    .padding(.top, WFSpace.lg)
            }
            TaskTitleField(task: task, workspace: workspace,
                           focused: $titleFocused, draft: $presentation.titleDraft)
                .id(task.id)
                .inspectorRenderAnchor(.title)
                .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                .padding(.top, WFSpace.lg)
                .padding(.bottom, WFSpace.md)
            documentEditor(task)
                .inspectorRenderAnchor(.document)
                .padding(.top, WFSpace.sm)
            // 子任务区只在**已经有子任务**时出现——新建的空任务不自动带上它。
            // 原版 `task_editor_profile.dart:149-153` 就是这么挂的：
            // `if (!task.isChildTask && childrenOf(task.id).isNotEmpty)`，注释写着
            // "空父任务保持整屏正文；第一个子任务从更多菜单、行右键菜单或 / 面板来"。
            if task.parentID == nil, !editorChildren(task.id).isEmpty {
                subtaskSection(task)
                    .inspectorRenderAnchor(.childSection)
                    .padding(.top, TaskInspectorMetrics.childSectionTopGap)
            }
        }
        .padding(.bottom, WFSpace.xl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 顶部日期入口；点击仍使用现有日期 popover。
    private func scheduleChip(_ task: Task, field: ScheduleField) -> some View {
            Button {
                presentation.activePopover = field.popover
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: field.symbol)
                    Text(scheduleChipLabel(task, field: field))
                }
                .font(WFType.control).lineLimit(1)
                .frame(height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
                .foregroundStyle(scheduleChipColor(task, field: field))
            }
            .buttonStyle(.plain)
            .help(field.emptyLabel)
            .accessibilityLabel(scheduleChipLabel(task, field: field))
        .schedulePopover(isPresented: popoverBinding(field.popover)) {
            TaskDatePopoverV2(task: task, workspace: workspace, deadline: field == .deadline) {
                presentation.activePopover = nil
            }
        }
    }

    private func scheduleChipColor(_ task: Task, field: ScheduleField) -> Color {
        switch TaskInspectorSchedulePresentation.tone(
            date: field.date(in: task), hasTime: task.schedule.hasTime,
            now: workspace.clock(), calendar: workspace.calendar) {
        case .overdue: return WFColors.danger
        case .scheduled: return WFColors.accent
        case .empty: return WFColors.tertiaryText
        }
    }

    private func subtaskSection(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: TaskInspectorMetrics.childAddGap) {
            VStack(spacing: TaskInspectorMetrics.childRowGap) {
                ForEach(editorChildren(task.id)) { child in
                    childRow(child)
                }
            }
            // 一级子任务不再给这个入口：原版 `_addChildTask` 对子任务直接 return，
            // 动作层也会以"子任务不能再建子任务"失败，留着它只是个点了没反应的入口。
            if task.parentID == nil { addChildRow(task) }
        }
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
    }

    /// Existing add-child action, separated from neutral child surfaces by the
    /// Inspector childAddGap. Keep inline editing and focus behavior unchanged.
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
        .inspectorRenderAnchor(.addChild)
    }

    // MARK: - 底部工具行：左清单选择，右正文格式与更多操作

    private func bottomBar(_ task: Task) -> some View {
        HStack(spacing: WFSpace.xs) {
            listMenu(task)
                .inspectorRenderAnchor(.footerList)
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
            .inspectorRenderAnchor(.footerFormatting)
            moreMenu(task)
                .inspectorRenderAnchor(.footerMore)
        }
        .font(WFType.body)
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(height: TaskInspectorMetrics.footerHeight)
        .overlay(alignment: .bottom) {
            if showFormattingToolbar {
                formattingToolbar.padding(.horizontal, 16)
                    .padding(.bottom, TaskInspectorMetrics.footerOverlayInset)
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
        TaskRelationPicker(sourceTaskID: task.id, tasks: workspace.allTasks,
            notes: environment.notesWorkspace.notes, sourceNoteID: task.sourceNoteID,
            onSelect: { target in
                guard TaskRelationSelection.apply(target, sourceTaskID: task.id, workspace: workspace,
                    notes: environment.notesWorkspace.notes, handle: editorHandle) else { return false }
                actionPresentation.dismiss(.relation)
                return true
            }, onCancel: { actionPresentation.dismiss(.relation) })
    }

    private func openDocumentLink(_ link: String) -> Bool {
        guard let url = URL(string: link) else { return false }
        return environment.openResourceLink(url)
    }

    private func childRow(_ child: Task) -> some View {
        TaskInspectorChildRow(child: child,
            onComplete: { _ = workspace.changeStatus(child) },
            onOpen: { if inlineChildEditorID != child.id { workspace.select(child.id) } },
            title: {
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
                    .frame(maxWidth: .infinity, minHeight: TaskInspectorMetrics.childRowMinHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }, metadata: { TaskDateButton(task: child, workspace: workspace) })
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
                                         message: "是否用当前任务替换这个模板？",
                                         action: "替换") else { return }
        }
        _ = TemplateStore.shared.save(name: name, from: task,
                                      includingChildren: children, forceReplace: true)
    }

    @discardableResult
    private func handleEscape() -> InspectorEscapeEffect {
        if actionPresentation.submenu != nil {
            actionPresentation.dismissSubmenu()
            return .dismissPopover
        }
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
                profile: TaskDocumentProfile.make(task: task, host: TaskEditorHostActions(
                    createChild: {
                        workspace.requestChildTitleEditor(for: task.id)
                    },
                    openTags: { actionPresentation.open(.tags) },
                    openRelation: {
                        actionPresentation.open(.relation)
                    }, openLink: openDocumentLink)),
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

    @ViewBuilder
    private func listMenu(_ task: Task) -> some View {
        if task.parentID != nil {
            Label(task.list.name, systemImage: "tray")
                .font(WFType.control).foregroundStyle(WFColors.text)
                .help("子任务跟随父任务清单")
                .accessibilityLabel("清单：\(task.list.name)，子任务跟随父任务")
        } else {
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
        .help("移动到清单")
        .accessibilityLabel("清单：\(task.list.name)")
        }
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

    private func scheduleChipLabel(_ task: Task, field: ScheduleField) -> String {
        guard let date = field.date(in: task) else { return field.emptyLabel }
        return TaskInspectorSchedulePresentation.label(date: date,
            hasTime: field == .due && task.schedule.hasTime,
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
    var emptyLabel: String { self == .due ? "设置日期" : "截止日期" }
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
