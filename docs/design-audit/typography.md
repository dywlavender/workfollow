# D1 Typography 盘点

## 目标规范

macOS 桌面端只使用 `WorkFollowMacTypography` 语义角色。组件先声明“这段文字是什么”，再取字号、字重和行高；不要按局部视觉印象新增字号。

| 角色 | 当前规范 |
| --- | --- |
| 页面标题 | `pageTitle` 19 / semibold / `lineTight` |
| 分区标题 | `sectionTitle` 13 / semibold |
| 导航 | `navigation` 14 / regular / `lineControl` |
| 导航辅助 | `navigationMeta` 12 / regular |
| 任务标题 | `listTitle` 14 / regular / `lineList` |
| 任务预览 | `listBody` 12.5 / regular / `lineList` |
| 任务元数据 | `listMeta` 12 / regular |
| 详情标题 | `detailTitle` 18 / semibold / `lineControl` |
| 正文 | `body` 14 / regular / `lineBody` |
| 辅助文字 | `supporting` 12 / regular |
| 控件 | `control` 13 |
| 菜单 | `menu` 14 |
| Caption | `caption` 11 |
| 文档 H1/H2/H3 | 22 / 19 / 16，统一使用 `TaskDocumentStyles` |

字体族由系统解析，代码块使用 `SFMono-Regular` 与 `Menlo` fallback。中文默认字距为 0。

## 扫描结果

| 发现 | 数量 | 结论 |
| --- | ---: | --- |
| `TextStyle(...)` | 280 | 语法总量，不是违规数；大部分已使用语义 Token |
| 数字 `fontSize:` | 3 | 明确迁移候选 |
| `Theme.of(...).textTheme` | 8 | 需要改成明确的 macOS 语义角色，Quill 基础样式需保留上下文 |
| 数字 `fontWeight:` | 0 | 未发现直接 `FontWeight.w*` 字面量 |
| 字面 `fontFamily:` | 0 | 未发现固定字体族字面量 |
| 数字 `letterSpacing:` | 2 | 一个回收站标签、一个计时器显示值，需记录例外或迁移到 Display Role |
| 数字 `height:` | 215 | 混合了行高和布局高度，不能按计数直接替换 |

## 明确候选

| 文件 | 当前值 | 建议角色 | 备注 |
| --- | --- | --- | --- |
| `widgets/matrix/matrix_add_surface.dart:267` | `fontSize: 18` | `control` 或新增 Matrix Control Role | 先确认这是输入标题还是按钮文字 |
| `widgets/matrix/matrix_quadrant.dart:132` | `fontSize: 11` | `caption` 或 Matrix Quadrant Label Role | 与象限标题层级一起核对 |
| `widgets/sidebar.dart:542` | 隐藏输入 `fontSize: 1` | 允许的技术例外 | 用于隐藏搜索/输入承载，不参与视觉体系 |
| `widgets/task_inspector.dart` 等 8 处 | `Theme.of(...).textTheme` | 对应 `WorkFollowMacTypography` 角色 | D1 逐处确认，不能机械替换 Quill 编辑基线 |
| `screens/trash_screen.dart:118` | `letterSpacing: .45` | `caption` 的明确 tracking 角色 | 若为中文标签，应回到 `none` |
| `widgets/focus_timer_dialog.dart:87` | `letterSpacing: 1.2` | `WorkFollowMacDisplay.timer` 专属 | 计时器是允许的 Display 例外 |

## D1 规则

1. `WorkFollowMacTypography` 是桌面 UI 的唯一文字阶梯；`WorkFollowTypography` 仅是 Web catalog。
2. `WorkFollowMacDisplay.timer`、`slashHeading`、`slashHeadingIndex`、`slashOrderedNumeral` 是有记录的非正文显示例外。
3. `height` 只有在 `TextStyle` 中才属于行高；`SizedBox`、`Container` 等布局高度归 D5。
4. D1 不改颜色、padding、图标、圆角、阴影和布局。

