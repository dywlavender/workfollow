# 日历 / 四象限：锚定浮层对齐（2026-09-27）

本轮把日历与四象限的「新建 / 编辑」从**居中大浮层**改回原版的**锚定小浮层**，并把
尺寸、贴边、翻转、关闭方式逐条对齐 Flutter 基线（`desktop/lib`）。范围与优先级遵循
[native-migration-plan-v2](native-migration-plan-v2.md)：以仓库现有 Flutter 页面为准，
不新增产品设计。

## 两个浮层的契约

| | 任务的编辑器 | 新建卡 |
| --- | --- | --- |
| 原版来源 | `showTaskFloatingEditor` | `showTaskEditorPopover` + `TaskAddSurface` |
| 尺寸 | 400 × 356（`TaskSurfaceMetrics.editorWidth` / `editorMinHeight`） | 320 × 212（`composerWidth`；42 + 1 + 126 + 1 + 42） |
| 贴边 | 被点任务条/任务行的**下方居中**（`bottomCenter`） | 被点格/行/按钮的**下方右缘对齐**（`bottomEnd`） |
| 间距 | 6（`PopoverPlacement.gap`） | 6 |
| 焦点 | 打开**不抢**焦点（`focusPolicy: none`） | 打开即聚焦标题（`focusPolicy: searchField`） |
| 关闭 | 卡外任意按下（透明遮罩吃掉该次点击）、Esc | 同左 |

定位由 `WFOverlayGeometryMath.compute` 完成，是原版 `calculatePopoverGeometry`
（`desktop/lib/widgets/desktop_popover.dart:185`）的逐行移植：安全边距 12
（`popoverSafeArea = space3`）、近边装不下时翻转、十字对齐 start/center/end、再把矩形
夹进**窗口内容区**（原版用的是 `MediaQuery.sizeOf(context)`，不是屏幕）。

呈现方式是**页面自己的叠层**（`PlanningOverlayLayer`）：一张定位卡片 + 一层吃掉点击、
负责关闭的透明遮罩——与原版 `showAnchoredPopover` 的窗口叠层同架构。

> 曾用无边框 `NSPanel` 子窗口 + 无箭头卡面实现过，已废弃，原因是两个真问题：
> 1. **浮层收不到键盘**。`becomesKeyOnlyIfNeeded = true` 依赖 AppKit 的"控件需要键盘时
>    才变 key"机制，而 SwiftUI 的输入控件不会触发它，窗口永远不是 key，输入框点了没反应
>    （`SlashCommandPanel` 敢用这个开关是因为那是个纯列表、永不需要键盘）。`NSPopover`
>    也不行：自带箭头、尺寸由系统接管，拿不到"400×356、无箭头"这个契约。
> 2. 独立窗口的 `NSHostingView` **不继承主窗口的 environment**，`TaskInspectorShell` 的
>    `@EnvironmentObject AppEnvironment` 会是空的（用到"转笔记/关联"时会崩）。
>
> 改回窗口内叠层后，键盘/焦点/嵌套日期面板全部按原版走，窗口监视器与"点外吞事件"的
> 补丁也一并去掉了；代价是浮层被夹进的是**页面**（少了 52pt 导航栏）而不是整个窗口内容，
> 只有在贴着页面左缘时才会看出 52pt 的差别。

## 数据与语义

- 新建卡只持有草稿；页面的决定经 `PlanningComposerRequest` 传入：
  - 日历：`preset` 与 `fallback` 都是被点那天的 0 点（原版 `TaskScheduleDraft.forDay`），
    优先级为无。
  - 四象限：`preset` 为 nil（卡上显示「设置日期」），`fallback` 是象限默认日程
    （Ⅰ/Ⅲ 今天、Ⅱ 下周同一天、Ⅳ 无），优先级是象限默认值。
- 用户在卡上选了或清空了日期都算"他的决定"（`overridden`），提交时不再被 fallback
  覆盖——对齐 `createTaskFromComposer` 的 `scheduleOverridden` / `forceUnscheduled`。
