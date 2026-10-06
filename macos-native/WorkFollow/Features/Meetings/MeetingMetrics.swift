import Foundation

/// 会议纪要页自己的几何值。
///
/// 与 `WFCalendarMetrics` 同一个做法：**这一页专属、别处用不到的**尺寸放在
/// feature 目录里，而不是塞进全局 `WFMetrics`——全局那份是任务列/笔记列/检查器
/// 共用的口径，往里加会议专属的值会让「改一处影响哪些页」变得说不清。
///
/// 与其它页共用的值（列宽、行高、分割线、圆角）仍然从 `WFMetrics` 取，不在这里重复。
enum MeetingMetrics {
    /// 详情栏内部再分左右两栏的门槛。
    ///
    /// 两侧各约 320pt 才排得下：转写栏扣掉左右内边距 24、时间列 34、说话人列 46、
    /// 两个列间距 16，正文只剩约 200pt；再窄就一行放不下几个字，不如改成上下分。
    /// 默认窗口 1280 时详情栏是 `1280 − 62(图标栏) − 340(列表) − 1(分割线) = 877`，
    /// 远在门槛之上，所以默认就是左右并排。
    static let splitMinimum: CGFloat = 640

    /// 拖动分割线时两侧各自的最小占比。
    ///
    /// 留 28% 而不是 20%：再窄的那一侧表头（「对话记录」+ 进度）就换行了，
    /// 拖到极值时界面会突然跳一下。
    static let minFraction: CGFloat = 0.28
    static let maxFraction: CGFloat = 0.72

    /// 两栏各自的表头 / 底部操作行高度。与列表列的头部 44 分开算——
    /// 那一条横跨整页，这两条只在自己栏内。
    static let columnHeaderHeight: CGFloat = 30
    static let columnFooterHeight: CGFloat = 38

    /// 转写行的两个固定列宽。时间列按 `0:00` 的最宽形（四位数字）给，
    /// 说话人列按四个汉字给——超出就截断，不换行，否则一行的行高会被最长的名字带跑。
    static let timeColumn: CGFloat = 34
    static let speakerColumn: CGFloat = 46

    /// 底栏「记录者」输入框的宽度。四个汉字 + 内边距。
    static let speakerField: CGFloat = 56
}
