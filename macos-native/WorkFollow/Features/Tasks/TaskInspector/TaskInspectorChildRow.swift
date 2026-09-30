import SwiftUI

/// Neutral inspector child surface. Completion and metadata keep independent
/// actions; the open button behind the content also covers row padding/blank space.
struct TaskInspectorChildRow<Title: View, Metadata: View>: View {
    let child: Task
    let onComplete: () -> Void
    let onOpen: () -> Void
    @ViewBuilder let title: () -> Title
    @ViewBuilder let metadata: () -> Metadata
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onComplete) {
                TaskCompletionBox(size: TaskInspectorMetrics.childCompletionSize,
                                  completed: child.isClosed)
                    .overlay {
                        if child.isAbandoned {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WFColors.secondaryText)
                        }
                    }
                    .frame(width: 24, height: TaskInspectorMetrics.childRowMinHeight)
                    .contentShape(Rectangle())
            }
            .help(child.isClosed ? "恢复任务" : "完成任务")
            .accessibilityLabel((child.isClosed ? "恢复子任务：" : "完成子任务：") + child.title)
            title().frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(child.isClosed ? WFColors.tertiaryText : WFColors.text)
            if child.schedule.dueAt != nil { metadata() }
        }
        .buttonStyle(.plain).font(WFType.listTitleMedium)
        .padding(.horizontal, TaskInspectorMetrics.childRowHorizontalPadding)
        .frame(minHeight: TaskInspectorMetrics.childRowMinHeight)
        .background {
            Button(action: onOpen) {
                RoundedRectangle(cornerRadius: TaskInspectorMetrics.childRowRadius)
                    .fill(hovering ? Color.primary.opacity(0.07) : WFColors.hover)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开子任务：\(child.title.isEmpty ? "未命名子任务" : child.title)")
        }
        .onHover { hovering = $0 }
        .inspectorRenderAnchor(.childRow(child.id))
    }
}
