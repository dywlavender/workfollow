import AppKit
import SwiftUI

/// 四象限页。
///
/// 一张固定的 2×2 棋盘：每个象限有自己的滚动区，一个象限里的长列表永远不会把其他
/// 三个推下去。象限由「重要」（优先级）与「紧急」（安排日在三天内）两个属性推出来，
/// 所以拖进另一个象限就是改这两项，视图自己不写这两个字段。
///
/// 与 Flutter `screens/matrix_screen.dart` 逐项对齐；唯一的差异是编辑器的呈现方式，
/// 见 `PlanningWorkspaceChrome`。
struct MatrixWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var settings: PlanningSettingsStore

    /// 已完成的任务默认在棋盘里，与原版参考图一致。可选的开关放在页面菜单里，
    /// 不占页头。
    private var showCompleted: Bool { settings.matrix.showCompleted }
    @State private var editingRule: MatrixQuadrantConfiguration?

    @MainActor
    init(workspace: TaskWorkspaceModel, settings: PlanningSettingsStore? = nil) {
        let settings = settings ?? PlanningSettingsStore.shared
        self.workspace = workspace; self.settings = settings
    }
    /// 折叠的分组 id。按 id 记：两个象限里可能有同名清单。
    @State private var collapsedGroups: Set<String> = []
    @State private var editingTaskID: UUID?
    /// 正在开着的新建卡；nil 表示没有。
    @State private var composerRequest: PlanningComposerRequest?
    /// 浮层的锚：点象限加号/菜单或任务行时把宿主视图写进来。
    @State private var anchorSink = PlanningAnchorRef()

    private var quadrants: [MatrixQuadrantViewModel] {
        MatrixProjection.project(
            tasks: workspace.tasksInActiveLists,
            now: workspace.clock(),
            listOrder: workspace.orderedListNames,
            includeCompleted: showCompleted,
            calendar: workspace.calendar,
            configuration: settings.matrix,
            hasChildren: { workspace.hasChildren($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
            MatrixBoardView(
                quadrants: quadrants,
                showCompleted: showCompleted,
                workspace: workspace,
                isExpanded: { !collapsedGroups.contains($0.id) },
                onToggleGroup: toggleGroup,
                onExpandAll: { quadrant in
                    collapsedGroups = collapsedGroups.filter {
                        !$0.hasPrefix(MatrixProjection.groupIDPrefix(quadrant))
                    }
                },
                onCollapseAll: { quadrant in
                    guard let model = quadrants.first(where: { $0.quadrant == quadrant }) else { return }
                    collapsedGroups.formUnion(model.groups.map(\.id))
                },
                onAddTask: addTask,
                onEditRule: { editingRule = settings.matrix.configuration(for: $0) },
                onUpdate: updateConfiguration(_:for:),
                onDropTask: proposeDrop,
                onMoveQuadrant: { source, target in settings.updateMatrix { $0.move(source, before: target) } },
                onOpenTask: openTask,
                listColor: listColor,
                anchorSink: anchorSink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.matrixBackdrop)
        // 浮层的坐标基准：锚点矩形与弹框位置都在这一个坐标系里算。
        .coordinateSpace(name: PlanningCoordinateSpace.name)
        .sheet(item: $editingRule) { value in
            MatrixRuleEditor(value: value, tasks: workspace.tasksInActiveLists, lists: workspace.availableListNames,
                             tags: workspace.tagNames, now: workspace.clock(), calendar: workspace.calendar) { updated in
                settings.updateMatrix { $0.update(updated) }
                editingRule = nil
            } onCancel: { editingRule = nil }
        }
        .overlay {
            PlanningWorkspaceChrome(workspace: workspace,
                                    anchor: anchorSink,
                                    request: $composerRequest,
                                    editingTaskID: $editingTaskID)
        }
    }

    /// 页头只有标题与页面设置：象限本身的开关（新建、显示已完成、展开折叠）挂在
    /// 每个象限自己的 hover 动作里，因为它们各管一个象限。
    private var pageHeader: some View {
        HStack(spacing: 0) {
            Text("四象限")
                .font(WFType.pageTitle)
                .foregroundStyle(WFColors.text)
            Spacer(minLength: 0)
            // 页头「…」只管一件事：整页的已完成任务显隐。
            // 撤销/重做、展开/折叠分组都不在这里——拖拽与规则编辑本身可以 ⌘Z，
            // 展开折叠是每个分组的局部动作（点分组标题）。
            BusinessMenu {
                Button(showCompleted ? "隐藏已完成" : "显示已完成") {
                    settings.updateMatrix { $0.showCompleted.toggle() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .fixedSize()
            .help("四象限设置")
        }
        .padding(.leading, WFSpace.relaxed)
        .padding(.top, WFSpace.cardInset)
        .padding(.trailing, WFSpace.md)
        .padding(.bottom, WFSpace.xs)
        .frame(height: WFMatrixMetrics.pageHeaderHeight, alignment: .bottom)
    }

    // MARK: - 交互

    /// 已完成开关走的是「固定 id 的分组」这条既有通道：象限自己不留第二份可见性
    /// 状态（对齐 Flutter `__toggle-completed__`）。
    private func toggleGroup(_ group: MatrixGroupViewModel) {
        if group.id == MatrixQuadrantViewModel.completedToggleID {
            settings.updateMatrix { $0.showCompleted.toggle() }
            return
        }
        if collapsedGroups.remove(group.id) == nil { collapsedGroups.insert(group.id) }
    }

    /// 打开新建卡。原版 `createTaskInMatrixQuadrant` 给卡的是象限默认优先级与
    /// `quadrant.defaultSchedule(today)`：Ⅰ/Ⅲ 落今天、Ⅱ 落下周同一天、Ⅳ 无日期；
    /// 卡上因此没有预置日期（显示「设置日期」），用户选的日期会覆盖这个 fallback。
    private func addTask(_ quadrant: MatrixQuadrant) {
        workspace.select(nil)
        let now = workspace.clock()
        let blank = Task(id: UUID(), title: "", list: .inbox, priority: .none, schedule: TaskSchedule(),
                         parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
        let proposal = MatrixDropPlanner.propose(task: blank, target: quadrant,
                                                 configuration: settings.matrix, now: now, calendar: workspace.calendar)
        let schedule = proposal.schedule ?? blank.schedule
        composerRequest = PlanningComposerRequest(fallback: schedule, preset: schedule,
            priority: proposal.priority ?? blank.priority, list: proposal.list, tags: proposal.tags ?? [],
            )
    }

    private func proposeDrop(_ id: UUID, _ target: MatrixQuadrant, _ before: UUID?) {
        guard let task = workspace.task(for: id) else { return }
        let source = settings.matrix.quadrant(for: task, now: workspace.clock(), calendar: workspace.calendar)
        if source == target {
            guard settings.matrix.configuration(for: target).sort == .manual else { return }
            guard id != before else { return }
            let groups = quadrants.first { $0.quadrant == target }?.groups ?? []
            guard let group = groups.first(where: { $0.tasks.contains { $0.id == id } }) else { return }
            let rows = group.tasks.map(\.id)
            if let before, !rows.contains(before) { return }
            var reordered = rows.filter { $0 != id }
            let position = before.flatMap { reordered.firstIndex(of: $0) } ?? reordered.count
            reordered.insert(id, at: position)
            guard reordered != rows else { return }
            settings.updateMatrix { configuration in
                guard let index = configuration.quadrants.firstIndex(where: { $0.quadrant == target }) else { return }
                let old = configuration.quadrants[index].manualOrder
                configuration.quadrants[index].manualOrder = old.filter { !rows.contains($0) } + reordered
            }
            return
        }
        // 跨象限拖拽直接落地：原来这里先弹一个「移入 XX / 优先级改为 YY」的确认框，
        // 拖一次要点两下。改为按规则算完直接提交；有冲突（`canCommit == false`）时
        // 不移动，保持原状——宁可不动，也不悄悄改半套属性。
        let proposal = MatrixDropPlanner.propose(task: task, target: target, configuration: settings.matrix,
                                                 now: workspace.clock(), calendar: workspace.calendar)
        guard proposal.canCommit else { return }
        _ = workspace.updateAttributes(proposal.taskID, priority: proposal.priority,
                                       schedule: proposal.schedule, list: proposal.list,
                                       tags: proposal.tags)
    }

    /// 改某个象限的分组 / 排序 / 顺序。
    private func updateConfiguration(_ mutate: @escaping (inout MatrixQuadrantConfiguration) -> Void,
                                     for quadrant: MatrixQuadrant) {
        settings.updateMatrix { configuration in
            guard let index = configuration.quadrants.firstIndex(where: { $0.quadrant == quadrant }) else { return }
            mutate(&configuration.quadrants[index])
        }
    }

    private func openTask(_ id: UUID) {
        guard editingTaskID == nil else { return }
        editingTaskID = id
        workspace.select(id)
    }

    private func listColor(_ name: String) -> Color {
        WFPlanningPalette.listColor(name: name, meta: workspace.listMeta(for: name))
    }
}

// MARK: - 棋盘

/// 固定的 2×2 棋盘。每个子格自己拥有滚动区，一个象限里的长列表不会把另外三个
/// 推下去。
struct MatrixBoardView: View {
    let quadrants: [MatrixQuadrantViewModel]
    let showCompleted: Bool
    @ObservedObject var workspace: TaskWorkspaceModel
    let isExpanded: (MatrixGroupViewModel) -> Bool
    let onToggleGroup: (MatrixGroupViewModel) -> Void
    let onExpandAll: (MatrixQuadrant) -> Void
    let onCollapseAll: (MatrixQuadrant) -> Void
    let onAddTask: (MatrixQuadrant) -> Void
    let onEditRule: (MatrixQuadrant) -> Void
    let onUpdate: (@escaping (inout MatrixQuadrantConfiguration) -> Void, MatrixQuadrant) -> Void
    let onDropTask: (UUID, MatrixQuadrant, UUID?) -> Void
    let onMoveQuadrant: (MatrixQuadrant, MatrixQuadrant) -> Void
    let onOpenTask: (UUID) -> Void
    let listColor: (String) -> Color
    let anchorSink: PlanningAnchorRef

    var body: some View {
        VStack(spacing: WFSpace.control) {
            row(Array(quadrants.prefix(2).map(\.quadrant)))
            row(Array(quadrants.dropFirst(2).prefix(2).map(\.quadrant)))
        }
        .padding(.leading, WFSpace.cardInset)
        .padding(.trailing, WFSpace.cardInset)
        .padding(.bottom, WFSpace.cardInset)
    }

    private func row(_ values: [MatrixQuadrant]) -> some View {
        HStack(spacing: WFSpace.control) {
            ForEach(values, id: \.self) { quadrant in
                if let model = quadrants.first(where: { $0.quadrant == quadrant }) {
                    MatrixQuadrantCard(
                        model: model,
                        showCompleted: showCompleted,
                        workspace: workspace,
                        isExpanded: isExpanded,
                        onToggleGroup: onToggleGroup,
                        onExpandAll: { onExpandAll(quadrant) },
                        onCollapseAll: { onCollapseAll(quadrant) },
                        onAddTask: { onAddTask(quadrant) },
                        onEditRule: { onEditRule(quadrant) },
                        onUpdate: { mutate in onUpdate(mutate, quadrant) },
                        onDropTask: { id, before in onDropTask(id, quadrant, before) },
                        onMoveQuadrant: { onMoveQuadrant($0, quadrant) },
                        onOpenTask: onOpenTask,
                        listColor: listColor,
                        anchorSink: anchorSink)
                } else {
                    Color.clear
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - 象限

/// 一个象限：彩点序号 + 同色标题，白底圆角细边；清单分组可折叠，任务行是
/// 勾选框 + 标题 + 右对齐元信息。拖动悬停时整卡染色并加亮描边。
struct MatrixQuadrantCard: View {
    let model: MatrixQuadrantViewModel
    let showCompleted: Bool
    @ObservedObject var workspace: TaskWorkspaceModel
    let isExpanded: (MatrixGroupViewModel) -> Bool
    let onToggleGroup: (MatrixGroupViewModel) -> Void
    let onExpandAll: () -> Void
    let onCollapseAll: () -> Void
    let onAddTask: () -> Void
    let onEditRule: () -> Void
    /// 改这个象限的分组 / 排序 / 顺序。
    let onUpdate: (@escaping (inout MatrixQuadrantConfiguration) -> Void) -> Void
    let onDropTask: (UUID, UUID?) -> Void
    let onMoveQuadrant: (MatrixQuadrant) -> Void
    let onOpenTask: (UUID) -> Void
    let listColor: (String) -> Color
    let anchorSink: PlanningAnchorRef

    @State private var hovering = false
    @State private var dropping = false
    /// 这一张卡自己的锚：卡上的新建按钮/菜单弹的是贴着这张卡的浮层。
    @State private var anchor = PlanningAnchorRef()
    /// 「+」按钮自己的锚。用它而不是整张卡，弹层才会贴着按钮，而不是跑到卡片左上角。
    @State private var addButtonAnchor = PlanningAnchorRef()
    /// 「…」菜单是否展开。展开期间要压住 hover 判定：
    /// 菜单在独立浮层里，鼠标一移过去卡片的 `hovering` 就变 false，
    /// 原来会让按钮透明+禁用，菜单跟着消失，根本点不中。
    @State private var menuOpen = false

    private var style: MatrixQuadrant { model.quadrant }

    private var grouping: MatrixGrouping { model.configuration?.grouping ?? .list }
    private var sort: MatrixSort { model.configuration?.sort ?? .manual }
    private var direction: MatrixOrderDirection { model.configuration?.direction ?? .ascending }

    /// 子菜单里的单选行：左侧名称、右侧当前值，展开后逐项打勾。
    private func pickerMenu<T: Hashable>(_ title: String, selection: T, options: [T],
                                          current: String,
                                          apply: @escaping (T) -> Void) -> some View {
        BusinessMenu(title: title) {
            ForEach(options, id: \.self) { option in
                Button {
                    apply(option)
                } label: {
                    if option == selection {
                        Label(label(of: option, title: title), systemImage: "checkmark")
                    } else {
                        Text(label(of: option, title: title))
                    }
                }
            }
        } label: {
            HStack(spacing: WFSpace.sm) {
                Text(title)
                Spacer(minLength: 8)
                Text(current).foregroundStyle(WFColors.secondaryText)
            }
        }
    }

    private func label(of option: Any, title: String) -> String {
        switch option {
        case let value as MatrixGrouping: return value.title
        case let value as MatrixSort: return value.title
        case let value as MatrixOrderDirection: return value.title
        default: return "\(option)"
        }
    }
    private var color: Color { WFPlanningPalette.quadrant[model.configuration?.colorIndex ?? style.rawValue] }
    private var title: String { model.configuration?.title ?? style.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: WFSpace.inline)
            if model.groups.isEmpty {
                Text("把任务拖到这里")
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.groups) { group in
                            MatrixGroupView(
                                model: group,
                                quadrantColor: color,
                                workspace: workspace,
                                expanded: isExpanded(group),
                                onToggle: { onToggleGroup(group) },
                                onOpenTask: onOpenTask,
                                onReorder: model.configuration?.sort == .manual ? onDropTask : nil,
                                listColor: listColor,
                                anchorSink: anchorSink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, WFMatrixMetrics.quadrantPadding.top)
        .padding(.leading, WFMatrixMetrics.quadrantPadding.leading)
        .padding(.bottom, WFMatrixMetrics.quadrantPadding.bottom)
        .padding(.trailing, WFMatrixMetrics.quadrantPadding.trailing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(dropping ? color.opacity(0.07) : WFColors.content,
                    in: RoundedRectangle(cornerRadius: WFMatrixMetrics.quadrantRadius))
        .overlay {
            RoundedRectangle(cornerRadius: WFMatrixMetrics.quadrantRadius)
                .stroke(dropping ? color.opacity(0.60) : WFColors.border.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: WFMatrixMetrics.quadrantRadius))
        .onHover { hovering = $0 }
        .background(PlanningAnchorProbe(ref: anchor))
        .dropDestination(for: String.self) { values, _ in
            NativeAcceptanceInteractionTrace.record("matrix.drop", ["count": values.count, "quadrant": style.rawValue])
            guard let value = values.first else { return false }
            if value.hasPrefix("matrix-quadrant:"), let number = Int(value.dropFirst("matrix-quadrant:".count)),
               let quadrant = MatrixQuadrant(rawValue: number) { onMoveQuadrant(quadrant); return true }
            guard let id = UUID(uuidString: value) else { return false }
            onDropTask(id, nil)
            return true
        } isTargeted: {
            dropping = $0
            NativeAcceptanceInteractionTrace.record("matrix.target", ["targeted": $0, "quadrant": style.rawValue])
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(style.numeral)
                .font(WFType.caption.weight(.semibold))
                .foregroundStyle(WFPlanningPalette.markerForeground)
                .frame(width: WFMatrixMetrics.quadrantHeaderMarkerSize,
                       height: WFMatrixMetrics.quadrantHeaderMarkerSize)
                .background(color, in: Circle())
            Spacer().frame(width: WFSpace.sm)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            hoverAction(icon: "plus", tooltip: "在\(style.title)中新建任务",
                        visible: hovering,
                        probe: addButtonAnchor,
                        action: {
                            anchorSink.rect = addButtonAnchor.rect ?? anchor.rect
                            onAddTask()
                        })
            quadrantMenu
        }
        .draggable("matrix-quadrant:\(style.rawValue)")
    }

    /// 象限自己的动作只在指针停上来时出现；离开时不接收点击，也不被读屏念出来。
    @ViewBuilder
    private func hoverAction(icon: String, tooltip: String, visible: Bool,
                             probe: PlanningAnchorRef? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: WFMatrixMetrics.quadrantActionIconSize))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: WFMatrixMetrics.quadrantActionSize,
                       height: WFMatrixMetrics.quadrantActionSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .background {
            if let probe { PlanningAnchorProbe(ref: probe) }
        }
        .disabled(!visible)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .help(tooltip)
    }

    /// 象限菜单：新建、显示/隐藏已完成、展开全部、折叠全部。
    /// 已完成是页面的偏好，所以那一项回传给页面，象限自己不留第二份状态。
    private var quadrantMenu: some View {
        // 象限自己的菜单：编辑规则 + 排序（分组 / 排序依据 / 顺序方向，三级）。
        // 「新建任务 / 显示已完成 / 展开折叠全部」是整页级动作，统一放在页头的「…」里。
        BusinessMenu(isPresented: $menuOpen) {
            Button("编辑") { onEditRule() }
            Divider()
            BusinessMenu(title: "排序") {
                pickerMenu("分组", selection: grouping, options: MatrixGrouping.allCases,
                           current: grouping.title) { value in
                    onUpdate { $0.grouping = value }
                }
                pickerMenu("排序", selection: sort, options: MatrixSort.allCases,
                           current: sort.title) { value in
                    onUpdate { $0.sort = value }
                }
                pickerMenu("顺序", selection: direction, options: MatrixOrderDirection.allCases,
                           current: direction.title) { value in
                    onUpdate { $0.direction = value }
                }
            } label: {
                Label("排序", systemImage: "arrow.up.arrow.down")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: WFMatrixMetrics.quadrantActionIconSize))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: WFMatrixMetrics.quadrantActionSize,
                       height: WFMatrixMetrics.quadrantActionSize)
                .contentShape(Rectangle())
        }
        .fixedSize()
        // 菜单展开时保持可见可点，否则鼠标一移向菜单它就消失。
        .opacity(hovering || menuOpen ? 1 : 0)
        .disabled(!hovering && !menuOpen)
        .allowsHitTesting(hovering || menuOpen)
        .accessibilityHidden(!hovering && !menuOpen)
        .help("\(style.title)更多操作")
    }
}

/// 象限里的一个清单分组，或该象限的「已完成」分组。
struct MatrixGroupView: View {
    let model: MatrixGroupViewModel
    let quadrantColor: Color
    @ObservedObject var workspace: TaskWorkspaceModel
    let expanded: Bool
    let onToggle: () -> Void
    let onOpenTask: (UUID) -> Void
    var onReorder: ((UUID, UUID?) -> Void)? = nil
    let listColor: (String) -> Color
    let anchorSink: PlanningAnchorRef

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 0) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 15))
                        .foregroundStyle(WFColors.tertiaryText)
                    Spacer().frame(width: WFSpace.tight)
                    Text(model.title)
                        .font(WFType.sectionSemibold)
                        .foregroundStyle(WFColors.text)
                    Spacer().frame(width: WFSpace.inline)
                    Text(String(model.count))
                        .font(WFType.listMeta)
                        .foregroundStyle(WFColors.tertiaryText)
                    Spacer(minLength: 0)
                }
                .frame(height: WFMatrixMetrics.groupRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(model.title) \(expanded ? "收起" : "展开")")
            if expanded {
                ForEach(model.tasks) { row in
                    MatrixTaskRowView(
                        model: row,
                        quadrantColor: quadrantColor,
                        workspace: workspace,
                        listColor: listColor,
                        onOpen: { onOpenTask(row.task.id) },
                        onReorder: onReorder,
                        anchorSink: anchorSink)
                }
            }
        }
    }
}

// MARK: - 任务行

struct MatrixTaskRowLayout: Equatable {
    let showsSecondaryIcons: Bool
    let listNameWidth: Double
    init(width: Double) {
        showsSecondaryIcons = width >= 480
        listNameWidth = width < 280 ? 0 : min(showsSecondaryIcons ? 96 : 64, width * 0.16)
    }
}

/// 一张扁平的四象限行。象限本身已经用位置表达了重要性，所以行不再额外挂优先级
/// 色条或卡片边框。
struct MatrixTaskRowView: View {
    let model: MatrixTaskViewModel
    let quadrantColor: Color
    @ObservedObject var workspace: TaskWorkspaceModel
    let listColor: (String) -> Color
    let onOpen: () -> Void
    var onReorder: ((UUID, UUID?) -> Void)? = nil
    let anchorSink: PlanningAnchorRef

    @State private var hovering = false
    @State private var showDatePopover = false
    @State private var rowWidth: CGFloat = 0
    /// 这一行自己的锚：编辑器贴着被点的这一行弹出来。
    @State private var anchor = PlanningAnchorRef()

    private var task: Task { model.task }
    private var completed: Bool { task.status == .completed }
    private var metadataLayout: MatrixTaskRowLayout { MatrixTaskRowLayout(width: Double(rowWidth)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                completionBox
                Spacer().frame(width: WFSpace.compactInset)
                Button {
                    anchorSink.rect = anchor.rect
                    onOpen()
                } label: {
                    Text(task.title.isEmpty ? "无标题" : task.title)
                        .font(WFType.listTitle)
                        .foregroundStyle(completed ? WFColors.tertiaryText : WFColors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.vertical, WFSpace.tight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                Spacer().frame(width: WFSpace.control)
                metadata
                    .layoutPriority(2)
            }
            .padding(.vertical, WFSpace.inline)
            // 行分隔线：左端收进一截，让行读成一组而不是一张表。
            Rectangle()
                .fill(WFColors.border.opacity(0.65))
                .frame(height: WFMatrixMetrics.taskRowDividerHeight)
                .padding(.leading, WFSpace.nestedContentIndent)
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { rowWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in rowWidth = width }
            }
        }
        .background(hovering ? WFColors.listRowHover : .clear,
                    in: RoundedRectangle(cornerRadius: hovering ? 12 : 0))
        .onHover { hovering = $0 }
        .schedulePopover(isPresented: $showDatePopover) {
            if let current = workspace.task(for: task.id) {
                TaskDatePopoverV2(task: current, workspace: workspace) { showDatePopover = false }
            }
        }
        .draggable(task.id.uuidString) {
            Text(task.title.isEmpty ? "无标题" : task.title)
                .font(WFType.listTitle)
                .foregroundStyle(WFColors.text)
                .lineLimit(1)
                .padding(.horizontal, WFSpace.md)
                .padding(.vertical, WFSpace.cardInset)
                .frame(width: WFMatrixMetrics.taskRowDragPreviewWidth, alignment: .leading)
                .background(WFColors.content,
                            in: RoundedRectangle(cornerRadius: WFMatrixMetrics.taskRowDragPreviewRadius))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                .onAppear { NativeAcceptanceInteractionTrace.record("matrix.drag-preview") }
        }
        .dropDestination(for: String.self) { values, _ in
            guard let onReorder, let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            onReorder(id, task.id)
            return true
        }
        .help(([task.title, model.listName] + metadataDescriptions).joined(separator: " · "))
        .background(PlanningAnchorProbe(ref: anchor))
    }

    /// 与任务行、日历条同一个勾选框，边长按矩阵行的槽位。未完成时描边取象限色
    /// ——矩阵用颜色区分象限，勾选框是行上唯一能带上这个颜色的地方；完成后改为
    /// 完成态的浅填充，勾是从内容色切出来的。点它完成或恢复同一个任务。
    private var completionBox: some View {
        Button {
            _ = workspace.changeStatus(task)
        } label: {
            TaskCompletionBox(
                size: WFMatrixMetrics.taskRowCheckboxSize,
                completed: completed,
                openColor: completed ? nil : quadrantColor)
            .frame(width: WFMatrixMetrics.taskRowCheckboxHitTarget,
                   height: WFMatrixMetrics.taskRowCheckboxHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(completed ? "恢复任务" : "完成任务")
        .accessibilityLabel(completed ? "恢复：\(task.title)" : "完成：\(task.title)")
    }

    /// 行尾元信息：清单名、重复、备注、子任务、提醒，最后是日期标签。
    /// 日期是唯一有颜色的文字：过期红、其余强调色；已完成的行整条退墨。
    private var metadata: some View {
        HStack(spacing: WFSpace.inline) {
            if metadataLayout.listNameWidth > 0 {
                Text(model.listName)
                    .font(WFType.listMeta)
                    .foregroundStyle(WFColors.tertiaryText)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: CGFloat(metadataLayout.listNameWidth), alignment: .trailing)
                    .help(model.listName)
            }
            if metadataLayout.showsSecondaryIcons {
                if model.recurring { metadataIcon("repeat", "重复任务") }
                if model.hasNote { metadataIcon("text.alignleft", "有备注") }
                if model.hasSubtasks { metadataIcon("list.bullet.indent", "有子任务") }
                if model.hasReminder { metadataIcon("bell", "有提醒") }
            }
            if let label = model.dateLabel {
                Button {
                    showDatePopover = true
                } label: {
                    Text(label)
                        .font(WFType.listMeta)
                        .foregroundStyle(dateColor)
                        .fixedSize(horizontal: true, vertical: false)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("修改安排日期")
                .scheduleTrigger()
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var metadataDescriptions: [String] {
        [(model.recurring, "重复任务"), (model.hasNote, "有备注"),
         (model.hasSubtasks, "有子任务"), (model.hasReminder, "有提醒")].compactMap { $0.0 ? $0.1 : nil }
    }

    private var dateColor: Color {
        if completed { return WFColors.tertiaryText }
        return model.overdue ? WFColors.danger : WFColors.accent
    }

    private func metadataIcon(_ symbol: String, _ label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(WFColors.tertiaryText)
            .accessibilityLabel(label)
    }
}
