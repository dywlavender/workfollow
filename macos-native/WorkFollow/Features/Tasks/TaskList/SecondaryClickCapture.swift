import AppKit
import SwiftUI

struct SecondaryClickCapture: NSViewRepresentable {
    let onSecondaryClick: (NSView, CGPoint) -> Void

    func makeNSView(context: Context) -> SecondaryClickView {
        let view = SecondaryClickView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: SecondaryClickView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    final class SecondaryClickView: NSView {
        // 回调带 self（行视图），调用方需要在视图坐标里挂锚点呈现弹窗。
        var onSecondaryClick: ((NSView, CGPoint) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            onSecondaryClick?(self, CGPoint(x: location.x, y: location.y))
        }
    }
}
