import SwiftUI

/// 日历与四象限的几何与配色常量，数值逐条对齐 Flutter：
/// `CalendarMetrics` / `MatrixMetrics` / `WorkFollowColorTokens`（见
/// desktop/lib/theme/workfollow_theme.dart 与 workfollow_color_tokens.dart）。
///
/// 原生没有 theme 层，这一层就是这两页的量值契约——视图里不再出现裸数字，
/// 改动一个格宽只改一处。凡是本文件里的值都有一句说明它对应原版的哪一项。
enum WFCalendarMetrics {
    /// 顶栏：年月在左、控件在右。
    static let toolbarHeight: CGFloat = 52

    /// 工具条胶囊的高度（Flutter `WorkFollowMetrics.chipHeight`）。
    static let chipHeight: CGFloat = 30

    /// 网格上方 周日…周六 的表头。
    static let weekHeaderHeight: CGFloat = 32

    /// 日期号胶囊的直径。今天是它填色，其余是透底。
    static let dayCellSize: CGFloat = 24

    /// 格内到日期号与任务条的内边距。两者同一个值：条从号下面开始、铺满
    /// 格宽，任何一边单独改都会让另一边错位。
    static let cellHorizontalPadding: CGFloat = 3
    static let cellTopPadding: CGFloat = 3
    static let cellBottomPadding: CGFloat = 4

    /// 日期号与第一条任务条之间的距离。
    static let dayNumberGap: CGFloat = 2

    /// 表头文字距列左缘。表头是网格上方的一行字，不跟着格的 3pt。
    static let weekHeaderPadding: CGFloat = 8

    /// 一条任务条的高度，以及它与下一条之间的间距。
    ///
    /// 高度是**有意偏离原版**的一处：原版 17，按需求分两步放大——先 1.5 倍到 25.5，
    /// 再抬到 29（约原版的 1.7 倍）。步进 `slotStride` 由它推出，所以格内小条、跨天
    /// 色带的分道、格子的容量计算会一起跟着走，不需要第二处改动。
    static let taskBarHeight: CGFloat = 29
    static let taskBarGap: CGFloat = 2

    /// 条上的标题与时刻字号（原版分别是 `listMeta` 12 与 `caption` 11）。
    ///
    /// 条放高了以后字不跟着走会显得空，所以另立两个值而不是改 `WFType`：那两个是
    /// 列表元信息的角色，任务行、象限行也都在用，改角色会连带把别处放大。
    static let taskBarTitleFont = Font.system(size: 16)
    static let taskBarClockFont = Font.system(size: 14)

    /// 相邻条的步进。格内小条、跨天色带与溢出计数都用它定位，改一处必须三处一起看。
    static let slotStride: CGFloat = taskBarHeight + taskBarGap

    /// 条的圆角。跨天任务是一个整盒而不是若干相邻片段，所以这个圆角属于条
    /// 本身，不是两端的装饰。
    static let taskBarRadius: CGFloat = 3

    /// 日历条上的勾选框。比任务行的 14.58 小一号：它是一枚记号而不是一行控件，
    /// 跟着行高一起放会把条填满。
    ///
    /// 原版是 9.9（条高 17、标题 12 时的比例）。条高放到 29、标题放到 16 后，框按
    /// 同一节奏跟到 13.5——条与字都放大了、只有框不动，它会读成条上的一块小瑕疵。
    /// 要还原原值就改这一处。
    static let taskBarCheckboxSize: CGFloat = 13.5

    /// 勾选框命中区比方框本身每边多出来的宽度。方框是 13.5 的记号，直接拿它当按钮
    /// 太窄；外扩的部分由条的内边距让出来，框的落点与标题的起点都不动。
    static let taskBarCheckboxHitPadding: CGFloat = 3

    /// 未完成与已完成两档条底透明度。它们是一对：未完成离白的距离约为已完成
    /// 的三倍，只动一个等于让日历失去唯一的完成区分。
    static let taskBarFillAlpha: Double = 0.32
    static let taskBarCompletedFillAlpha: Double = 0.12
    static func taskBarFill(completed: Bool) -> Double {
        completed ? taskBarCompletedFillAlpha : taskBarFillAlpha
    }

