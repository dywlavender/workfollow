import AppKit
import SwiftUI

// MARK: - 底部按钮

/// AppKit 绘制，SwiftUI 按钮保留命中、辅助功能与默认 Return 动作。
struct AppKitScheduleFooter: View {
    static let contentHeight = ScheduleFooterCanvas.preferredHeight
    let onClear: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ScheduleFooterDrawing()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                HStack(spacing: 12) {
                    Button(action: onClear) { Color.clear.contentShape(Rectangle()) }
                        .accessibilityLabel("清除")
                        .accessibilityIdentifier("schedule-clear")
                    Button(action: onConfirm) { Color.clear.contentShape(Rectangle()) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("确定")
                        .accessibilityIdentifier("schedule-confirm")
                }
                .buttonStyle(.plain)
            }
            .frame(height: Self.contentHeight)
            .scheduleRenderAnchor(.mainFooter, label: "清除 / 确定")
    }
}

private struct ScheduleFooterDrawing: NSViewRepresentable {
    func makeNSView(context: Context) -> ScheduleFooterCanvas {
        ScheduleFooterCanvas()
    }

    func updateNSView(_ view: ScheduleFooterCanvas, context: Context) {
        view.needsDisplay = true
    }
}

final class ScheduleFooterCanvas: NSView {
    private let gap: CGFloat = 12
    private let corner: CGFloat = 8
    static let preferredHeight: CGFloat = 28

    override var isFlipped: Bool { true }

    private var buttonWidth: CGFloat { (bounds.width - gap) / 2 }
    private var clearRect: NSRect { NSRect(x: 0, y: 0, width: buttonWidth, height: bounds.height) }
    private var confirmRect: NSRect {
        NSRect(x: clearRect.maxX + gap, y: 0, width: buttonWidth, height: bounds.height)
    }

    private var accentColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.494, green: 0.533, blue: 1, alpha: 1)
                : NSColor(red: 0.357, green: 0.361, blue: 0.922, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0 else { return }

        let clearPath = NSBezierPath(roundedRect: clearRect.insetBy(dx: 0.5, dy: 0.5),
                                     xRadius: corner, yRadius: corner)
        NSColor.controlBackgroundColor.setFill()
        clearPath.fill()
        NSColor.separatorColor.setStroke()
        clearPath.lineWidth = 1
        clearPath.stroke()
        drawTitle("清除", in: clearRect, color: NSColor.labelColor,
                  font: NSFont.systemFont(ofSize: 14))

        let confirmPath = NSBezierPath(roundedRect: confirmRect, xRadius: corner, yRadius: corner)
        accentColor.setFill()
        confirmPath.fill()
        drawTitle("确定", in: confirmRect, color: .white,
                  font: NSFont.systemFont(ofSize: 14))
    }

    private func drawTitle(_ title: String, in rect: NSRect, color: NSColor, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                       width: size.width, height: size.height),
            withAttributes: attributes)
    }

}

// MARK: - 日期 / 时间段分段

/// 日期面板「日期 / 时间段」分段的 AppKit 版本（灰底 + 白色选中胶囊）。
struct AppKitScheduleSegmented: View {
    static let contentHeight = ScheduleSegmentedCanvas.preferredHeight
    let titles: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScheduleSegmentedDrawing(titles: titles, selectedIndex: selectedIndex)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                HStack(spacing: 3) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        Button { onSelect(index) } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(title)
                        .accessibilityValue(index == selectedIndex ? "已选择" : "未选择")
                        .accessibilityIdentifier("schedule-tab-\(index)")
                        .scheduleRenderAnchor(.option(title), label: title,
                                              active: index == selectedIndex)
                    }
                }
                .padding(.horizontal, 3)
                .frame(height: 18)
            }
            .frame(height: Self.contentHeight)
    }
}

private struct ScheduleSegmentedDrawing: NSViewRepresentable {
    let titles: [String]
    let selectedIndex: Int

    func makeNSView(context: Context) -> ScheduleSegmentedCanvas {
        let view = ScheduleSegmentedCanvas()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ScheduleSegmentedCanvas, context: Context) {
        apply(to: view)
        view.needsDisplay = true
    }

