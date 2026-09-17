# D10 Light / Dark 盘点

## 扫描结果

- 明暗模式相关命中 32 次，分布在 10 个文件。
- 主要集中在 `sidebar.dart`、`workfollow_theme.dart`、`app.dart`、`settings_panel.dart`、`task_menu_style.dart`、`task_schedule_options.dart`、`command_palette.dart` 和文档样式。
- 主题定义本身的 `WorkFollowTheme` 已有 Light/Dark surface 和语义色；债务主要是组件绕过 Theme 的特殊分支。

## 明确复核面

| 区域 | 当前风险 | 目标 |
| --- | --- | --- |
| Sidebar | Light rail 有局部 hex，Dark 直接读 Theme | Light/Dark 都从 rail/navigation semantic surface 解析 |
| Task Menu | Light 复制一套颜色，Dark 返回 tokens | 菜单只消费同一套 Theme extension |
| Checklist | checked fill/check color 由组件明暗分支决定 | Document Style 只声明语义，Theme 提供对比度 |
| Schedule Picker | `#f6f6f6` 等浅色固定值 | input/menu surface role |
| Overlay | black/white 直接作为 barrier/前景 | overlay contrast role，保留必要反色例外 |

## D10 验收矩阵

逐页检查 Light + Dark：Today、Recent、Inbox、Plan、Task Detail、Notes、Calendar、Matrix、Board、Habits、Stats、Settings，以及 Slash、More、Context、日期、清单、标签、提醒和重复 Picker。

重点观察正文、标题、禁用态、边框、Popover、Selected、Checklist、Danger/Warning 和 Feedback HUD 的对比度与层级，不把“颜色反转”当作主题适配完成。

