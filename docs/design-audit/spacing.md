# D4 Spacing 盘点

## 目标规范

基础间距使用 `WorkFollowSpacing` 的 4 / 8 / 12 / 16 / 20 / 24 / 28 / 32 级。跨组件重复的局部值先提升为语义间距（例如 page gutter、menu padding、toolbar gap、inspector padding），不要在每个 Widget 中重新解释数字。

## 扫描结果

| 构造 | 命中数 | 说明 |
| --- | ---: | --- |
| `EdgeInsets.*` | 224 | 包含 Token 和局部数字 |
| `SizedBox` | 291 | 同时承载间距和固定尺寸，需结合 D5 区分 |
| `Padding` | 99 | 需要按页面/控件/菜单语义归类 |
| `gap` / `spacing` / `runSpacing` 等数字 | 40 | 重点检查 Wrap、Grid 和设置页 |

## 热点文件

| 文件 | EdgeInsets | SizedBox | 重点 |
| --- | ---: | ---: | --- |
| `widgets/sidebar.dart` | 18 | 12 | 导航列中有多套局部 padding 和小间距 |
| `widgets/settings_panel.dart` | 14 | 29 | 设置表单垂直节奏较多，需要语义化 |
| `screens/calendar_screen.dart` | 13 | 12 | 日历格子与日期 Picker 的间距混合 |
| `screens/notes_screen.dart` | 12 | 19 | 索引、详情和编辑器各自定义节奏 |
| `widgets/quick_add.dart` | 10 | 11 | 输入槽、token 和属性行需要分层 |
| `screens/board_screen.dart` | 9 | 12 | 卡片、列和任务行间距需要与任务列表对齐 |
| `screens/today_screen.dart` | 9 | — | 任务列表已经部分使用 `TaskListMetrics` |
| `widgets/task_inspector.dart` | 9 | — | 详情标题、正文和 footer 间距待收口 |

## 数字频率提示

在 spacing 构造中最常见的字面值是 8、10、12、18、6、14、16、4 和 9。4/8/12/16 已有 Primitive Token；10、14、18、9 等应先判断是否是控件专属值，不能在 D4 直接全局替换。

## D4 规则

1. `SizedBox(height: ...)` 若表达控件高度，归 D5；若只表达两个内容块之间的空白，归 D4。
2. 不为了一致性抹掉有意义的紧凑布局；先记录语义角色，再选择 Primitive 或新增 Semantic Alias。
3. D4 不改变字号、颜色、图标、圆角、阴影、动画和控件自身尺寸。

