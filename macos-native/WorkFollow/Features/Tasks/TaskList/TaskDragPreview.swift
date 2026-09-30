import SwiftUI

struct TaskDragPreview: View {
    let title: String

    var body: some View {
        Text(title.isEmpty ? "无标题" : title)
            .font(WFType.listTitle)
            .foregroundStyle(WFColors.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(width: TaskListMetrics.dragPreviewWidth)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

struct TaskDropMarker: View {
    var body: some View {
        Capsule()
            .fill(WFColors.accent)
            .frame(height: TaskListMetrics.dragMarkerHeight)
            .padding(.horizontal, TaskListMetrics.rowHorizontalPadding)
    }
}
