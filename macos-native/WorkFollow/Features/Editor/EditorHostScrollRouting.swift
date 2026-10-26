import AppKit

/// A growing embedded editor has no inner viewport. Keep the original wheel
/// event (including its phase and momentum) with the surrounding NSScrollView.
@MainActor
enum EditorHostScrollRouting {
    static func contains(_ event: NSEvent, in view: NSView) -> Bool {
        guard event.window === view.window, view.window != nil,
              !view.isHiddenOrHasHiddenAncestor else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.intersection(view.visibleRect).contains(point)
    }

    /// Web popup rectangles use CSS coordinates, measured from the top left.
    @discardableResult
    static func forward(_ event: NSEvent, over view: NSView, enabled: Bool,
                        internalScrollRegions: [NSRect] = []) -> Bool {
        guard enabled, event.type == .scrollWheel,
              !event.modifierFlags.contains(.shift),
              abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
              contains(event, in: view),
              let scroll = view.enclosingScrollView else { return false }
        let local = view.convert(event.locationInWindow, from: nil)
        let webPoint = NSPoint(x: local.x - view.bounds.minX,
                              y: view.isFlipped ? local.y - view.bounds.minY : view.bounds.maxY - local.y)
        guard !internalScrollRegions.contains(where: { $0.contains(webPoint) }) else { return false }
        scroll.scrollWheel(with: event)
        return true
    }
}
