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

    /// 已完成的任务默认在棋盘里，与原版参考图一致。可选的开关放在页面菜单里，
    /// 不占页头。
    @State private var showCompleted = true
    /// 折叠的分组 id。按 id 记：两个象限里可能有同名清单。
    @State private var collapsedGroups: Set<String> = []
    @State private var editingTaskID: UUID?
    /// 正在开着的新建卡；nil 表示没有。
    @State private var composerRequest: PlanningComposerRequest?
    /// 浮层的锚：点象限加号/菜单或任务行时把宿主视图写进来。
    @State private var anchorSink = PlanningAnchorRef()

    private var quadrants: [MatrixQuadrantViewModel] {
        MatrixProjection.project(
            tasks: workspace.allTasks,
            now: workspace.clock(),
            listOrder: workspace.orderedListNames,
            includeCompleted: showCompleted,
            calendar: workspace.calendar,
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
                onOpenTask: openTask,
                listColor: listColor,
                anchorSink: anchorSink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.matrixBackdrop)
        // 浮层的坐标基准：锚点矩形与弹框位置都在这一个坐标系里算。
        .coordinateSpace(name: PlanningCoordinateSpace.name)
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
            Menu {
                Button {
                    showCompleted.toggle()
                } label: {
                    if showCompleted {
                        Label("显示已完成任务", systemImage: "checkmark")
                    } else {
                        Text("显示已完成任务")
                    }
                }
                Divider()
                Button("展开全部分组") { collapsedGroups.removeAll() }
                Button("折叠全部分组") {
                    collapsedGroups.formUnion(quadrants.flatMap { $0.groups.map(\.id) })
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
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
            showCompleted.toggle()
            return
        }
        if collapsedGroups.remove(group.id) == nil { collapsedGroups.insert(group.id) }
    }

    /// 打开新建卡。原版 `createTaskInMatrixQuadrant` 给卡的是象限默认优先级与
    /// `quadrant.defaultSchedule(today)`：Ⅰ/Ⅲ 落今天、Ⅱ 落下周同一天、Ⅳ 无日期；
    /// 卡上因此没有预置日期（显示「设置日期」），用户选的日期会覆盖这个 fallback。
    private func addTask(_ quadrant: MatrixQuadrant) {
        workspace.select(nil)
        let fallback: TaskSchedule
        if let offset = quadrant.defaultScheduleOffset {
            fallback = TaskSchedule(dueAt: workspace.dateFromToday(offset))
        } else {
            fallback = TaskSchedule()
        }
        composerRequest = PlanningComposerRequest(fallback: fallback,
                                                  preset: nil,
                                                  priority: quadrant.defaultPriority)
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
    let onOpenTask: (UUID) -> Void
    let listColor: (String) -> Color
    let anchorSink: PlanningAnchorRef

    var body: some View {
        VStack(spacing: WFSpace.control) {
            row([.doNow, .schedule])
            row([.delegate, .later])
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
    let onOpenTask: (UUID) -> Void
    let listColor: (String) -> Color
    let anchorSink: PlanningAnchorRef

    @State private var hovering = false
    @State private var dropping = false
    /// 这一张卡自己的锚：卡上的新建按钮/菜单弹的是贴着这张卡的浮层。
    @State private var anchor = PlanningAnchorRef()

    private var style: MatrixQuadrant { model.quadrant }
    private var color: Color { WFPlanningPalette.quadrant[style.rawValue] }

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
            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            _ = workspace.moveTaskToMatrix(id, style)
            return true
        } isTargeted: { dropping = $0 }
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
            Text(style.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            hoverAction(icon: "plus", tooltip: "在\(style.title)中新建任务",
                        visible: hovering,
                        action: {
                            anchorSink.rect = anchor.rect
                            onAddTask()
                        })
            quadrantMenu
        }
    }

    /// 象限自己的动作只在指针停上来时出现；离开时不接收点击，也不被读屏念出来。
    @ViewBuilder
    private func hoverAction(icon: String, tooltip: String, visible: Bool,
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
        .disabled(!visible)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .help(tooltip)
    }

    /// 象限菜单：新建、显示/隐藏已完成、展开全部、折叠全部。
    /// 已完成是页面的偏好，所以那一项回传给页面，象限自己不留第二份状态。
    private var quadrantMenu: some View {
        Menu {
            Button("新建任务") {
                anchorSink.rect = anchor.rect
                onAddTask()
            }
            Button(showCompleted ? "隐藏已完成任务" : "显示已完成任务") {
                onToggleGroup(MatrixGroupViewModel(id: MatrixQuadrantViewModel.completedToggleID,
                                                   title: "", count: 0,
                                                   completedGroup: true, tasks: []))
            }
            Divider()
            Button("展开全部分组") { onExpandAll() }
            Button("折叠全部分组") { onCollapseAll() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: WFMatrixMetrics.quadrantActionIconSize))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: WFMatrixMetrics.quadrantActionSize,
                       height: WFMatrixMetrics.quadrantActionSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(hovering ? 1 : 0)
        .disabled(!hovering)
        .allowsHitTesting(hovering)
        .accessibilityHidden(!hovering)
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
                        anchorSink: anchorSink)
                }
            }
        }
    }
}

// MARK: - 任务行

/// 一张扁平的四象限行。象限本身已经用位置表达了重要性，所以行不再额外挂优先级
/// 色条或卡片边框。
struct MatrixTaskRowView: View {
    let model: MatrixTaskViewModel
    let quadrantColor: Color
    @ObservedObject var workspace: TaskWorkspaceModel
    let listColor: (String) -> Color
    let onOpen: () -> Void
    let anchorSink: PlanningAnchorRef

    @State private var hovering = false
    @State private var showDatePopover = false
    /// 这一行自己的锚：编辑器贴着被点的这一行弹出来。
    @State private var anchor = PlanningAnchorRef()

    private var task: Task { model.task }
    private var completed: Bool { task.status == .completed }

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
                Spacer().frame(width: WFSpace.control)
                metadata
            }
            .padding(.vertical, WFSpace.inline)
            // 行分隔线：左端收进一截，让行读成一组而不是一张表。
            Rectangle()
                .fill(WFColors.border.opacity(0.65))
                .frame(height: WFMatrixMetrics.taskRowDividerHeight)
                .padding(.leading, WFSpace.nestedContentIndent)
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
        }
        .help(task.title)
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
            Text(model.listName)
                .font(WFType.listMeta)
                .foregroundStyle(WFColors.tertiaryText)
                .lineLimit(1)
            if model.recurring { metadataIcon("repeat", "重复任务") }
            if model.hasNote { metadataIcon("text.alignleft", "有备注") }
            if model.hasSubtasks { metadataIcon("list.bullet.indent", "有子任务") }
            if model.hasReminder { metadataIcon("bell", "有提醒") }
            if let label = model.dateLabel {
                Button {
                    showDatePopover = true
                } label: {
                    Text(label)
                        .font(WFType.listMeta)
                        .foregroundStyle(dateColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("修改安排日期")
                .scheduleTrigger()
            }
        }
        .lineLimit(1)
        .fixedSize()
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
