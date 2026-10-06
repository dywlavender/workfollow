import AppKit

/// Page selection and keyboard focus are independent. A pointer navigation
/// commits the old editor and drops the rail's remembered focus; keyboard and
/// accessibility activation keep the native focus indicator and Tab chain.
@MainActor
enum RailNavigationFocus {
    static func activate(eventType: NSEvent.EventType?, window: NSWindow?,
                         clearRailFocus: () -> Void, navigate: () -> Void) {
        let pointer = eventType == .leftMouseDown || eventType == .leftMouseUp
        if pointer {
            // Commit marked text before the old page is removed.
            guard window?.makeFirstResponder(nil) != false else { return }
            clearRailFocus()
        }
        navigate()
        if pointer {
            clearRailFocus()
            window?.makeFirstResponder(nil)
        }
    }
}
