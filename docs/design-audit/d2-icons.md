# D2 图标体系迁移报告

## 迁移前清单

在 `desktop/lib/**/*.dart` 中扫描到：

- 业务组件直接使用 `Icons.*` 9 次，集中在 Toolbar、任务上下文菜单、日期面板和 Schedule Options。
- 直接使用 `CupertinoIcons.*` 0 次。
- `TaskContextMenuPanel` 和 `TaskMoreMenu` 各自维护了一套任务动作 glyph switch；同一动作在两个入口可能出现不同图标。
- Toolbar、Picker、Schedule 和 Matrix 中有若干 `18/19/23` 的图标尺寸字面量；这些值与现有 Rail、Navigation、Header、Toolbar、Field、Compact Field、Metadata 角色没有绑定。

## 迁移结果

| 区域 | 改动 |
| --- | --- |
| 语义词汇 | `WorkFollowIcons` 新增 `insertTime`、`tomorrow`、`chevronPrevious`，并统一 add/more/back/check/chevron glyph；close 保留现有 glyph 以维持 Quick Add 的输入芯片自动化契约。 |
| 任务菜单 | 新增 `WorkFollowIcons.taskAction()`；Context Menu 和 More Menu 共用同一套动作图标来源。 |
| 日期导航 | Toolbar、Calendar、Date Picker、Schedule Panel 使用 `chevronPrevious` / `chevronNext`，不再直接写 Material glyph。 |
| 编辑器 | 当前时间、选中标记和附件使用语义图标；格式化 glyph 仍由专用绘制器负责。 |
| Picker | List Picker 改用 Inbox/List/Search/Check 语义图标；Tag Picker 和 Schedule Options 的图标尺寸归入共享 Metrics。 |
| 尺寸 | 业务图标尺寸改用 `WorkFollowMetrics` 角色；`TaskMenuStyle.iconSize` 和 `TaskEditorPopoverStyle.iconSize` 仅保留为兼容别名，不再被组件消费。 |

## 明确白名单

以下不是普通业务图标，不强行替换成 Material glyph：

- Slash Menu 的 `H₁/H₂/H₃`、项目符号、有序数字、检查项、引用线、分割线、子任务分支和关联图形。
- Toolbar/日期面板的 `TaskEditorGlyph` 专用格式与日期 glyph。
- Context Menu/Schedule 的日期快捷方式和优先级旗帜；它们需要绘制 `+7`、太阳/明日、清除日期和 filled priority 状态。
- Tag Picker 的空状态标签插画（60pt）。
- `WorkFollowIcons` 定义文件自身的 Material glyph 映射。

这些例外只改变图形来源，不允许在调用方重新定义同一产品语义。

## 迁移后静态结果

- `desktop/lib` 业务组件不再直接消费 `Icons.*` 或 `CupertinoIcons.*`。
- `iconSize:` 不再出现数字字面量；旧的公开尺寸名只转发到 `WorkFollowMetrics`。
- Task Context Menu 与 More Menu 的任务动作使用同一 `taskAction()` 映射。
- `undo / restore`、`delete / deleteForever`、`calendar / schedule / deadline` 继续保持独立语义。
- Light/Dark 不通过替换 glyph 解决可见性；颜色仍由现有 Theme tokens 决定，留待 D3。

## 验收

- `/`、A Toolbar、More、右键菜单的共享语义不再各自选择 glyph。
- Task List、Inspector、Calendar、Notes、Matrix 的业务图标都从 `WorkFollowIcons` 或登记的专用绘制器获取。
- D2 未修改字体、颜色、间距、按钮高度、圆角、边框、阴影、动画或业务动作。
