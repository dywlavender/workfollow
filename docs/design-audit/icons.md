# D2 Icons 盘点

## 目标规范

UI 组件消费 `WorkFollowIcons` 语义映射，并按组件角色使用 `WorkFollowMetrics` 的尺寸：Rail 22、Navigation 20、Header 20、Toolbar 18、Field 20、Compact Field 17、Metadata 15。D2 只迁移图标来源和语义，不改按钮尺寸或颜色。

## 扫描结果

- `WorkFollowIcons` 定义集中在 [`workfollow_icons.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_icons.dart)。
- 主题外直接使用 `Icons.*` 共 9 次，分布在 4 个文件。
- 未发现 `CupertinoIcons.*` 直接使用。

## 明确候选

| 文件 | 当前 glyph | 建议动作 |
| --- | --- | --- |
| `widgets/task_editor_toolbar.dart:197` | `Icons.history` | 增加明确的 `history` 语义映射，或确认应使用已有 `historyToggle` |
| `widgets/task_editor_toolbar.dart:318` | `Icons.check` | 使用 `WorkFollowIcons.check` |
| `widgets/task_context_menu_panel.dart:170` | `Icons.wb_twilight_outlined` | 使用已有 `tomorrow` 或补充“明早/明天”专属语义，不能凭外观复用 |
| `widgets/task_schedule_panel.dart:281` | `Icons.chevron_left` | 使用 `collapse` 或补充 `chevronPrevious` |
| `widgets/task_schedule_panel.dart:287` | `Icons.circle_outlined` | 使用已有 `circle` |
| `widgets/task_schedule_panel.dart:293` | `Icons.chevron_right` | 使用已有 `chevronNext` |
| `widgets/task_schedule_panel.dart:557` | `Icons.chevron_right` | 使用已有 `chevronNext` |
| `widgets/task_schedule_options.dart:170` | `Icons.keyboard_arrow_down` | 使用 `expandMore` |
| `widgets/task_schedule_options.dart:170` | `Icons.close` | 使用 `close` |

## 已有映射中需要复核的重复语义

- `today` 与 `habitSun` 都使用太阳类 glyph，但语义分别是任务视图和习惯类型，保留前先确认是否应共享。
- `notes`、`summary` 使用相同 glyph；如果产品语义不同，D2 需要拆开命名或确认这是有意同形。
- `delete`、`trash`、`deleteForever` 已区分普通删除、回收站和永久删除，不能因为外观相近而合并。

## D2 规则

1. 先统一语义映射，再统一尺寸；不在 D2 调颜色、padding、按钮高和圆角。
2. 文字 glyph（例如 `H1`、`B`、`1.`）和真正图标分开记录，不强行替换成相似 Material 图标。
3. 直接 `Icons.*` 只有在绘制层、测试夹具或确实没有产品语义的临时 glyph 中才能保留，并须在 D2 记录原因。

## D2 状态

D2 迁移已完成，详细变更、白名单和验收结果见 [`d2-icons.md`](d2-icons.md)。业务组件中的直接 `Icons.*` / `CupertinoIcons.*` 已清零，任务菜单动作已统一到 `WorkFollowIcons.taskAction()`。
