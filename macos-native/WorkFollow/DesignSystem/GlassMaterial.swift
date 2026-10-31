import AppKit
import SwiftUI

/// 窗口材质。经典模式完全沿用原来的实色/主题表面；液态玻璃只在 macOS 26+
/// 真正生效，旧系统和「降低透明度」都自动回退到经典底色。
enum WFAppearanceMaterial: String, CaseIterable, Identifiable {
    case classic
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "经典"
        case .liquidGlass: return "液态玻璃"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "当前的主题底色与不透明卡片"
        case .liquidGlass: return "系统玻璃材质，适合导航与浮层"
        }
    }

    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

enum WFGlassSupport {
    static func isActive(_ material: WFAppearanceMaterial,
                         reduceTransparency: Bool) -> Bool {
        guard material == .liquidGlass, !reduceTransparency else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }

    @MainActor
    static var systemReduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

private struct WFAppearanceMaterialKey: EnvironmentKey {
    static let defaultValue = WFAppearanceMaterial.classic
}

extension EnvironmentValues {
    var workfollowMaterial: WFAppearanceMaterial {
        get { self[WFAppearanceMaterialKey.self] }
        set { self[WFAppearanceMaterialKey.self] = newValue }
    }
}

/// 玻璃/实色二选一的背景层。`fallback` 在经典模式、旧系统和降低透明度时使用。
struct WFGlassSurface<Shape: SwiftUI.Shape>: View {
    var shape: Shape
    var fallback: Color
    var tint: Color? = nil
    var interactive: Bool = false

    @Environment(\.workfollowMaterial) private var material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *),
           WFGlassSupport.isActive(material,
                                   reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency) {
            Color.clear
                .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            shape.fill(fallback)
        }
    }
}

extension View {
    func wfGlassSurface<S: SwiftUI.Shape>(_ shape: S,
                                          fallback: Color,
                                          tint: Color? = nil,
                                          interactive: Bool = false) -> some View {
        background {
            WFGlassSurface(shape: shape, fallback: fallback, tint: tint, interactive: interactive)
        }
    }
}

/// 一组相邻的浮动控件共用一块玻璃；经典模式只保留原有排列，不改变间距。
struct WFGlassControlGroup<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    @Environment(\.workfollowMaterial) private var material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *),
           WFGlassSupport.isActive(material,
                                   reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency) {
            HStack(spacing: spacing) { content }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            HStack(spacing: spacing) { content }
        }
    }
}
