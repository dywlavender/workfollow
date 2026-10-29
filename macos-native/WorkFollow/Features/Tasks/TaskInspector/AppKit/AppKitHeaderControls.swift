import AppKit
import SwiftUI

/// 顶栏图标按钮的 AppKit 版本（返回 / 重复 / 优先级）。
///
/// 组件对应：滴答 `TTTaskDetailTopView` 里的 `NSButton`（`returnButton`、
/// `repeatIcon` 旁按钮、`priorityButton`）。几何由外层 SwiftUI `.frame` 给定，
/// 这里只负责 `NSButton` 的边框、图标、色与点击。
struct AppKitIconButton: NSViewRepresentable {
    let symbol: String
    /// 图标本身的点尺寸；按钮命中区由外层 frame 决定。
    let pointSize: CGFloat
    let tint: NSColor
    let accessibilityLabel: String
    let action: () -> Void
    /// 底栏图标放到控件上方，避免提示卡落到窗口外。
    var hoverTipPlacement: HoverTipPlacement = .automatic
    /// Optional pointer callback for controls that explicitly need hover behavior.
    var onHover: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = HoverButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        button.onHover = { [weak coordinator = context.coordinator] inside in
            coordinator?.onHover?(inside)
        }
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.onHover = onHover
        (button as? HoverButton)?.onHover = { [weak coordinator = context.coordinator] inside in
            coordinator?.onHover?(inside)
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        button.contentTintColor = tint
        // 系统 toolTip 要等约 1 秒；图标名称统一走即时提示层。
        button.toolTip = nil
        (button as? HoverButton)?.hoverTitle = accessibilityLabel
        (button as? HoverButton)?.hoverTipPlacement = hoverTipPlacement
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityRole(.button)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        var onHover: ((Bool) -> Void)?
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}

/// 带悬停回调的 `NSButton`（SwiftUI 的 `.onHover` 套在 NSViewRepresentable 上
/// 会被 AppKit 的 tracking 抢走，直接在这里判定）。
final class HoverButton: NSButton {
    var onHover: ((Bool) -> Void)?
    var hoverTitle: String? {
        didSet {
            guard hoverTitle != oldValue else { return }
            if pointerInside { presentTip() }
            else if oldValue == HoverTipCenter.shared.activeTitle {
                HoverTipCenter.shared.hide(oldValue)
            }
        }
    }
    var hoverTipPlacement: HoverTipPlacement = .automatic {
        didSet { if pointerInside, hoverTipPlacement != oldValue { presentTip() } }
    }
    private var hoverTracking: NSTrackingArea?
    private var pointerInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        needsDisplay = true
        presentTip()
        onHover?(true)
    }
    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        needsDisplay = true
        if let hoverTitle { HoverTipCenter.shared.hide(hoverTitle) }
        onHover?(false)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            pointerInside = false
            if let hoverTitle { HoverTipCenter.shared.hide(hoverTitle) }
        } else if pointerInside {
            presentTip()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if pointerInside { presentTip() }
    }

    private func presentTip() {
        guard let hoverTitle else { return }
        HoverTipCenter.shared.show(hoverTitle, from: self, placement: hoverTipPlacement)
    }
    override func draw(_ dirtyRect: NSRect) {
        if pointerInside && isEnabled {
            NSColor(WFColors.hover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: PopupMetrics.buttonCornerRadius,
                         yRadius: PopupMetrics.buttonCornerRadius).fill()
        }
        super.draw(dirtyRect)
    }
}

/// 顶栏日期 chip 的 AppKit 版本（图标 + 文案 + 色调）。
///
/// 组件对应：滴答 `TTTaskDetailTopView.dateButton`（`NSButton`，标题随日期变化）。
/// 文案、色彩与空态由调用方的既有推导提供，这里不重算业务。
struct AppKitScheduleChip: NSViewRepresentable {
    let symbol: String
    let title: String
    let tint: NSColor
    let accessibilityLabel: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = HoverButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.alignment = .left
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        button.contentTintColor = tint
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: tint,
        ])
        button.toolTip = nil
        (button as? HoverButton)?.hoverTitle = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityRole(.button)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}

/// 字面文字按钮的 AppKit 版本（底栏「A」格式入口等）。
///
/// 组件对应：滴答 `TTTaskDetailBottomActionView.mdEditButton`（字面 "A" 的 NSButton）。
struct AppKitTextButton: NSViewRepresentable {
    let title: String
    let pointSize: CGFloat
    let tint: NSColor
    let accessibilityLabel: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        // 字面图标也吃同一层悬停底色；提示由调用方的 `.hoverTip` 给出。
        let button = HoverButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .noImage
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: pointSize, weight: .medium),
            .foregroundColor: tint,
        ])
        // 调用方用 `.hoverTip` 给出即时名称；系统 toolTip 的 1 秒延迟不再叠加。
        button.toolTip = nil
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityRole(.button)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}

extension NSColor {
    /// 顶栏图标常用色：正文墨色、次级墨色、强调色、危险色。
    static var inspectorPrimary: NSColor { .labelColor }
    static var inspectorSecondary: NSColor { .secondaryLabelColor }
}
