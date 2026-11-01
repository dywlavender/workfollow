import AppKit
import SwiftUI

/// Overlay thumbs stay slim even when macOS is set to always show scrollbars.
/// The native track and hit target remain available for dragging and paging.
/// Knobs are skipped entirely when the document fits the viewport.
@MainActor
enum CompactScrollStyle {
    static func apply(to scroll: NSScrollView) {
        if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
        if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
        if scroll.hasVerticalScroller, !(scroll.verticalScroller is CompactOverlayScroller) {
            scroll.verticalScroller = CompactOverlayScroller(frame: NSRect(x: 0, y: 0, width: 12, height: 100))
        }
        if scroll.verticalScroller?.controlSize != .small { scroll.verticalScroller?.controlSize = .small }
        // 横向同样是 3pt 细条：选项条/提示卡横滑时不能露出系统粗滚条。
        // 没有横向滚条（showsIndicators: false）时保持原样，不凭空造一条。
        if scroll.hasHorizontalScroller, !(scroll.horizontalScroller is CompactOverlayScroller) {
            scroll.horizontalScroller = CompactOverlayScroller(
                frame: NSRect(x: 0, y: 0, width: 100, height: 12), isHorizontal: true)
        }
        if scroll.horizontalScroller?.controlSize != .small { scroll.horizontalScroller?.controlSize = .small }
        // 探针会反复调用到这里，顺便补挂滚动监听：SwiftUI 常常在换完 scroller
        // 之后才把 documentView 配好，第一次挂载时还找不到内容视口。
        (scroll.verticalScroller as? CompactOverlayScroller)?.refreshScrollObservation()
        (scroll.horizontalScroller as? CompactOverlayScroller)?.refreshScrollObservation()
    }
}

final class CompactOverlayScroller: NSScroller {
    /// 停止滚动后停留一会儿再淡出，避免逐行滚动时闪烁。
    static let fadeDelay: TimeInterval = 0.9
    static let fadeOutDuration: TimeInterval = 0.35
    static let fadeInDuration: TimeInterval = 0.12

    private let isHorizontal: Bool
    private weak var observedContentView: NSView?
    private var fadeWorkItem: DispatchWorkItem?
    private var hoverArea: NSTrackingArea?

    init(frame: NSRect, isHorizontal: Bool = false) {
        self.isHorizontal = isHorizontal
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        isHorizontal = false
        super.init(coder: coder)
    }

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopObservingScrollActivity()
            return
        }
        refreshScrollObservation()
        // 自绘滚条不参与 AppKit 的 overlay 淡出，挂上来先按“没在滚动”处理。
        if alphaValue != 0 { alphaValue = 0 }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refreshScrollObservation()
    }

    override func layout() {
        super.layout()
        refreshScrollObservation()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                 options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                 owner: self, userInfo: nil)
        hoverArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        fadeWorkItem?.cancel()
        guard let scroll = owningScrollView,
              Self.hasOverflow(scroll, horizontal: isHorizontal) else { return }
        showKnob()
    }

    override func mouseExited(with event: NSEvent) {
        scheduleFadeOut()
    }

    /// 监听内容视口的位移：滚轮、触控板惯性、键盘翻页和代码滚动都会走到这里。
    /// SwiftUI 会在挂载之后才配好滚动视图，所以允许被反复调用。
    func refreshScrollObservation() {
        guard window != nil, let scroll = owningScrollView else { return }
        let content = scroll.contentView
        guard content !== observedContentView else { return }
        stopObservingScrollActivity()
        observedContentView = content
        content.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(contentBoundsDidChange),
                                              name: NSView.boundsDidChangeNotification,
                                              object: content)
    }

    private func stopObservingScrollActivity() {
        fadeWorkItem?.cancel()
        fadeWorkItem = nil
        if let observedContentView {
            NotificationCenter.default.removeObserver(self,
                                                    name: NSView.boundsDidChangeNotification,
                                                    object: observedContentView)
        }
        observedContentView = nil
    }

    @objc private func contentBoundsDidChange() {
        guard let scroll = owningScrollView,
              Self.hasOverflow(scroll, horizontal: isHorizontal) else { return }
        fadeWorkItem?.cancel()
        showKnob()
        scheduleFadeOut()
    }

    private func showKnob() {
        if alphaValue == 1 { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            animator().alphaValue = 1
        }
    }

    private func scheduleFadeOut() {
        fadeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideKnob() }
        fadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDelay, execute: work)
    }

    private func hideKnob() {
        if alphaValue == 0 { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        guard let scroll = owningScrollView,
              Self.hasOverflow(scroll, horizontal: isHorizontal) else { return }
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        let thumb = Self.thumbRect(in: knob, isHorizontal: isHorizontal)
        NSColor.labelColor.withAlphaComponent(0.30).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 1.5, yRadius: 1.5).fill()
    }

    /// SwiftUI 的 HostingScrollView 不会给替换进来的 scroller 设
    /// `enclosingScrollView`，要沿父视图链自己找。
    var owningScrollView: NSScrollView? {
        if let enclosingScrollView { return enclosingScrollView }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? NSScrollView { return scroll }
            ancestor = view.superview
        }
        return nil
    }

    /// 内容装得下时不画滚条：否则短列表/短正文旁边会常驻一条满长的 3pt 细线。
    static func hasOverflow(_ scroll: NSScrollView, horizontal: Bool) -> Bool {
        guard let document = scroll.documentView else { return false }
        let content = horizontal ? document.frame.width : document.frame.height
        let viewport = horizontal ? scroll.contentView.bounds.width : scroll.contentView.bounds.height
        return content > viewport + 0.5
    }

    static func thumbRect(in knob: NSRect, isHorizontal: Bool = false) -> NSRect {
        // 编辑区、任务列表、清单侧栏统一约 3pt 的自绘细条；
        // 外层 12pt 的 scroller 仍保留，拖拽命中不受细条宽度影响。
        if isHorizontal {
            let height = min(3, knob.height)
            return NSRect(x: knob.minX, y: knob.midY - height / 2, width: knob.width, height: height)
        }
        let width = min(3, knob.width)
        return NSRect(x: knob.midX - width / 2, y: knob.minY, width: width, height: knob.height)
    }
}

