import AppKit
import SwiftUI

/// Only the drag handle observes pointer changes; the task's controls do not.
@MainActor
final class TaskRowPointerState: ObservableObject {
    @Published private(set) var inside = false
    func update(_ value: Bool) {
        if inside != value { inside = value }
    }
}

/// Native hover view used by the task row; the shared implementation lives in
/// DesignSystem/RowHoverBackground.swift.
typealias TaskRowHoverView = RowHoverView

struct TaskRowReorderHandle: View {
    let taskID: UUID
    let title: String
    let selected: Bool
    @ObservedObject var pointer: TaskRowPointerState
    @State private var hovering = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(WFColors.secondaryText)
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
            .opacity(pointer.inside || hovering || selected ? 1 : 0)
            .onHover { hovering = $0 }
            .hoverTip("拖动调整任务顺序")
            .accessibilityLabel("拖动调整任务顺序")
            .draggable(taskID.uuidString) { TaskDragPreview(title: title) }
            .modifier(TaskReorderDragPolicy())
            .transaction { $0.animation = nil }
    }
}
