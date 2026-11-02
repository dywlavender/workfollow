import AppKit
import SwiftUI

/// 侧栏行在窗口未激活时的第一次点击直接执行动作。
///
/// 行本身是 SwiftUI 按钮：AppKit 默认不把非 key 窗口的首击交给控件，第一次
/// 点击只用于激活窗口——用户实测「清单第一次点击没反应」。原生任务行已用
/// `acceptsFirstMouse` 修过同类问题（`NativeTaskRowView`）；SwiftUI 按钮没有
/// 这个口子，这里用一层透明宿主接管：窗口非 key 时首击命中这层并直接执行
/// 行动作，key 状态下 `hitTest` 返回 nil，点击行为与从前完全一致。
struct FirstMouseAction: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.action = action
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) { view.action = action }

    final class Catcher: NSView {
        var action: (() -> Void)?
        override var isOpaque: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        /// 只在窗口非 key 时接管；其余事件（含滚动、右键）沿响应链照常传递。
        override func hitTest(_ point: NSPoint) -> NSView? {
            window?.isKeyWindow == false ? self : nil
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeKeyAndOrderFront(nil)
            action?()
        }
    }
}

extension View {
    /// 窗口未激活时的第一次点击直接执行动作（详见 `FirstMouseAction`）。
    func firstMouseAction(_ action: @escaping () -> Void) -> some View {
        overlay(FirstMouseAction(action: action))
    }
}
