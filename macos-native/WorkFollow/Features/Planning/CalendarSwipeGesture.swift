import AppKit
import SwiftUI

/// 日历页的触控板/滚轮翻页手势（2026-10-07，用户需求"左右切换或上下滑动"）。
///
/// 实现走 `NSEvent` 本地监听器而非 SwiftUI 手势：部署目标 14.0 没有
/// `onScrollGesture`（15+ 才有），而 `DragGesture` 不响应触控板双指滚动。
/// 监听器**从不吞事件**：横扫在日历页没有原生用途，纵扫要留给周格里的
/// 纵向任务列表；弹窗/浮层是独立 NSWindow，天然不在监听范围。
///
/// 自然滚动方向下手指向左/向上 = 看下一周期（同 Safari 前进）；方向与
/// 预期相反时改 `directionSign` 一行。累积/阈值/冷却：触控板一个手势会
/// 连发几十个事件，累积到阈值才翻一页，冷却防止一次长扫连翻多页。
struct CalendarSwipeGestureModifier: ViewModifier {
    /// ±1 翻到下/上一周期；`horizontal` = 手势主轴是否横向（纵向在周模式
    /// 由视图侧忽略——那里纵向是任务列表滚动）。
    let onSwipe: (_ direction: Int, _ horizontal: Bool) -> Void

    /// 方向校正位：实测与预期相反时改 -1。
    private static let directionSign = 1
    /// 触发一次翻页需要的累积滚动量（约一根手指半程的滑动）。
    private static let threshold: CGFloat = 60
    private static let cooldown: TimeInterval = 0.45

    @State private var monitor: Any?
    @State private var globalFrame: CGRect = .zero
    @State private var accumulation: CGFloat = 0
    @State private var cooldownUntil = Date.distantPast

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: CalendarGlobalFrameKey.self,
                                           value: geo.frame(in: .global))
                }
            )
            .onPreferenceChange(CalendarGlobalFrameKey.self) { globalFrame = $0 }
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handle(event)
            return event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        self.monitor = nil
    }

    private func handle(_ event: NSEvent) {
        // 诊断探针（仅 DEBUG）：光标不在日历区时保持安静，避免刷屏。
        #if DEBUG
        if appkitFrame.contains(NSEvent.mouseLocation) {
            NSLog("wf-swipe probe: dx=%f dy=%f frame=%@ window=%@",
                  event.scrollingDeltaX, event.scrollingDeltaY,
                  NSStringFromRect(appkitFrame),
                  event.window == nil ? "nil" : (event.window!.isMainWindow ? "main" : "other"))
        }
        #endif
        // 只认主窗口的滚轮（弹窗/浮层是独立 NSWindow，天然排除）。
        guard let window = event.window, window.isKeyWindow || window.isMainWindow,
              appkitFrame.contains(NSEvent.mouseLocation) else { return }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard dx != 0 || dy != 0 else { return }
        let horizontal = abs(dx) > abs(dy)
        guard Date() >= cooldownUntil else { return }
        accumulation += horizontal ? dx : dy
        guard abs(accumulation) >= Self.threshold else { return }
        let direction = accumulation > 0 ? Self.directionSign : -Self.directionSign
        accumulation = 0
        cooldownUntil = Date().addingTimeInterval(Self.cooldown)
        onSwipe(direction, horizontal)
    }

    /// SwiftUI `.global`（屏幕左上原点）→ AppKit 屏幕坐标（左下原点）。
    private var appkitFrame: CGRect {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        return CGRect(x: globalFrame.minX,
                      y: screenHeight - globalFrame.maxY,
                      width: globalFrame.width,
                      height: globalFrame.height)
    }
}

private struct CalendarGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
