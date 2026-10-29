import AppKit
import SwiftUI

/// 通用整行 hover 背景。
///
/// 用 AppKit 追踪区而不是 SwiftUI `.onHover`：行内按钮在悬停后出现时，
/// 指针仍落在同一块追踪区里，底色和按钮不会互相触发 enter/exit 闪断；
/// 普通悬停只重绘背景层，不重建标题、日期、菜单等内容。
struct RowHoverBackground: NSViewRepresentable {
    var selected = false
    var cornerRadius: CGFloat = WFMetrics.corner
    /// 可视底色相对整行左右各内缩多少；追踪区域仍覆盖整行。
    var horizontalInset: CGFloat = 0
    var idleFill: Color = .clear
    var selectedFill: Color = WFColors.listSelection
    var hoverFill: Color = WFColors.hover
    /// 菜单子窗口通常不成为 key window，需用 app 级追踪才能收到 hover。
    var activeInActiveApp = false
    /// 需要悬停时显示行内操作的行接这个回调；只画背景的行留空即可。
    var onHoverChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> RowHoverView {
        let view = RowHoverView()
        configure(view)
        return view
    }

    func updateNSView(_ view: RowHoverView, context: Context) {
        configure(view)
    }

    private func configure(_ view: RowHoverView) {
        view.onHover = onHoverChanged
        view.cornerRadius = cornerRadius
        view.horizontalInset = horizontalInset
        view.idleFill = idleFill
        view.selectedFill = selectedFill
        view.hoverFill = hoverFill
        view.activeInActiveApp = activeInActiveApp
        view.setSelected(selected)
    }
}

final class RowHoverView: NSView {
    private var pointerArea: NSTrackingArea?
    private var selected = false
    private(set) var hovered = false
    var onHover: ((Bool) -> Void)?
    /// 用 mask 把可视底色内缩，但 view（以及它的追踪区域）仍覆盖整行：
    /// 鼠标移到行左侧的拖拽柄或行内按钮上时，底色不会消失。
    private let insetMask = CALayer()
    var horizontalInset: CGFloat = 0 {
        didSet { if horizontalInset != oldValue { needsLayout = true } }
    }
    var cornerRadius: CGFloat = WFMetrics.corner {
        didSet {
            guard cornerRadius != oldValue else { return }
            layer?.cornerRadius = cornerRadius
            insetMask.cornerRadius = cornerRadius
        }
    }
    var idleFill: Color = .clear {
        didSet { if idleFill != oldValue { paint() } }
    }
    var selectedFill: Color = WFColors.listSelection {
        didSet { if selectedFill != oldValue { paint() } }
    }
    var hoverFill: Color = WFColors.hover {
        didSet { if hoverFill != oldValue { paint() } }
    }
    var activeInActiveApp = false {
        didSet {
            guard activeInActiveApp != oldValue else { return }
            updateTrackingAreas()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        insetMask.backgroundColor = NSColor.white.cgColor
        insetMask.cornerRadius = cornerRadius
        layer?.mask = insetMask
        paint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        insetMask.frame = bounds.insetBy(dx: horizontalInset, dy: 0)
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let activity: NSTrackingArea.Options = activeInActiveApp ? .activeInActiveApp : .activeInKeyWindow
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, activity, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovered(false) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    func setSelected(_ value: Bool) {
        guard selected != value else { return }
        selected = value
        paint()
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        paint()
        onHover?(value)
    }

    private func paint() {
        let color = selected ? NSColor(selectedFill)
            : hovered ? NSColor(hoverFill) : NSColor(idleFill)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = color.cgColor
            layer?.cornerRadius = cornerRadius
            insetMask.cornerRadius = cornerRadius
            CATransaction.commit()
        }
    }
}

private struct RowHoverBackgroundModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat
    let horizontalInset: CGFloat
    let idleFill: Color
    let selectedFill: Color
    let hoverFill: Color
    let activeInActiveApp: Bool
    let onHoverChanged: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            RowHoverBackground(selected: selected,
                               cornerRadius: cornerRadius,
                               horizontalInset: horizontalInset,
                               idleFill: idleFill,
                               selectedFill: selectedFill,
                               hoverFill: hoverFill,
                               activeInActiveApp: activeInActiveApp,
                               onHoverChanged: onHoverChanged)
        }
    }
}

extension View {
    /// 整行 hover/选中底色。`selected` 优先于 hover；`idleFill` 用于本身
    /// 有底色的卡片，让同一层同时绘制静止/悬停两态。
    func rowHoverBackground(
        selected: Bool = false,
        cornerRadius: CGFloat = WFMetrics.corner,
        horizontalInset: CGFloat = 0,
        idleFill: Color = .clear,
        selectedFill: Color = WFColors.listSelection,
        hoverFill: Color = WFColors.hover,
        activeInActiveApp: Bool = false,
        onHoverChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(RowHoverBackgroundModifier(selected: selected,
                                            cornerRadius: cornerRadius,
                                            horizontalInset: horizontalInset,
                                            idleFill: idleFill,
                                            selectedFill: selectedFill,
                                            hoverFill: hoverFill,
                                            activeInActiveApp: activeInActiveApp,
                                            onHoverChanged: onHoverChanged))
    }
}
