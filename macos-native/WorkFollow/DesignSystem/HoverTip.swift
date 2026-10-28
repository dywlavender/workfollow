import AppKit
import SwiftUI

/// 全局即时悬停名称。规范见 `docs/macos-personal-app-design.md` §8.6。
///
/// 系统 `.help` 要等约 1 秒，`NSButton.toolTip` 也一样；rail 的入口则是指针一放上去
/// 就出现。这里把 rail 的样式与时机抽成一套共享实现：所有图标控件都用它，
/// 不再各自决定提示出现得多快、长什么样。
enum HoverTipPlacement {
    /// 默认放在控件下方；贴屏幕底部时改到控件上方。横向排列的图标不会被挡住。
    case automatic
    /// 固定放在控件右侧（rail 的入口仍在它自己的坐标层里画，不走这里）。
    case right
    case above
}

enum HoverTipMetrics {
    static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let height: CGFloat = 28
    static let horizontalPadding: CGFloat = 9
    static let cornerRadius: CGFloat = 6
    static let gap: CGFloat = 6

    static func width(for title: String) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: font]).width)
            + horizontalPadding * 2
    }

    /// 屏幕坐标下的提示卡原点；传入屏幕可见区域，避免被菜单栏/Dock 裁掉。
    /// AppKit 屏幕坐标（原点在左下角）：`below` 是更小的 y，`above` 是更大的 y。
    static func origin(anchor: CGRect, size: CGSize, in screen: CGRect,
                       placement: HoverTipPlacement) -> CGPoint {
        var origin = CGPoint(x: anchor.midX - size.width / 2,
                             y: anchor.minY - gap - size.height)
        switch placement {
        case .automatic:
            let fitsBelow = origin.y >= screen.minY + gap
            let fitsAbove = anchor.maxY + gap + size.height <= screen.maxY
            if !fitsBelow, fitsAbove {
                origin.y = anchor.maxY + gap
            }
        case .right:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
            let left = anchor.minX - gap - size.width
            if origin.x + size.width > screen.maxX, left >= screen.minX { origin.x = left }
        case .above:
            origin.y = anchor.maxY + gap
        }
        origin.x = min(max(screen.minX, origin.x), max(screen.minX, screen.maxX - size.width))
        origin.y = min(max(screen.minY, origin.y), max(screen.minY, screen.maxY - size.height))
        return origin
    }
}

/// 与 rail 提示卡完全同款：深色底、12 medium、28 高、圆角 6。
struct HoverTipCard: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WFColors.tooltipText)
            .lineLimit(1)
            .padding(.horizontal, HoverTipMetrics.horizontalPadding)
            .frame(height: HoverTipMetrics.height)
            .background(WFColors.tooltipSurface,
                        in: RoundedRectangle(cornerRadius: HoverTipMetrics.cornerRadius))
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 全 App 只保留一块提示窗；内容随悬停目标更新，不会出现两个提示叠在一起。
@MainActor
final class HoverTipCenter {
    static let shared = HoverTipCenter()

    private struct Presentation: Equatable {
        let title: String
        let anchor: CGRect
        let placement: HoverTipPlacement
        let windowNumber: Int
    }

