# D8 Menu / Overlay 盘点

## 扫描结果

- 弹层 API 命中 34 次，分布在 18 个文件。
- 主要入口包括 `DesktopPopover`、Task Editor Popover、Persistent Toolbar、Context/More Menu、Slash Menu、Command Palette、Date/List/Tag/Priority/Reminder/Repeat Picker。
- `desktop_popover.dart` 已提供通用定位基础；问题集中在调用方的视觉、Focus Policy、尺寸和关闭规则。

## Overlay 族清单

| 族 | 主要文件 | 需要统一的维度 |
| --- | --- | --- |
| Context / More Menu | `task_context_menu_panel.dart`、`task_more_menu.dart` | 行高、分组 Divider、disabled/selected、子菜单箭头 |
| Slash / Command Menu | `task_slash_menu.dart`、`command_palette.dart` | 搜索、键盘选中、Focus、placement、滚动 |
| Formatting Toolbar | `task_editor_toolbar.dart`、`persistent_anchored_popover.dart` | 持久开关、锚点、Esc、selection 保留、surface |
| Property Picker | 日期、清单、标签、优先级、提醒、重复 Picker | 宽度、padding、空状态、selected、取消/确认 |
| Dialog / Panel | `settings_panel.dart`、`focus_timer_dialog.dart` | barrier、圆角、阴影、进入/退出、默认焦点 |

## D8 审计规则

- 定位统一从 `desktop_popover.dart` 走；组件不通过增加 z-index 解决层叠问题。
- Menu、Picker、Toolbar、Dialog 先分别定义 Surface Role，再共用圆角、阴影和键盘规则。
- `Esc` 顺序必须记录：子菜单/搜索状态 → 当前浮层 → 持久 Toolbar → Inspector/页面。
- Popover 打开和关闭不能意外夺走编辑器或输入框 Focus。

