import SwiftUI

struct TaskListView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var templateStore = TemplateStore.shared
    @State private var draft = ""
    @State private var showNavigation = false
    @State private var showComposer = false
    @State private var showTemplatePicker = false
    @State private var showQuickAddSchedule = false
    @State private var showQuickAddProperties = false
    @State private var quickAddScheduleOverride: QuickAddScheduleDraft?
    @State private var quickAddPriorityOverride: TaskPriority?
    @State private var quickAddListOverride: String?
    @State private var quickAddTagsOverride: [String]?
    @State private var dismissedQuickAddTokens: Set<String> = []
    @State private var selecting = false
    @State private var groupExpansion = TaskGroupExpansionState()
    @State private var sortMode = TaskListSortMode.manual
    @State private var seenCompletedGroupIDs: Set<String> = []
    @FocusState private var quickAddFocused: Bool
    @FocusState private var listFocused: Bool

    private var scope: TaskListScope? { TaskWorkspaceModel.scope(for: navigation.destination) }
    private var query: TaskListQuery {
        guard scope == .allTasks else { return TaskListQuery() }
        return TaskListQuery(list: workspace.activeList, tag: workspace.activeTag)
    }
    private var groups: [TaskListGroup] { scope.map { workspace.groups(for: $0, query: query) } ?? [] }
    private var canAdd: Bool { scope == .today || scope == .inbox || scope == .allTasks || scope == .nextSevenDays }
    private var visibleTaskIDs: [UUID] {
        guard let scope else { return [] }
        return groups.flatMap { displayedNodes(for: $0, scope: scope) }.map { $0.task.id }
    }
    /// TickTick shows each row's owning list unless the view is already that list.
    private var showsListBadge: Bool { workspace.activeList == nil && scope != .inbox }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if canAdd, let scope { quickAddBar(in: scope) }
            if !workspace.bulkSelection.isEmpty { TaskBulkBar(workspace: workspace) }
            taskListSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .onChange(of: environment.quickAddRequest) { _, _ in quickAddFocused = true }
        .onChange(of: showQuickAddSchedule) { _, isPresented in
            if !isPresented { quickAddFocused = true }
        }
        .onChange(of: showQuickAddProperties) { _, isPresented in
            if !isPresented { quickAddFocused = true }
        }
        .onChange(of: groupIDs) { _, _ in collapseNewCompletedGroups() }
        .sheet(isPresented: $showComposer) {
            TaskComposer(workspace: workspace, onClose: { created in
                showComposer = false
                if created {
                    draft = ""
                    dismissedQuickAddTokens.removeAll()
                    quickAddScheduleOverride = nil
                    quickAddPriorityOverride = nil
                    quickAddListOverride = nil
                    quickAddTagsOverride = nil
                }
            }, dismissedTokenIDs: dismissedQuickAddTokens, title: draft,
                         list: workspace.activeList ?? TaskList.inbox.name,
                         scheduled: scope == .today && !hasDismissedQuickAddScheduleToken,
                         date: workspace.dateFromToday(0),
                         initialSchedule: quickAddScheduleOverride,
                         initialProperties: QuickAddPropertiesOverrides(
                            priority: quickAddPriorityOverride,
                            listName: quickAddListOverride,
                            tags: quickAddTagsOverride))
        }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView(workspace: workspace, templateStore: templateStore,
                               onDismiss: { showTemplatePicker = false })
        }
        .onChange(of: workspace.selectedTaskID) { _, _ in revealSelectedClosedTask() }
        .onAppear {
            if environment.quickAddRequest > 0 { quickAddFocused = true }
            else { listFocused = true }
            revealSelectedClosedTask()
            collapseNewCompletedGroups()
        }
        .onExitCommand { quickAddFocused = false }
    }

    // MARK: - Header bar：☰ + 标题 + 排序/更多（TickTick 式精简）

    private var headerBar: some View {
        HStack(spacing: WFSpace.sm) {
            if !navigationVisible {
                Button { showNavigation.toggle() } label: {
                    Image(systemName: "line.3.horizontal")
                        .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help("显示导航")
                    .popover(isPresented: $showNavigation) {
                        NavigationColumnView(workspace: workspace, navigation: navigation,
                                             filterStore: environment.filterStore) {
                            showNavigation = false
                        }
                        .frame(width: WFMetrics.navigationWidth, height: 440)
                    }
            }
            Text(headerTitle)
                .font(WFType.pageTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
            sortMenu
            moreMenu
        }
        .padding(.horizontal, WFSpace.xl)
        .padding(.top, WFSpace.lg)
        .padding(.bottom, WFSpace.md)
    }

    private var headerTitle: String {
        workspace.activeList ?? workspace.activeTag.map { "#" + $0 } ?? navigation.destination.title
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TaskListSortMode.allCases, id: \.self) { mode in
                Button {
                    sortMode = mode
                } label: {
                    if sortMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("排序：\(sortMode.title)")
    }

    /// 模板、撤销、多选等低频操作全部收进"更多"，保持顶栏只剩排序/更多两个小图标。
    private var moreMenu: some View {
        Menu {
            Menu("从模板添加", systemImage: "doc.badge.plus") {
                if templateStore.templates.isEmpty {
                    Button("还没有模板") {}
                        .disabled(true)
                } else {
                    Button("选择模板…") { showTemplatePicker = true }
                }
            }
            Button("撤销", systemImage: "arrow.uturn.backward") { workspace.undo() }
                .disabled(!workspace.canUndo)
            Divider()
            Button(selecting ? "退出多选" : "多选任务") { selecting.toggle(); workspace.clearBulkSelection() }
            Button("全选当前结果") {
                selecting = true
                let ids = groups.flatMap { displayedNodes(for: $0, scope: scope ?? .allTasks) }
                    .map { $0.task.id }
                workspace.setBulkSelection(in: ids)
            }
            Button("展开/收起已完成", systemImage: "checkmark.circle") {
                groupExpansion.toggleClosedGroups(in: groups)
            }
            .disabled(!groups.contains { $0.kind == .completed && !$0.tasks.isEmpty })
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("列表操作")
    }

    // MARK: - 快速添加：浅灰圆角条，聚焦后展开解析预览

    /// 快速添加日期入口的配色：与任务行日期徽标共用 dateBadgeStyle 归类
    /// （过期红、今天强调色、未来/无日期灰）。
    private func quickAddBadgeColor(_ timing: QuickAddScheduleDraft) -> Color {
        guard let dueAt = timing.dueAt else { return WFColors.secondaryText }
        switch TaskListViewDefaults.dateBadgeStyle(dueAt: dueAt, isClosed: false,
                                                   now: workspace.clock(),
                                                   calendar: workspace.calendar) {
        case .overdue: return .red
        case .today: return WFColors.accent
        case .scheduled, .none: return WFColors.secondaryText
        }
    }

    private func quickAddBar(in scope: TaskListScope) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: WFSpace.sm) {
                Button { showComposer = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(WFColors.secondaryText)
                }.buttonStyle(.plain).help("新建任务（完整属性）")
                TextField("添加任务至“\(quickAddTargetName)”", text: $draft)
                    .textFieldStyle(.plain).font(WFType.body)
                    .focused($quickAddFocused)
                    .onSubmit { addTask(in: scope) }
                if quickAddFocused || !draft.isEmpty || showQuickAddSchedule || showQuickAddProperties {
                    let timing = quickAddScheduleOverride ?? currentQuickAddSchedule(for: scope)
                    // 日期入口与任务行日期徽标同款：10pt 日历图标 + 日期文案，
                    // 配色走 dateBadgeStyle（过期红、今天强调色、其余灰）。
                    Button { showQuickAddSchedule = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar").font(.system(size: 10))
                            if navigation.destination != .inbox, let dueAt = timing.dueAt {
                                Text(TaskDateLabel.text(dueAt, hasTime: timing.hasTime,
                                                        now: workspace.clock(), calendar: workspace.calendar))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(quickAddBadgeColor(timing))
                        .frame(height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("安排日期、提醒和重复")
                    .popover(isPresented: $showQuickAddSchedule, arrowEdge: .bottom) {
                        QuickAddSchedulePopover(workspace: workspace, initial: timing,
                            onCancel: { showQuickAddSchedule = false },
                            onApply: { value in
                                quickAddScheduleOverride = value
                                showQuickAddSchedule = false
                            })
                    }
                    Button { showQuickAddProperties = true } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(WFColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("更多任务属性")
                    .popover(isPresented: $showQuickAddProperties, arrowEdge: .bottom) {
                        QuickAddPropertiesPopover(
                            workspace: workspace,
                            selectedPriority: quickAddPriorityOverride ?? quickAddResult.priority,
                            selectedList: quickAddListOverride ?? quickAddResult.listName ?? workspace.activeList ?? TaskList.inbox.name,
                            selectedTags: quickAddTagsOverride ?? quickAddResult.tags,
                            onPriority: { value in
                                quickAddPriorityOverride = value
                                showQuickAddProperties = false
                            },
                            onList: { quickAddListOverride = $0 },
                            onTags: { quickAddTagsOverride = $0 }
                        )
                    }
                }
            }
            let parsed = quickAddResult
            if !parsed.tokens.isEmpty {
                HStack(spacing: 5) {
                    ForEach(parsed.tokens) { token in
                        Button {
                            dismissedQuickAddTokens.insert(token.id)
                        } label: {
                            HStack(spacing: 3) {
                                Text(token.label)
                                Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                            }
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(WFColors.selection, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("移除识别项：\(token.label)")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 24)
            }
            if quickAddFocused || !draft.isEmpty {
                // 识别摘要行（Flutter 语义：→ 日期 · 提醒 · 每天 · #tag · @清单 · 高优先级）。
                let summary = QuickAddParser.summaryLine(for: draft,
                                                         knownLists: Set(workspace.allListNames),
                                                         now: workspace.clock(),
                                                         calendar: workspace.calendar)
                if !summary.isEmpty {
                    Text(summary).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                        .padding(.leading, 24)
                }
            }
        }
        .frame(minHeight: 36, alignment: .center)
        .padding(.horizontal, WFSpace.md)
        .padding(.vertical, 4)
        // 滴答式可见的浅灰圆角条：controlBackgroundColor 在浅色模式下与白底无差别。
        .background(WFColors.canvas, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        // 描边必须用 stroke：overlay 直接填颜色会整块盖住输入框并吃掉点击。
        .overlay(RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border, lineWidth: 1))
        // 对齐 Flutter：点击栏上任意位置都聚焦输入框（按钮优先级更高不受影响）。
        .onTapGesture { quickAddFocused = true }
        .padding(.horizontal, WFSpace.xl)
        .padding(.bottom, WFSpace.xs)
    }

    private var quickAddTargetName: String {
        TaskListViewDefaults.quickAddTargetName(scope: scope,
                                                activeList: workspace.activeList,
                                                activeTag: workspace.activeTag,
                                                inboxName: TaskList.inbox.name)
    }

    @ViewBuilder
    private func groupHeader(_ group: TaskListGroup) -> some View {
        HStack(spacing: WFSpace.sm) {
            Button { groupExpansion.toggle(group) } label: {
                HStack(spacing: 6) {
                    Image(systemName: groupExpansion.isCollapsed(group) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                    Text(groupTitle(group)).font(WFType.section)
                    Text("\(group.tasks.count)").font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let note = TaskListViewDefaults.groupTrailingNote(for: group.kind) {
                Button(note) {
                    workspace.postponeOverdue(Set(group.tasks.map(\.id)))
                }
                .buttonStyle(.plain)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.accent)
                .help("将已过期任务顺延到今天")
            }
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.top, WFSpace.md)
        .padding(.bottom, WFSpace.xs)
    }

    private func revealSelectedClosedTask() {
        guard let scope, let task = workspace.selectedTask else { return }
        groupExpansion.reveal(task, in: scope, calendar: workspace.calendar)
    }

    /// "已完成"分组默认折叠在列表底部（TickTick 行为）；只在每个分组第一次出现时折叠一次，
    /// 之后尊重用户手动展开/收起。已完成视图本身不折叠。
    private var groupIDs: [String] { groups.map(\.id) }

    private func collapseNewCompletedGroups() {
        guard scope != .completed else { return }
        for group in groups where group.kind == .completed {
            if seenCompletedGroupIDs.insert(group.id).inserted,
               !groupExpansion.isCollapsed(group) {
                groupExpansion.toggle(group)
            }
        }
    }

    private func displayedNodes(for group: TaskListGroup, scope: TaskListScope) -> [TaskTreeNode] {
        workspace.nodes(for: group, scope: scope, query: query,
                        orderedRoots: group.orderedTasks(using: sortMode, calendar: workspace.calendar))
    }

    private func selectFiltered(_ offset: Int) {
        guard let scope else { return }
        let nodes = groups.flatMap { displayedNodes(for: $0, scope: scope) }
        guard !nodes.isEmpty else { return }
        let current = nodes.firstIndex { $0.task.id == workspace.selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), nodes.count - 1) } ?? (offset < 0 ? nodes.count - 1 : 0)
        workspace.selectFromKeyboard(nodes[index].task.id)
    }

    private func groupTitle(_ group: TaskListGroup) -> String {
        switch group.kind {
        case .pinned: return "置顶"
        case .overdue: return "已过期"
        // 滴答式组标题带星期上下文："今天, 周六"。
        case .today:
            return "今天, " + workspace.clock().formatted(.dateTime.weekday(.abbreviated).locale(.appDate))
        case .upcoming: return "最近 7 天"
        case .later: return "更远"
        case .undated: return "无日期"
        case .day:
            guard let day = group.day else { return "" }
            return day.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated).locale(.appDate))
        case .plain: return ""
        case .completed:
            guard let day = group.day else { return group.label ?? "已完成" }
            return day.formatted(.dateTime.month(.abbreviated).day().locale(.appDate))
        }
    }

    private func rowIdentity(group: TaskListGroup, task: Task) -> String {
        let status = task.status == .completed ? "completed" : "active"
        let abandoned = task.isAbandoned ? "abandoned" : "normal"
        return group.id + ":" + task.id.uuidString + ":" + status + ":" + abandoned
    }

    @ViewBuilder
    private func taskListSection() -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if groups.isEmpty {
                    Text(TaskListViewDefaults.emptyStateMessage(destination: navigation.destination))
                        .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                        .frame(maxWidth: .infinity).padding(.vertical, WFSpace.page)
                }
                ForEach(groups, id: \.id) { group in
                    if group.kind != .plain { groupHeader(group) }
                    if group.kind == .plain || !groupExpansion.isCollapsed(group) {
                        ForEach(displayedNodes(for: group, scope: scope ?? .today),
                                id: \.task.id) { node in
                            taskRow(group: group, node: node)
                        }
                    }
                }
            }
            .padding(.horizontal, WFSpace.md)
            .padding(.bottom, WFSpace.xl)
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            guard !quickAddFocused, scope != nil else { return .ignored }
            selectFiltered(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !quickAddFocused, scope != nil else { return .ignored }
            selectFiltered(1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !quickAddFocused, scope != nil else { return .ignored }
            if workspace.selectedTaskID == nil { selectFiltered(1) }
            return .handled
        }
        .onKeyPress(.space) {
            guard !quickAddFocused, let task = workspace.selectedTask else { return .ignored }
            _ = workspace.changeStatus(task, in: scope); return .handled
        }
    }

    @ViewBuilder
    private func taskRow(group: TaskListGroup, node: TaskTreeNode) -> some View {
        let row = HStack(spacing: 0) {
            if selecting {
                Toggle("选择", isOn: Binding(get: { workspace.bulkSelection.contains(node.task.id) }, set: { value in
                    workspace.setBulkSelected(node.task.id, value)
                })).labelsHidden()
            }
            TaskRowView(
                task: node.task,
                workspace: workspace,
                depth: node.depth,
                hasChildren: node.hasChildren,
                expanded: node.expanded,
                selected: workspace.selectedTaskID == node.task.id || workspace.bulkSelection.contains(node.task.id),
                showsListBadge: showsListBadge,
                onSelect: { handleSelection(of: node.task.id) },
                onComplete: { _ = workspace.complete(node.task.id, in: scope) },
                onRestore: { _ = workspace.restore(node.task.id, in: scope) },
                onToggleExpanded: { workspace.toggleExpanded(node.task.id) }
            )
        }
        if node.depth == 0 {
            row
                .draggable(node.task.id.uuidString)
                .modifier(TaskReorderDropModifier(workspace: workspace, targetID: node.task.id))
                .id(rowIdentity(group: group, task: node.task))
        } else {
            // 子任务不可拖、也不作为重排落点（对齐 Flutter）。
            row.id(rowIdentity(group: group, task: node.task))
        }
        // 行分隔线：与行悬浮底色同色（WFColors.hover），右端收进一截。
        Rectangle()
            .fill(WFColors.hover)
            .frame(height: 1)
            .padding(.leading, WFSpace.page)
            .padding(.trailing, WFSpace.lg)
    }

    private func handleSelection(of taskID: UUID) {
        listFocused = true
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) || modifiers.contains(.control) {
            selecting = true
            workspace.toggleBulkSelection(taskID)
        } else if modifiers.contains(.shift) {
            selecting = true
            workspace.extendBulkSelection(to: taskID, in: visibleTaskIDs)
        } else if selecting {
            workspace.toggleBulkSelection(taskID)
        } else {
            workspace.clearBulkSelection()
            workspace.select(taskID)
        }
    }

    private var quickAddResult: QuickAddParseResult {
        QuickAddParser.parse(draft, now: workspace.clock(), calendar: workspace.calendar,
                             knownLists: Set(workspace.allListNames),
                             dismissedTokenIDs: dismissedQuickAddTokens)
    }

    private var hasDismissedQuickAddScheduleToken: Bool {
        QuickAddParser.hasDismissedScheduleToken(in: draft, now: workspace.clock(),
            calendar: workspace.calendar, knownLists: Set(workspace.allListNames),
            dismissedTokenIDs: dismissedQuickAddTokens)
    }

    private func currentQuickAddSchedule(for scope: TaskListScope) -> QuickAddScheduleDraft {
        QuickAddScheduleDraft(parsed: quickAddResult,
                              defaultDueAt: scope == .today && !hasDismissedQuickAddScheduleToken
                                ? workspace.dateFromToday(0) : nil)
    }

    private func addTask(in scope: TaskListScope) {
        let parsed = quickAddResult
        guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let timing = quickAddScheduleOverride ?? currentQuickAddSchedule(for: scope)
        let priority = quickAddPriorityOverride ?? parsed.priority
        let list = quickAddListOverride ?? parsed.listName ?? workspace.activeList ?? TaskList.inbox.name
        let selectedTags = quickAddTagsOverride ?? parsed.tags
        var tags = workspace.activeTag.map { [$0] } ?? []
        tags.append(contentsOf: selectedTags)
        tags = tags.reduce(into: []) { values, tag in if !values.contains(tag) { values.append(tag) } }
        _ = workspace.createDraft(title: parsed.title,
                                  list: list,
                                  schedule: timing.schedule,
                                  priority: priority, tags: tags,
                                  reminder: timing.reminderAt, repeatFrequency: timing.repeatFrequency,
                                  recurrenceRule: timing.recurrenceRule)
        draft = ""
        dismissedQuickAddTokens.removeAll()
        quickAddScheduleOverride = nil
        quickAddPriorityOverride = nil
        quickAddListOverride = nil
        quickAddTagsOverride = nil
    }
}

// MARK: - 任务行：复选框 + 标题同行，徽标右对齐，子任务灰色预览

struct TaskRowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    var showsListBadge: Bool = true
    let onSelect: () -> Void
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onToggleExpanded: () -> Void
    @State private var hovering = false
    @State private var showDatePopover = false
    @State private var showTagPicker = false

    /// 父行展开箭头区宽度：14 + WFSpace.sm 间距 = 22，是子行缩进与父复选框对齐的基准；
    /// 子行缩进步进 44 = 22 + 22，让 depth=1 的子复选框落在父标题起点再偏右一点。
    private var chevronZoneWidth: CGFloat { 14 }

    var body: some View {
        HStack(alignment: .top, spacing: WFSpace.sm) {
            if depth == 0 {
                ZStack(alignment: .leading) {
                    if hasChildren {
                        Button(action: onToggleExpanded) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WFColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .help(expanded ? "收起子任务" : "展开子任务")
                    } else {
                        Color.clear
                    }
                }
                .frame(width: chevronZoneWidth)
            }
            Button(action: task.isClosed ? onRestore : onComplete) {
                TaskRowCompletionBox(task: task)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isClosed ? "恢复任务" : "完成任务")
            .accessibilityLabel(task.isClosed ? "恢复：\(task.title)" : "完成：\(task.title)")

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title.isEmpty ? "无标题" : task.title)
                        .font(WFType.listTitle).lineLimit(1)
                        .foregroundStyle(task.isClosed ? WFColors.secondaryText : WFColors.text)
                    if let preview = rowPreview {
                        Text(preview)
                            .font(WFType.supporting).lineLimit(1)
                            .foregroundStyle(WFColors.secondaryText)
                    }
                }
                // 内容区高度 = 行高 55 − 上下 11 内边距：点击区铺满内容区，
                // 标题顶对齐（勾选框与标题首行同轴，对齐 Flutter 顶对齐行）。
                .frame(maxWidth: .infinity, minHeight: 33, alignment: .topLeading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            // 与 Flutter 行一致：元数据尾栏常驻，悬浮只做行背景高亮，不浮现
            // 任何快捷按钮（日期走尾栏日期徽章，优先级走右键菜单/检查器）。
            TaskRowMetadataTrail(task: task, workspace: workspace,
                                 showsListBadge: showsListBadge,
                                 onOpenDate: { showDatePopover = true })
        }
        .padding(.horizontal, WFSpace.sm)
        // 对齐 Flutter rowVerticalPadding = 11：内容顶对齐，勾选框贴标题首行。
        .padding(.vertical, 11)
        // 子行每层缩进 44：父行 depth=0 不变；展开箭头区只挂在 depth=0 行上不受影响。
        .padding(.leading, CGFloat(depth) * 44)
        // 行高 55：在 Flutter rowMinHeight = 50 的基础上按使用习惯放宽。
        .frame(minHeight: 55)
        .background(selected ? WFColors.selection : hovering ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .onHover { hovering = $0 }
        .overlay {
            // 右键菜单走 AppKit NSPopover 显式定位（对齐 Flutter bottomStart：
            // 面板顶部在光标下方、左缘对齐光标），见 TaskContextMenuPresenter。
            SecondaryClickCapture { rowView, point in
                guard let current = workspace.task(for: task.id) else { return }
                TaskContextMenuPresenter.show(in: rowView, at: point,
                                              environment: environment,
                                              workspace: workspace, task: current,
                                              onCustomDate: { showDatePopover = true })
            }
        }
        .popover(isPresented: $showDatePopover, arrowEdge: .trailing) {
            if let current = workspace.task(for: task.id) {
                TaskDatePopoverV2(task: current, workspace: workspace) { showDatePopover = false }
            }
        }
        .popover(isPresented: $showTagPicker, arrowEdge: .trailing) {
            if let current = workspace.task(for: task.id) {
                TaskTagPickerPopover(initialTags: current.tags, workspace: workspace,
                                     onCancel: { showTagPicker = false },
                                     onApply: { tags in
                                         workspace.setTags(task.id, tags)
                                         showTagPicker = false
                                     })
            }
        }
    }

    private var children: [Task] {
        workspace.allTasks.filter {
            $0.parentID == task.id && $0.deletedAt == nil && $0.skippedAt == nil &&
                !$0.isAbandoned && !$0.isConverted
        }.sorted { $0.childOrder < $1.childOrder }
    }

    /// 折叠时在标题下方显示灰色的"- [ ] 子任务"预览；展开后由子任务行呈现，不再重复。
    private var subtaskPreview: String? {
        guard hasChildren, !expanded else { return nil }
        return TaskListViewDefaults.subtaskPreview(titles: children.map(\.title))
    }

    /// 标题下的灰色预览行：折叠且有子任务用子任务预览，否则正文有内容时用单行正文。
    private var rowPreview: String? {
        subtaskPreview ?? TaskListViewDefaults.bodyPreview(of: task.document.plainText)
    }

}

private enum TaskRowPriority {
    static func title(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }

    static func color(_ priority: TaskPriority) -> Color {
        switch priority {
        case .none: WFColors.secondaryText
        case .low: WFColors.accent
        case .medium: .orange
        case .high: .red
        }
    }
}

/// 勾选框对齐 Flutter：18×18 槽位（即点击区），描边盒按 completionBoxSize
/// 14.58 绘制（圆角 4.5 × 缩放 0.81 ≈ 3.6），贴槽位左缘；完成/放弃图标居中。
/// 描边按优先级着色（高红/中橙/低=强调色），完成后强调色填充。
private struct TaskRowCompletionBox: View {
    let task: Task

    var body: some View {
        if task.isAbandoned {
            Image(systemName: "circle.slash")
                .font(.system(size: 15))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 18, height: 18)
        } else if task.isClosed {
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 14.5))
                .foregroundStyle(WFColors.accent)
                .frame(width: 18, height: 18)
        } else {
            RoundedRectangle(cornerRadius: 3.6)
                .stroke(TaskRowPriority.color(task.priority), lineWidth: 1.5)
                .frame(width: 14.58, height: 14.58)
                .frame(width: 18, height: 18, alignment: .leading)
        }
    }
}

