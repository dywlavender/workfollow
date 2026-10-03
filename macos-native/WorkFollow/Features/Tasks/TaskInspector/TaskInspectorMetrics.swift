import Foundation

/// Task surface structure. Retain measured shell sizes until matched-size TickTick
/// reference renders establish replacements; do not infer sizes from resized images.
enum TaskInspectorMetrics {
    static let headerHeight: CGFloat = 58
    static let completionSize: CGFloat = 15
    static let footerHeight: CGFloat = 52
    /// 内容原点距 Inspector 左缘的基准（规范：`task-inspector-content-alignment.md`）。
    /// 注意两条线的差别：本值是**内容原点**的距离；可见分栏线在内容原点外约 1pt，
    /// 因此"距分栏线"的实测值约为 21pt。
    static let horizontalPadding: CGFloat = 20
    static let titleTopPadding: CGFloat = 20
    static let titleDocumentGap: CGFloat = 10
    // NSTextContainer's default fragment padding is additional to the host inset.
    // Compensate at the Task boundary; leave Note/TextKit layout unchanged.
    static let documentFragmentPadding: CGFloat = 5
    static var documentLeadingPadding: CGFloat { horizontalPadding - documentFragmentPadding }
    static let headerDividerWidth: CGFloat = 1
    static let headerDividerHeight: CGFloat = 20
    static let breadcrumbHeight: CGFloat = 30
    static let childRowMinHeight: CGFloat = 42
    static let childRowRadius: CGFloat = 8
    static let childRowHorizontalPadding: CGFloat = 12
    static let childCompletionSize: CGFloat = 16
    static let childAddGap: CGFloat = 6
    static let childRowGap: CGFloat = 6
    static let childSectionTopGap: CGFloat = 20
    static var footerOverlayInset: CGFloat { footerHeight + 4 }
}
