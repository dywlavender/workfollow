import SwiftUI

struct TaskListView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @State private var draft = ""
    @State private var showNavigation = false
    @State private var showComposer = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            HStack(spacing: WFSpace.md) {
                if !navigationVisible {
                    Button { showNavigation.toggle() } label: {
                        Image(systemName: "sidebar.left")
                    }.buttonStyle(.plain).help("显示导航")
                        .popover(isPresented: $showNavigation) {
                            NavigationColumnView(workspace: workspace, navigation: navigation) {
                                showNavigation = false
                            }
                            .frame(width: WFMetrics.navigationWidth, height: 340)
                        }
                }
                Label(workspace.activeList ?? workspace.activeTag.map { "#" + $0 } ?? navigation.destination.title, systemImage: navigation.destination.symbol)
                    .font(WFType.pageTitle)
                Spacer(minLength: 0)
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
                .help("排序：\(sortMode.title)")
                Button { workspace.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("撤销上一次任务操作").disabled(!workspace.canUndo)
                Menu {
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
                .help("列表操作")
                if let scope {
                    Text("\(query.isFiltering ? workspace.visibleNodes(for: scope, query: query).filter { scope == .completed || !$0.task.isClosed }.count : workspace.count(for: scope))")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
            }
            .padding(.horizontal, WFSpace.xl)
            .padding(.top, WFSpace.xl)

            if canAdd, let scope {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: WFSpace.sm) {
                        Button { showComposer = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("新建任务（完整属性）")
                        TextField("添加任务至\(workspace.activeList ?? TaskList.inbox.name)", text: $draft)
                            .textFieldStyle(.plain).font(WFType.body)
                            .focused($quickAddFocused)
                            .onSubmit { addTask(in: scope) }
                        if quickAddFocused || !draft.isEmpty || showQuickAddSchedule || showQuickAddProperties {
                            let timing = quickAddScheduleOverride ?? currentQuickAddSchedule(for: scope)
                            Button { showQuickAddSchedule = true } label: {
                                HStack(spacing: WFSpace.xs) {
                                    Image(systemName: timing.dueAt == nil ? "calendar.badge.plus" : "calendar")
                                    if navigation.destination != .inbox, let dueAt = timing.dueAt {
                                        Text(TaskDateLabel.text(dueAt, hasTime: timing.hasTime,
                                                               now: workspace.clock(), calendar: workspace.calendar))
                                            .lineLimit(1)
                                    }
                                }
                                .foregroundStyle(timing.dueAt == nil ? WFColors.secondaryText : WFColors.accent)
                                .padding(.horizontal, WFSpace.sm)
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
                        }
                        Button { showQuickAddProperties = true } label: { Image(systemName: "ellipsis") }
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
                        .padding(.leading, 26)
                    }
                }
                .padding(WFSpace.md)
                .background(WFColors.secondarySurface,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .padding(.horizontal, WFSpace.xl)
            }

            if !workspace.bulkSelection.isEmpty { TaskBulkBar(workspace: workspace) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if groups.isEmpty {
                        Text(navigation.destination == .trash ? "垃圾桶是空的" : "这里还没有任务")
                            .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity).padding(.vertical, WFSpace.page)
                    }
                    ForEach(groups, id: \.id) { group in
                        if group.kind != .plain { groupHeader(group) }
                        if group.kind == .plain || !groupExpansion.isCollapsed(group) {
                            ForEach(displayedNodes(for: group, scope: scope ?? .today),
                                    id: \.task.id) { node in
                                HStack(spacing: 0) {
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
                                        onSelect: { handleSelection(of: node.task.id) },
                                        onComplete: { _ = workspace.complete(node.task.id, in: scope) },
                                        onRestore: { _ = workspace.restore(node.task.id, in: scope) },
                                        onToggleExpanded: { workspace.toggleExpanded(node.task.id) }
                                    )
                                }
                                .draggable(node.task.id.uuidString)
                                .dropDestination(for: String.self) { values, _ in
                                    guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                                    workspace.reorder(id, before: node.task.id); return true
                                }
                                .id(rowIdentity(group: group, task: node.task))
                                Divider().padding(.leading, WFSpace.page)
                            }
                        }
                    }
                }
                .padding(.horizontal, WFSpace.md)
                .padding(.bottom, WFSpace.xl)
            }
            .focusable()
            .focused($listFocused)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .onChange(of: environment.quickAddRequest) { _, _ in quickAddFocused = true }
        .onChange(of: showQuickAddSchedule) { _, isPresented in
            if !isPresented { quickAddFocused = true }
        }
        .onChange(of: showQuickAddProperties) { _, isPresented in
            if !isPresented { quickAddFocused = true }
        }
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
        .onChange(of: workspace.selectedTaskID) { _, _ in revealSelectedClosedTask() }
        .onAppear {
            if environment.quickAddRequest > 0 { quickAddFocused = true }
            else { listFocused = true }
            revealSelectedClosedTask()
        }
        .onExitCommand { quickAddFocused = false }
    }

    @ViewBuilder
    private func groupHeader(_ group: TaskListGroup) -> some View {
        HStack(spacing: WFSpace.sm) {
            Button { groupExpansion.toggle(group) } label: {
                HStack(spacing: WFSpace.sm) {
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
            if group.kind == .overdue {
                Button("顺延") {
                    workspace.postponeOverdue(Set(group.tasks.map(\.id)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.accent)
                .help("将已过期任务顺延到今天")
            }
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.top, WFSpace.lg)
        .padding(.bottom, WFSpace.sm)
    }

    private func revealSelectedClosedTask() {
        guard let scope, let task = workspace.selectedTask else { return }
        groupExpansion.reveal(task, in: scope, calendar: workspace.calendar)
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
        case .today: return "今天"
        case .upcoming: return "最近 7 天"
        case .later: return "更远"
        case .undated: return "无日期"
        case .day:
            guard let day = group.day else { return "" }
            return day.formatted(.dateTime.month(.abbreviated).day())
        case .plain: return ""
        case .completed:
            guard let day = group.day else { return group.label ?? "已完成" }
            return day.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func rowIdentity(group: TaskListGroup, task: Task) -> String {
        let status = task.status == .completed ? "completed" : "active"
        let abandoned = task.isAbandoned ? "abandoned" : "normal"
        return group.id + ":" + task.id.uuidString + ":" + status + ":" + abandoned
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
                             availableLists: workspace.allListNames,
                             dismissedTokenIDs: dismissedQuickAddTokens)
    }

    private var hasDismissedQuickAddScheduleToken: Bool {
        QuickAddParser.hasDismissedScheduleToken(in: draft, now: workspace.clock(),
            calendar: workspace.calendar, availableLists: workspace.allListNames,
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

struct TaskRowView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    let onSelect: () -> Void
    let onComplete: () -> Void
    let onRestore: () -> Void
    let onToggleExpanded: () -> Void
    @State private var hovering = false
    @State private var showDatePopover = false
    @State private var showTagPicker = false
    @State private var showTaskContextMenu = false
    @State private var contextMenuAnchor = CGPoint.zero

    var body: some View {
        HStack(spacing: WFSpace.sm) {
            if depth == 0, hasChildren {
                Button(action: onToggleExpanded) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: WFSpace.md, height: WFMetrics.controlHeight)
                }
                .buttonStyle(.plain)
                .help(expanded ? "收起子任务" : "展开子任务")
            } else {
                Color.clear.frame(width: WFSpace.md, height: WFMetrics.controlHeight)
            }
            Button(action: task.isClosed ? onRestore : onComplete) {
                Image(systemName: task.isAbandoned ? "circle.slash"
                                 : task.isClosed ? "checkmark.square.fill" : "square")
                    .font(.system(size: WFMetrics.icon))
                    .foregroundStyle(task.isClosed ? WFColors.tertiaryText
                                     : task.priority == .high ? .red
                                        : task.priority == .medium ? .orange : WFColors.accent)
                    .frame(width: WFSpace.xxl, height: WFMetrics.controlHeight)
            }
            .buttonStyle(.plain)
            .help(task.isClosed ? "恢复任务" : "完成任务")
            .accessibilityLabel(task.isClosed ? "恢复：\(task.title)" : "完成：\(task.title)")

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: WFSpace.xs) {
                    Text(task.title.isEmpty ? "无标题" : task.title)
                        .font(WFType.listTitle).lineLimit(1)
                        .foregroundStyle(task.isClosed ? WFColors.secondaryText : WFColors.text)
                    if !task.document.isEmpty {
                        Text(task.document.plainText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(WFType.supporting).lineLimit(1)
                            .foregroundStyle(WFColors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: WFMetrics.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            TaskRowMetadataTrail(task: task, workspace: workspace, onSelect: onSelect)
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.leading, CGFloat(depth) * 24)
        .background(selected ? WFColors.selection : hovering ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .onHover { hovering = $0 }
        .overlay {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    SecondaryClickCapture { point in
                        contextMenuAnchor = CGPoint(x: point.x,
                            y: geometry.size.height - point.y)
                        showTaskContextMenu = true
                    }
                    Color.clear
                        .frame(width: 1, height: 1)
                        .position(x: contextMenuAnchor.x, y: contextMenuAnchor.y)
                        .popover(isPresented: $showTaskContextMenu, arrowEdge: .trailing) {
                            if let current = workspace.task(for: task.id) {
                                TaskContextMenuPopover(workspace: workspace,
                                    isPresented: $showTaskContextMenu, task: current,
                                    onCustomDate: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            showDatePopover = true
                                        }
                                    })
                                }
                            }
                        }
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

    private func dateLabel(_ date: Date, hasTime: Bool) -> String {
        date.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted)
    }
}

/// Keeps task properties in a bounded, right-aligned trail so the title and
/// document preview retain their own column, matching Flutter's shared row.
private struct TaskRowMetadataTrail: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    let onSelect: () -> Void

    private var children: [Task] {
        workspace.allTasks.filter {
            $0.parentID == task.id && $0.deletedAt == nil && $0.skippedAt == nil &&
                !$0.isAbandoned && !$0.isConverted
        }
    }

    private var deadlineOverdue: Bool {
        guard let deadline = task.schedule.deadlineAt, !task.isClosed else { return false }
        return workspace.calendar.startOfDay(for: deadline) <= workspace.calendar.startOfDay(for: workspace.clock())
    }

    private var muted: Color { task.isClosed ? WFColors.tertiaryText : WFColors.secondaryText }

    var body: some View {
        HStack(spacing: WFSpace.xs) {
            Button(action: onSelect) {
                HStack(spacing: WFSpace.xs) {
                    if task.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(task.isClosed ? muted : WFColors.accent)
                            .accessibilityLabel("已置顶")
                    }
                    if task.isAbandoned { Text("已放弃").foregroundStyle(muted) }
                    if workspace.activeList == nil, task.list.name != TaskList.inbox.name {
                        Text(task.list.name).lineLimit(1).frame(maxWidth: 48).foregroundStyle(muted)
                    }
                    if task.priority != .none {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(task.isClosed ? muted : priorityColor)
                            .accessibilityLabel(priorityLabel)
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("打开任务：\(task.title.isEmpty ? "无标题" : task.title)")
            .accessibilityAddTraits(.isButton)
            if task.schedule.dueAt != nil {
                TaskDateButton(task: task, workspace: workspace, timeOnly: true)
            }
        }
        .font(WFType.supporting)
        .lineLimit(1)
        .frame(maxWidth: 180, alignment: .trailing)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .none: WFColors.secondaryText
        case .low: WFColors.accent
        case .medium: .orange
        case .high: .red
        }
    }

    private var priorityLabel: String {
        switch task.priority {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }

    private var secondaryMetadata: [TaskRowSecondaryMetadata] {
        var items: [TaskRowSecondaryMetadata] = []
        if !children.isEmpty {
            let completed = children.filter(\.isClosed).count
            items.append(.init(id: "children", value: "\(completed)/\(children.count)",
                               accessibilityLabel: "子任务完成 \(completed)/\(children.count)"))
        }
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
