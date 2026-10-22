# 弹框一致性审计与规范草案

日期：2026-10-22。范围：`experiment/macos-native` 初审时的 macOS 源码快照。

后续已开始按本审计改造，最新实施范围和验证结果见 [弹框规范实施计划](popup-standardization-plan-2026-10-22.md)。下文问题描述与次数保留初审口径，不应直接解释为改造后的缺陷。

## 判断与证据范围

需要按用途统一弹框规范。现有共用呈现底座已经覆盖主要任务入口，本轮应补齐使用规则、视觉规格和接入检查，继续复用已有定位与键盘路由。不同用途应保留恰当的尺寸、提交方式和模态程度。

初审为代码审计与规范草案，未逐一操作全部日用窗口，也没有将以下风险认定为已实机复现的故障；初审阶段仅新增这份文档。后续实施另见上方计划。

2026-10-01 的 `native-popup-architecture-audit.md` 已提出分类合同；后续共享 NSPanel、Escape 路由及多批迁移已有实现。该历史文档中“任务详情仍用内部 Overlay”等现状描述已过期，不能作为当前缺陷直接重报。本次以当前代码重新核对。

## 当前底座与盘点口径

- `Infrastructure/Presentation/AnchoredPropertyPanel.swift`：无箭头子面板、锚点定位、父子窗口、按需构建内容、屏幕边缘避让和关闭清理。
- `Infrastructure/Presentation/PopupEscapeRouter.swift`：跨面板的外部点击、窗口家族与 Escape 路由；已有输入法候选优先、系统模态优先、最深子窗口先处理的逻辑。
- `Features/Tasks/Schedule/SchedulePopoverModifier.swift`：统一日程入口，使用真实触发控件或显式鼠标锚点。
- `SummaryPopoverMetrics`、`ScheduleMetrics`、`WFPlanningOverlayMetrics`：已有分类尺寸来源，尚不是覆盖所有功能的规范。

下面是静态 API 使用次数，包含可复用入口、底层构造和菜单栏菜单；同一用户弹框可能经过多层，因此不能相加解释为独立弹框数量。另有自绘 Overlay 与自定义 NSPanel 子类，已纳入后文分类审查。

| 呈现方式 | 静态调用数 |
| --- | ---: |
| 共享锚定面板 | 36 |
| 统一日程入口 | 12 |
| SwiftUI Popover | 1 |
| Sheet | 29 |
| Alert | 5 |
| ConfirmationDialog | 7 |
| 原生 NSAlert | 8 |
| 原生 NSPanel | 6 |
| 原生文件面板 | 4 |
| SwiftUI Menu | 41 |
| 系统 contextMenu | 15 |
| NSMenu | 2 |

静态入口涉及 55 个源文件。下列主类覆盖任务、摘要、日历、四象限、专注、倒数日、笔记、编辑器、快速添加、筛选、设置与同步。

## 按用途分类

