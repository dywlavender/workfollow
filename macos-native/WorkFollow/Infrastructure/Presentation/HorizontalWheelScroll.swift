import AppKit
import SwiftUI

/// 单行工具条在窄宿主里靠横向滚动收纳被挡住的按钮。SwiftUI 的横向
/// ScrollView 只认触控板横扫，普通鼠标滚轮会被外层纵向滚动吃掉；
/// 这里把落在横条上的纵向滚轮折算成横向位移，滚动条仍然保持隐藏。
enum HorizontalWheelScroll {
    /// 滚轮事件按“行”计量，一格大约挪过一个按钮。
    static let lineStep: CGFloat = 30

    /// 返回 nil 表示事件已被横条消费，返回原事件表示交还给外层滚动。
    static func handle(_ event: NSEvent, over scroll: NSScrollView) -> NSEvent? {
        guard event.type == .scrollWheel, event.window === scroll.window,
              scroll.window != nil, !scroll.isHiddenOrHasHiddenAncestor else { return event }
        let point = scroll.convert(event.locationInWindow, from: nil)
        guard scroll.bounds.intersection(scroll.visibleRect).contains(point) else { return event }
        // Control+滚轮是系统缩放，不能改成横移。
        guard !event.modifierFlags.contains(.control) else { return event }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        // 横向手势交给 NSScrollView 自己处理，保留惯性。
        guard dy != 0, abs(dy) > abs(dx) else { return event }
        let clip = scroll.contentView
        let documentWidth = scroll.documentView?.frame.width ?? 0
        let viewport = clip.bounds.width
        guard documentWidth > viewport + 0.5 else { return event }
        let step = event.hasPreciseScrollingDeltas ? dy : dy * lineStep
        let maximum = documentWidth - viewport
        // 正 delta 是向上滚：内容往左走，露出前面的按钮。
        let origin = min(maximum, max(0, clip.bounds.minX - step))
        guard abs(origin - clip.bounds.minX) > 0.01 else { return event }
        clip.scroll(to: NSPoint(x: origin, y: clip.bounds.minY))
        scroll.reflectScrolledClipView(clip)
        return nil
    }
}

extension View {
    /// 放在横向 ScrollView 的内容里：纵向滚轮也能滚到被藏住的按钮。
    func horizontalWheelScroll() -> some View {
        background(HorizontalWheelScrollProbe().frame(width: 0, height: 0))
    }
}

private struct HorizontalWheelScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.resolve() }

    final class Probe: NSView {
        private weak var scroll: NSScrollView?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { uninstall() } else { resolve(); install() }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            resolve(); install()
        }

        deinit { uninstall() }

        func resolve() {
            guard let scroll = enclosingScrollView, scroll !== self.scroll else { return }
            self.scroll = scroll
            install()
        }

        private func install() {
            guard monitor == nil, scroll != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let scroll = self.scroll else { return event }
                return HorizontalWheelScroll.handle(event, over: scroll)
            }
        }

        private func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
