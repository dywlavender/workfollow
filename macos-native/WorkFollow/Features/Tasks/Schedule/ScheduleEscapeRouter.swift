import AppKit
import SwiftUI

/// NSPopover consumes Escape before SwiftUI exit commands. Intercept it only
/// in this panel's window so the expanded editor can close before its parent.
struct ScheduleEscapeRouter: NSViewRepresentable {
    let onEscape: () -> Void

    final class Coordinator {
        var onEscape: () -> Void
        var monitor: Any?
        init(onEscape: @escaping () -> Void) { self.onEscape = onEscape }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onEscape: onEscape) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view, weak coordinator] event in
            guard event.keyCode == 53, view != nil, let coordinator else { return event }
            let window = view?.window
            // A transient NSPopover keeps its owner as the key event window.
            let belongsToPanel = window == nil || event.window == nil || event.window === window
                || event.window === window?.parent
                || (window?.isVisible == true && event.window === NSApp.keyWindow)
            guard belongsToPanel else { return event }
            coordinator.onEscape()
            return nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
}
