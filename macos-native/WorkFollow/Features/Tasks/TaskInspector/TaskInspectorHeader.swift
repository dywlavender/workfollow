import SwiftUI

enum TaskInspectorHeaderPanel: Hashable { case kind, info }

struct TaskInspectorHeader<Schedule: View, Priority: View>: View {
    let task: Task
    let showBack: Bool
    let onBack: () -> Void
    let onComplete: () -> Void
    let onRepeat: () -> Void
    /// 在独立窗口打开（TI2-17）：宿主不传就不渲染入口。
    var onDetach: (() -> Void)? = nil
    /// 笔记信息（TI2-15）：只在宿主给出回调时渲染（有正文的任务）。
    var onInfo: (() -> Void)? = nil
    /// 任务形态按钮（TI2-05b）：滴答标题 cell 的 kindButton。
    var onKind: (() -> Void)? = nil
    var kindSymbol: String = "text.alignleft"
    @ViewBuilder let schedule: () -> Schedule
    @ViewBuilder let priority: () -> Priority

    static func showsRepeat(_ task: Task) -> Bool {
        task.recurrence != .never || task.recurrenceRule != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            if showBack {
                AppKitIconButton(symbol: "chevron.left", pointSize: 14,
                                 tint: .inspectorPrimary, accessibilityLabel: "返回列表",
                                 action: onBack)
                    .frame(width: 24, height: WFMetrics.controlHeight)
                    .inspectorRenderAnchor(.back)
            }
            Button(action: onComplete) {
                AppKitCompletionBox(size: TaskInspectorMetrics.completionSize,
                                    completed: task.isClosed)
                    // 显式固定墨迹尺寸：AppKit 视图的布局尺寸由这里决定，
                    // 锚点才能测到 15×15 而不是外层 24×34 的命中区。
                    .frame(width: TaskInspectorMetrics.completionSize,
                           height: TaskInspectorMetrics.completionSize)
                    .overlay {
                        if task.isAbandoned {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WFColors.secondaryText)
                        }
                    }
                    // 可见墨迹（15pt 方框）单独打锚点：契约测试断言"渲染出来的框"，
                    // 而不是只断言 `completionSize` 常量。
                    .inspectorRenderAnchor(.completionInk)
                    .frame(width: 24, height: WFMetrics.controlHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isClosed ? "恢复任务" : "完成任务")
            .accessibilityLabel(task.isClosed ? "恢复任务" : "完成任务")
            .inspectorRenderAnchor(.completion)
            Rectangle().fill(WFColors.border)
                .frame(width: TaskInspectorMetrics.headerDividerWidth,
                       height: TaskInspectorMetrics.headerDividerHeight)
                .accessibilityHidden(true)
                .inspectorRenderAnchor(.divider)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    schedule().fixedSize(horizontal: true, vertical: false)
                        .inspectorRenderAnchor(.schedule)
                    if Self.showsRepeat(task) {
                        propertyButton("重复", symbol: "repeat", action: onRepeat)
                            .scheduleTrigger(.recurrence)
                            .inspectorRenderAnchor(.repeatControl)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: WFMetrics.controlHeight)
            .inspectorRenderAnchor(.scheduleViewport)
            if let onKind {
                AppKitIconButton(symbol: kindSymbol, pointSize: 13,
                                 tint: .inspectorSecondary, accessibilityLabel: "任务类型",
                                 action: onKind)
                    .frame(width: 24, height: WFMetrics.controlHeight)
                    .help("任务类型")
                    .propertyPanelTrigger(TaskInspectorHeaderPanel.kind)
                    .inspectorRenderAnchor(.kind)
            }
            if let onInfo {
                AppKitIconButton(symbol: "info.circle", pointSize: 13,
                                 tint: .inspectorSecondary, accessibilityLabel: "笔记信息",
                                 action: onInfo)
                    .frame(width: 24, height: WFMetrics.controlHeight)
                    .help("笔记信息")
                    .propertyPanelTrigger(TaskInspectorHeaderPanel.info)
                    .inspectorRenderAnchor(.noteInfo)
            }
            if let onDetach {
                AppKitIconButton(symbol: "arrow.up.forward.app", pointSize: 13,
                                 tint: .inspectorSecondary, accessibilityLabel: "在独立窗口打开",
                                 action: onDetach)
                    .frame(width: 24, height: WFMetrics.controlHeight)
                    .help("在独立窗口打开")
                    .inspectorRenderAnchor(.detach)
            }
            priority().fixedSize()
                .inspectorRenderAnchor(.priority)
        }
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(height: TaskInspectorMetrics.headerHeight)
        .inspectorRenderAnchor(.header)
    }

    private func propertyButton(_ title: String, symbol: String,
                                action: @escaping () -> Void) -> some View {
        AppKitIconButton(symbol: symbol, pointSize: 14,
                         tint: NSColor(WFColors.accent), accessibilityLabel: title,
                         action: action)
            .frame(width: 24, height: WFMetrics.controlHeight)
    }
}

struct TaskParentBreadcrumbView: View {
    let title: String
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 4) {
                Text(title.isEmpty ? "无标题" : title).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 9))
                Spacer(minLength: 0)
            }
            .font(WFType.control).foregroundStyle(WFColors.secondaryText)
            .frame(height: TaskInspectorMetrics.breadcrumbHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("返回父任务")
        .accessibilityLabel("父任务：\(title.isEmpty ? "无标题" : title)")
        .inspectorRenderAnchor(.breadcrumb)
    }
}