    private(set) var activeTitle: String?
    private var presentation: Presentation?
    private var panel: HoverTipPanel?
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        // 点击、滚动、切换窗口时，锚点可能已经移位或消失，提示必须先收掉。
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.hide()
            return event
        } ?? NSObject())
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
    }

    /// 测试与验收用：提示窗当前是否可见、落在屏幕上的哪一格。
    var isShowing: Bool { panel?.isVisible == true }
    var currentFrame: CGRect? { isShowing ? panel?.frame : nil }

    func show(_ title: String, from view: NSView, placement: HoverTipPlacement = .automatic) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let window = view.window,
              view.window != nil, !view.isHiddenOrHasHiddenAncestor else { return }
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        show(title, anchor: anchor, placement: placement,
             windowNumber: window.windowNumber, appearance: window.effectiveAppearance,
             container: window.frame)
    }

    func show(_ title: String, anchor: CGRect, placement: HoverTipPlacement,
              windowNumber: Int, appearance: NSAppearance?,
              container: CGRect? = nil) {
        let next = Presentation(title: title, anchor: anchor,
                                placement: placement, windowNumber: windowNumber)
        guard presentation != next else { return }
        presentation = next
        activeTitle = title

        let panel = panel ?? makePanel()
        let card = HoverTipCard(title: title)
        let hosting = panel.contentView as? NSHostingView<HoverTipCard>
        hosting?.rootView = card
        hosting?.layoutSubtreeIfNeeded()

        let measured = HoverTipMetrics.width(for: title)
        var size = hosting?.fittingSize ?? .zero
        if size.width < 1 { size.width = measured }
        size.height = HoverTipMetrics.height
        size.width = max(size.width, measured)

        let screen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY))
        } ?? windowScreen(number: windowNumber) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: anchor.minX, y: anchor.minY,
                                                     width: 10_000, height: 10_000)
        var origin = HoverTipMetrics.origin(anchor: anchor, size: size,
                                           in: visible, placement: placement)
        // 横向收在窗口内：详情头部的优先级图标贴近右缘，卡片伸出圆角窗口很难看。
        // 纵向仍允许浮出小弹层，否则日期面板底部控件的提示会被挤回面板里面。
        if let container {
            let minX = max(visible.minX, container.minX + 6)
            let maxX = min(visible.maxX, container.maxX - 6)
            if maxX - minX >= size.width {
                origin.x = min(max(origin.x, minX), maxX - size.width)
            }
        }
        panel.appearance = appearance
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
        self.panel = panel
    }

    /// 只收起指定标题的提示：从 A 划到 B 时，A 的离开事件可能晚于 B 的进入事件。
    func hide(_ title: String? = nil) {
        if let title, title != activeTitle { return }
        presentation = nil
        activeTitle = nil
        panel?.orderOut(nil)
    }

    private func windowScreen(number: Int) -> NSScreen? {
        NSApp.windows.first { $0.windowNumber == number }?.screen
    }

    private func makePanel() -> HoverTipPanel {
        let panel = HoverTipPanel()
        let hosting = NSHostingView(rootView: HoverTipCard(title: ""))
        hosting.wantsLayer = true
        panel.contentView = hosting
        return panel
    }
}

@MainActor
final class HoverTipPanel: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 80, height: HoverTipMetrics.height),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HoverTipAnchorView: NSViewRepresentable {
    let title: String
    let placement: HoverTipPlacement
    let activeAlways: Bool

    func makeNSView(context: Context) -> HoverTipTrackingView {
        let view = HoverTipTrackingView()
        view.title = title
        view.placement = placement
        view.activeAlways = activeAlways
        return view
    }

    func updateNSView(_ view: HoverTipTrackingView, context: Context) {
        view.title = title
        view.placement = placement
        view.activeAlways = activeAlways
    }

    static func dismantleNSView(_ view: HoverTipTrackingView, coordinator: ()) {
        view.tearDown()
    }
}

/// 只负责追踪指针的透明层；不参与命中测试，点击仍落到下面的按钮上。
final class HoverTipTrackingView: NSView {
    var title: String = "" {
        didSet {
            guard title != oldValue else { return }
            if inside { present() } else if oldValue == HoverTipCenter.shared.activeTitle {
                HoverTipCenter.shared.hide(oldValue)
            }
        }
    }
    var placement: HoverTipPlacement = .automatic {
        didSet { if inside, placement != oldValue { present() } }
    }
    /// 子面板是非激活窗口（永远不会成为 key window），指针进出事件按
    /// `.activeInKeyWindow` 根本不会送达——插入浮条的图标名称此前就是因此不显示。
    var activeAlways = false {
        didSet { if activeAlways != oldValue { updateTrackingAreas() } }
    }

    private var tracking: NSTrackingArea?
    private var inside = false

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited,
                                            activeAlways ? .activeAlways : .activeInKeyWindow,
                                            .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        inside = true
        present()
    }

    override func mouseExited(with event: NSEvent) {
        inside = false
        HoverTipCenter.shared.hide(title)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            inside = false
            HoverTipCenter.shared.hide(title)
        } else if inside {
            present()
        }
    }

    override func layout() {
        super.layout()
        if inside { present() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if inside { present() }
    }

    func tearDown() {
        inside = false
        HoverTipCenter.shared.hide(title)
    }

    private func present() {
        HoverTipCenter.shared.show(title, from: self, placement: placement)
    }
}

private struct HoverTipModifier: ViewModifier {
    let title: String
    let placement: HoverTipPlacement
    let activeAlways: Bool

    func body(content: Content) -> some View {
        content.background {
            HoverTipAnchorView(title: title, placement: placement, activeAlways: activeAlways)
        }
    }
}

extension View {
    /// 指针一放上去就显示名称，样式与 rail 入口一致。
    /// - Parameter activeAlways: 非激活子面板（如插入浮条）里必须为 true——
    ///   这类窗口永远不会成为 key window。
    func hoverTip(_ title: String, placement: HoverTipPlacement = .automatic,
                  activeAlways: Bool = false) -> some View {
        modifier(HoverTipModifier(title: title, placement: placement, activeAlways: activeAlways))
    }
}
