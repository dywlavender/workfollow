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

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        button.contentTintColor = tint
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityRole(.button)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
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
        let button = NSButton()
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
        button.toolTip = accessibilityLabel
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
        let button = NSButton()
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
        button.toolTip = accessibilityLabel
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
