import Foundation

/// Task surface structure. Retain measured shell sizes until matched-size TickTick
/// reference renders establish replacements; do not infer sizes from resized images.
enum TaskInspectorMetrics {
    static let headerHeight: CGFloat = 58
    static let completionSize: CGFloat = 18
    static let footerHeight: CGFloat = 52
    static let horizontalPadding: CGFloat = 20
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
