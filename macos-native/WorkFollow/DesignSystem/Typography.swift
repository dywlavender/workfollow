import SwiftUI

/// 字号/字重按滴答 macOS 8.0.80 运行时实测（2026-10-29）对齐：
/// 页面标题 20 Medium、任务标题 14 Regular、正文预览 12 Regular、
/// 行元信息 10、列表分组 14 Demi、侧栏分组 12 Medium、侧栏计数 10。
enum WFType {
    static let pageTitle = Font.system(size: 20, weight: .medium)
    static let taskListPageTitle = Font.system(size: 20, weight: .medium)
    static let detailTitle = Font.system(size: 18, weight: .semibold)
    /// 任务详情标题输入框（滴答富文本导出 `\fs38` = 19pt Medium，2026-10-16）。
    static let taskTitle = Font.system(size: 19, weight: .medium)
    static let navigation = Font.system(size: 14)
    static let listTitle = Font.system(size: 14)
    static let body = Font.system(size: 14)
    static let supporting = Font.system(size: 12)
    static let section = Font.system(size: 13, weight: .medium)

    /// 看板卡标题、时间轴、日历日号等次级列表正文。
    static let listBody = Font.system(size: 12.5, weight: .medium)
    /// 任务行正文预览：滴答 12pt Regular。
    static let taskPreview = Font.system(size: 12)
    static let completedTaskPreview = Font.system(size: 12)
    /// 日历小条标题等次级列表文字。
    static let listMeta = Font.system(size: 12)
    /// 任务行右侧元信息（清单名、日期、图标）：滴答 10pt Regular。
    static let taskMeta = Font.system(size: 10)
    /// 说明性文字、日历条上的时刻、象限空态。
    static let caption = Font.system(size: 11)
    /// 工具条文字控件（月/周、今天）。
    static let control = Font.system(size: 13, weight: .medium)
    /// 弹层与表单的常规标签：日期面板、检查项提醒、显示设置等。
    static let controlLabel = Font.system(size: 13)
    /// 弹层分区标题、面板名称。
    static let controlLabelStrong = Font.system(size: 13, weight: .semibold)
    /// 紧凑标题：显示设置卡片、AI 面板待办计数。
    static let captionStrong = Font.system(size: 12, weight: .semibold)
    /// 数字角标：评论数、同步问题数、菜单偏移量。
    static let badgeStrong = Font.system(size: 10, weight: .semibold)
    /// 极小计数角标：评论数、同步问题数。
    static let badgeSmall = Font.system(size: 9, weight: .semibold)
    /// 设置页与统计页的强调页面标题。
    static let pageTitleStrong = Font.system(size: 20, weight: .semibold)
    /// 显示设置的分节标题。
    static let groupTitle = Font.system(size: 15, weight: .semibold)
    /// 专注页任务标题与节奏行等较大正文。
    static let bodyLarge = Font.system(size: 15)
    /// 专注设置行标题与时长输入。
    static let controlLarge = Font.system(size: 16, weight: .medium)
    /// 专注笔记等分栏面板标题。
    static let paneTitle = Font.system(size: 17, weight: .semibold)
    /// AI 面板紧凑操作文字。
    /// 紧凑字号的数值，供需要同尺寸不同字重的地方复用（避免再写裸 10.5）。
    static let compactSize: CGFloat = 10.5
    static let compact = Font.system(size: compactSize)
    /// AI 面板最小说明与来源。
    static let compactCaption = Font.system(size: 9.5)
    /// AI 面板最小注释文字。
    static let compactFine = Font.system(size: 9)
    /// AI 面板紧凑强调文字。
    static let compactStrong = Font.system(size: 11, weight: .medium)
    /// 对话框正文。
    static let dialogBody = Font.system(size: 12.5)
    /// 对话框按钮文字。
    static let dialogAction = Font.system(size: 12.5, weight: .medium)
    /// 任务列表分组标题：滴答 14pt Demi。
    static let sectionSemibold = Font.system(size: 14, weight: .semibold)
    static let listTitleMedium = Font.system(size: 14, weight: .medium)
    static let menu = Font.system(size: 14)
    static let metaMedium = Font.system(size: 12, weight: .medium)

    /// 侧栏“清单/过滤器/标签”分组：滴答 12pt Medium + 弱灰。
    static let sidebarSection = Font.system(size: 12, weight: .medium)
    /// 侧栏计数：滴答 10pt Regular。
    static let sidebarBadge = Font.system(size: 10)
    /// 列表分组计数：滴答 12pt Regular。
    static let groupCount = Font.system(size: 12)
    /// 空状态文案：滴答 13pt Regular。
    static let emptyState = Font.system(size: 13)

    // 专注统计（滴答实测：标签 12 Medium、数字 SF Rounded 24）。
    static let focusStatLabel = Font.system(size: 12, weight: .medium)
    static let focusStatValue = Font.system(size: 24, weight: .regular, design: .rounded)
}
