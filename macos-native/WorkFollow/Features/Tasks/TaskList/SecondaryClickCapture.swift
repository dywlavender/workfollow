import AppKit
import SwiftUI

struct SecondaryClickCapture: NSViewRepresentable {
    let onSecondaryClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> SecondaryClickView {
        let view = SecondaryClickView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: SecondaryClickView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    final class SecondaryClickView: NSView {
        var onSecondaryClick: ((CGPoint) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onSecondaryClick?(CGPoint(x: location.x, y: location.y))
        }
    }
}
