# D5 Geometry 盘点与迁移

> 状态：已完成。D5 只收口组件宽高、最小/最大约束和命中区域；字体、颜色、图标、间距语义、圆角、阴影、动画与业务行为保持原有契约。

## 事实源

| 几何语义 | 唯一事实源 |
| --- | --- |
| 全局按钮、输入、命中区域、菜单与工具栏控制 | `WorkFollowMetrics` |
| 任务列表行、Checkbox、分组标题、列表 Pane | `TaskListMetrics` |
| 工作区导航 / 列表 / 详情宽度和响应式边界 | `WorkFollowLayout` |
| 编辑器工具栏与文档 Popover | `TaskEditorMetrics` |
| 日期、清单、标签、重复 Picker | `TaskPickerMetrics` |
| More / Context Menu | `TaskMenuMetrics` |
| Task Inspector | `TaskInspectorMetrics` |
| Schedule 面板 | `TaskScheduleMetrics` |
| Command Palette | `CommandPaletteMetrics` |
| Sidebar、Calendar、Board、Matrix、Notes、Settings、Home、Stats、Habits、Trash | 对应模块 Metrics |

## 本轮统一规则

### 全局控件

- 普通按钮与输入高度使用 `primaryButtonHeight` / `inputHeight`（36）。
- 紧凑按钮与紧凑菜单项使用 `compactButtonHeight` / `compactMenuRowHeight`（34）。
- 普通菜单行使用 `menuRowHeight`（40），Picker 行使用 `pickerRowHeight`（36）。
- 图标按钮命中区域使用 `iconHitTarget`（32）；工具栏控制槽使用 26×28。
- Divider 厚度保留 1px，并通过 `dividerThickness` 表达。

### 任务工作区

- 任务列表的原生行由 `TaskListMetrics.rowMinHeight`（当前 50）和 `checkboxSize`（当前 20）控制。
- Web 迁移契约中的 `WorkFollowLayout.taskRowComfortableHeight`（48）保留为独立响应式契约，不再作为原生列表的第二个行高来源。
- 导航、列表、详情 Pane 继续由 `WorkFollowLayout` 与 `TaskListMetrics.paneWidth` 决定；Today 的可拖拽宽度只在这些边界内变化。

### 编辑器、菜单和弹层

- Slash、A 工具栏、More、Context Menu、日期/清单/标签/重复 Picker 的宽度、最大高度、行高均改为命名 Metrics。
- 编辑器和笔记编辑器共用 `TaskEditorMetrics` 的工具栏尺寸；`TaskEditorPopoverStyle` 只保留兼容转发，不再保存第二份数值。
- Inspector 的 Header/Footer 最小高度和关系 Picker 约束集中在 `TaskInspectorMetrics`。

## 迁移的页面几何

以下页面的固定宽高已提升为模块角色，调用方保留原值，后续视觉轮次可以单独调整角色而不搜索散落数字：

- Sidebar：rail/footer/brand、文件夹更多命中区、清单颜色选择器与色块。
- Home：Quick Add、重复面板、回顾图标、任务完成框和小日历标记。
- Notes：索引宽度、Header、搜索槽、新建按钮、空状态和关联任务 Checkbox。
- Calendar：日期格、标记点、Agenda 面板。
- Board：窄列、列标记、卡片 Checkbox、关联内容宽度。
- Matrix：页面 Header 和新增任务面板。
- Settings、Stats、Habits、Trash、Focus Timer：窗口与图表/空状态几何。

## 扫描对比

| 项目 | D0 基线 | D5 结果 |
| --- | ---: | ---: |
| 数字 `width/minWidth/maxWidth` | 162 | 仍有少量模块内容宽度与技术边界；主要重复控件宽度已命名 |
| 数字 `height/minHeight/maxHeight` | 231 | 仍有 Divider、绘制 stroke、文档/Matrix 内容和并行任务组件；主要重复控件高度已命名 |
| 业务代码中的几何 Metrics 引用 | — | 覆盖全局控件、任务工作区、编辑器、Picker、菜单和主要页面 |

D5 不把所有数字强行消灭：内容最大宽度、图表尺寸、绘制用 stroke、1px Divider 和当前并行任务新增组件仍保留在白名单或其模块边界内。

## 例外白名单

- `height: 1` / `width: 1` 的 Divider、Border、VerticalDivider：属于表面边界，留给 D6。
- Quill 文档中的代码/图片/水平线和自定义绘制 stroke：属于内容渲染几何。
- Today 的响应式 clamp、编辑器 viewport 的动态约束：属于 Layout contract，不替换成固定值。
- Matrix、Feedback、Schedule Options 等并行任务新增文件：本轮保留其现有改动，下一次对应模块收口时迁移。

## 验收

- `task_geometry_contract_test.dart` 锁定全局控件、任务 Pane、编辑器/Picker/Menu 和主要页面 Metrics。
- `git diff --check` 通过；Flutter 几何契约测试和全量测试通过后，进入 D6 Surface。
