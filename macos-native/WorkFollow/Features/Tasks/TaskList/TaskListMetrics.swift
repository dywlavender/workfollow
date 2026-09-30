import Foundation

/// Flutter TaskListMetrics: list-specific geometry, independent of global controls.
enum TaskListMetrics {
    static let groupTopGap: CGFloat = 18
    static let groupHeaderHeight: CGFloat = 30
    static let groupChevronSize: CGFloat = 11
    static let quickAddHeight: CGFloat = 42
    static let quickAddRadius: CGFloat = 10
    static let hierarchyIndent: CGFloat = 24
    static let disclosureWidth: CGFloat = 22
    static let disclosureTitleGap: CGFloat = 2
    static let rowHorizontalPadding: CGFloat = 8
    static var checkboxLeading: CGFloat { rowHorizontalPadding + disclosureWidth + disclosureTitleGap }
    // Keep every divider just left of the root checkbox column, including child rows.
    static var dividerLeading: CGFloat { checkboxLeading - disclosureTitleGap }
    static let dragMarkerHeight: CGFloat = 3
    static let dragPreviewWidth: CGFloat = 360
}
