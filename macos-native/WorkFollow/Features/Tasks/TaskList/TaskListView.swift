import SwiftUI

struct TaskListView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @State private var draft = ""
    @State private var search = ""
    @State private var listFilter: String?
    @State private var tagFilter: String?
    @State private var showNavigation = false
    @FocusState private var quickAddFocused: Bool
    @FocusState private var listFocused: Bool

    private var scope: TaskListScope? { TaskWorkspaceModel.scope(for: navigation.destination) }
    private var query: TaskListQuery { TaskListQuery(search: search, list: listFilter, tag: tagFilter) }
    private var groups: [TaskListGroup] { scope.map { workspace.groups(for: $0, query: query) } ?? [] }
    private var canAdd: Bool { scope == .today || scope == .inbox || scope == .allTasks }

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
                Label(navigation.destination.title, systemImage: navigation.destination.symbol)
                    .font(WFType.pageTitle)
                Spacer(minLength: 0)
                Button { workspace.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("撤销上一次任务操作").disabled(!workspace.canUndo)
                if let scope {
                    Text("\(workspace.count(for: scope))")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
            }
            .padding(.horizontal, WFSpace.xl)
            .padding(.top, WFSpace.xl)

            if canAdd, let scope {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "plus").foregroundStyle(WFColors.secondaryText)
                    TextField("添加任务至\(navigation.destination.title)", text: $draft)
                        .textFieldStyle(.plain).font(WFType.body)
                        .focused($quickAddFocused)
                        .onSubmit { addTask(in: scope) }
                    if scope == .today {
                        Image(systemName: "calendar")
                            .foregroundStyle(WFColors.accent).help("今天")
                    }
                }
                .padding(WFSpace.md)
                .background(WFColors.secondarySurface,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .padding(.horizontal, WFSpace.xl)
            }

            HStack {
                TextField("搜索任务", text: $search)
                Menu(listFilter ?? "清单") {
                    Button("全部清单") { listFilter = nil }
                    ForEach(Array(Set(workspace.allTasks.filter { $0.deletedAt == nil }.map { $0.list.name })).sorted(), id: \.self) { name in
                        Button(name) { listFilter = name }
                    }
                }
                Menu(tagFilter.map { "#" + $0 } ?? "标签") {
                    Button("全部标签") { tagFilter = nil }
                    ForEach(Array(Set(workspace.allTasks.filter { $0.deletedAt == nil }.flatMap(\.tags))).sorted(), id: \.self) { tag in
                        Button(tag) { tagFilter = tag }
                    }
                }
            }.padding(.horizontal, WFSpace.xl)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if groups.isEmpty {
                        Text(navigation.destination == .trash ? "垃圾桶是空的" : "这里还没有任务")
                            .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity).padding(.vertical, WFSpace.page)
                    }
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        if group.kind != .plain { groupHeader(group) }
                        ForEach(workspace.nodes(for: group, scope: scope ?? .today, query: query),
                                id: \.task.id) { node in
                            TaskRowView(
                                task: node.task,
                                workspace: workspace,
                                depth: node.depth,
                                hasChildren: node.hasChildren,
                                expanded: node.expanded,
                                selected: workspace.selectedTaskID == node.task.id,
                                onSelect: {
                                    listFocused = true
                                    workspace.select(node.task.id)
                                },
                                onComplete: { _ = workspace.complete(node.task.id, in: scope) },
                                onRestore: { _ = workspace.restore(node.task.id, in: scope) },
                                onToggleExpanded: { workspace.toggleExpanded(node.task.id) }
                            )
                            .id("\(group.kind)-\(node.task.id)-\(node.task.status)")
                            Divider().padding(.leading, WFSpace.page)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .onChange(of: environment.quickAddRequest) { _, _ in quickAddFocused = true }
        .onChange(of: navigation.destination) { _, _ in workspace.select(nil) }
        .onAppear {
            if environment.quickAddRequest > 0 { quickAddFocused = true }
            else { listFocused = true }
        }
        .onExitCommand { quickAddFocused = false }
    }

    @ViewBuilder
    private func groupHeader(_ group: TaskListGroup) -> some View {
        HStack(spacing: WFSpace.sm) {
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
            Text(groupTitle(group)).font(WFType.section)
            Text("\(group.tasks.count)").font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.top, WFSpace.lg)
        .padding(.bottom, WFSpace.sm)
    }

    private func selectFiltered(_ offset: Int) {
        guard let scope else { return }
        let nodes = workspace.visibleNodes(for: scope, query: query)
        guard !nodes.isEmpty else { return }
        let current = nodes.firstIndex { $0.task.id == workspace.selectedTaskID }
        let index = current.map { min(max($0 + offset, 0), nodes.count - 1) } ?? (offset < 0 ? nodes.count - 1 : 0)
        workspace.select(nodes[index].task.id)
    }

    private func groupTitle(_ group: TaskListGroup) -> String {
        switch group.kind {
        case .overdue: return "已过期"
        case .today: return "今天"
        case .plain: return ""
        case .completed:
            guard let day = group.day else { return "已完成" }
            return day.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func addTask(in scope: TaskListScope) {
        _ = workspace.createTask(title: draft, in: scope)
        draft = ""
    }
}

struct TaskRowView: View {
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
                Color.clear.frame(width: depth == 0 ? WFSpace.md : 0,
                                  height: WFMetrics.controlHeight)
            }
            Button(action: task.status == .completed ? onRestore : onComplete) {
                Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: WFMetrics.icon))
                    .foregroundStyle(task.status == .completed ? WFColors.tertiaryText
                                     : task.priority == .high ? .orange : WFColors.secondaryText)
                    .frame(width: WFSpace.xxl, height: WFMetrics.controlHeight)
            }
            .buttonStyle(.plain)
            .help(task.status == .completed ? "恢复任务" : "完成任务")
            .accessibilityLabel(task.status == .completed ? "恢复：\(task.title)" : "完成：\(task.title)")

            Button(action: onSelect) {
                HStack(spacing: WFSpace.sm) {
                    Text(task.title.isEmpty ? "无标题" : task.title)
                        .font(WFType.listTitle).lineLimit(1)
                        .foregroundStyle(task.status == .completed ? WFColors.secondaryText : WFColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(task.list.name).font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText).lineLimit(1)
                    if let tag = task.tags.first { Text("#" + tag).font(WFType.supporting).foregroundStyle(.secondary).lineLimit(1) }
                    if task.reminderAt != nil { Image(systemName: "bell").font(.caption).foregroundStyle(.secondary) }
                    if task.recurrence != .never { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.leading, CGFloat(depth) * WFSpace.lg)
                .frame(maxWidth: .infinity, minHeight: WFMetrics.rowHeight)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            TaskDateButton(task: task, workspace: workspace)
        }
        .padding(.horizontal, WFSpace.sm)
        .background(selected ? WFColors.selection : hovering ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("打开任务", action: onSelect)
            Button(task.status == .completed ? "恢复任务" : "完成任务",
                   action: task.status == .completed ? onRestore : onComplete)
            if depth == 0, hasChildren {
                Button(expanded ? "收起子任务" : "展开子任务", action: onToggleExpanded)
            }
        }
    }

    private func dateLabel(_ date: Date, hasTime: Bool) -> String {
        date.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted)
    }
}
