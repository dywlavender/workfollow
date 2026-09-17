# D5 Geometry 盘点

## 目标规范

控件尺寸、任务行、Checkbox、菜单行、Pane 和编辑器工具栏使用现有 `WorkFollowMetrics`、`TaskListMetrics`、`WorkFollowLayout`。页面不应为相同类型控件重新定义 42、44、48 等近似值。

## 扫描结果

| 构造 | 数量 | 判断 |
| --- | ---: | --- |
| 数字 `BorderRadius.*` | 29 | D6 也会消费，D5 只记录与几何相关的控件形状 |
| 数字 `width/minWidth/maxWidth` | 162 | 含 Divider、Icon、Pane 和内容宽度，需要按组件归类 |
| 数字 `height/minHeight/maxHeight` | 231 | 含行高、输入高度、弹窗高度和布局高度，需要按组件归类 |

## 已有统一值

- 通用按钮：`primaryButtonHeight` 36、`compactButtonHeight` 34、`chipHeight` 30。
- 菜单：`menuRowHeight` 40。
- 任务列表：`TaskListMetrics.rowMinHeight` 42、`checkboxSize` 18、`groupHeaderHeight` 30。
- 编辑器：`editorToolbarHeight` 42、Popover 的宽度和行高集中在 `TaskEditorPopoverStyle`。
- 页面布局：任务列表/详情 Pane 使用 `WorkFollowLayout` 和 `TaskListMetrics`。

## 原始数字热点

`screens/home_screen.dart`、`widgets/quick_add.dart`、`widgets/sidebar.dart`、`screens/habits_screen.dart`、`screens/board_screen.dart` 和 `screens/notes_screen.dart` 的宽高字面值最多。任务列表相关的新组件已经大部分使用 `TaskListMetrics`，其它页面需要在 D5 逐组件对齐。

## D5 规则

1. 先按控件类型建立 Geometry Spec，再迁移调用方；不要凭数字接近就合并。
2. `1` 像素 Divider、绘制 stroke、不可见输入承载和内容最大宽度可以是明确例外。
3. D5 不改变颜色、字号、间距语义、圆角、阴影和动画。

