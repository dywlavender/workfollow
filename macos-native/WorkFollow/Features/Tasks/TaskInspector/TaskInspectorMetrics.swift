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
    static let childRowRadius: CGFloat = 8
    static let childRowHorizontalPadding: CGFloat = 12
    /// 滴答子任务完成框 AX 实测 ≈19（2026-10-16）。
    static let childCompletionSize: CGFloat = 19
    static let childAddGap: CGFloat = 6
    static let childRowGap: CGFloat = 6
    static let childSectionTopGap: CGFloat = 20
    static var footerOverlayInset: CGFloat { footerHeight + 4 }
}
