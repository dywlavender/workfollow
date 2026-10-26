import AppKit
import SwiftUI

/// Overlay thumbs stay slim even when macOS is set to always show scrollbars.
/// The native track and hit target remain available for dragging and paging.
@MainActor
enum CompactScrollStyle {
    static func apply(to scroll: NSScrollView) {
        if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
        if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
        if scroll.hasVerticalScroller, !(scroll.verticalScroller is CompactOverlayScroller) {
            scroll.verticalScroller = CompactOverlayScroller(frame: NSRect(x: 0, y: 0, width: 12, height: 100))
        }
        if scroll.verticalScroller?.controlSize != .small { scroll.verticalScroller?.controlSize = .small }
    }
}

final class CompactOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        let thumb = Self.thumbRect(in: knob)
        NSColor.labelColor.withAlphaComponent(0.30).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: thumb.width / 2, yRadius: thumb.width / 2).fill()
    }

    static func thumbRect(in knob: NSRect) -> NSRect {
        // 编辑区、任务列表、清单侧栏统一约 3pt 的自绘细条；
        // 外层 12pt 的 scroller 仍保留，拖拽命中不受细条宽度影响。
        let width = min(3, knob.width)
        return NSRect(x: knob.midX - width / 2, y: knob.minY, width: width, height: knob.height)
    }
}

extension View {
    /// Apply inside ScrollView's content, so the probe finds that viewport only.
    func compactScrollbars() -> some View {
        background(CompactScrollProbe().frame(width: 0, height: 0))
    }

    /// 固定滚条：放在 ScrollView 内容里调用，滚条占布局宽度、常显轨道。
    func fixedScrollbars() -> some View {
        background(FixedScrollProbe().frame(width: 0, height: 0))
    }
}

/// 经典滚条样式（非 overlay）：轨道固定在内容右侧，不与行内容重叠。
@MainActor
enum FixedScrollStyle {
    static func apply(to scroll: NSScrollView) {
        if scroll.scrollerStyle != .legacy { scroll.scrollerStyle = .legacy }
        if scroll.autohidesScrollers { scroll.autohidesScrollers = false }
        if !scroll.hasVerticalScroller { scroll.hasVerticalScroller = true }
    }
}

private struct FixedScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.apply() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); apply() }

        func apply() {
            guard let scroll = enclosingScrollView else { return }
            FixedScrollStyle.apply(to: scroll)
        }
    }
}

private struct CompactScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.applyAfterAttachment() }

    final class Probe: NSView {
        private weak var observedScrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyAfterAttachment() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); applyAfterAttachment() }

        func applyAfterAttachment() {
            apply()
            // SwiftUI can configure its NSScrollView after attaching content.
            // Apply again once that configuration has finished.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let scroll = enclosingScrollView else { return }
            if observedScrollView !== scroll {
                observedScrollView = scroll
                styleObservation = scroll.observe(\.scrollerStyle, options: [.new]) { [weak self] _, change in
                    guard change.newValue != .overlay else { return }
                    DispatchQueue.main.async { self?.apply() }
                }
            }
            CompactScrollStyle.apply(to: scroll)
        }
    }
}
