import SwiftUI
import UniformTypeIdentifiers

/// One drop destination per list, not one retained destination per row.
@MainActor
final class TaskDropFeedback: ObservableObject {
    struct Target: Equatable {
        let rowID: UUID
        let placement: TaskDropPlacement
    }
    @Published private(set) var target: Target?
    private var releaseTimer: Timer?
    private var endMonitor: Any?

    func update(rowID: UUID, placement: TaskDropPlacement) {
        let next = Target(rowID: rowID, placement: placement)
        if target != next { target = next }
        guard releaseTimer == nil else { return }
        endMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseUp || event.keyCode == 53 { self?.clear() }
            }
            return event
        }
        // Drag tracking can omit dropExited when cancelled or released outside
        // the list. Watch only while feedback exists, including tracking mode.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearIfReleased(pressedButtons: NSEvent.pressedMouseButtons)
            }
        }
        releaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func exit(rowID: UUID) {
        // A late exit from A must not erase the newer destination B.
        if target?.rowID == rowID { clear() }
    }

    func clear() {
        target = nil
        releaseTimer?.invalidate()
        releaseTimer = nil
        if let endMonitor { NSEvent.removeMonitor(endMonitor) }
        endMonitor = nil
    }

    func clearIfReleased(pressedButtons: Int) {
        if pressedButtons & 1 == 0 { clear() }
    }

    deinit {
        releaseTimer?.invalidate()
        if let endMonitor { NSEvent.removeMonitor(endMonitor) }
    }
}

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
    let feedback: TaskDropFeedback

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

    func dropEntered(info: DropInfo) { feedback.update(rowID: targetID, placement: destination(at: info.location)) }
    func dropExited(info: DropInfo) { feedback.exit(rowID: targetID) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        feedback.update(rowID: targetID, placement: destination(at: info.location))
        return Self.moveProposal
    }
    static var moveProposal: DropProposal { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        let destination = destination(at: info.location)
        feedback.clear()
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
