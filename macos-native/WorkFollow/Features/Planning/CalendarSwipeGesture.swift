import AppKit
import SwiftUI

/// 日历页的触控板/滚轮翻页手势（2026-10-07，用户需求"左右切换或上下滑动"）。
///
/// 实现走 `NSEvent` 本地监听器而非 SwiftUI 手势：部署目标 14.0 没有
/// `onScrollGesture`（15+ 才有），而 `DragGesture` 不响应触控板双指滚动。
/// 监听器**从不吞事件**：横扫在日历页没有原生用途，纵扫要留给周格里的
/// 纵向任务列表；弹窗/浮层是独立 NSWindow，天然不在监听范围。
///
/// ⚠️ 命中判定用 **AppKit 主窗口框**，不用 SwiftUI `.global` 框——实测
/// `.global` 在这套宿主里给出零矩形（`{{0,982},{0,0}}`，2026-10-07 探针
/// 实锤），坐标换算整条路都不可信。日历页占满主窗口内容区、rail/工具条
/// 无滚动内容，窗口级判定精度足够；任务页不装监听器（onAppear/onDisappear）。
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
    @State private var accumulation: CGFloat = 0
    @State private var cooldownUntil = Date.distantPast

    func body(content: Content) -> some View {
        content
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
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard dx != 0 || dy != 0 else { return }
        // 只认主窗口：弹窗/浮层是独立 NSWindow 天然排除；光标须落在主窗口内。
        guard let window = event.window, window === NSApp.mainWindow,
              window.frame.contains(NSEvent.mouseLocation) else {
            #if DEBUG
            if dx != 0 || dy != 0 {
                NSLog("wf-swipe skip: mouse=%@ mainWindow=%@",
                      NSStringFromPoint(NSEvent.mouseLocation),
                      NSApp.mainWindow.map { NSStringFromRect($0.frame) } ?? "nil")
            }
            #endif
            return
        }
        let horizontal = abs(dx) > abs(dy)
        guard Date() >= cooldownUntil else { return }
        accumulation += horizontal ? dx : dy
        guard abs(accumulation) >= Self.threshold else { return }
        let direction = accumulation > 0 ? Self.directionSign : -Self.directionSign
        accumulation = 0
        cooldownUntil = Date().addingTimeInterval(Self.cooldown)
        onSwipe(direction, horizontal)
    }
}
