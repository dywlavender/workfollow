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
    static let dragPreviewMaxWidth: CGFloat = 220

    /// 任务行里最多平铺几个标签胶囊（其余折成「+N」），避免行被撑爆。
    static let maxVisibleTags = 3

    /// 任务行高度：标题行固定，预览行与标签行各占一档（滴答的行会随之变高）。
    /// 行高必须由这里给出确定值——`NSOutlineView` 的 `heightOfRowByItem` 不能反查
    /// SwiftUI 的 fittingSize（cell 高度与内容高度会互相依赖）。
    static func taskRowHeight(hasPreview: Bool, hasTags: Bool) -> CGFloat {
        var content: CGFloat = 18                     // 标题行
        if hasPreview { content += 1 + 17 }           // 预览行（spacing + 行高）
        if hasTags { content += 4 + 22 }              // 标签胶囊行
        return max(WFMetrics.rowHeight, content + WFMetrics.rowVerticalPadding * 2)
    }
}
