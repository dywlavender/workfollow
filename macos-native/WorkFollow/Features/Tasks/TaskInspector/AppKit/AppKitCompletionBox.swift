import AppKit
import SwiftUI

/// 完成框的 AppKit 绘制版本。
///
/// 组件对应：滴答 `TTTaskDetailTopView.checkButton` / `TTTaskDetailTitleCell.checkboxButton`
/// （nib 里的 `NSButton`，自绘圆角方框 + 勾）。
/// 几何与配色沿用 `TaskCompletionBox` 的推导：圆角 = 边长 × 0.25、描边随边长等比、
/// 勾色取内容底色。锚点仍由外层 SwiftUI 提供，渲染契约不受影响。
struct AppKitCompletionBox: NSViewRepresentable {
    let size: CGFloat
    let completed: Bool

    func makeNSView(context: Context) -> CompletionBoxView {
        let view = CompletionBoxView()
        view.size = size
        view.completed = completed
        return view
    }

    func updateNSView(_ view: CompletionBoxView, context: Context) {
        guard view.size != size || view.completed != completed else { return }
        view.size = size
        view.completed = completed
        view.invalidateIntrinsicContentSize()
        view.needsDisplay = true
    }
}

final class CompletionBoxView: NSView {
    var size: CGFloat = 15
    var completed = false

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

    override func draw(_ dirtyRect: NSRect) {
        guard size > 0 else { return }
        let radius = size * 0.25
        let borderWidth = max(1, size * 1.5 / 18)
        let box = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        if completed {
            NSColor(WFColors.taskCompletedCheckbox).setFill()
            path.fill()

            let check = NSBezierPath()
            check.lineWidth = max(1, size * 0.15)
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: NSPoint(x: size * 0.23, y: size * 0.44))
            check.line(to: NSPoint(x: size * 0.42, y: size * 0.64))
            check.line(to: NSPoint(x: size * 0.77, y: size * 0.25))
            NSColor(WFColors.content).setStroke()
            check.stroke()
        } else {
            NSColor(WFColors.secondaryText).setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }
    }
}