extension View {
    /// 放在 ScrollView 内容里，或直接加在 ScrollView 后面：
    /// 探针优先找包住自己的滚动视图，找不到时按几何位置找同层的那个。
    func compactScrollbars() -> some View {
        background(CompactScrollProbe().frame(width: 0, height: 0))
    }

    /// 固定滚条：放在 ScrollView 内容里调用，滚条占布局宽度、常显轨道。
    func fixedScrollbars() -> some View {
        background(FixedScrollProbe().frame(width: 0, height: 0))
    }

    /// `TextEditor` 专用：它自己的滚动视图包不住修饰器，而外层常还有宿主
    /// ScrollView，所以只按几何位置找 NSTextView 的滚动视图。
    func compactTextEditorScrollbars() -> some View {
        background(CompactTextEditorScrollProbe().frame(width: 0, height: 0))
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
        private weak var targetScrollView: NSScrollView?
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
            let cached = targetScrollView.flatMap { $0.window === window ? $0 : nil }
            guard let scroll = cached ?? resolveScrollView() else { return }
            if observedScrollView !== scroll {
                observedScrollView = scroll
                styleObservation = scroll.observe(\.scrollerStyle, options: [.new]) { [weak self] _, change in
                    guard change.newValue != .overlay else { return }
                    DispatchQueue.main.async { self?.apply() }
                }
            }
            CompactScrollStyle.apply(to: scroll)
        }

        /// 探针可能落在滚动视图内部（内容里），也可能落在滚动视图外层。
        /// 外层还有嵌套滚动时，包住探针的那个是外层，真正要改的是与探针
        /// 范围最贴合的那一个，所以两者都作为候选按几何范围挑。
        /// 有几何证据的结果才缓存；布局前的兜底结果下一轮继续找。
        private func resolveScrollView() -> NSScrollView? {
            guard let owner = superview?.convert(superview?.bounds ?? .zero, to: nil) else {
                return enclosingScrollView
            }
            var best: (scroll: NSScrollView, overlap: CGFloat, area: CGFloat)?
            func consider(_ scroll: NSScrollView) {
                let frame = scroll.convert(scroll.bounds, to: nil)
                guard frame.width > 0, frame.height > 0, frame.intersects(owner) else { return }
                let overlap = frame.intersection(owner).size.width * frame.intersection(owner).size.height
                let area = frame.width * frame.height
                if best == nil || overlap > best!.overlap
                    || (overlap == best!.overlap && area < best!.area) {
                    best = (scroll, overlap, area)
                }
            }
            if let enclosing = enclosingScrollView {
                let area = enclosing.frame.width * enclosing.frame.height
                // 布局前的探针还没有几何范围：包住它的滚动视图就是答案。
                best = (enclosing, -1, area)
            }
            var ancestor = superview
            for _ in 0..<4 {
                guard let container = ancestor else { break }
                Self.scrollViews(in: container).forEach(consider)
                ancestor = container.superview
            }
            guard let best else { return nil }
            if best.overlap >= 0 {
                targetScrollView = best.scroll
            }
            return best.scroll
        }

        fileprivate static func scrollViews(in root: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            func walk(_ view: NSView) {
                if let scroll = view as? NSScrollView { result.append(scroll) }
                view.subviews.forEach(walk)
            }
            walk(root)
            return result
        }
    }
}

private struct CompactTextEditorScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.applyAfterAttachment() }

    final class Probe: NSView {
        private weak var observedScrollView: NSScrollView?
        private weak var targetScrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyAfterAttachment() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); applyAfterAttachment() }

        func applyAfterAttachment() {
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            let cached = targetScrollView.flatMap { $0.window === window ? $0 : nil }
            guard let scroll = cached ?? resolveScrollView() else { return }
            if observedScrollView !== scroll {
                observedScrollView = scroll
                styleObservation = scroll.observe(\.scrollerStyle, options: [.new]) { [weak self] _, change in
                    guard change.newValue != .overlay else { return }
                    DispatchQueue.main.async { self?.apply() }
                }
            }
            CompactScrollStyle.apply(to: scroll)
        }

        private func resolveScrollView() -> NSScrollView? {
            guard let owner = superview?.convert(superview?.bounds ?? .zero, to: nil) else { return nil }
            var best: (scroll: NSScrollView, overlap: CGFloat, area: CGFloat)?
            var ancestor = superview
            for _ in 0..<4 {
                guard let container = ancestor else { break }
                for scroll in CompactScrollProbe.Probe.scrollViews(in: container)
                where scroll.documentView is NSTextView {
                    let frame = scroll.convert(scroll.bounds, to: nil)
                    guard frame.width > 0, frame.height > 0, frame.intersects(owner) else { continue }
                    let overlap = frame.intersection(owner).size.width * frame.intersection(owner).size.height
                    let area = frame.width * frame.height
                    if best == nil || overlap > best!.overlap
                        || (overlap == best!.overlap && area < best!.area) {
                        best = (scroll, overlap, area)
                    }
                }
                ancestor = container.superview
            }
            if let best { targetScrollView = best.scroll }
            return best?.scroll
        }
    }
}
