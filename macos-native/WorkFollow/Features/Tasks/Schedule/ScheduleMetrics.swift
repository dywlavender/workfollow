import CoreGraphics

/// 日程浮层的统一尺寸契约（对齐滴答 `TaskScheduleMetrics`）。
///
/// 主面板始终260pt宽；容器高度由 SchedulePopoverLayoutV2 固定，属性在内部滚动。
enum ScheduleMetrics {
    /// 主面板宽（pt）。
    static let panelWidth: CGFloat = 260
    /// 主面板内容内边距。
    static let horizontalPadding: CGFloat = 14
    /// 属性行高（时间 / 提醒 / 重复 / 重复结束）。
    static let rowHeight: CGFloat = 30
    /// 展开内容选项行高。
    static let optionRowHeight: CGFloat = 34
    /// 时间展开列表高（约 8 个半点选项）。
    static let timeOptionsHeight: CGFloat = 280
    /// 展开内容宽 = 主面板内容宽（260 − 2×14）。
    static let optionPanelWidth: CGFloat = panelWidth - horizontalPadding * 2
}
