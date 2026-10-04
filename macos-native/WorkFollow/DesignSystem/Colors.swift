import AppKit
import SwiftUI

enum WFColors {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let content = Color(nsColor: .textBackgroundColor)
    static let secondarySurface = Color(nsColor: .controlBackgroundColor)
    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.5)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.494, green: 0.533, blue: 1, alpha: 1)
            : NSColor(red: 0.357, green: 0.361, blue: 0.922, alpha: 1)
    })
    /// Hover emphasis used for time fragments in Flutter's smart Quick Add.
    static let accentHover = themed(rgb(0x4B4CD9), rgb(0x98A1FF))
    static let selection = accent.opacity(0.10)
    /// 第二栏（导航）与第三栏（任务/笔记列表）的**选中行底色**。滴答实测：导航栏
    /// 选中 `(241,241,241)`、任务行选中 `(242,242,242)`——同一档中性灰，取 `#F2F2F2`。
    ///
    /// 这两栏原来用 `selection`（accent 10% ≈ `(239,239,252)`），用户反馈"太显眼"，
    /// 要求照滴答改成灰。注意它比行分割线 `listRowSeparator`（`#F4F4F4`）只深 2 级
    /// ——滴答也是这样，靠"选中行不画分割线"才分得开（见 `ListRowDivider` 的调用点）。
    ///
    /// 其余地方（菜单、浮层候选、日历格、习惯打卡）继续用 `selection`：那里是
    /// 中性表面上的强调色，不是列表选中。深色未实测，取 `menuSelected` 同族的灰。
    static let listSelection = themed(rgb(0xF2F2F2), rgb(0x363A42))
    static let hover = Color.primary.opacity(0.04)

    /// Flutter `WorkFollowTheme` 的浅/深两套值，按当前外观取其一。日历与四象限
    /// 的过期红、节假日绿、控件描边都要和原版逐值一致，语义色（systemRed 之类）
    /// 在两种外观下换的是另一组值，所以这几个角色照抄原版的两个取值。
    private static func themed(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    private static func rgb(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha)
    }

    /// 控件描边（工具条胶囊、象限卡、星期表头细线）。比 `border` 重一档。
    static let borderStrong = themed(rgb(0xD3D5DC), rgb(0x4A505B))
    /// 过期日期与高优先级。
    static let danger = themed(rgb(0xFF4D4F), rgb(0xFF6868))
    /// 中优先级。
    static let warning = themed(rgb(0xA15C08), rgb(0xF2B84B))
    /// 优先级旗（滴答实测色,2026-10 截图取色):高 #FF393C、中 #FF8D29、
    /// 低=accent(#5B5CEB,与 accent 浅色值一致故不另立)。旗子是图形不是
    /// 文字,用饱和图形色;danger/warning 是文字语义色,饱和度不同,不混用。
    static let flagHigh = themed(rgb(0xFF393C), rgb(0xFF5B5E))
    static let flagMedium = themed(rgb(0xFF8D29), rgb(0xFFA14D))
    /// 批量瓦片图标色（滴答实测,2026-10 截图取色):完成/复制文本蓝 #4672FB、
    /// 置顶黄 #FFCC00、关联主任务/转换笔记绿 #04CF9C、创建副本青 #08C4EF。
    /// 滴答每个动作一个色,扫一眼可分辨;删除用红。
    static let tileBlue = themed(rgb(0x4672FB), rgb(0x6B8CFF))
    static let tileYellow = themed(rgb(0xF5B800), rgb(0xFFCC2E))
    static let tileGreen = themed(rgb(0x04CF9C), rgb(0x2BDDB0))
    static let tileCyan = themed(rgb(0x08C4EF), rgb(0x35D2FF))
    /// 列表行之间的细分割线。滴答实测 `#F4F4F4`（浅色）；深色取菜单分组线
    /// `menuDivider` 的同族值（未实测，按同层级推断）。
    ///
    /// 它取代了原来两栏各写各的两种线：任务列用 `hover`（4% 墨 ≈ #F5F5F5，
    /// 与滴答实测值几乎相同），笔记列用系统 `Divider()`（深一档，明显更重）。
    static let listRowSeparator = themed(rgb(0xF4F4F4), rgb(0x3A3E47))
    /// 节假日名与完成态。
    static let success = themed(rgb(0x237A57), rgb(0x5BCE91))
    /// 法定休息日（「休」）与调休上班日（「班」）徽标的底色。
    ///
    /// 滴答 2026-10 截图实测（2× 图取色）：休 `(94,203,149)`、班 `(238,122,118)`。
    /// 两者与 `success` 不同值——`success` 是**文字**语义色（浅色下压到 `#237A57`
    /// 才够黑够读），徽标是**实心圆上的白字**，底色必须够浅才衬得出白字。
    /// 同一个绿在两种用法下取两个明度是对的，混用会把其中一个做坏。
    ///
    /// 深色未实测，暂沿用同一值：徽标是实心圆 + 白字，两档底色在深底上依然可辨，
    /// 不凭猜另立一对深色值。
    ///
    /// ⚠️ **屏上会略浅于滴答，这是色彩管理、不是取错了值。** 2026-10-03 实测：
    /// 我们渲染成休 `(123,201,153)`、班 `(223,128,122)`，而滴答是 `(94,203,149)` /
    /// `(238,122,118)`（两张截图同为 Display 配置，比较成立）。原因是 `themed(rgb:)`
    /// 走 sRGB、由系统转到显示器色彩空间，而滴答的值本身就落在显示器空间里。
    /// 用 ImageCms 验过：sRGB `(94,203,149)` → Display `(123,201,153)`，与我们实测
    /// **逐值一致**；同一模型对 `accent` 蓝的预测 `(91,92,227)` 也与实测一致。
    /// 想要屏上逐值相同，源值要写反解后的 sRGB `(9,206,144)` / `(255,114,114)`。
    /// **没有那样做**：全工程的颜色（`flagHigh`、`tile*`、`danger`…）都是「截图实测值
    /// 直接当源值」，只把徽标反解会让它成为全app 最饱和的一块，与自己的色板冲突。
    /// 要改成屏上逐值对齐，就该整层一起改，不是单独改这一对。
    static let restDay = themed(rgb(0x5ECB95), rgb(0x5ECB95))
    static let makeupWorkday = themed(rgb(0xEE7A76), rgb(0xEE7A76))
    /// 徽标上的字。两档底色都够深，白字对比安全（同 `tooltipText` 的做法：
    /// 这种"切在实心块里的洞"不按底色算明度）。
    static let onWorkdayBadge = themed(rgb(0xFFFFFF), rgb(0xFFFFFF))
    /// 强调色的浅底（周视图卡片投放高亮、导航选中）。
    static let accentSoft = themed(rgb(0xEEF0FF), rgb(0x2D355C))
    /// 强调色最浅的一档（Flutter `accentFaint`）：只用在"这一行可以点"的悬停底色上，
    /// 比 `accentSoft` 再淡一档——它底下通常是内容而不是选中态。
    static let accentFaint = themed(rgb(0xF6F7FF), rgb(0x252B4A))
    /// 已勾选检查项的填充（原版 `documentChecklistFill`：浅色取次要墨色、深色取 borderStrong）。
    static let documentChecklistFill = themed(rgb(0x5D6B75), rgb(0x4A505B))
    /// 填充上的勾（原版 `documentChecklistCheck`：对比安全色）。
    static let documentChecklistCheck = themed(rgb(0xFFFFFF), rgb(0xEDEFF2))
    /// 列表行的 hover 底。四象限任务行与侧栏清单行共用。
    static let listRowHover = themed(rgb(0xF5F7F8), rgb(0x272B32))
    /// 菜单行的 hover 底（Flutter `menuSelected`）。刻意是中性灰而不是强调色：
    /// 菜单是中性表面，行不该在指针移过时"跳"一下——原版为此专门留了这个 token。
    static let menuSelected = themed(rgb(0xF6F6F6), rgb(0x363A42))
    /// 菜单内部的分组细线（Flutter `menuDivider`）。比 `border` 更弱：细线是分隔，
    /// 不是给菜单镶边。
    static let menuDivider = themed(rgb(0xF2F3F3), rgb(0x3A3E47))
    /// 下拉字段的底：日期浮层里的月/日/年。参考图里它是**中性浅灰、无描边**的字段，
    /// 与 `content` 的白底靠明度分开，不靠描边——所以不能拿 `border` 去凑。
    static let fieldFill = themed(rgb(0xF2F2F2), rgb(0x3A3E47))
    /// 画布：四象限棋盘背后的底色（Flutter `matrixBackdrop` 浅色取 neutral50，
    /// 深色取 canvas）。
    static let matrixBackdrop = themed(rgb(0xF7F8FA), rgb(0x1B1D22))
    /// 日历里"不属于本月"的日期格（Flutter `WorkFollowTheme.canvas`）。它比
    /// 页面底色的浅灰再深一档，日号退到三级墨色——两件事一起才说明这不属于本
    /// 月，只退墨色会让它看起来像被禁用。
    static let calendarCanvas = themed(rgb(0xF2F4F8), rgb(0x1B1D22))
    /// 完成任务的勾选框填充（Flutter `taskCompletedCheckbox`）。它是完成态四级
    /// 墨色里最浅的一档：勾是从 `content` 色切出来的，底越浅勾的对比也越弱，
    /// 两者必须同步移动。
    static let taskCompletedCheckbox = themed(rgb(0xE3E3E3), rgb(0x34383F))
    /// Completed rows leave the active workflow: independently toned roles,
    /// not an opacity applied to the entire interactive row.
    static let taskCompletedTitle = themed(rgb(0xA6A6A6), rgb(0xA0A0A0))
    static let taskCompletedPreview = themed(rgb(0xD0D0D0), rgb(0x858585))
    static let taskCompletedMetadata = themed(rgb(0xE0E0E0), rgb(0x707070))
    static let taskCompletedCount = themed(rgb(0xA6A6A6), rgb(0xA0A0A0))

    // MARK: 锚定浮层（日历/四象限的编辑器与新建卡）

    /// 浮层底色（Flutter `WorkFollowTheme.overlay`）。它比 `content` 深一档：
    /// 弹在内容之上的面要能和底下那一层分开，所以不取系统内容色。
    static let overlay = themed(rgb(0xFFFFFF), rgb(0x2A2D34))
    /// 浮层描边（Flutter `WorkFollowTheme.border`）。
    static let overlayBorder = themed(rgb(0xE6E7EB), rgb(0x30343D))
    /// 浮层阴影（Flutter `WorkFollowTheme.shadow`：浅色 8% 墨、深色 53% 黑）。
    static let overlayShadow = themed(rgb(0x161B2B, alpha: 0x14 / 255.0),
                                      rgb(0x000000, alpha: 0x88 / 255.0))
    /// 悬停提示的底与字（原版 `TooltipThemeData`：底取 `feedbackSurface`、字取
    /// `feedbackText`）。与结果 HUD 同一族的"浮在最上面的深色面"，两种外观同值。
    static let tooltipSurface = themed(rgb(0x2C2C2E), rgb(0x2C2C2E))
    static let tooltipText = themed(rgb(0xFFFFFF, alpha: 0xF5 / 255.0),
                                    rgb(0xFFFFFF, alpha: 0xF5 / 255.0))

    /// 浮层里的三级墨色（Flutter `textPrimary` / `textSecondary` / `textTertiary`）。
    /// 新建卡上的日期、清单与提示语用它们，和弹层底色成对出现。
    static let overlayText = themed(rgb(0x20272C), rgb(0xF4F5F7))
    static let overlaySecondaryText = themed(rgb(0x5D6B75), rgb(0xB8BEC9))
    static let overlayTertiaryText = themed(rgb(0x7F8D92), rgb(0x858D9A))
}
