import AppKit
import SwiftUI

/// 日期面板属性行：AppKit 负责绘制（图标 / 标题或值 / 尾控件 / 展开灰底），
/// SwiftUI 负责命中区域与渲染锚点。
///
/// 这样分工的原因：`NSViewRepresentable` 的 host frame 在
/// `NSHostingController` / 子窗口等不同宿主下会滞后一拍，条件插入
/// 「重复结束」行时容易与上一行重叠；把点击和锚点留在 SwiftUI 层，
/// 坐标与布局始终由 SwiftUI 决定，AppKit 只做像素级绘制。
struct SchedulePropertyRow: View {
    let property: ScheduleProperty
    let icon: String
    let presentation: SchedulePropertyPresentation
    var editor: AnyView?
    let onOpen: () -> Void
    let onClear: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        AppKitSchedulePropertyRow(
            property: property,
            icon: icon,
            presentation: presentation,
            editor: editor
        )
        .frame(height: ScheduleMetrics.rowHeight)
        // 命中区域是 SwiftUI 透明按钮，会吃掉画布的 tracking area，悬停交给 SwiftUI。
        .overlay { hitAreas }
        .onHover(perform: onHover)
        .scheduleRenderAnchor(.row(property),
                              label: presentation.value ?? presentation.title,
                              active: presentation.isActive)
        .scheduleRenderAnchor(.expandedRow(property), active: presentation.isExpanded)
    }

    /// 命中区域：图标 / 值 / 尾控件。透明的 `Color.clear` 只承载点击与锚点，
    /// 视觉全部由 AppKit 画布输出。
    private var hitAreas: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 18)
            .scheduleRenderAnchor(.icon(property))
            .accessibilityLabel("展开\(presentation.title)")

            // 值区域点击一律打开子面板（时间行也如此：先展开列表，聚焦由
            // `openSheet` 后的 requestsFocus 完成，和原 SwiftUI 行一致）。
            Button(action: onOpen) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .scheduleRenderAnchor(.value(property))
            .accessibilityLabel("展开\(presentation.title)")

            Button(action: presentation.trailingControl == .clear ? onClear : onOpen) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 18)
            .scheduleRenderAnchor(.trailing(property), label: trailingSymbol)
            .help(presentation.trailingControl == .clear
                  ? "清除\(presentation.title)" : "展开\(presentation.title)")
            .accessibilityLabel(presentation.trailingControl == .clear
                                ? "清除\(presentation.title)" : "展开\(presentation.title)")
        }
        .padding(.horizontal, ScheduleMetrics.propertyRowHorizontalPadding)
    }

    private var trailingSymbol: String {
        switch presentation.trailingControl {
        case .clear: "xmark"
        case .chevronDown: "chevron.down"
        case .chevronRight: "chevron.right"
        }
    }
}

/// 属性行画布：只绘制，不处理点击。
struct AppKitSchedulePropertyRow: NSViewRepresentable {
    let property: ScheduleProperty
    let icon: String
    let presentation: SchedulePropertyPresentation
    let editor: AnyView?

    func makeNSView(context: Context) -> PropertyRowCanvas {
        let view = PropertyRowCanvas()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: PropertyRowCanvas, context: Context) {
        apply(to: view)
        view.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: ScheduleMetrics.rowHeight)
    }

    private func apply(to view: PropertyRowCanvas) {
        view.property = property
        view.iconSymbol = icon
        view.title = presentation.title
        view.valueText = presentation.value
        view.isActive = presentation.isActive
        view.isExpanded = presentation.isExpanded
        view.isHovered = presentation.isHovered
        view.canClear = presentation.canClear
        view.setEditor(editor)
    }
}

/// 属性行画布：自绘图标、标题/值、尾控件、展开灰底；
/// 时间行把 SwiftUI 输入框（`NSHostingView`）放进值区域。
final class PropertyRowCanvas: NSView {
    var property: ScheduleProperty = .time
    var iconSymbol = ""
    var title = ""
    var valueText: String?
    var isActive = false
    var isExpanded = false
    var isHovered = false
    var canClear = false

    private var editorHost: NSHostingView<AnyView>?

    private let horizontalPadding: CGFloat = ScheduleMetrics.propertyRowHorizontalPadding
    private let iconSide: CGFloat = 18
    private let gap: CGFloat = 8

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ScheduleMetrics.rowHeight)
    }

    private var accentColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.494, green: 0.533, blue: 1, alpha: 1)
                : NSColor(red: 0.357, green: 0.361, blue: 0.922, alpha: 1)
        }
    }

    private var iconRect: NSRect {
        NSRect(x: horizontalPadding, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
    }

    private var trailingRect: NSRect {
        NSRect(x: max(horizontalPadding, bounds.width - horizontalPadding - iconSide),
               y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
    }

    private var valueRect: NSRect {
        let x = iconRect.maxX + gap
        return NSRect(x: x, y: 0, width: max(0, trailingRect.minX - gap - x), height: bounds.height)
    }

    // MARK: 编辑器

    func setEditor(_ editor: AnyView?) {
        guard let editor else {
            editorHost?.removeFromSuperview()
            editorHost = nil
            return
        }
        if let host = editorHost {
            host.rootView = editor
        } else {
            let host = NSHostingView(rootView: editor)
            host.frame = valueRect
            addSubview(host)
            editorHost = host
        }
    }

    override func layout() {
        super.layout()
        editorHost?.frame = valueRect
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0 else { return }

        if isExpanded {
            NSColor.labelColor.withAlphaComponent(0.04).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }

        drawIcon()
        drawValue()
        drawTrailing()
    }

    private func drawIcon() {
        guard let image = NSImage(systemSymbolName: iconSymbol, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let configured = image.withSymbolConfiguration(config) ?? image
        let color = isActive ? accentColor : NSColor.secondaryLabelColor
        let tinted = configured.tinted(with: color)
        let size = tinted.size
        tinted.draw(in: NSRect(x: iconRect.midX - size.width / 2,
                               y: iconRect.midY - size.height / 2,
                               width: size.width, height: size.height))
    }

    private func drawValue() {
        guard editorHost == nil else { return }
        let text = valueText ?? title
        // 未设值的占位文案（时间 / 提醒 / 重复）与滴答一致用正文色，设了值才按 active 上色。
        let color = isActive ? accentColor : NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            in: NSRect(x: valueRect.minX, y: valueRect.midY - size.height / 2,
                       width: min(size.width, valueRect.width), height: size.height),
            withAttributes: attributes)
    }

    private func drawTrailing() {
        let symbol: String
        let pointSize: CGFloat
        switch (canClear, isHovered, isExpanded) {
        case (true, true, _):
            symbol = "xmark"; pointSize = 9
        case (_, _, true):
            symbol = "chevron.down"; pointSize = 10
        default:
            symbol = "chevron.right"; pointSize = 10
        }
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let configured = image.withSymbolConfiguration(config) ?? image
        let tinted = configured.tinted(with: NSColor.tertiaryLabelColor)
        let size = tinted.size
        tinted.draw(in: NSRect(x: trailingRect.midX - size.width / 2,
                               y: trailingRect.midY - size.height / 2,
                               width: size.width, height: size.height))
    }

}

private extension NSImage {
    /// 用模板渲染把 SF Symbol 染成指定颜色。
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as? NSImage ?? self
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        rect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
