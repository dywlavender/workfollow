import SwiftUI
import UniformTypeIdentifiers

/// 任务详情：顶部状态/日期/优先级，标题与正文连续编辑，一级子任务跟在正文后；
/// 底部清单入口与正文格式、更多操作入口固定显示。
struct TaskInspectorShell: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.taskFocusStore) private var taskFocusStore
    let showBack: Bool
    var allowsClosing = false
    /// 评论条数角标的观察源。由宿主显式传入（测试/预览可以不传）——
    /// 避免在 body 里直接读 `@EnvironmentObject`（没有 environment 的宿主会崩）。
    var commentStore: TaskCommentStore? = nil
    /// 浮层里的详情（日历/四象限点任务条打开的那个）：Esc 要关掉浮层，而不是
    /// 把选中项清掉后留在原地不动——对齐 Flutter `TaskInspector._escape()` 的
    /// `_isPopup` 分支（它排在"退回列表"之前）。
    var onRequestClose: (() -> Void)? = nil
    /// 标题字段改用 AppKit `NSTextField` 后，焦点状态由外部状态驱动（不再是 `@FocusState`）。
    @State private var titleEditing = false
    @State private var presentation = TaskInspectorPresentationState()
    @State private var newListName = ""
    @State private var listMenuQuery = ""
    /// 正在行内编辑的子任务（NSOutlineView 消费，"添加子任务"后自动聚焦新行）。
    @State private var inlineChildEditorID: UUID?
    @State private var showNewList = false
    @State private var actionPresentation = TaskInspectorActionPresentationState()
    /// 优先级浮层（自绘，带彩色旗；SwiftUI Menu 不渲染菜单项图标）。
    @State private var showPriorityMenu = false
    /// 「更多」菜单里的"设置预计专注"浮层（专注摘要行改为有数据才显示后保留入口）。
    @State private var showFocusEstimate = false
    @State private var focusSubmenuWork: DispatchWorkItem?
    @State private var focusSubmenuIntentID: UUID?
    @State private var focusStartFailed = false
    /// 「添加子任务」整行的悬停态（原版 `InkWell.hoverColor`）。
    @State private var hoveringAddChild = false
    /// 子任务树里当前折叠的节点（TI2-04 收尾）：折叠后要告诉用户"少了多少"。
    @State private var collapsedSubtaskIDs: Set<UUID> = []
    /// 文件拖到详情时的目标高亮（TI2-03：拖放即附件）。
    @State private var attachmentDropTargeted = false
    /// 内联评论区的展开态（TI2-09）。
    @State private var showComments = false
    /// 笔记信息浮层（TI2-15）。
    @State private var showNoteInfo = false
    /// 任务类型浮层（TI2-05b）。
    @State private var showKindMenu = false
    /// 切到清单会压平标题/引用/代码/分割线时的确认目标。
    @State private var pendingChecklistTaskID: UUID?
    @State private var aiTaskRequest: AITaskRequest?
    @StateObject private var editorHandle = DocumentEditorHandle()
    /// 浮窗打开时详情只读预览用的独立身份，避免和浮窗争同一份编辑状态。
    @State private var previewDocumentID = UUID()
    @ObservedObject private var floatingTasks = StickyNoteWindowController.shared

    private var selectedTaskHasFloatingEditor: Bool {
        guard let id = workspace.selectedTaskID else { return false }
        return floatingTasks.isOpen(id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let task = workspace.selectedTask, workspace.isListArchived(task.list.name) {
                ArchivedTaskInspectorView(task: task, showsBack: showBack || allowsClosing) { _ = handleEscape() }
            } else if let task = workspace.selectedTask {
                headerBar(task)
                Divider()
                // 未设置提醒时整行不出现（用户反馈：多余）；有提醒才摘要。
                if !ReminderSchedule.fireDates(for: task, calendar: workspace.calendar).isEmpty {
                    reminderSummaryRow(task)
                }
                if !selectedTaskHasFloatingEditor {
                    DocumentFormattingToolbarRow(
                        handle: editorHandle,
                        leadingPadding: TaskInspectorMetrics.documentLeadingPadding,
                        trailingPadding: TaskInspectorMetrics.horizontalPadding)
                        .inspectorRenderAnchor(.formattingToolbar)
                    Divider()
                }
                GeometryReader { viewport in
                    ScrollView {
                        inspectorContent(task)
                            .frame(minWidth: viewport.size.width,
                                   minHeight: viewport.size.height,
                                   alignment: .topLeading)
                            .background {
                                if !selectedTaskHasFloatingEditor {
                                    EditorWhitespaceHitTarget(handle: editorHandle, documentID: task.id)
                                }
                            }
                            .compactScrollbars()
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
        .sheet(item: $aiTaskRequest) { AITaskComposerView(request: $0) }
        .onReceive(workspace.selectionWillChange) { nextID in
            guard editorHandle.textView?.documentIdentity != nextID else { return }
            editorHandle.prepareForDocumentChange()
        }
        .onChange(of: titleEditing) { _, editing in
            if editing {
                presentation.editingTarget = .title
            } else if presentation.editingTarget == .title {
                presentation.editingTarget = .none
            }
        }
        .onChange(of: workspace.selectedTaskID) { _, _ in
            presentation.synchronizeTitle(taskID: workspace.selectedTask?.id,
                                          title: workspace.selectedTask?.title ?? "")
            titleEditing = false
            presentation.editingTarget = .none
            revealPendingChecklistItem()
            dismissTransientPanels()
            showComments = false
            pendingChecklistTaskID = nil
        }
        .onDisappear { dismissTransientPanels() }
        .onChange(of: workspace.pendingChildTitleEditorID) { _, _ in beginPendingChildEditing() }
        // 新建的空任务自动聚焦标题（TI2-22）。放到下一拍：`select()` 会先把
        // `titleEditing` 复位成 false，同一拍里置 true 会被那次复位吃掉。
        .onChange(of: workspace.pendingTitleEditorID) { _, _ in
            guard let id = workspace.consumePendingTitleEditor() else { return }
            DispatchQueue.main.async {
                guard workspace.selectedTaskID == id else { return }
                titleEditing = true
            }
        }
        .onChange(of: workspace.pendingChecklistReveal) { _, _ in revealPendingChecklistItem() }
        .onAppear {
            focusPendingTitleIfNeeded()
            revealPendingChecklistItem()
        }
        .alert("切换模式后，当前排版格式将失效，是否继续？",
               isPresented: Binding(get: { pendingChecklistTaskID != nil },
                                    set: { if !$0 { pendingChecklistTaskID = nil } })) {
            Button("取消", role: .cancel) { pendingChecklistTaskID = nil }
            Button("继续") {
                guard let id = pendingChecklistTaskID else { return }
                pendingChecklistTaskID = nil
                workspace.setKind(id, .checklist)
            }
        } message: {
            Text("标题、引用、代码与分割线会保留，但不会变成检查事项，也不计入清单进度。")
        }
        .onExitCommand {
            _ = handleEscape()
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
        TaskInspectorHeader(task: task, showBack: showBack || allowsClosing,
                            onBack: { workspace.select(nil) },
                            onComplete: { _ = workspace.changeStatus(task) },
                            onRepeat: { openSchedulePanel(.recurrence) },
                            onDetach: {
                                dismissTransientPanels()
                                editorHandle.prepareForDocumentChange()
                                TaskDetailWindowController.shared.show(workspace: workspace,
                                                                       environment: environment)
                            },
                            onInfo: task.document.isEmpty ? nil : { togglePanel($showNoteInfo) },
                            onKind: { togglePanel($showKindMenu) },
                            kindSymbol: task.kind.symbol,
                            schedule: { scheduleChip(task, field: .due) },
                            priority: { priorityMenu(task) })
        .anchoredPropertyPanel(isPresented: $showKindMenu, trigger: TaskInspectorHeaderPanel.kind,
                               width: PopupMetrics.taskMenuWidth, title: "任务类型") {
            kindPopover(task)
        }
        .anchoredPropertyPanel(isPresented: $showNoteInfo, trigger: TaskInspectorHeaderPanel.info,
                               width: PopupMetrics.noteInfoWidth, title: "笔记信息") {
            TaskNoteInfoPanel(info: TaskNoteInfo(task: task), calendar: workspace.calendar)
        }
        .schedulePopover(isPresented: popoverBinding(.recurrence), trigger: .recurrence) {
            TaskDatePopoverV2(task: task, workspace: workspace, initialPage: .recurrence) {
                presentation.activePopover = nil
            }
        }
    }

    private func moreMenu(_ task: Task) -> some View {
        Button {
            let opening = actionPresentation.panel != .more
            dismissTransientPanels()
            if opening { openActionPanel(.more) }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popupMenuRowBackground()
        .hoverTip("更多操作", placement: .above)
        .accessibilityLabel("更多任务操作")
        .background {
            AnchoredPropertyPanel(
                isPresented: Binding(get: { hasFooterPopover },
                                     set: { if !$0 { dismissFooterPopover() } }),
                width: footerPanelWidth, prefersAbove: true, placement: .verticalInOwner,
                focusPolicy: actionPresentation.panel == .more ? .preservePresenter : .panel,
                title: "任务详情操作") {
                    footerPopover(task)
                }
                // A new action owns a fresh draft and keyboard focus, not the
                // previous panel's search field or child-window lifecycle.
                .id(actionPresentation.panel)
        }
        .background {
            AnchoredPropertyPanel(
                isPresented: Binding(get: { showFocusEstimate },
                                     set: { if !$0 { showFocusEstimate = false } }),
                width: PopupMetrics.focusEstimateWidth, prefersAbove: true, placement: .verticalInOwner,
                focusPolicy: .preservePresenter, title: "预计专注") {
                    TaskFocusEstimateEditor(
                        estimate: task.focusEstimate,
                        onSave: { value in
                            _ = workspace.setFocusEstimate(task.id, value)
                            showFocusEstimate = false
                        },
                        onCancel: { showFocusEstimate = false })
                }
        }
    }

    private var footerPanelWidth: CGFloat {
        switch actionPresentation.panel {
        case .more: PopupMetrics.taskActionsWidth
        case .tags: PopupMetrics.tagPickerWidth
        case .parent: PopupMetrics.parentPickerWidth
        default: PopupMetrics.relationPickerWidth
        }
    }

    private var hasFooterPopover: Bool {
        actionPresentation.panel != nil
    }

    @ViewBuilder
    private func footerPopover(_ task: Task) -> some View {
        Group {
            if actionPresentation.panel == .activity {
                TaskActivityPanel(taskID: task.id, store: environment.taskActivityStore) {
                    actionPresentation.dismiss(.activity)
                }
            } else if actionPresentation.panel == .more {
                moreActionsPopover(task)
            } else if actionPresentation.panel == .tags {
                TaskTagPickerPopover(initialTags: task.tags, workspace: workspace,
                    onCancel: { actionPresentation.dismiss(.tags) },
                    onApply: { tags in
                        workspace.setTags(task.id, tags)
                        actionPresentation.dismiss(.tags)
                    })
                    .inspectorRenderAnchor(.tagPicker)
            } else if actionPresentation.panel == .relation {
                relationPicker(task)
            } else if actionPresentation.panel == .parent {
                TaskParentPicker(taskID: task.id, workspace: workspace) {
                    actionPresentation.dismiss(.parent)
                }
                .inspectorRenderAnchor(.parentPicker)
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.border))
        .background(PopupEscapeRouter(depth: 2) {
            if !actionPresentation.handleEscape() { dismissFooterPopover() }
        })
    }

    private func dismissFooterPopover() {
        cancelFocusSubmenuIntent()
        actionPresentation.dismiss()
    }

    /// Opening a date entry also works through accessibility/keyboard actions,
    /// which do not necessarily generate an outside mouse-down for the footer.
    private func openSchedulePanel(_ popover: InspectorPopover) {
        dismissTransientPanels()
        presentation.activePopover = popover
    }

    /// Root panels open on click. Switching the target or host cannot leave a
    /// stale draft or a delayed hover callback attached to the previous task.
    private func dismissTransientPanels() {
        cancelFocusSubmenuIntent()
        presentation.activePopover = nil
        actionPresentation.dismiss()
        showPriorityMenu = false
        showNoteInfo = false
        showKindMenu = false
        showFocusEstimate = false
    }

    private func openActionPanel(_ panel: TaskInspectorActionPanel) {
        dismissTransientPanels()
        actionPresentation.open(panel)
    }

    private func togglePanel(_ binding: Binding<Bool>) {
        let opening = !binding.wrappedValue
        dismissTransientPanels()
        binding.wrappedValue = opening
    }

    private func moreActionsPopover(_ task: Task) -> some View {
        VStack(spacing: 2) {
            moreAction("添加子任务", symbol: "list.bullet.indent") {
                workspace.requestChildTitleEditor(for: task.id)
            }
            if !task.isNoteTask {
                moreAction("拆分子任务…", symbol: "sparkles") {
                    editorHandle.prepareForDocumentChange()
                    do {
                        let current = workspace.task(for: task.id) ?? task
                        aiTaskRequest = try environment.aiTaskRequest(for: current)
                    } catch { environment.feedback.show(FeedbackEvent(kind: .error, message: error.localizedDescription)) }
                }.disabled(task.isClosed || task.deletedAt != nil ||
                    (task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && task.document.isEmpty))
                .inspectorRenderAnchor(.aiBreakdownMenuRow)
            }
            moreAction("关联主任务", symbol: "rectangle.3.group") {
                openActionPanel(.parent)
            }
            .disabled(task.isClosed || task.skippedAt != nil || task.convertedNoteID != nil ||
                      workspace.allTasks.contains { $0.parentID == task.id })
            .inspectorRenderAnchor(.parentMenuRow)
            moreAction(task.isPinned ? "取消置顶" : "置顶", symbol: "pin") {
                _ = workspace.setPinned(task.id, !task.isPinned)
            }
            moreAction(task.isAbandoned ? "恢复" : "放弃", symbol: "xmark.square") {
                if task.isAbandoned { _ = workspace.restore(task.id) }
                else { _ = workspace.abandon(task.id) }
            }
            .disabled(task.status == .completed)
            moreAction("标签", symbol: "tag") { openActionPanel(.tags) }
                .inspectorRenderAnchor(.tagsMenuRow)
            moreAction("上传附件", symbol: "paperclip") { addAttachments(to: task.id) }
            focusSubmenuRow(task)
            // 预计专注入口随专注动作进子菜单（TI2-10）：滴答的 focus 动作
            // （番茄 / 正计时 / 预计）同属一个出口，顶层菜单保持滴答的项序。
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
            moreAction("任务动态", symbol: "list.bullet.rectangle") { openActionPanel(.activity) }
                .inspectorRenderAnchor(.activityMenuRow)
            moreAction("保存为模板", symbol: "doc.badge.plus") { saveAsTemplate() }
            moreAction("创建副本", symbol: "square.on.square") { workspace.duplicate(task.id) }
                .inspectorRenderAnchor(.duplicateMenuRow)
            moreAction(task.kind == .note ? "转换为任务" : "转换为笔记", symbol: "doc.text") {
                if task.kind == .note { _ = workspace.setKind(task.id, .text) }
                else { _ = environment.convertTaskToNote(task.id) }
            }
            .inspectorRenderAnchor(.noteConversionMenuRow)
            // 本工程比滴答多的一项：正文流程图入口（与斜杠菜单同一个编辑器命令）。
            moreAction("流程图", symbol: "point.3.connected.trianglepath.dotted") {
                if let floating = FloatingEditorWindowController.shared.panel(for: .task(task.id)) {
                    floatingTasks.bringToFront(taskID: task.id)
                    floating.editorHandle.insertDiagram()
                } else {
                    editorHandle.insertDiagram()
                }
            }
            moreAction("删除", symbol: "trash") { _ = workspace.delete(task.id) }
        }
        .padding(8)
        .frame(width: PopupMetrics.taskActionsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .inspectorRenderAnchor(.moreMenu)
    }

    private func focusSubmenuRow(_ task: Task) -> some View {
        PopupMenuRow(action: {
            // A click after hover must keep the already-open submenu visible.
            cancelFocusSubmenuIntent()
            actionPresentation.openSubmenu(.focus)
        }, onHoverChanged: { focusSubmenuHover($0, taskID: task.id) }) {
            HStack {
                Label("开始专注", systemImage: "circle.inset.filled")
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .font(WFType.menu)
        }
        .foregroundStyle(WFColors.text)
        .inspectorRenderAnchor(.focusMenuRow)
        .background(AnchoredPropertyPanel(
            isPresented: Binding(get: { actionPresentation.submenu == .focus },
                                 set: { if !$0 { actionPresentation.dismissSubmenu() } }),
            width: PopupMetrics.taskMenuWidth, placement: .submenu) {
                TaskFocusSubmenu(onStart: { stopwatch in
                    guard let taskID = workspace.resolveTaskForAction(task.id) else { return }
                    if !TaskInspectorFocusAction.start(taskID: taskID, stopwatch: stopwatch,
                        store: environment.focusStore, presentation: &actionPresentation) {
                        actionPresentation.dismiss()
                        focusStartFailed = true
                    } else {
                        environment.navigation.taskSelectionToPreserveOnNextNavigation = taskID
                        environment.navigate(to: .focus)
                    }
                }, onSetEstimate: {
                    actionPresentation.dismiss()
                    showFocusEstimate = true
                }, onCancel: { actionPresentation.dismissSubmenu() })
            })
    }

    private func cancelFocusSubmenuIntent() {
        focusSubmenuWork?.cancel()
        focusSubmenuWork = nil
        focusSubmenuIntentID = nil
    }

    private func focusSubmenuHover(_ inside: Bool, taskID: UUID) {
        cancelFocusSubmenuIntent()
        guard inside, actionPresentation.panel == .more else { return }
        guard actionPresentation.submenu == nil else {
            actionPresentation.openSubmenu(.focus)
            return
        }
        let intentID = UUID()
        focusSubmenuIntentID = intentID
        let work = DispatchWorkItem {
            guard focusSubmenuIntentID == intentID, workspace.selectedTaskID == taskID,
                  actionPresentation.panel == .more else { return }
            focusSubmenuIntentID = nil
            focusSubmenuWork = nil
            actionPresentation.openSubmenu(.focus)
        }
        focusSubmenuWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PopupMetrics.submenuIntent, execute: work)
    }

    private func moreAction(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        PopupMenuRow(action: {
            actionPresentation.dismiss(.more)
            action()
        }, onHoverChanged: { entering in
            if entering {
                cancelFocusSubmenuIntent()
                actionPresentation.dismissSubmenu()
            }
        }) {
            Label(title, systemImage: symbol)
                .font(WFType.menu)
        }
        .foregroundStyle(WFColors.text)
    }

    // MARK: - 主体：标题 → 正文 → 一级子任务

    private func reminderSummaryRow(_ task: Task) -> some View {
        let dates = ReminderSchedule.fireDates(for: task, calendar: workspace.calendar)
        let value = ScheduleDisplay.reminderSummary(fireDates: dates,
            now: workspace.clock(), calendar: workspace.calendar)
        let summary = dates.isEmpty ? value : (task.isClosed ? "原提醒：" : "提醒：") + value
        return Button { openSchedulePanel(.reminder) } label: {
            Label(summary, systemImage: dates.isEmpty ? "bell.slash" : "bell")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .padding(.top, 4)
        .help(summary + "，点击修改提醒")
        .inspectorRenderAnchor(.reminder)
        .scheduleTrigger(.reminder)
        .schedulePopover(isPresented: popoverBinding(.reminder), trigger: .reminder) {
            TaskDatePopoverV2(task: task, workspace: workspace, initialPage: .reminder) {
                presentation.activePopover = nil
            }
        }
    }

    private func inspectorContent(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let parentID = task.parentID, let parent = workspace.task(for: parentID) {
                TaskParentBreadcrumbView(title: parent.title) { workspace.select(parentID) }
                    .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                    .padding(.top, WFSpace.lg)
            }
            AppKitTaskTitleField(text: $presentation.titleDraft,
                                 isEditing: $titleEditing,
                                 placeholder: task.parentID == nil ? "任务标题" : "准备做什么？",
                                 // 标题 Return → 正文（TI2-22，滴答 `focusOnContentIfNeeded`）。
                                 onSubmit: { editorHandle.focusEditor() },
                                 readOnly: selectedTaskHasFloatingEditor)
                .id(task.id)
                .inspectorRenderAnchor(.title)
                .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                .padding(.top, TaskInspectorMetrics.titleTopPadding)
                .onChange(of: presentation.titleDraft) { _, value in
                    _ = workspace.setTitle(task.id, value)
                }
                .onChange(of: task.title) { _, value in
                    if !titleEditing { presentation.titleDraft = value }
                }
            documentEditor(task)
                .inspectorRenderAnchor(.document)
                .padding(.top, TaskInspectorMetrics.titleDocumentGap)
            if let guideAction = WelcomeGuide.action(for: task),
               WelcomeGuide.mediaURL(for: guideAction) != nil {
                WelcomeGuideMediaView(action: guideAction)
                    .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                    .padding(.top, 12)
            }
            if let guideAction = WelcomeGuide.action(for: task) {
                WelcomeGuideActionView(action: guideAction) {
                    _ = environment.openGuideAction(guideAction)
                }
                .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                .padding(.top, 12)
            }
            // 附件行（TI2-03）：此前「上传附件」只写库、详情里看不见；这里复用笔记面的
            // 同一个 `AttachmentListView`（打开 / Finder / 移除 / 再加）。
            if !task.attachments.isEmpty {
                AttachmentListView(attachments: task.attachments) { attachments in
                    workspace.setAttachments(task.id, attachments)
                }
                .inspectorRenderAnchor(.attachments)
                .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                .padding(.top, 12)
            }
            // 标签集合行（TI2-02）：对齐滴答 `TTTaskDetailTagCollectionCell` 的可见 chip。
            if !task.tags.isEmpty {
                TaskTagStrip(tags: task.tags,
                             colors: Dictionary(uniqueKeysWithValues: workspace.taskTags.compactMap { tag in
                                 tag.colorARGB.map { (tag.name, $0) }
                             }),
                             onEdit: { openActionPanel(.tags) },
                             onRemove: { tag in
                                 workspace.setTags(task.id, task.tags.filter { $0 != tag })
                             })
                    .inspectorRenderAnchor(.tagStrip)
                    .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                    .padding(.top, 12)
            }
            // 子任务区只在**已经有子任务**时出现——新建的空任务不自动带上它。
            // 放开嵌套（2026-10-17）后，子任务详情同样显示自己的子任务区（孙任务）。
            if !editorChildren(task.id).isEmpty {
                subtaskSection(task)
                    .inspectorRenderAnchor(.childSection)
                    .padding(.top, TaskInspectorMetrics.childSectionTopGap)
            }
            // 滴答右栏对普通任务不显示专注摘要行（2026-10-17 同窗口实测）；
            // 仅在"已设预计专注或有专注记录"时显示，设置入口在「更多」菜单。
            if shouldShowFocusSummary(task) {
                focusSummaryRow(task)
                    .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                    .padding(.top, 12)
            }
            // 内联评论区（TI2-09）：有评论时显示标题行，底栏 💬 展开/收起。
            if let commentStore {
                TaskCommentSection(taskID: task.id, store: commentStore, isExpanded: $showComments)
                    .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                    .padding(.top, 12)
            }
        }
        .padding(.bottom, WFSpace.xl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // 拖文件到详情即附件（对齐滴答 `TTTaskDetailDropFileView`）。
        .onDrop(of: [.fileURL], isTargeted: $attachmentDropTargeted) { providers in
            importDroppedAttachments(providers, taskID: task.id)
            return true
        }
        .overlay(alignment: .top) {
            if attachmentDropTargeted {
                Text("松开以添加附件")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(WFColors.overlay, in: Capsule())
                    .overlay(Capsule().stroke(WFColors.border))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 专注摘要行的显示条件：有预计专注，或有实际专注记录（对齐滴答普通任务不显示该行）。
    private func shouldShowFocusSummary(_ task: Task) -> Bool {
        if task.focusEstimate != nil { return true }
        guard let focusStore = taskFocusStore else { return false }
        return focusStore.taskTotalActiveSeconds(taskID: task.id) > 0
    }

    @ViewBuilder
    private func focusSummaryRow(_ task: Task) -> some View {
        if let focusStore = taskFocusStore {
            TaskFocusSummaryRow(task: task, workspace: workspace, focusStore: focusStore) {
                focusStore.showRecords(taskID: task.id)
                environment.navigation.taskSelectionToPreserveOnNextNavigation = task.id
                environment.navigate(to: .focus)
            }
        } else {
            TaskFocusEstimateControl(task: task, workspace: workspace)
        }
    }

    /// 顶部日期入口：安排日期 chip；有截止日期时右侧并列「截止 …」标签（滴答 `secondaryDateLabel`）。
    /// 安排日期锚在 chip 上；已有截止日期的次要入口使用同一日程浮层呈现壳。
    private func scheduleChip(_ task: Task, field: ScheduleField) -> some View {
        HStack(spacing: WFSpace.dense) {
            AppKitScheduleChip(symbol: field.symbol,
                               title: scheduleChipLabel(task, field: field),
                               tint: NSColor(scheduleChipColor(task, field: field)),
                               accessibilityLabel: scheduleChipLabel(task, field: field),
                               action: { openSchedulePanel(field.popover) })
            .frame(height: WFMetrics.controlHeight)
            // 显式标出 chip 矩形：两个 popover 都读 `.date` 锚点，没有它时外层面板
            // 会退化成"整行（chip + 截止日期标签）"锚点。
            .scheduleTrigger(.date)
            // 日程区（`.schedule`）现在并列着截止入口，点击 chip 用这个更精确的锚点。
            .inspectorRenderAnchor(.scheduleChip)
            .schedulePopover(isPresented: popoverBinding(field.popover)) {
                TaskDatePopoverV2(task: task, workspace: workspace, deadline: field == .deadline) {
                    presentation.activePopover = nil
                }
            }
            // 滴答顶栏只在任务已有截止日期时显示 `secondaryDateLabel`（不是常驻入口）；
            // 日期面板也没有「截止日期」行，所以未设置时顶栏不占位。
            if field == .due, let deadline = task.schedule.deadlineAt {
                deadlineLabel(task, deadline: deadline)
                    .inspectorRenderAnchor(.deadlineLabel)
            }
        }
        .schedulePopover(isPresented: popoverBinding(.deadline)) {
            TaskDatePopoverV2(task: task, workspace: workspace, deadline: true) {
                presentation.activePopover = nil
            }
        }
    }

    /// 顶栏次要日期（滴答 `secondaryDateLabel`）：只在任务已有截止日期时渲染，逾期红字。
    private func deadlineLabel(_ task: Task, deadline: Date) -> some View {
        let now = workspace.clock()
        let overdue = !task.isClosed
            && workspace.calendar.startOfDay(for: deadline) < workspace.calendar.startOfDay(for: now)
        let day = TaskDateLabel.text(deadline, hasTime: false, now: now, calendar: workspace.calendar)
        return Button { openSchedulePanel(.deadline) } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 11))
                Text("截止 \(day)")
                    .lineLimit(1)
            }
            .font(WFType.control)
            .foregroundStyle(overdue ? WFColors.danger : WFColors.secondaryText)
            .padding(.horizontal, WFSpace.xs)
            .padding(.vertical, WFSpace.xs)
            .contentShape(Rectangle())
            .popupMenuRowBackground()
        }
        .buttonStyle(.plain)
        .hoverTip("修改截止日期", placement: .above)
        .accessibilityLabel("截止日期：\(day)")
    }

    private func scheduleChipColor(_ task: Task, field: ScheduleField) -> Color {
        if task.isClosed { return WFColors.secondaryText }
        let tone = field == .due
            ? TaskInspectorSchedulePresentation.tone(schedule: task.schedule,
                now: workspace.clock(), calendar: workspace.calendar)
            : TaskInspectorSchedulePresentation.tone(date: field.date(in: task),
                hasTime: task.schedule.hasTime, now: workspace.clock(), calendar: workspace.calendar)
        switch tone {
        case .overdue: return WFColors.danger
        case .scheduled: return WFColors.accent
        case .empty: return WFColors.tertiaryText
        }
    }

    private func subtaskSection(_ task: Task) -> some View {
        let layout = SubtaskOutlineLayout.measure(under: task.id,
            children: { editorChildren($0).map(\.id) }, collapsed: collapsedSubtaskIDs)
        return VStack(alignment: .leading, spacing: TaskInspectorMetrics.childAddGap) {
            AppKitSubtaskOutlineView(
                rootTasks: editorChildren(task.id),
                allTasks: workspace.allTasks,
                completionSize: TaskInspectorMetrics.childCompletionSize,
                inlineEditingID: inlineChildEditorID,
                dateLabel: { child in
                    guard let date = child.schedule.dueAt else { return nil }
                    return TaskInspectorSchedulePresentation.label(
                        date: date, hasTime: child.schedule.hasTime,
                        now: workspace.clock(), calendar: workspace.calendar)
                },
                onComplete: { id in
                    if let child = workspace.task(for: id) { _ = workspace.changeStatus(child) }
                },
                onOpen: { id in
                    if inlineChildEditorID != id { workspace.select(id) }
                },
                onRename: { id, text in
                    _ = workspace.setTitle(id, text)
                    // "添加子任务"触发的行内编辑：提交后回车续加（对齐滴答）。
                    if inlineChildEditorID == id {
                        let hadTitle = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let parentID = workspace.task(for: id)?.parentID
                        inlineChildEditorID = nil
                        if hadTitle, let parentID {
                            workspace.requestChildTitleEditor(for: parentID)
                        }
                    }
                },
                onReorder: { id, index in
                    workspace.reorder(id, toSiblingIndex: index)
                },
                onCollapseChange: { collapsed in
                    if collapsedSubtaskIDs != collapsed { collapsedSubtaskIDs = collapsed }
                }
            )
            .frame(height: layout.height(rowHeight: TaskInspectorMetrics.childRowMinHeight))
            if layout.hiddenRowCount > 0 {
                Text("已折叠 \(layout.hiddenRowCount) 项")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .inspectorRenderAnchor(.collapsedCount)
            }
            // 放开嵌套（2026-10-17）：子任务同样给"添加子任务"入口，可建孙任务。
            addChildRow(task)
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
                Text("添加子任务").font(WFType.listTitle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(WFColors.accent)
            .padding(.horizontal, WFSpace.sm)
            .frame(minHeight: TaskInspectorMetrics.childRowMinHeight, alignment: .leading)
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

    // MARK: - 底部工具行：左清单选择，右标签 / 合并 / 格式 / 评论 / 更多（滴答 8 出口运行态）

    private func bottomBar(_ task: Task) -> some View {
        HStack(spacing: WFSpace.xs) {
            listMenu(task)
                .inspectorRenderAnchor(.footerList)
            Spacer(minLength: 0)
            // 标签出口（tagButton）：有标签才显示。
            if !task.tags.isEmpty {
                footerIconButton("tag", label: "标签") {
                    let opening = actionPresentation.panel != .tags
                    dismissTransientPanels()
                    if opening { openActionPanel(.tags) }
                }
                    .inspectorRenderAnchor(.footerTag)
            }
            // 合并出口（mergeButton）：有子任务才显示，子任务标题并入正文后软删。
            let children = editorChildren(task.id)
            if !children.isEmpty {
                footerIconButton("arrow.triangle.merge", label: "合并子任务到正文") {
                    _ = workspace.mergeChildrenIntoDocument(task.id)
                }
                .inspectorRenderAnchor(.footerMerge)
            }
            // 评论出口（commentButton）：打开任务评论面板；有条数角标（TI2-09）。
            footerIconButton("bubble.left", label: "评论") { showComments.toggle() }
                .overlay(alignment: .topTrailing) {
                    if let commentStore {
                        TaskCommentCountBadge(store: commentStore, taskID: task.id)
                    }
                }
                .inspectorRenderAnchor(.footerComment)
            moreMenu(task)
                .inspectorRenderAnchor(.footerMore)
        }
        .font(WFType.body)
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(height: TaskInspectorMetrics.footerHeight)
    }

    /// 底栏图标出口统一封装：AppKit `NSButton`，命中区 34×34，次级墨色。
    private func footerIconButton(_ symbol: String, label: String,
                                  action: @escaping () -> Void) -> some View {
        AppKitIconButton(symbol: symbol, pointSize: 14, tint: .inspectorSecondary,
                         accessibilityLabel: label, action: action,
                         hoverTipPlacement: .above)
            .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
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

    /// 详情先出现、`pendingTitleEditorID` 早已置位的顺序（切换目的地后重建视图）
    /// 也要能接上焦点。
    private func focusPendingTitleIfNeeded() {
        guard let id = workspace.consumePendingTitleEditor(), workspace.selectedTaskID == id else { return }
        DispatchQueue.main.async { titleEditing = true }
    }

    private func revealPendingChecklistItem() {
        guard let taskID = workspace.selectedTaskID,
              let blockID = workspace.consumeChecklistReveal(for: taskID),
              let task = workspace.task(for: taskID),
              let document = try? task.document.materialized(),
              let line = document.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        DispatchQueue.main.async {
            guard workspace.selectedTaskID == taskID else { return }
            editorHandle.revealChecklistLine(line)
        }
    }

    private func beginPendingChildEditing() {
        guard let childID = workspace.consumePendingChildTitleEditor() else { return }
        inlineChildEditorID = childID
    }

    @MainActor
    private func addAttachments(to taskID: UUID) {
        NativeAttachmentFiles.choose { result in
            guard case .success(let attachments) = result,
                  let current = workspace.task(for: taskID) else { return }
            workspace.setAttachments(taskID, current.attachments + attachments)
        }
    }

    /// 拖放导入：`NSItemProvider` 的文件 URL 收集完后再落盘（顺序按拖入顺序）。
    private func importDroppedAttachments(_ providers: [NSItemProvider], taskID: UUID) {
        AttachmentDropImport.collect(from: providers) { urls in
            guard !urls.isEmpty else { return }
            do {
                let imported = try NativeAttachmentFiles.importFiles(urls)
                guard let current = workspace.task(for: taskID) else { return }
                workspace.setAttachments(taskID, current.attachments + imported)
                environment.feedback.show(FeedbackEvent(
                    kind: .success, message: imported.count == 1 ? "已添加附件" : "已添加 \(imported.count) 个附件"))
            } catch {
                environment.feedback.show(FeedbackEvent(kind: .error, message: "无法添加附件"))
            }
        }
    }

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
        // 浮层优先于"退回列表"：原版里 popup 的 Esc 就是把浮层关掉。
        if let onRequestClose {
            onRequestClose()
            return .dismissPopover
        }
        let previousTarget = presentation.editingTarget
        let effect = presentation.handleEscape(isNarrow: showBack || allowsClosing)
        switch effect {
        case .dismissPopover:
            break
        case .endEditing:
            if previousTarget == .title { titleEditing = false }
        case .returnToList:
            workspace.select(nil)
        case .keepInspector:
            break
        }
        return effect
    }

    private func documentEditor(_ task: Task) -> some View {
        ZStack(alignment: .topLeading) {
            if floatingTasks.isOpen(task.id) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("正在浮窗中编辑").font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText)
                        Spacer()
                        Button("定位浮窗") { floatingTasks.bringToFront(taskID: task.id) }
                            .buttonStyle(.plain).foregroundStyle(WFColors.accent)
                    }
                    // 编辑权在浮窗，这里仍按原生版式展示同一份富文本，禁止修改。
                    DocumentEditor(documentID: previewDocumentID, document: task.document,
                                   onDocumentChange: { _ in },
                                   onEscape: { .keepInspector },
                                   onEditingChanged: { _ in },
                                   profile: documentProfile(task),
                                   contentSized: true,
                                   decorationVisibleMinX: max(0, DocumentEditorGeometry.decorationLane - TaskInspectorMetrics.documentLeadingPadding),
                                   readOnly: true)
                        .overlay(alignment: .topLeading) {
                            if DocumentEditorPlaceholder.isVisible(for: task.document) {
                                DocumentEditorPlaceholder(title: "添加描述…")
                            }
                        }
                }
            } else {
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
                    profile: documentProfile(task),
                    contentSized: true,
                    handle: editorHandle,
                    // 传给编辑器的是"宿主内可见的装饰槽宽度"（容器坐标），不是分栏线位置；
                    // 标记再由 DocumentEditorGeometry.decorationMarkerX 向内让 4pt。
                    decorationVisibleMinX: max(0, DocumentEditorGeometry.decorationLane - TaskInspectorMetrics.documentLeadingPadding)
                )

                if DocumentEditorPlaceholder.isVisible(for: task.document, handle: editorHandle) {
                    DocumentEditorPlaceholder(title: "添加描述…")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.leading, TaskInspectorMetrics.documentLeadingPadding)
        .padding(.trailing, TaskInspectorMetrics.horizontalPadding)
    }

    private func documentProfile(_ task: Task) -> DocumentProfile {
        TaskDocumentProfile.make(task: task, host: TaskEditorHostActions(
            createChild: {
                workspace.requestChildTitleEditor(for: task.id)
            },
            openTags: { openActionPanel(.tags) },
            openRelation: {
                openActionPanel(.relation)
            }, openLink: openDocumentLink,
            availableTags: { workspace.tagNames },
            addTag: { tag in
                guard let current = workspace.task(for: task.id) else { return }
                guard !current.tags.contains(tag) else { return }
                workspace.setTags(task.id, current.tags + [tag])
            },
            availableLists: {
                // 当前清单排除在外：候选里列出"已经在的清单"没有意义。
                workspace.availableListNames.filter { $0 != task.list.name }
            },
            moveToList: { name in
                guard let current = workspace.task(for: task.id) else { return }
                guard current.list.name != name else { return }
                workspace.moveToList(task.id, TaskList(name: name))
            },
            pasteFiles: { urls in
                guard let imported = try? NativeAttachmentFiles.importFiles(urls),
                      !imported.isEmpty else { return }
                guard let current = workspace.task(for: task.id) else { return }
                workspace.setAttachments(task.id, current.attachments + imported)
            },
            checklistItem: { line in
                workspace.checklistItemMeta(task.id, line: line)
            },
            setChecklistReminder: { line, date in
                _ = workspace.setChecklistItemReminder(task.id, line: line, at: date)
            },
            checklistReminderNotice: { environment.reminders.checklistReminderNotice }))
    }

    /// 优先级菜单：滴答为四行「彩色旗 + 文案」、无当前值标记（实测 2026-10-16）。
    /// SwiftUI `Menu` 桥接 NSMenu 不渲染菜单项图标（实测 2026-10-17），
    /// 因此改用与「更多」同款的自绘浮层，保证彩色旗可见。
    private func priorityMenu(_ task: Task) -> some View {
        AppKitIconButton(symbol: task.priority == .none ? "flag" : "flag.fill",
                         pointSize: 14,
                         tint: NSColor(priorityColor(task.priority)),
                         accessibilityLabel: "优先级：\(task.priority.shortTitle)",
                         action: { togglePanel($showPriorityMenu) })
            .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
        .background {
            AnchoredPropertyPanel(isPresented: $showPriorityMenu, width: PopupMetrics.priorityMenuWidth,
                                  placement: .dropdown,
                                  focusPolicy: .preservePresenter, title: "优先级") {
                priorityPopover(task)
            }
        }
        .onChange(of: task.id) { _, _ in showPriorityMenu = false }
    }

    /// 任务类型菜单（TI2-05b）：三行 + 当前值对勾。
    private func kindPopover(_ task: Task) -> some View {
        VStack(spacing: 2) {
            ForEach(TaskKind.menuOrder, id: \.self) { kind in
                PopupMenuRow(action: {
                    showKindMenu = false
                    if kind == .checklist,
                       let document = try? task.document.materialized(),
                       TaskActions.checklistConversionImpact(in: document).requiresConfirmation {
                        pendingChecklistTaskID = task.id
                    } else {
                        workspace.setKind(task.id, kind)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(WFColors.secondaryText)
                            .frame(width: 16)
                        Text(kind.title)
                        Spacer(minLength: 0)
                        if task.kind == kind {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WFColors.accent)
                        }
                    }
                    .font(WFType.menu)
                }
                .foregroundStyle(WFColors.text)
            }
        }
        .padding(8)
        .frame(width: PopupMetrics.taskMenuWidth)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.border))
        .background(PopupEscapeRouter(depth: 2) { showKindMenu = false })
    }

    private func priorityPopover(_ task: Task) -> some View {
        VStack(spacing: 2) {
            // 顺序取 `TaskPriority.menuOrder`（滴答：高 → 中 → 低 → 无）。
            ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                PopupMenuRow(action: {
                    showPriorityMenu = false
                    _ = workspace.setPriority(task.id, priority)
                }) {
                    HStack(spacing: WFSpace.dense) {
                        Image(systemName: priority == .none ? "flag" : "flag.fill")
                            .foregroundStyle(priorityColor(priority))
                        Text(priority.title)
                        Spacer(minLength: 0)
                    }
                    .font(WFType.menu)
                }
                .foregroundStyle(WFColors.text)
            }
        }
        .padding(8)
        .frame(width: PopupMetrics.priorityMenuWidth)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.border))
        .background(PopupEscapeRouter(depth: 2) { showPriorityMenu = false })
    }

    @ViewBuilder
    private func listMenu(_ task: Task) -> some View {
        if task.parentID != nil {
            Label(task.list.name, systemImage: "tray")
                .font(WFType.control)
                .foregroundStyle(WFColors.tertiaryText)
                .help("子任务跟随父任务清单")
                .accessibilityLabel("清单：\(task.list.name)，子任务跟随父任务")
        } else {
        BusinessMenu(title: "移动到清单", search: workspace.availableListNames.count > 10 ? $listMenuQuery : nil,
                     prefersAbove: true) {
            ForEach(workspace.availableListNames.filter { listMenuQuery.isEmpty || $0.localizedStandardContains(listMenuQuery) }, id: \.self) { name in
                let list = TaskList(name: name)
                BusinessMenuOption(list.name, selected: task.list == list, symbol: "tray") {
                    _ = workspace.moveToList(task.id, list)
                }
            }
            Divider()
            Button("新清单…") { newListName = ""; showNewList = true }
        } label: {
            Label(task.list.name, systemImage: "tray")
                .font(WFType.control)
                .foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.xs)
                .padding(.vertical, WFSpace.xs)
                .popupMenuRowBackground()
        }
        .fixedSize()
        .disabled(!workspace.canMoveToList(task.id))
        .id(task.id)
        .hoverTip("移动到清单", placement: .above)
        .accessibilityLabel("清单：\(task.list.name)")
        }
    }

    private func popoverBinding(_ popover: InspectorPopover) -> Binding<Bool> {
        Binding(
            get: { presentation.activePopover == popover },
            set: { presented in
                if presented {
                    openSchedulePanel(popover)
                } else if presentation.activePopover == popover {
                    presentation.activePopover = nil
                }
            }
        )
    }

    private func scheduleChipLabel(_ task: Task, field: ScheduleField) -> String {
        guard let date = field.date(in: task) else { return field.emptyLabel }
        let now = workspace.clock()
        let calendar = workspace.calendar
        if field == .due {
            return TaskInspectorSchedulePresentation.label(schedule: task.schedule, now: now,
                calendar: calendar, isClosed: task.isClosed)
        }
        return TaskInspectorSchedulePresentation.label(date: date,
            hasTime: false, now: now, calendar: calendar)
    }

    /// 与列表、看板、快速添加共用同一份配色。
    private func priorityColor(_ priority: TaskPriority) -> Color { priority.menuColor }
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