/// 手动排序的拖放目标（Round B1，对齐 Flutter moveTaskBefore）：拖行悬停时在
/// 目标行上缘显示插入条，drop → workspace.reorder(id, before:)。只挂在根任务
/// 行上（见 taskRow），子任务不可拖也不作为落点。
private struct TaskReorderDropModifier: ViewModifier {
    @ObservedObject var workspace: TaskWorkspaceModel
    let targetID: UUID
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { values, _ in
                guard let id = values.first.flatMap(UUID.init(uuidString:)),
                      id != targetID else { return false }
                workspace.reorder(id, before: targetID)
                return true
            } isTargeted: { targeted = $0 }
            .overlay(alignment: .top) {
                if targeted {
                    Capsule()
                        .fill(WFColors.accent)
                        .frame(height: 2)
                        .padding(.horizontal, WFSpace.sm)
                        .transition(.opacity)
                }
            }
    }
}

/// 行尾右对齐的元数据：清单、优先级旗标、截止、描述/提醒等小图标与日期徽标
/// 全部常驻（与迁移版一致），悬浮时快捷操作在尾栏右侧追加，不替换任何元素。
/// 日期徽标颜色：今天=强调色、过期=红色、其余=灰色。
private struct TaskRowMetadataTrail: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var showsListBadge: Bool
    let onOpenDate: () -> Void

    private var deadlineOverdue: Bool {
        guard let deadline = task.schedule.deadlineAt, !task.isClosed else { return false }
        return workspace.calendar.startOfDay(for: deadline) <= workspace.calendar.startOfDay(for: workspace.clock())
    }

    private var dateStyle: TaskListViewDefaults.DateBadgeStyle {
        TaskListViewDefaults.dateBadgeStyle(dueAt: task.schedule.dueAt, isClosed: task.isClosed,
                                            now: workspace.clock(), calendar: workspace.calendar)
    }

    private var muted: Color { task.isClosed ? WFColors.tertiaryText : WFColors.secondaryText }

    var body: some View {
        HStack(spacing: WFSpace.xs) {
            if task.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(task.isClosed ? muted : WFColors.accent)
                    .accessibilityLabel("已置顶")
            }
            if task.isAbandoned { Text("已放弃").foregroundStyle(muted) }
            if showsListBadge, task.list.name != TaskList.inbox.name {
                // 清单名最先被压缩：低优先级 + 40pt 上限，把宽度让给日期。
                Text(task.list.name).lineLimit(1)
                    .frame(maxWidth: 40).foregroundStyle(muted).layoutPriority(-1)
            }
            if task.priority != .none {
                Image(systemName: "flag.fill")
                    .foregroundStyle(task.isClosed ? muted : TaskRowPriority.color(task.priority))
                    .accessibilityLabel(TaskRowPriority.title(task.priority))
            }
            ForEach(Array(secondaryMetadata.prefix(WFMetrics.secondaryMetadataLimit))) { item in
                if let value = item.value {
                    Text(value).foregroundStyle(muted).accessibilityLabel(item.accessibilityLabel)
                } else if let symbol = item.symbol {
                    Image(systemName: symbol).foregroundStyle(muted)
                        .accessibilityLabel(item.accessibilityLabel)
                }
            }
            if let deadline = task.schedule.deadlineAt {
                Text(TaskDateLabel.text(deadline, hasTime: false,
                                        now: workspace.clock(), calendar: workspace.calendar) + "截止")
                    .foregroundStyle(task.isClosed ? muted : deadlineOverdue ? .red : muted)
                    .layoutPriority(0)
            }
            if task.schedule.dueAt != nil {
                // 日期是行内最重要的元信息：固定尺寸不被压缩。
                dateBadge.fixedSize().layoutPriority(2)
            }
        }
        .font(WFType.supporting)
        .lineLimit(1)
        .frame(maxWidth: 200, alignment: .trailing)
    }

    private var dateBadge: some View {
        Button { onOpenDate() } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar").font(.system(size: 10))
                Text(TaskDateLabel.text(task.schedule.dueAt ?? Date(), hasTime: task.schedule.hasTime,
                                        now: workspace.clock(), calendar: workspace.calendar))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(task.isClosed ? WFColors.tertiaryText : badgeColor)
        .help("修改安排日期")
        .accessibilityLabel("安排日期：\(task.title.isEmpty ? "无标题" : task.title)")
    }

    private var badgeColor: Color {
        switch dateStyle {
        case .overdue: .red
        case .today: WFColors.accent
        case .scheduled: WFColors.secondaryText
        case .none: WFColors.secondaryText
        }
    }

    private var secondaryMetadata: [TaskRowSecondaryMetadata] {
        var items: [TaskRowSecondaryMetadata] = []
        if task.recurrence != .never {
            items.append(.init(id: "repeat", symbol: "repeat", accessibilityLabel: "重复任务"))
        }
        if task.reminderAt != nil {
            items.append(.init(id: "reminder", symbol: "bell", accessibilityLabel: "有提醒"))
        }
        if !task.tags.isEmpty {
            items.append(.init(id: "tags", symbol: "tag", accessibilityLabel: "有标签"))
        }
        if !task.document.isEmpty {
            items.append(.init(id: "description", symbol: "text.alignleft", accessibilityLabel: "有描述"))
        }
        if !task.attachments.isEmpty {
            items.append(.init(id: "attachments", symbol: "paperclip", accessibilityLabel: "有附件"))
        }
        return items
    }
}

