import SwiftUI
import UniformTypeIdentifiers

/// Reordering is a move, never a copy/export of the internal task identifier.
struct TaskReorderDragPolicy: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.dragConfiguration(DragConfiguration(
                operationsWithinApp: .init(allowCopy: false, allowMove: true),
                operationsOutsideApp: .init(allowCopy: false)))
        } else {
            content
        }
    }
}

struct TaskReorderDropDelegate: DropDelegate {
    let workspace: TaskWorkspaceModel
    let targetID: UUID
    let depth: Int
    let rowHeight: CGFloat
    @Binding var placement: TaskDropPlacement?

    private func destination(at point: CGPoint) -> TaskDropPlacement {
        Self.destination(at: point, rowHeight: rowHeight, depth: depth,
                         targetID: targetID, parentID: workspace.task(for: targetID)?.parentID)
    }

    static func destination(at point: CGPoint, rowHeight: CGFloat, depth: Int,
                            targetID: UUID, parentID: UUID?) -> TaskDropPlacement {
        if depth > 0, point.x < TaskListMetrics.titleLeading, let parentID {
            return point.y < rowHeight * 0.25 ? .rootBefore(parentID) : .rootAfter(parentID)
        }
        if point.y < rowHeight * 0.25 { return .before(targetID) }
        if point.y > rowHeight * 0.75 { return .after(targetID) }
        return depth == 0 ? .childOf(targetID) : .after(targetID)
    }

    func dropEntered(info: DropInfo) { placement = destination(at: info.location) }
    func dropExited(info: DropInfo) { placement = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        placement = destination(at: info.location)
        return Self.moveProposal
    }
    static var moveProposal: DropProposal { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        let destination = destination(at: info.location)
        placement = nil
        guard let provider = info.itemProviders(for: [UTType.utf8PlainText]).first,
              provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let payload = value as? String else { return }
            _Concurrency.Task { @MainActor in
                _ = Self.apply(payload: payload, placement: destination, workspace: workspace)
            }
        }
        return true
    }

    @MainActor
    @discardableResult
    static func apply(payload: String, before targetID: UUID, workspace: TaskWorkspaceModel) -> Bool {
        apply(payload: payload, placement: .before(targetID), workspace: workspace)
    }

    @MainActor
    @discardableResult
    static func apply(payload: String, placement: TaskDropPlacement, workspace: TaskWorkspaceModel) -> Bool {
        guard let id = UUID(uuidString: payload) else { return false }
        return workspace.moveTask(id, to: placement).taskID != nil
    }
}

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