| 类别 | 当前入口 | 应统一的规则 | 合理保留的差异 |
| --- | --- | --- | --- |
| 轻量菜单与下拉 | 排序、分组、显示设置、优先级、任务类型、模板操作、原生 Menu/contextMenu | 行高、选中/悬停反馈、图标栏、命令完成后的关闭、键盘导航 | 系统菜单继续原生；业务无箭头卡用共享面板；即时设置与命令动作分别声明是否保留菜单 |
| 属性与筛选工作面板 | 日期/时间/提醒/重复、标签、清单、关联主任务、摘要日期/状态/更多 | 真实按钮锚点、可用区域、父子层级、草稿、取消/确认、搜索焦点 | 日程主卡 260 点，摘要日期 240 点，标签 264 点等已验证尺寸先保留；摘要筛选确认语义与直接改任务属性不同 |
| 页面内任务编辑卡 | 日历/四象限任务详情和新建、专注时长编辑 | 页面坐标定位、遮罩范围、焦点、关闭时的保存语义、内容滚动 | 详情 400 点、新建 320 点；原有任务详情即时保存，新建任务确认创建，不能用同一套“取消回滚” |
| 文本辅助层 | 斜杠命令、标签补全、链接悬停、选区/格式工具条 | 光标或选区锚点、输入法优先、键盘归编辑器、即时高亮、不重复抢焦点 | 可以跟随光标、按结果变高；紧凑工具条圆角和菜单面板可不同 |
| 模态编辑与预览 | 摘要预览/历史/来源/配置、模板、过滤器、专注预设和记录、倒数日编辑、系统日程详情、周计划任务池 | 所属窗口、标题区、内容区、固定操作栏、提交和取消、错误展示 | 根据内容设定表单宽高，长列表滚动；长摘要预览可以比短表单宽 |
| 系统确认与文件工具 | 删除/清空、导入/恢复、结束专注、命名、链接编辑、附件/导出 | 明确动作名、默认安全取消、窗口归属、系统面板优先级 | 保留原生确认框与文件选择器，不把文件选择和危险确认做成属性菜单 |
| 独立工作及提醒窗口 | 全局快速添加、独立任务详情、便签、专注浮窗、到时提醒 | 自有窗口生命周期、关闭/保存、恢复位置、父子辅助层 | 点击外部一般不自动关闭；提醒“停止”涉及声音与提醒状态，不等同于普通菜单关闭 |

## 已确认的差异与风险

### 1. 初审命中的系统 Popover 入口（已完成迁移）

初审快照中 `Features/Shell/AppleSyncStatusButton.swift:30` 使用 `.popover(...arrowEdge: .trailing)`，面板宽 340。其他主要属性弹框已走共享无箭头 NSPanel。

`ArrowlessTaskPopupContractTests.swift` 的 `testGlobalArrowEdgeCountIsZero` 与 `testBusinessSourceDoesNotUseSystemPopover` 明确要求业务代码中对应使用次数为零。初审静态扫描命中上述唯一入口，与要求冲突。本轮没有运行 XCTest，结论来自当前测试断言与源码的直接对照。

实施前复核时，此入口已经接入共享底座。实施中进一步将其定位改为导航栏内侧展开，并增加明确的窗口标题；共享底座现在也支持此类信息卡随内容变化重新测高。未来真正需要系统 Popover 的入口应说明用途并有显式例外。

### 2. 点击与悬停展开的规则不一致

任务详情的优先级、任务类型、重复、标签和更多等根入口支持 120ms 悬停打开、250ms 延迟关闭；任务右键菜单使用 220ms 子菜单意图延迟，并允许已打开子菜单即时切换。摘要根下拉则通过点击切换。

根入口的快速悬停打开容易造成扫过工具栏就出现面板；这属于交互设计判断，尚未把它认定为本轮鼠标卡顿的已复现原因。建议根入口点击打开；菜单内部的二级、三级项继续使用意图延迟。普通灰色悬停反馈保持即时，不跟着展开延迟。

任务详情切换目标时会清理部分弹层状态，但未统一取消 `hoverPanelWork`，也没有统一取消所有悬停工作的消失处理。已排队回调可能在目标变化后再次改变弹层状态，这是代码可推导的生命周期风险。

### 3. 几何与尺寸有底座，仍缺统一声明

共享定位目前有左对齐、右对齐、日程及子菜单策略；摘要下拉间距 4 点，日程/子菜单 6 点，旧 vertical 路径紧贴锚点；屏幕面板安全边距 8 点，Planning 页面卡安全边距 12 点。这些差异需要按用途解释，不应直接认定全部为错误。

摘要已经集中 176/188/236/240/252 点宽度；日程是 260 点；标签入口多处重复写 264 点，关联主任务多处写 280 点。应将相同内容的规格集中为具名值，避免下一次只调整一个入口。先保存已验证尺寸，再合并确属同类的值。

当前共享面板动态重测高度仅在 dropdown 策略中处理；其他类型依靠宿主更新或固定外框。应明确“按内容自适应”和“开场固定、内部滚动”两种合同，不能要求搜索、日期子卡和长表单用同一种高度规则。