private struct TaskRowSecondaryMetadata: Identifiable {
    let id: String
    var symbol: String? = nil
    var value: String? = nil
    let accessibilityLabel: String
}

// MARK: - 纯展示规则（Foundation 逻辑，供 WorkFollowTests/TaskListViewDefaults.swift 覆盖）

/// 对齐滴答清单的纯展示规则：快速添加占位、空状态文案、日期徽标归类、
/// 子任务预览与分组尾注。只依赖 Foundation 与投影类型，保持可单测。
enum TaskListViewDefaults {
    /// 日期徽标归类：过期红、今天强调色、未来灰、无日期/已关闭不给色。
    enum DateBadgeStyle: Equatable {
        case overdue, today, scheduled, none
    }

    /// 快速添加框占位"添加任务至"X""的目标名：清单 → 标签 → 视图语义 → 收集箱。
    static func quickAddTargetName(scope: TaskListScope?, activeList: String?,
                                   activeTag: String?, inboxName: String) -> String {
        if let activeList { return activeList }
        if let activeTag { return "#" + activeTag }
        switch scope {
        case .today: return "今天"
        case .nextSevenDays: return "最近 7 天"
        default: return inboxName
        }
    }

    /// 列表为空时的文案，对齐滴答各视图的空状态。
    static func emptyStateMessage(destination: NativeDestination) -> String {
        switch destination {
        case .trash: return "垃圾桶是空的"
        case .today: return "今天的事情都做完了"
        case .inbox: return "没想好把任务安排在哪？可以先放这里"
        default: return "这里还没有任务"
        }
    }

    static func dateBadgeStyle(dueAt: Date?, isClosed: Bool, now: Date, calendar: Calendar) -> DateBadgeStyle {
        guard let dueAt, !isClosed else { return .none }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: dueAt)
        if day < today { return .overdue }
        if day == today { return .today }
        return .scheduled
    }

    /// TickTick 式子任务预览：`- [ ] 甲 - [ ] 乙`，取前 limit 条；无标题兜底"无标题"。
    static func subtaskPreview(titles: [String], limit: Int = 3) -> String? {
        let names = titles.map { $0.isEmpty ? "无标题" : $0 }.prefix(max(limit, 1))
        guard !names.isEmpty else { return nil }
        return names.map { "- [ ] " + $0 }.joined(separator: " ")
    }

    /// 行内正文预览：取纯文本第一个非空行；正文为空返回 nil（不占预览行）。
    static func bodyPreview(of plainText: String) -> String? {
        for line in plainText.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// 分组标题右侧的小字尾注；只有"已过期"组显示"顺延"。
    static func groupTrailingNote(for kind: TaskGroupKind) -> String? {
        kind == .overdue ? "顺延" : nil
    }
}
