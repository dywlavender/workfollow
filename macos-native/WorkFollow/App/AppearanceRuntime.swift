import AppKit
import SwiftUI

extension NativeAppearance {
    /// 对应的 AppKit 外观。`.system` 返回 `nil`——语义是「不覆盖」，
    /// 回落到系统当前外观，这正是「跟随系统」应有的行为。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// 把「外观」偏好同步到 AppKit。
///
/// 只有 SwiftUI 的 `.preferredColorScheme` 是不够的：
///
/// - 它作用在 SwiftUI 视图树上，管不到 AppKit 自绘的部分（分隔线、滚动条、
///   `NSColor` 语义色、弹层的 `NSWindow`）；
/// - 更关键的是**切回「跟随系统」时它传 `nil`**，语义是「不覆盖」而不是
///   「改成系统当前值」。于是颜色回落到窗口 / App 的 `effectiveAppearance`，
///   而那一层如果停在旧值上，用户看到的就是「选浅色好使，改回跟随系统没反应，
///   得关掉设置窗或切一下窗口才刷新」——那两下操作碰巧让 AppKit 重算了外观。
///
/// 所以每次偏好变化都要显式落到 `NSApp.appearance`，并把**每个窗口和它的
/// contentView** 一起归位。注意必须无条件归位，不能因为
/// `window.appearance` 已经是目标值就跳过：上一轮留下的 `contentView.appearance`
/// 才是真正压住内容的那一层（标题栏跟着窗口变了，正文却没变）。
@MainActor
enum AppearanceRuntime {
    static func apply(_ appearance: NativeAppearance) {
        let app = NSApplication.shared
        let resolved = appearance.nsAppearance
        app.appearance = resolved
        for window in app.windows {
            window.appearance = resolved
            // contentView 必须单独归位：它是上一轮遗留覆盖的实际持有者，
            // 且窗口 appearance 变了不会自动把它重置成 nil。
            window.contentView?.appearance = resolved
            window.contentView?.needsDisplay = true
            window.invalidateShadow()
        }
    }
}
