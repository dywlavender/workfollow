# D6 Surfaces 盘点

## 目标规范

所有背景、边框和阴影先归入 Surface 角色：页面、Rail、Navigation、List、Detail、Input、Dialog、Menu、Popover、Card、Pill。组件消费 Theme 和 Surface Token，不在局部同时叠加一套白底、边框和阴影。

## 扫描结果

| 构造 | 数量 | 重点 |
| --- | ---: | --- |
| `BoxDecoration` | 91 | 页面、卡片、Picker、菜单和任务行混合使用 |
| `BoxShadow` | 7 | 需要统一 blur、offset、alpha 和 Surface 角色 |
| `Border.*` | 27 | 需要区分结构边界、Focus Ring 和状态边框 |
| `BorderRadius.*` | 130 | 包含 Token 调用；29 个仍是数字字面值 |

## 阴影热点

| 文件 | 用途 |
| --- | --- |
| `features/feedback/feedback_toast.dart` | 全局反馈 HUD |
| `widgets/app_surfaces.dart` | 通用卡片 |
| `widgets/command_palette.dart` | 搜索/命令浮层 |
| `widgets/matrix/matrix_task_row.dart` | Matrix 卡片状态 |
| `widgets/persistent_anchored_popover.dart` | 编辑器持久浮层 |
| `widgets/quick_add.dart` | Quick Add 卡片 |
| `widgets/task_editor_popover.dart` | 编辑器 Popover |

## D6 规则

1. 圆角、边框、阴影一起描述一个 Surface 角色，但施工时保持改动可审查。
2. Popover、Dialog 和 Toast 的阴影不能由页面容器继承；它们属于独立浮层层级。
3. D6 不重新定义颜色、字体、间距、控件尺寸和动画时序。