- 卡的「日期 / 提醒 / 重复」都打开同一个日期面板（`TaskDatePopoverV2`）；为此给它加了
  **草稿模式**（`draftCommit`）：确定/清除只把 `CommitPlan` 交回卡，不写工作区、不动
  批量选择。
- 编辑器复用 `TaskInspectorShell`（`onRequestClose` 让 Esc 关掉浮层而不是退回列表，
  对齐原版 `TaskInspector._escape()` 的 `_isPopup` 分支）；任务被删/取消选中时浮层
  自动消失（原版 `_closeWhenMissing`）。

## 日历年视图：不恢复

`HEAD` 的旧单文件 `PlanningWorkspaceView.swift` 里有一个**年视图 + 当日计数热力图**
（`ViewMode.year` / `yearBoard` / `PlanningProjection.countsByDay` / `yearMonths`），
连同 `PlanningProjectionYearTests.swift`（162 行）在未提交的 Planning 重构中被删除。

Flutter 基线**没有**年视图（`CalendarViewMode` 只有 month / week），因此按"以现有
Flutter 功能、UI、交互为准"的约定**不恢复**。要恢复的话，源码与测试都在 git 历史里
（`git show HEAD:macos-native/WorkFollow/Features/Planning/PlanningWorkspaceView.swift`）。

## 与原版仍存在的差异

1. **子菜单用系统 `Menu`**：新建卡上的优先级、清单、更多（提醒/重复），以及象限卡上
   的省略菜单。原版是自绘的锚定面板。这与日历工具条月/周切换、象限菜单的既有做法
   一致（见 `PlanningMetrics` 的说明），功能与选项一致，位置由系统决定。
2. **清单选择**：原版是可搜索的 picker（`TaskListPicker`，topStart），这里是系统菜单。
3. **浮层不跟随滚动**：原版监听滚动重算锚点；这里锚点矩形虽然会随布局更新，但没有
   主动观察它，滚动时不会重排（浮层要等下一次状态变化才落位）。
4. **日历任务条按需求放大**（用户要求，有意偏离原版）：`WFCalendarMetrics.taskBarHeight`
   17 → 25.5 → 29，条内标题 12 → 14 → 16、时刻 11 → 12.5 → 14、勾选框 9.9 → 13.5
   （比任务行的 14.58 小一号的规矩不变）。
5. **日历条/周视图胶囊上的勾选框可点击**（用户要求，有意偏离原版）：原版那里点框开的
   是编辑器、框只报状态。现在点框＝完成/恢复（`workspace.changeStatus`），点条上其余
   地方＝打开编辑器；命中区由 `taskBarCheckboxHitPadding` 外扩 3pt，且这份空间从条的
   内边距与框后间距里让回，框的落点与标题的起点与原来完全一致。步进 `slotStride` 由条高推出，跨天色带分道与格子容量自动跟随；
   字号另立 `taskBarTitleFont` / `taskBarClockFont`，不改 `WFType` 的角色（列表元信息
   的角色别处也在用）。

## 验证

- `xcodebuild ... build`：BUILD SUCCEEDED。
- `xcodebuild ... test`：401 项通过（新增 `PlanningOverlayGeometryTests` 8 项，覆盖间距
  6、下方居中/右对齐、装不下翻转、安全边距夹取、窄窗与矮窗夹取、两种尺寸契约）。
- 截图对照**未完成**：当前进程没有屏幕录制权限（`screencapture` 报 could not create
  image from display），需要人工在真实窗口核对——见下节。

## 人工核对清单

1. 日历页双击某一天 → 卡片出现在**那一格下方右缘对齐**，320×212，标题自动聚焦，回车创建。
2. 日历页点任务条 → 编辑器出现在**那一条下方居中**，400×356，打开时不抢焦点。
3. 四象限点象限「+」或菜单「新建任务」→ 卡出现在该象限卡下方右缘，日期显示「设置日期」。
4. 四象限点任务行标题 → 编辑器贴该行下方居中。
5. 卡外任意处按下 → 浮层关闭且该次点击不穿透到底层控件；Esc 同样关闭。
6. 拖动/缩放主窗口 → 浮层跟随重新定位。
