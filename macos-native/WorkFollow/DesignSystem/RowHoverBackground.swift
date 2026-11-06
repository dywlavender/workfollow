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
    /// nil 表示按当前表面取默认选中色：主题页面用偏白底，其他表面用中性灰。
    var selectedFill: Color? = nil
    var hoverFill: Color = WFColors.hover
    /// 刚创建、正在短暂标识的行。**与 `selected` 是两件事**：它只说明"这行是新的"，
    /// 不说明"这行正被打开"。以前调用点把两者或进同一个 `selected`，于是新建行涂上了
    /// 选中底色、详情栏却还停在上一条任务——看着像选中了，编辑的却是别人。
    var highlighted = false
    /// 新建标识的底色：比选中灰更淡，避免和真选中混淆。
    var highlightFill: Color = WFColors.listCreationHighlight
    /// 菜单子窗口通常不成为 key window，需用 app 级追踪才能收到 hover。
    var activeInActiveApp = false
    /// 需要悬停时显示行内操作的行接这个回调；只画背景的行留空即可。
    var onHoverChanged: ((Bool) -> Void)?
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme
    @Environment(\.workfollowPageCanvasActive) private var pageCanvasActive

    /// 弹层和独立面板不透视主题，仍用中性灰；主题页面按主题取对应色相。
    private var resolvedSelectedFill: Color {
        if let selectedFill { return selectedFill }
        return WFColors.listSelectionFill(theme: backgroundTheme, pageCanvasActive: pageCanvasActive)
    }

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
        view.selectedFill = resolvedSelectedFill
        view.hoverFill = hoverFill
        view.highlightFill = highlightFill
        view.activeInActiveApp = activeInActiveApp
        view.setSelected(selected)
        view.setHighlighted(highlighted)
    }
}

final class RowHoverView: NSView {
    private var pointerArea: NSTrackingArea?
    private(set) var selected = false
    private(set) var hovered = false
    private(set) var highlighted = false
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
    var highlightFill: Color = WFColors.listCreationHighlight {
        didSet { if highlightFill != oldValue { paint() } }
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

    func setHighlighted(_ value: Bool) {
        guard highlighted != value else { return }
        highlighted = value
        paint()
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        paint()
        onHover?(value)
    }

    private func paint() {
        // 选中 > 新建标识 > 悬停 > 静止。选中必须压过新建标识：同一行刚建完又被
        // 打开时，用户该看到的是"正被编辑"，而不是"刚建出来"。
        let color = selected ? NSColor(selectedFill)
            : highlighted ? NSColor(highlightFill)
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
    let selectedFill: Color?
    let hoverFill: Color
    let highlighted: Bool
    let highlightFill: Color
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
                               highlighted: highlighted,
                               highlightFill: highlightFill,
                               activeInActiveApp: activeInActiveApp,
                               onHoverChanged: onHoverChanged)
        }
    }
}

extension View {
    /// 整行 hover/选中底色。`selected` 优先于 hover；`idleFill` 用于本身
    /// 有底色的卡片，让同一层同时绘制静止/悬停两态。
    ///
    /// `highlighted` 是"刚创建"的短暂标识，**独立于 `selected`**：它不该让行看起来
    /// 被打开。调用点不要再用 `selected: selected || recentlyCreated` 把两者或起来。
    func rowHoverBackground(
        selected: Bool = false,
        cornerRadius: CGFloat = WFMetrics.corner,
        horizontalInset: CGFloat = 0,
        idleFill: Color = .clear,
        selectedFill: Color? = nil,
        hoverFill: Color = WFColors.hover,
        highlighted: Bool = false,
        highlightFill: Color = WFColors.listCreationHighlight,
        activeInActiveApp: Bool = false,
        onHoverChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(RowHoverBackgroundModifier(selected: selected,
                                            cornerRadius: cornerRadius,
                                            horizontalInset: horizontalInset,
                                            idleFill: idleFill,
                                            selectedFill: selectedFill,
                                            hoverFill: hoverFill,
                                            highlighted: highlighted,
                                            highlightFill: highlightFill,
                                            activeInActiveApp: activeInActiveApp,
                                            onHoverChanged: onHoverChanged))
    }
}
