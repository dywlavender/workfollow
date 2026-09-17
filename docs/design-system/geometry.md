# Geometry

全局控件几何来自 `WorkFollowMetrics`；任务列表、编辑器、Picker、菜单、Inspector、Sidebar、Calendar、Board、Matrix、Notes、Settings、Habits、Stats 和 Quick Add 使用各自模块 Metrics。

```text
WorkFollowMetrics
TaskListMetrics / TaskEditorMetrics / TaskPickerMetrics
TaskMenuMetrics / TaskInspectorMetrics / TaskScheduleMetrics
SidebarMetrics / CalendarMetrics / BoardMetrics / MatrixMetrics
NotesMetrics / SettingsMetrics / HabitsMetrics / StatsMetrics
```

响应式宽度和 min/max 约束属于 Layout contract。自定义绘制的 stroke、图表 cell、Quill embed 和 drag target 只有在 [Exceptions](exceptions.md) 中说明后才能保留局部几何值。