    private func apply(to view: ScheduleSegmentedCanvas) {
        view.titles = titles
        view.selectedIndex = selectedIndex
    }
}

final class ScheduleSegmentedCanvas: NSView {
    var titles: [String] = []
    var selectedIndex = 0

    private let padding: CGFloat = 3
    private let corner: CGFloat = 9
    static let preferredHeight: CGFloat = 30

    override var isFlipped: Bool { true }

    private var trackRect: NSRect {
        NSRect(x: 0, y: (bounds.height - 24) / 2, width: bounds.width, height: 24)
    }

    private func segmentRect(_ index: Int) -> NSRect {
        guard !titles.isEmpty else { return .zero }
        let gap: CGFloat = 3
        let width = (trackRect.width - padding * 2 - gap * CGFloat(titles.count - 1)) / CGFloat(titles.count)
        return NSRect(x: trackRect.minX + padding + CGFloat(index) * (width + gap),
                      y: trackRect.minY + padding,
                      width: width, height: trackRect.height - padding * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, !titles.isEmpty else { return }

        let track = NSBezierPath(roundedRect: trackRect, xRadius: corner, yRadius: corner)
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        track.fill()

        for (index, title) in titles.enumerated() {
            let rect = segmentRect(index)
            if index == selectedIndex {
                let capsule = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
                NSColor.controlBackgroundColor.setFill()
                capsule.fill()
            }
            let color = index == selectedIndex ? NSColor.labelColor : NSColor.secondaryLabelColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: color,
            ]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(
                in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                           width: size.width, height: size.height),
                withAttributes: attributes)
        }
    }

}

// MARK: - 快捷行

/// 日期面板快捷行（今天 / 明天 / 下周 / 周末）的 AppKit 版本。
struct AppKitScheduleShortcutRow: View {
    static let contentHeight = ScheduleShortcutCanvas.preferredHeight
    /// 0 = 今天，1 = 明天，7 = 下周，-1 = 周末。
    let onQuick: (Int) -> Void

    var body: some View {
        ScheduleShortcutDrawing()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                HStack(spacing: 0) {
                    shortcut("今天", value: 0)
                    shortcut("明天", value: 1)
                    shortcut("下周", value: 7)
                    shortcut("周末", value: -1)
                }
            }
            .frame(height: Self.contentHeight)
    }

    private func shortcut(_ title: String, value: Int) -> some View {
        Button { onQuick(value) } label: { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .help(title)
            .scheduleRenderAnchor(.shortcut(title), label: title)
    }
}

private struct ScheduleShortcutDrawing: NSViewRepresentable {
    func makeNSView(context: Context) -> ScheduleShortcutCanvas {
        ScheduleShortcutCanvas()
    }

    func updateNSView(_ view: ScheduleShortcutCanvas, context: Context) {
        view.needsDisplay = true
    }
}

final class ScheduleShortcutCanvas: NSView {
    private struct Item {
        let symbol: String
        let badge: String?
    }

    private let items: [Item] = [
        Item(symbol: "sun.max", badge: nil),
        Item(symbol: "sunrise", badge: nil),
        Item(symbol: "calendar", badge: "+7"),
        Item(symbol: "moon", badge: nil),
    ]

    static let preferredHeight: CGFloat = 26

    override var isFlipped: Bool { true }

    private var cellWidth: CGFloat { bounds.width / CGFloat(items.count) }

    private func itemRect(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * cellWidth, y: 0, width: cellWidth, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0 else { return }
        for (index, item) in items.enumerated() {
            let rect = itemRect(index)
            guard let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil) else {
                continue
            }
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let configured = image.withSymbolConfiguration(config) ?? image
            let tinted = configured.tinted(with: NSColor.secondaryLabelColor)
            let size = tinted.size
            tinted.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                   width: size.width, height: size.height))
            if let badge = item.badge {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                let badgeSize = (badge as NSString).size(withAttributes: attributes)
                (badge as NSString).draw(
                    in: NSRect(x: rect.midX + size.width / 2 - badgeSize.width + 4,
                               y: rect.midY - size.height / 2 - 2,
                               width: badgeSize.width, height: badgeSize.height),
                    withAttributes: attributes)
            }
        }
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
