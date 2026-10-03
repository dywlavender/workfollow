import SwiftUI

struct TaskInspectorHeader<Schedule: View, Priority: View>: View {
    let task: Task
    let showBack: Bool
    let onBack: () -> Void
    let onComplete: () -> Void
    let onRepeat: () -> Void
    @ViewBuilder let schedule: () -> Schedule
    @ViewBuilder let priority: () -> Priority

    static func showsRepeat(_ task: Task) -> Bool {
        task.recurrence != .never || task.recurrenceRule != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            if showBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: WFMetrics.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("返回列表").accessibilityLabel("返回列表")
                .inspectorRenderAnchor(.back)
            }
            Button(action: onComplete) {
                TaskCompletionBox(size: TaskInspectorMetrics.completionSize,
                                  completed: task.isClosed)
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
                            .inspectorRenderAnchor(.repeatControl)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: WFMetrics.controlHeight)
            .inspectorRenderAnchor(.scheduleViewport)
            priority().fixedSize()
                .inspectorRenderAnchor(.priority)
        }
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(height: TaskInspectorMetrics.headerHeight)
        .inspectorRenderAnchor(.header)
    }

    private func propertyButton(_ title: String, symbol: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(WFColors.accent)
                .frame(width: 24, height: WFMetrics.controlHeight)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
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
