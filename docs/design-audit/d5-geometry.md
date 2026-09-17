# D5 尺寸与几何迁移

> 状态：已完成。该轮只处理宽高、最小/最大约束和命中区域。

## 迁移摘要

- `WorkFollowMetrics` 增加输入、紧凑菜单、Picker、工具栏控制槽、Divider 和通用 Popover 角色。
- `TaskListMetrics` 继续负责原生 TaskRow（当前 50pt）与 Checkbox（当前 20pt）；`WorkFollowLayout` 负责导航、列表、详情 Pane 的响应式边界。
- 新增 `TaskEditorMetrics`、`TaskPickerMetrics`、`TaskMenuMetrics`、`TaskInspectorMetrics`、`TaskScheduleMetrics`、`CommandPaletteMetrics`。
- Sidebar、Home、Notes、Calendar、Board、Matrix、Settings、Stats、Habits、Trash、Focus Timer 的重复固定几何已提升为模块 Metrics。
- `TaskEditorPopoverStyle` 保留为兼容层，实际调用方读取统一的 `TaskEditorMetrics`。

## 迁移清单

| 区域 | 收口内容 | 事实源 |
| --- | --- | --- |
| Task Editor | heading/time/list/date/more Popover、工具栏、Picker 行 | `TaskEditorMetrics` |
| Task Menu | Context Menu 宽度、普通行、日期网格行 | `TaskMenuMetrics` + `WorkFollowMetrics` |
| Task Inspector | 关系 Picker、Header/Footer、标签宽度、Divider | `TaskInspectorMetrics` |
| Task Schedule | 面板上限、快捷日期、属性行、提醒/重复弹层 | `TaskScheduleMetrics` |
| Navigation | footer/rail/brand、颜色选择器、色块 | `SidebarMetrics` |
| Other Views | Home、Notes、Calendar、Board、Matrix、Settings、Stats、Habits、Trash | 对应模块 Metrics |

## 保留项

1px 边框、Quill 图片/代码/水平线、图表与 CustomPainter 的绘制参数、Today/Editor 的动态约束和并行任务新增文件属于明确例外，后续在 D6 或对应模块轮次复核。

## 验证

```text
flutter test test/task_geometry_contract_test.dart
flutter test
git diff --check
```

几何契约测试验证全局控件、TaskRow/Pane、编辑器/Picker/Menu 以及主要页面 Metrics 的委托关系。