    /// 周视图卡片里任务条的描边。月视图的条不描边——17pt 的条本身已有格线。
    static let taskBarBorderAlpha: Double = 0.34

    /// 拖动悬停时格的着色。
    static let dropHighlightAlpha: Double = 0.12

    /// 今天那一格的洗色，画在内容之上，跨过今天的色带也被它染一层。
    static let todayCellAlpha: Double = 0.05

    /// 工具条胶囊与周视图任务胶囊的圆角（Flutter `WorkFollowRadii.control`）。
    static let controlRadius: CGFloat = 7

    // 这里没有 Flutter 的 `viewModeMenuWidth`：月/周与日历设置走的是系统
    // `Menu`，宽度由系统决定，抄一个宽度进来是给一个不存在的量值立契约。
}

/// 四象限的几何。
enum WFMatrixMetrics {
    static let pageHeaderHeight: CGFloat = 56

    static let quadrantRadius: CGFloat = 12
    /// 象限标题前的序号圆点。
    static let quadrantHeaderMarkerSize: CGFloat = 22
    /// 清单分组行高。
    static let groupRowHeight: CGFloat = 34
    static let taskRowDividerHeight: CGFloat = 1
    /// 拖动预览卡片的宽度与圆角。
    static let taskRowDragPreviewWidth: CGFloat = 280
    static let taskRowDragPreviewRadius: CGFloat = 8
    /// 勾选框的点击区与绘制边长（后者即 completionBoxSize）。
    static let taskRowCheckboxHitTarget: CGFloat = 17.01
    static let taskRowCheckboxSize: CGFloat = 14.58
    /// 象限内的 hover 动作按钮边长，以及按钮里图标的字号
    /// （Flutter `size: 28` / `iconSize: WorkFollowMetrics.toolbarIcon`）。
    static let quadrantActionSize: CGFloat = 28
    static let quadrantActionIconSize: CGFloat = 18
    /// 象限卡内边距：上右下左（Flutter `relaxedGap / space3 / space3 / space2`）。
    static let quadrantPadding = EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 12)

    // 勾选框的圆角不在这里：`TaskCompletionBox` 按自身边长比例推出来
    // （边长 × 0.25），棋盘四周与象限之间的间距走 `WFSpace.cardInset` /
    // `WFSpace.control`。同一个数只留一处，第二处必然漂移。
}

/// 日历与四象限共用的滴答语义色（对齐 WorkFollowColorTokens）。
enum WFPlanningPalette {
    /// 四象限四个分类：macOS 系统红/黄/蓝/绿，浅色取值。
    static let quadrant: [Color] = [
        Color(red: 1.0, green: 0.231, blue: 0.188),   // Ⅰ 重要且紧急 #FF3B30
        Color(red: 1.0, green: 0.800, blue: 0.0),     // Ⅱ 重要不紧急 #FFCC00
        Color(red: 0.0, green: 0.478, blue: 1.0),     // Ⅲ 不重要但紧急 #007AFF
        Color(red: 0.204, green: 0.780, blue: 0.349), // Ⅳ 不重要不紧急 #34C759
    ]

    /// 清单色板的 SwiftUI 颜色（值见 WFListPalette.argb，与原版 14 色同表）。
    static func swatch(at index: Int) -> Color {
        let clamped = min(max(index, 0), WFListPalette.argb.count - 1)
        return WFListPalette.swatch(WFListPalette.argb[clamped])
    }

    /// 清单在当前工作区里的最终颜色：显式选色优先，否则按清单名稳定折叠。
    /// 日历条、象限行的清单名与侧栏圆点因此永远同色。
    static func listColor(name: String, meta: TaskListMeta?) -> Color {
        WFListPalette.color(for: name, meta: meta)
    }

    /// 序号圆上文字的颜色。它是切在实心圆里的一个洞，不是一行字，所以原版
    /// 给的是固定的白（`WorkFollowThemeContrast.markerForeground`），不按底色
    /// 算明度——黄色圆上的白字正是参考图里的样子。
    static let markerForeground = Color.white
}
