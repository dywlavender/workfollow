import SwiftUI
import UniformTypeIdentifiers

/// Match the explicit item-provider transport already used by task reordering.
/// Copy is a pasteboard operation only; the receiver reschedules the original.
struct TaskTimelineDropDelegate: DropDelegate {
    let allowsDrop: Bool
    let onTargeted: (Bool) -> Void
    let onDrop: @MainActor (UUID, CGPoint) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        allowsDrop && info.hasItemsConforming(to: [UTType.utf8PlainText])
    }

    func dropEntered(info: DropInfo) {
        onTargeted(validateDrop(info: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        validateDrop(info: info) ? DropProposal(operation: .copy) : DropProposal(operation: .cancel)
    }

    func dropExited(info: DropInfo) { onTargeted(false) }

    func performDrop(info: DropInfo) -> Bool {
        onTargeted(false)
        guard allowsDrop, let provider = info.itemProviders(for: [UTType.utf8PlainText]).first else { return false }
        NativeAcceptanceInteractionTrace.record("task-timeline.drop.perform", [
            "x": info.location.x, "y": info.location.y
        ])
        return Self.receive(provider, at: info.location, onDrop: onDrop)
    }

    @discardableResult
    static func receive(_ provider: NSItemProvider, at point: CGPoint,
                        onDrop: @escaping @MainActor (UUID, CGPoint) -> Void) -> Bool {
        guard provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let payload = value as? String,
                  let id = TaskSectionDropTarget.taskID(for: payload) else { return }
            _Concurrency.Task { @MainActor in
                NativeAcceptanceInteractionTrace.record("task-timeline.drop.received", ["taskID": id.uuidString])
                onDrop(id, point)
            }
        }
        return true
    }
}
