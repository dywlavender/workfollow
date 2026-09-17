# D1 Typography 迁移报告

## 范围

本轮只处理字体族、字号、字重、行高、字距和 Quill 文档字体。颜色、图标、间距、组件尺寸、圆角、边框、阴影、动画和布局没有作为 D1 目标修改。

## 迁移前清单

| 编号 | 位置 | 当前写法 | 目标 | 结果 |
| --- | --- | --- | --- | --- |
| TYPO-001 | `widgets/matrix/matrix_add_surface.dart:267` | `fontSize: 18` | `detailTitle` | migrated |
| TYPO-002 | `widgets/matrix/matrix_quadrant.dart:132` | `fontSize: 11` | `caption` | migrated |
| TYPO-003 | `widgets/sidebar.dart:542` | 隐藏输入 `fontSize: 1` | 技术例外 | accepted-exception |
| TYPO-004 | 8 处 Inspector/Editor/Popover `Theme.of(...).textTheme` | Material text theme | 明确 macOS 语义角色 | migrated |
| TYPO-005 | `screens/trash_screen.dart:118` | `letterSpacing: .45` | `WorkFollowMacTracking.none` | migrated |
| TYPO-006 | `widgets/focus_timer_dialog.dart:87` | `letterSpacing: 1.2` | `WorkFollowMacDisplay.timer` 专属显示例外 | accepted-exception |
| TYPO-007 | `widgets/task_menu_style.dart` | `fontSize = 15.0` | `WorkFollowMacTypography.menu` | migrated / constant removed |
| TYPO-008 | `widgets/task_editor_popover.dart` | 未使用 `fontSize = 14.0` | 无重复字体常量 | migrated / constant removed |

## 实际改动

- Task Editor 和 Note Editor 的 Quill base style 改为 `TaskDocumentStyles.body(tokens)`，不再从 `Theme.of(context).textTheme` 猜测正文。
- `TaskDocumentStyles` 为正文、H1/H2/H3、列表、检查项、引用和链接统一使用 macOS system cascade；代码块继续使用独立 monospace role。
- Toolbar、Inspector、Popover、Schedule Picker 和 Context Menu 的 Material `textTheme` 基线改为显式的 `WorkFollowMacTypography` + `WorkFollowMacWeight` + `WorkFollowMacTracking`。
- Matrix 输入标题和象限 numeral 的数字字号归入现有语义角色。
- Toolbar/菜单绘制的文字 glyph 补齐 PingFang fallback。

## 迁移后静态结果

在 `desktop/lib` 中：

- 数字 `fontSize` 只剩 Sidebar 隐藏输入白名单项。
- 数字 `letterSpacing` 只剩 Focus Timer display 白名单项。
- 未发现 `Theme.of(...).textTheme` 消费者。
- 未发现 macOS 组件使用 `WorkFollowTypography` Web catalog。
- 未发现直接 `FontWeight.w500/w600` 或固定字体族字面量。

`WorkFollowTypography` 仍保留在 `workfollow_theme.dart`，它是 Web 客户端 catalog；`WorkFollowThemeData` 只在非 macOS target 选择它，macOS 仍使用系统字体和 PingFang fallback。这部分是平台分支，不是桌面组件绕过。

## 验收

- Task / Notes / Calendar / Board / Matrix / Habits / Stats / Settings / Menu 的字号来源都归入 macOS 语义角色。
- Light/Dark 共用同一套字体 Token；明暗模式没有字体分支。
- Quill 的正文、标题、列表、检查项、引用、链接和代码样式都从 `TaskDocumentStyles` 获取字体属性。