### 4. 外观应按语义收敛

共享面板外壳圆角为 12 点；编辑器链接工具条为 8 点、标签补全为 10 点；Planning 的阴影按页面 Overlay 绘制，原生子面板由 NSWindow 绘制。不同宿主不能通过机械复制同一条 shadow 修饰符来保证一致，否则可能出现双重阴影。

摘要已有紧凑自绘操作栏，其他选择器和表单使用各自按钮与内边距。建议分别统一“紧凑选择器操作栏”和“模态表单操作栏”，复用颜色、字体、禁用状态、对齐和顺序，不把 26 点的下拉按钮硬套到大型表单。

### 5. 关闭与保存语义需要写清

共享子面板的外部点击观察器会关闭面板并返回原鼠标事件；Planning 卡片使用页面遮罩；Sheet、系统 Alert 和独立浮窗又各有模态语义。应按类别规定点击是否穿透以及是否关闭，不能全局改成一条规则。

草稿类取消不落库；日程子卡确认只影响父草稿，父确认统一提交；即时保存的任务详情关闭不回滚；命令类动作成功后关闭；多项显示开关可连续操作。单选摘要“状态”保留确认，与直接修改任务“优先级”即时应用的区别来自业务用途，属于合理差异。

焦点规则应继承本轮任务切换修复：打开搜索选择器只请求一次焦点，关闭时只恢复仍有效的来源输入；用户已经切到其他输入框后，旧弹层或旧标题不得再抢回焦点。

## 建议规范

1. 每个入口只声明类别、所属窗口和目标、真实锚点、尺寸策略、对齐、焦点策略、提交方式及关闭方式；底层继续复用 `AnchoredPropertyPanel`、现有几何和 Escape 路由，不新建全局巨型控制器。
2. 根下拉与属性按钮点击打开；根悬停只显示即时反馈。菜单子项首次悬停约 220ms 展开，已展开时切换其他子项即时响应，跨越父子间隙保持可达。
3. 控件锚定卡默认使用 4 点间距，日程与横向子菜单保留具名 6 点策略；页面卡遵循自身 12 点安全边距。对齐方式由用途指定，弹层打开不改变列表列宽或父卡位置。
4. 普通卡片表面圆角 12 点；文本辅助工具可用紧凑规格。每种宿主只有一层阴影。颜色和字体走现有语义 token，已确认的模块主题以具名例外保留。
5. 短列表按内容变高，长列表到上限后滚动；日期工作面板保持有界稳定外框，子卡不撑父卡；错误提示不挤走主要操作按钮。
6. Escape 顺序为输入法候选、最深子层、父层；系统模态优先。Enter 只在明确确认上下文生效，避免搜索框、补全列表和多行编辑误提交。
7. 关闭父层、切换任务/摘要范围或移除宿主时，统一取消待执行工作、关闭子层并清理失效锚点；合法的父子层可以共存。
8. 小属性弹框取消不再追加二次确认；只有长表单存在真实未保存内容时才需要离开提示；即时保存的详情不显示“丢弃修改”。

## 实施顺序与验收范围

| 顺序 | 交付 | 涉及范围 | 定向验收 |
| --- | --- | --- | --- |
| P0 | 固定触发、焦点与关闭合同，清理目标变化后的延迟工作 | 任务详情、任务右键与各子菜单、快速添加 | 任务间切换、鼠标扫过、子层跨越、Escape、输入法、搜索与编辑焦点；不启动全量回归 |
| P1 | 收口定位、尺寸与紧凑外壳，迁移绕过入口 | 摘要、任务日期/标签/清单、Apple 同步状态 | 真实按钮锚点、父卡稳定、内容高度、取消/确定、窗口内定位与浅深外观；包含既有摘要和日程相关用例 |
| P2 | 统一编辑 Sheet 的结构和系统确认文案，补齐接入门禁 | 专注、倒数日、过滤器、摘要预览/历史、导入恢复 | 所属窗口、保存/取消、错误提示、长内容滚动；各改动仅跑相关表单与状态用例 |

