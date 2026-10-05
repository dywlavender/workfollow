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
    static var titleLeading: CGFloat { checkboxLeading + 18 + WFSpace.sm }
    static func dividerLeading(completed: Bool, depth: Int) -> CGFloat {
        completed ? titleLeading + CGFloat(depth) * hierarchyIndent : dividerLeading
    }
    /// 「倒数纪念日」小节里那行的高度。比任务行（`WFMetrics.rowHeight` = 50）矮一档：
    /// 任务行要容下副标题与日期，倒计时行只有图标 + 名称 + 右侧标签，没有第二行。
    static let countdownRowHeight: CGFloat = 36
    static let dragMarkerHeight: CGFloat = 1
    static let dragPreviewWidth: CGFloat = 360
}
