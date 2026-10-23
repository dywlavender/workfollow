import Foundation

/// Task surface structure. 2026-10-17 同窗口 AX 实测校准（滴答 8.0.80 与本地同为
/// 1512×859、窗顶同为 y=33）：滴答内容区顶 96 / 底 843、标题 y=106、正文 y=145；
/// 本地据此把 Header/Footer/标题上边距调齐（正文 y 原本已一致）。不按缩放截图推断。
enum TaskInspectorMetrics {
    static let headerHeight: CGFloat = 62
    static let completionSize: CGFloat = 15
    static let footerHeight: CGFloat = 48
    /// 内容原点距 Inspector 左缘的基准（规范：`task-inspector-content-alignment.md`）。
    /// 注意两条线的差别：本值是**内容原点**的距离；可见分栏线在内容原点外约 1pt，
    /// 因此"距分栏线"的实测值约为 21pt。
    static let horizontalPadding: CGFloat = 20
    static let titleTopPadding: CGFloat = 10
    static let titleDocumentGap: CGFloat = 16
    // NSTextContainer's default fragment padding is additional to the host inset.
    // Compensate at the Task boundary; leave Note/TextKit layout unchanged.
    static let documentFragmentPadding: CGFloat = 5
    static var documentLeadingPadding: CGFloat { horizontalPadding - documentFragmentPadding }
    static let headerDividerWidth: CGFloat = 1
    static let headerDividerHeight: CGFloat = 20
    static let breadcrumbHeight: CGFloat = 30
    /// 滴答子任务行 AX 实测 ≈40（2026-10-16；原 42 为上一轮来源尺寸）。
    static let childRowMinHeight: CGFloat = 40
    /// 滴答子任务完成框 AX 实测 ≈19（2026-10-16）。
    static let childCompletionSize: CGFloat = 19
    static let childAddGap: CGFloat = 6
    static let childSectionTopGap: CGFloat = 20
    static var footerOverlayInset: CGFloat { footerHeight + 4 }

    // MARK: - 「更多」菜单几何（TI2-11 收尾）

    /// 菜单行高（`moreAction` 的 `minHeight`）。
    static let moreRowHeight: CGFloat = 32
    /// 行间距（`VStack(spacing: 2)`）。
    static let moreRowSpacing: CGFloat = 2
    /// 菜单内边距（`padding(8)`，上下各 8）。
    static let morePadding: CGFloat = 8
    /// 分组细线占用高度（含上下留白）：`Divider().padding(.vertical, 4)` ≈ 1 + 8。
    static let moreDividerHeight: CGFloat = 9

    /// 菜单高度按**实际行数**算，不再写死 490——写死会在加行后把底部项挤出可视区，
    /// 也会让短菜单留一大片空白。`screenHeight` 只用来夹到屏幕可用高度以内。
    static func moreMenuHeight(rowCount: Int, dividerCount: Int, screenHeight: CGFloat) -> CGFloat {
        let content = CGFloat(rowCount) * moreRowHeight
            + CGFloat(max(rowCount - 1, 0)) * moreRowSpacing
            + CGFloat(dividerCount) * moreDividerHeight
            + morePadding * 2
        return min(content, max(240, screenHeight - 2 * PopupMetrics.screenInset))
    }
}
