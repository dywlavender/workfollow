import AppKit

/// 系统取色盘（`NSColorPanel`）的一次性接线。
///
/// 面板是**全局单例**：同一个 `NSColorPanel.shared` 被所有调用方共用，
/// 谁最后设置 target 谁收消息。所以用完必须摘掉，否则关掉清单编辑器之后，
/// 别处再打开取色盘，颜色还会写回已经消失的那个弹框。
///
/// `NSColorPanel` 走 target/action，需要一个常驻对象接消息，这里就是那个对象。
enum WFColorPanelPicker {
    private final class Target: NSObject {
        var handler: ((UInt32) -> Void)?
        @objc func handle(_ sender: NSColorPanel) {
            let rgb = sender.color.usingColorSpace(.sRGB) ?? sender.color
            let value = 0xFF00_0000
                | UInt32((rgb.redComponent * 255).rounded()) << 16
                | UInt32((rgb.greenComponent * 255).rounded()) << 8
                | UInt32((rgb.blueComponent * 255).rounded())
            handler?(value)
        }
    }

    private static let target = Target()
    /// `NSColorPanel` 没有 target getter，只能自己记「接线的是不是我们」。
    private static var attached = false

    /// 打开面板并把选中的颜色回调出去（ARGB，alpha 恒为 FF）。
    static func present(seed: UInt32, onPick: @escaping (UInt32) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(srgbRed: CGFloat((seed >> 16) & 0xFF) / 255,
                              green: CGFloat((seed >> 8) & 0xFF) / 255,
                              blue: CGFloat(seed & 0xFF) / 255,
                              alpha: 1)
        target.handler = onPick
        attached = true
        panel.setTarget(target)
        panel.setAction(#selector(Target.handle(_:)))
        panel.orderFront(nil)
    }

    /// 摘掉接线。只在当前接线确实是自己的时候动，避免误摘别人的。
    static func dismiss() {
        guard attached else { return }
        attached = false
        target.handler = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
    }
}