规范与门禁从 P0 起同步更新。验收应覆盖代表性类型与已修改入口，同时保留各模块原有业务测试，不以只有外观截图代替取消、保存和焦点验证。

## 源文件清单

以下覆盖静态检索到的全部 55 个文件。次数不是运行时弹框数量。页面 Overlay、自定义子类和通用宿主的特殊语义见前面的分类表。

| 文件 | 检索到的呈现方式 |
| --- | --- |
| [App/AppCommands.swift](../macos-native/WorkFollow/App/AppCommands.swift) | SwiftUI Menu 1 |
| [App/WorkFollowApp.swift](../macos-native/WorkFollow/App/WorkFollowApp.swift) | 原生 NSAlert 1 |
| [Features/Countdown/CountdownEditorView.swift](../macos-native/WorkFollow/Features/Countdown/CountdownEditorView.swift) | 共享锚定面板 1；SwiftUI Menu 2 |
| [Features/Countdown/CountdownWorkspaceView.swift](../macos-native/WorkFollow/Features/Countdown/CountdownWorkspaceView.swift) | Sheet 1；SwiftUI Menu 3；系统 contextMenu 1 |
| [Features/Editor/DocumentContentActions.swift](../macos-native/WorkFollow/Features/Editor/DocumentContentActions.swift) | 原生 NSAlert 3 |
| [Features/Editor/DocumentFormatCommand.swift](../macos-native/WorkFollow/Features/Editor/DocumentFormatCommand.swift) | NSMenu 1 |
| [Features/Editor/DocumentSelectionToolbar.swift](../macos-native/WorkFollow/Features/Editor/DocumentSelectionToolbar.swift) | SwiftUI Menu 1 |
| [Features/Editor/LinkHoverMenu.swift](../macos-native/WorkFollow/Features/Editor/LinkHoverMenu.swift) | 原生 NSPanel 1 |
| [Features/Editor/NativeTextView.swift](../macos-native/WorkFollow/Features/Editor/NativeTextView.swift) | 原生 NSPanel 1 |
| [Features/Editor/SlashCommandPanel.swift](../macos-native/WorkFollow/Features/Editor/SlashCommandPanel.swift) | 原生 NSPanel 1 |
| [Features/Editor/TagCompletionPanel.swift](../macos-native/WorkFollow/Features/Editor/TagCompletionPanel.swift) | 原生 NSPanel 1 |
| [Features/Filters/AdvancedFilterRuleEditor.swift](../macos-native/WorkFollow/Features/Filters/AdvancedFilterRuleEditor.swift) | 共享锚定面板 1 |
| [Features/Filters/FilterEditorView.swift](../macos-native/WorkFollow/Features/Filters/FilterEditorView.swift) | SwiftUI Menu 1 |
| [Features/Focus/FocusActiveSessionPane.swift](../macos-native/WorkFollow/Features/Focus/FocusActiveSessionPane.swift) | Sheet 1 |
| [Features/Focus/FocusCompletionPane.swift](../macos-native/WorkFollow/Features/Focus/FocusCompletionPane.swift) | 共享锚定面板 1；Sheet 1；SwiftUI Menu 1 |
| [Features/Focus/FocusEndConfirmationPresenter.swift](../macos-native/WorkFollow/Features/Focus/FocusEndConfirmationPresenter.swift) | 原生 NSAlert 1 |
| [Features/Focus/FocusOverviewPane.swift](../macos-native/WorkFollow/Features/Focus/FocusOverviewPane.swift) | 共享锚定面板 1；Sheet 2；系统 contextMenu 1 |
| [Features/Focus/FocusPresentationWindows.swift](../macos-native/WorkFollow/Features/Focus/FocusPresentationWindows.swift) | 原生 NSPanel 1 |
| [Features/Focus/FocusPresetDetailPane.swift](../macos-native/WorkFollow/Features/Focus/FocusPresetDetailPane.swift) | Sheet 3；SwiftUI Menu 1；系统 contextMenu 1 |
| [Features/Focus/FocusPresetLibraryPane.swift](../macos-native/WorkFollow/Features/Focus/FocusPresetLibraryPane.swift) | Sheet 2；SwiftUI Menu 1；系统 contextMenu 1 |
| [Features/Focus/FocusRecordEditor.swift](../macos-native/WorkFollow/Features/Focus/FocusRecordEditor.swift) | Sheet 1 |
| [Features/Focus/FocusTaskPickerPopover.swift](../macos-native/WorkFollow/Features/Focus/FocusTaskPickerPopover.swift) | 共享锚定面板 1 |
| [Features/Focus/FocusTimerPane.swift](../macos-native/WorkFollow/Features/Focus/FocusTimerPane.swift) | 共享锚定面板 2；ConfirmationDialog 1；SwiftUI Menu 1 |
| [Features/Meetings/MeetingWorkspaceView.swift](../macos-native/WorkFollow/Features/Meetings/MeetingWorkspaceView.swift) | Sheet 1 |
| [Features/Notes/NotesWorkspaceView.swift](../macos-native/WorkFollow/Features/Notes/NotesWorkspaceView.swift) | 共享锚定面板 1；Alert 2；SwiftUI Menu 3 |
| [Features/Planning/CalendarDisplayOptions.swift](../macos-native/WorkFollow/Features/Planning/CalendarDisplayOptions.swift) | 系统 contextMenu 1 |
| [Features/Planning/CalendarTimelineView.swift](../macos-native/WorkFollow/Features/Planning/CalendarTimelineView.swift) | 系统 contextMenu 1 |
| [Features/Planning/CalendarWorkspaceView.swift](../macos-native/WorkFollow/Features/Planning/CalendarWorkspaceView.swift) | Sheet 2；ConfirmationDialog 1；SwiftUI Menu 2 |
| [Features/Planning/MatrixWorkspaceView.swift](../macos-native/WorkFollow/Features/Planning/MatrixWorkspaceView.swift) | 统一日程入口 1；Sheet 2；SwiftUI Menu 3 |
| [Features/Planning/TaskQuickComposer.swift](../macos-native/WorkFollow/Features/Planning/TaskQuickComposer.swift) | 统一日程入口 1；SwiftUI Menu 3 |
| [Features/QuickAdd/GlobalQuickAddController.swift](../macos-native/WorkFollow/Features/QuickAdd/GlobalQuickAddController.swift) | 共享锚定面板 1；统一日程入口 1；Sheet 1 |
| [Features/QuickAdd/StatusItemController.swift](../macos-native/WorkFollow/Features/QuickAdd/StatusItemController.swift) | NSMenu 1 |
| [Features/Settings/SettingsAppleRemindersView.swift](../macos-native/WorkFollow/Features/Settings/SettingsAppleRemindersView.swift) | ConfirmationDialog 1 |
| [Features/Settings/SettingsDataView.swift](../macos-native/WorkFollow/Features/Settings/SettingsDataView.swift) | Sheet 1；ConfirmationDialog 2；原生文件面板 3 |
| [Features/Shell/AppleSyncStatusButton.swift](../macos-native/WorkFollow/Features/Shell/AppleSyncStatusButton.swift) | SwiftUI Popover 1 |
| [Features/Shell/RootShellView.swift](../macos-native/WorkFollow/Features/Shell/RootShellView.swift) | 共享锚定面板 1；Sheet 1 |
| [Features/Sidebar/SidebarViews.swift](../macos-native/WorkFollow/Features/Sidebar/SidebarViews.swift) | Sheet 1；系统 contextMenu 3 |
| [Features/Summary/SummaryConfigurationView.swift](../macos-native/WorkFollow/Features/Summary/SummaryConfigurationView.swift) | 共享锚定面板 1；SwiftUI Menu 2 |
| [Features/Summary/SummaryWorkspaceView.swift](../macos-native/WorkFollow/Features/Summary/SummaryWorkspaceView.swift) | Sheet 4；Alert 1；SwiftUI Menu 1 |
| [Features/Tasks/Schedule/SchedulePopoverModifier.swift](../macos-native/WorkFollow/Features/Tasks/Schedule/SchedulePopoverModifier.swift) | 共享锚定面板 1 |
| [Features/Tasks/Schedule/TaskDatePopoverV2.swift](../macos-native/WorkFollow/Features/Tasks/Schedule/TaskDatePopoverV2.swift) | 共享锚定面板 2；ConfirmationDialog 1 |
| [Features/Tasks/TaskInspector/TaskFocusEstimateEditor.swift](../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskFocusEstimateEditor.swift) | 共享锚定面板 1 |
| [Features/Tasks/TaskInspector/TaskInspectorShell.swift](../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift) | 共享锚定面板 6；统一日程入口 4；Alert 2；SwiftUI Menu 1 |
| [Features/Tasks/TaskList/QuickAddPropertiesPopover.swift](../macos-native/WorkFollow/Features/Tasks/TaskList/QuickAddPropertiesPopover.swift) | 共享锚定面板 3 |
| [Features/Tasks/TaskList/TaskBatchPanelView.swift](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskBatchPanelView.swift) | 共享锚定面板 2；统一日程入口 1；SwiftUI Menu 1 |
| [Features/Tasks/TaskList/TaskContextMenuPopover.swift](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskContextMenuPopover.swift) | 共享锚定面板 4 |
| [Features/Tasks/TaskList/TaskKanbanCardView.swift](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskKanbanCardView.swift) | 统一日程入口 1 |
| [Features/Tasks/TaskList/TaskListView.swift](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift) | 共享锚定面板 3；统一日程入口 2；Sheet 3；SwiftUI Menu 4；系统 contextMenu 1 |
| [Features/Tasks/TaskList/TaskTimelineView.swift](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskTimelineView.swift) | ConfirmationDialog 1；SwiftUI Menu 1 |
| [Features/Tasks/TaskManagementViews.swift](../macos-native/WorkFollow/Features/Tasks/TaskManagementViews.swift) | 共享锚定面板 2；统一日程入口 1；原生 NSAlert 3；SwiftUI Menu 3；系统 contextMenu 3 |
| [Features/Tasks/TaskTagManagementView.swift](../macos-native/WorkFollow/Features/Tasks/TaskTagManagementView.swift) | 共享锚定面板 1；Sheet 1；SwiftUI Menu 1；系统 contextMenu 1 |
| [Features/Tasks/WeeklyPlanning/WeeklyPlanningToolbar.swift](../macos-native/WorkFollow/Features/Tasks/WeeklyPlanning/WeeklyPlanningToolbar.swift) | SwiftUI Menu 2 |
| [Features/Tasks/WeeklyPlanning/WeeklyPlanningWorkspaceView.swift](../macos-native/WorkFollow/Features/Tasks/WeeklyPlanning/WeeklyPlanningWorkspaceView.swift) | Sheet 1；SwiftUI Menu 1；系统 contextMenu 1 |
| [Infrastructure/Files/NativeAttachmentFiles.swift](../macos-native/WorkFollow/Infrastructure/Files/NativeAttachmentFiles.swift) | 原生文件面板 1 |
| [Infrastructure/Notifications/TaskReminderPresenter.swift](../macos-native/WorkFollow/Infrastructure/Notifications/TaskReminderPresenter.swift) | 原生 NSPanel 1；SwiftUI Menu 1 |

另核对的特殊宿主：`Features/Planning/PlanningOverlayLayer.swift`、`PlanningOverlay.swift`、`Features/Focus/FocusDurationPopover.swift`、`Features/StickyNote/StickyNoteWindowController.swift`、`Features/Tasks/TaskInspector/TaskDetailWindowController.swift`，以及共享面板的子类与日程呈现修饰符。
