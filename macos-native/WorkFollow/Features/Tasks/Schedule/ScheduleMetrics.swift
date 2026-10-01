import CoreGraphics

/// 日程浮层的统一尺寸契约（对齐滴答 `TaskScheduleMetrics`）。
///
/// 主面板始终260pt宽；高度由SchedulePopoverLayoutV2固定，属性子卡片不参与主布局。
enum ScheduleMetrics {
    /// 主面板宽（pt）。
    static let panelWidth: CGFloat = 260
    /// 主面板内容内边距。
    static let horizontalPadding: CGFloat = 14
    /// 属性行高（时间 / 提醒 / 重复 / 重复结束）。
    static let rowHeight: CGFloat = 30
    /// 展开、悬浮只改变外观，不改变属性行的列位置。
    static let propertyRowHorizontalPadding: CGFloat = 2
    /// 展开内容选项行高。
    static let optionRowHeight: CGFloat = 34
    /// 时间展开列表高（约 8 个半点选项）。
    static let timeOptionsHeight: CGFloat = 280
    /// 子卡片比主卡片每侧内收4pt，可覆盖主面板内容内边距。
    static let childInset: CGFloat = 4
    static let optionPanelWidth: CGFloat = panelWidth - childInset * 2
    static let childHorizontalOutset: CGFloat = horizontalPadding - childInset
}
