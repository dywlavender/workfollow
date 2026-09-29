import CoreGraphics

/// 日程浮层的统一尺寸契约（对齐滴答 `TaskScheduleMetrics`）。
///
/// 主面板 260pt 宽 × ~507pt 高（开启重复时 +30pt，出现「重复结束」行）；
/// 打开「时间 / 提醒 / 重复 / 重复结束」子浮层时**主面板尺寸绝不变**（硬契约）。
enum ScheduleMetrics {
    /// 主面板宽（pt）。
    static let panelWidth: CGFloat = 260
    /// 主面板内容内边距。
    static let horizontalPadding: CGFloat = 14
    /// 属性行高（时间 / 提醒 / 重复 / 重复结束）。
    static let rowHeight: CGFloat = 30
    /// 子浮层选项行高。
    static let optionRowHeight: CGFloat = 34
    /// 时间子浮层列表高（约 8 个半点选项）。
    static let timeOptionsHeight: CGFloat = 280
    /// 子浮层宽 = 主面板内容宽（260 − 2×14）。
    static let optionPanelWidth: CGFloat = panelWidth - horizontalPadding * 2
}
