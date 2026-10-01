import AppKit
import SwiftUI

/// One event monitor, explicit window ownership, and deepest layer first.
/// This routes presentation only; drafts and commit decisions remain in the caller.
@MainActor
final class PopupEscapeRegistry {
    static let shared = PopupEscapeRegistry()
    private struct Entry {
        weak var view: NSView?
        let depth: Int
        let action: () -> Void
    }
    private var entries: [(UUID, Entry)] = []
    private var monitor: Any?

    func register(view: NSView, depth: Int, action: @escaping () -> Void) -> UUID {
        let id = UUID()
        entries.append((id, Entry(view: view, depth: depth, action: action)))
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, self?.route(eventWindow: event.window) == true else { return event }
                return nil
            }
        }
        return id
    }

    func unregister(_ id: UUID) {
        entries.removeAll { $0.0 == id || $0.1.view == nil }
        if entries.isEmpty, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    @discardableResult
    func route(eventWindow: NSWindow?) -> Bool {
        guard let eventWindow, NSApp.modalWindow == nil,
              eventWindow.attachedSheet == nil else { return false }
        let candidates = entries.enumerated().filter { _, pair in
            guard let view = pair.1.view, let owner = view.window,
                  owner.isVisible, owner.attachedSheet == nil,
                  !view.isHiddenOrHasHiddenAncestor else { return false }
            return eventWindow === owner || eventWindow === owner.parent
        }
        let winner = candidates.max {
            $0.element.1.depth == $1.element.1.depth
                ? $0.offset < $1.offset : $0.element.1.depth < $1.element.1.depth
        }
        guard let winner else { return false }
        winner.element.1.action()
        return true
    }
}

struct PopupEscapeRouter: NSViewRepresentable {
    var depth = 1
    let onEscape: () -> Void
    final class Coordinator {
        var action: () -> Void
        var registration: UUID?
        init(action: @escaping () -> Void) { self.action = action }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: onEscape) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.registration = PopupEscapeRegistry.shared.register(view: view, depth: depth) { [weak coordinator] in
            coordinator?.action()
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.action = onEscape }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let id = coordinator.registration { PopupEscapeRegistry.shared.unregister(id) }
        coordinator.registration = nil
    }
}
