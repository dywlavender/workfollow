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
    /// 高度回到原版的 17。它曾被**有意放大**到 29（约原版的 1.7 倍），但那个尺寸在
    /// 真机上读起来"字大、条厚"，和滴答摆在一起明显不是一件东西；2026-10-03 照
    /// 参照图量回来：条高 34px（2× 图）= 17pt，条间距 4px = 2pt。
    ///
    /// 步进 `slotStride` 由它推出，所以格内小条、跨天色带的分道、格子的容量计算
    /// 会一起跟着走，不需要第二处改动。一格因此从装 3 条变成装 6 条。
    static let taskBarHeight: CGFloat = 17
    static let taskBarGap: CGFloat = 2

    /// 条上的标题与时刻字号。就是 `WFType` 里为它们准备好的那两个角色
    /// （`listMeta` 12 / `caption` 11）——曾为了配 29 的条高另立 16/14，现在条回到
    /// 17，字也回到角色本身，不再有"日历专用刻度"。
    ///
    /// 参照图实测（2× 图）：标题 CJK 墨迹高 21px、时刻数字墨迹高 16px；换算成
    /// system 字号分别是 ≈12 与 ≈11。
    static let taskBarTitleFont = WFType.listMeta
    static let taskBarClockFont = WFType.caption

    /// 相邻条的步进。格内小条、跨天色带与溢出计数都用它定位，改一处必须三处一起看。
    static let slotStride: CGFloat = taskBarHeight + taskBarGap

    /// 条的圆角。跨天任务是一个整盒而不是若干相邻片段，所以这个圆角属于条
    /// 本身，不是两端的装饰。参照图实测约 5px（2× 图）= 2.5pt，与 3 差半个
    /// 像素，没动。
    static let taskBarRadius: CGFloat = 3

    /// 日历条上的勾选框。参照图实测：外框 21×21px（2× 图）= 10.5pt，取 10。
    /// 原版是 9.9，两者同值——它一直就不该跟着条高放大。
    static let taskBarCheckboxSize: CGFloat = 10

    /// 勾选框命中区比方框本身每边多出来的宽度。方框是 10 的记号，直接拿它当按钮
    /// 太窄；外扩的部分由条的内边距让出来，框的落点与标题的起点都不动。
    static let taskBarCheckboxHitPadding: CGFloat = 3

    /// 未完成与已完成两档条底透明度。
    ///
    /// 这两档就是「未完成 / 已完成」本身，不是「强调 / 次要」。滴答把同一种清单色画在
    /// 两个透明度上，参照图实测 **未完成 ≈0.36、已完成 ≈0.12**——同色相的两档离白距离
    /// 正好是 1:3（蓝 0.34/0.33/0.33、橙 0.38/0.33/0.34、绿 0.33/0.32/0.34，三通道一致）。
    /// 交叉验证：全图 59 条里，实心勾选框（已完成）的 56 条标题全是浅灰墨，空心框
    /// （未完成）的 3 条标题全是深墨——两档与完成态一一对应。
    ///
    /// **我们有意比参照物淡一档：0.22 / 0.09，不是 0.36 / 0.12。** 理由是数据形态不同，
    /// 不是审美偏好：滴答那张参照图一格里最多 1 条强档 + 几条淡档，而我们的日历一格能
    /// 堆 5 条**同色**未完成（2026-10-03 实测：10月3日 一格 5 条，全是「收集箱」的蓝），
    /// 强档叠起来就是一整块实心蓝，压得整屏喘不过气。实测过：我们单条的颜色与几何尺寸
    /// 和滴答**逐项一致**（白底上未完成 (200,216,240) vs 滴答 (190,216,243)），所以问题
    /// 不在单条、在堆叠——只能靠整体降浓度解决。
    ///
    /// 比例仍是 2.4:1（原 2.67:1）：只动一个等于让日历失去唯一的完成区分，所以两个一起降。
    /// 再往下调要先确认已完成档还看得见——0.075 时已完成条基本消失在格底里了。
    static let taskBarFillAlpha: Double = 0.22
    static let taskBarCompletedFillAlpha: Double = 0.09
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
