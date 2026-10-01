import SwiftUI

enum WFType {
    static let pageTitle = Font.system(size: 19, weight: .semibold)
    static let detailTitle = Font.system(size: 18, weight: .semibold)
    static let navigation = Font.system(size: 14)
    static let listTitle = Font.system(size: 14)
    static let body = Font.system(size: 14)
    static let supporting = Font.system(size: 12)
    static let section = Font.system(size: 13, weight: .medium)

    // 对齐 Flutter `WorkFollowMacTypography` 的角色。这几个值不是新刻度，而是
    // 日历与四象限已经写在源码里的字号（12.5 的列表正文、12 的元信息、11 的
    // 说明、13 的控件字、13 半粗的分组标题），集中在这里以免同一页出现三种
    // 近似值。
    /// 列表正文：12.5，不是 13——它紧挨 14 的标题，取整会掉一整级。
    static let listBody = Font.system(size: 12.5, weight: .medium)
    static let completedListBody = Font.system(size: 12.5, weight: .regular)
    /// 行元信息与日历小条标题。
    static let listMeta = Font.system(size: 12)
    /// 说明性文字、日历条上的时刻、象限空态。
    static let caption = Font.system(size: 11)
    /// 工具条文字控件（月/周、今天）。
    static let control = Font.system(size: 13, weight: .medium)
    /// 分组标题：与 `section` 同字号，但半粗。
    static let sectionSemibold = Font.system(size: 13, weight: .semibold)
    /// 子任务行标题与「添加子任务」整行：原版两处都是 `listTitle`（14）配 `medium`，
    /// 比任务列表里的行标题（14 regular）重一档——层级靠字重，不靠颜色。
    static let listTitleMedium = Font.system(size: 14, weight: .medium)
    /// 命令/更多菜单的行文字（原版 `WorkFollowMacTypography.menu` = 14）。
    /// 不设字重时 SwiftUI 会用系统默认（约 13），菜单行会比原版小一档。
    static let menu = Font.system(size: 14)
    /// 12pt 但要用 medium 的元信息：快速输入行的日期摘要、批量操作条的计数
    /// （原版在 `supporting` / `listMeta` 上另配 `medium`）。
    static let metaMedium = Font.system(size: 12, weight: .medium)
}
