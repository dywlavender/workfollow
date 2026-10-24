import SwiftUI

/// 快速添加条（待办输入框）的**唯一**视觉真源。列表条（今天/收集箱/最近 7 天/
/// 各清单）与全局快速添加面板共用这一份参数，改样式只动这里，不做第二份。
///
/// 基准是滴答实测截图与 Flutter `quick_add.dart` 的迁移值：
/// - 前导加号小而浅（SF 的 `plus` 会撑满字框，比 Flutter 的 Material add 显得
///   大一号，所以这里取 13，视觉才与滴答应齐）；
/// - 占位符与「⌘N」角标同用中浅灰（Flutter `hintStyle = textTertiary`）；
/// - 未选中底色是带一点蓝调的极浅灰（Flutter `tokens.canvas` = 0xFFF2F4F8），
///   比中性的 hover 灰更接近滴答那条“浅浅的输入位”；
/// - 选中后仍是窗口底色 + 「今天」同款强调色描边（两态语义不变）。
enum QuickAddBarStyle {
    /// 前导加号字号（视觉 ~10pt 的线宽）。
    static let iconSize: CGFloat = 13
    static let iconColor = WFColors.secondaryText
    /// 全局面板的前导加号走强调色（Flutter 非列表样式用 accent）。
    static let panelIconColor = WFColors.accent
    /// 占位符颜色（映射到 NSTextField 的 secondaryLabel，≈ 0x7F8D92）。
    static let placeholderNSColor = NSColor.secondaryLabelColor
    /// SwiftUI 侧的同一份占位符灰（小卡/看板添加卡的 `TextField` prompt 用）。
    static let placeholderColor = WFColors.secondaryText
    /// 「⌘N」角标比占位符再退半档。
    static let shortcutColor = WFColors.tertiaryText
    /// 未选中的条底。
    static let idleFill = WFColors.quickAddIdleFill
}
