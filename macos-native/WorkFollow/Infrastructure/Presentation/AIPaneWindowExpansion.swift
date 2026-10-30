import AppKit

/// 把宿主窗口整体向右加宽，原有列宽不变，AI 面板占新增的一栏。
/// 右边缘会超出屏幕时先把窗口向左挪；屏幕确实放不下才返回 false，让调用方回退。
@MainActor
final class AIPaneWindowExpansion: ObservableObject {
    @Published private(set) var expandedWidth: CGFloat = 0

    private weak var window: NSWindow?
    private var baseFrame: NSRect?
    private var expandedFrame: NSRect?

    var isExpanded: Bool { expandedWidth > 0 }

    @discardableResult
    func expand(_ window: NSWindow, by width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        if isExpanded { return true }
        guard !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main,
              let target = AIPaneWindowExpansionGeometry.expandedFrame(
                base: window.frame, extraWidth: width, visible: screen.visibleFrame)
        else { return false }
        baseFrame = window.frame
        expandedFrame = target
        expandedWidth = width
        self.window = window
        window.setFrame(target, display: true)
        return true
    }

    /// 缩回 AI 栏占用的宽度。用户没动过窗口时回到打开前的 frame；
    /// 期间手动挪过/缩放过窗口则保留当前位置，只把 AI 那一栏宽度还回去。
    func collapse() {
        guard let window, let base = baseFrame else {
            reset()
            return
        }
        var frame = window.frame
        if let expanded = expandedFrame, sameFrame(frame, expanded) {
            frame = base
        } else {
            frame.size.width = max(window.minSize.width, frame.width - expandedWidth)
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                frame.size.width = min(frame.width, visible.width)
                frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            }
        }
        reset()
        window.setFrame(frame, display: true)
    }

    /// 用户手动拖 AI 分隔线等操作改变了列宽：结束“窗口扩展”模式，
    /// 但不再自动缩回窗口，之后的布局按普通窗口处理。
    func invalidate() {
        reset()
    }

    private func reset() {
        window = nil
        baseFrame = nil
        expandedFrame = nil
        if expandedWidth != 0 { expandedWidth = 0 }
    }

    private func sameFrame(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.width - rhs.width) < 1.5
            && abs(lhs.height - rhs.height) < 1.5
            && abs(lhs.minX - rhs.minX) < 1.5
            && abs(lhs.minY - rhs.minY) < 1.5
    }
}

enum AIPaneWindowExpansionGeometry {
    /// 宽度加上 AI 栏；右边缘超出屏幕可视区时整体左移，屏幕宽度不够则返回 nil。
    static func expandedFrame(base: NSRect, extraWidth: CGFloat, visible: NSRect) -> NSRect? {
        guard extraWidth > 0 else { return nil }
        let targetWidth = base.width + extraWidth
        guard targetWidth <= visible.width else { return nil }
        var target = base
        target.size.width = targetWidth
        target.origin.x = max(visible.minX, min(base.minX, visible.maxX - targetWidth))
        return target
    }
}
