# 任务弹窗无箭头迁移记录

记录日期：2026-10-02。进度定位：Task Context 三个入口已冻结；剩余四个显式箭头入口已迁移，全业务 `arrowEdge:` 为零。系统 `.popover` 全量迁移尚未完成。

## 本轮完成状态

主线已将任务右键菜单 presenter 与菜单子面板迁到共享锚定面板呈现路径。当前 `TaskContextMenuPresenter.swift` 和 `TaskContextMenuPopover.swift` 均不再包含 `NSPopover()`、`arrowEdge:` 或 `.popover(`。全局业务源码扫描也未发现直接 `NSPopover()` 构造。

本轮新增的静态契约覆盖 `macos-native/WorkFollow` 下全部 Swift 业务源码：

- 禁止直接构造 `NSPopover()`。
- 全业务源码 `arrowEdge:` 数量必须为零，无临时允许清单。
- Task Context Menu presenter/menu 与 Task Inspector 源码不允许传 `arrowEdge:`。

已完成独立 `build-for-testing`，并逐类执行最新产物的 XCTest：任务菜单窗口、源码门禁、共享锚定面板、Escape、Inspector Focus 子菜单、日期容器渲染、日期交互及原子提交，共 36 项通过。任务菜单测试包含真实菜单内容的尺寸测量、独立子窗口定位、外部点击、Esc 层级、父窗口移动与关闭清理。这不等同于日常运行 App 的截图验收。

布局规范：主菜单按光标锚定；子菜单不参与主菜单尺寸计算，空间边界来自所属应用主窗口，而不是小型菜单窗口。打开子层只改变呈现状态；点击子窗口或穿过间隙不关闭父菜单；Esc 先关子层、再关父层；点击外部关闭整套菜单。业务菜单内容与动作保持原样。

## 显式箭头清零阶段

清单颜色选择、Focus 补记专注、每日目标、节奏设置四个入口改用共享 `AnchoredPropertyPanel`。只替换呈现外壳，不改原有内容、保存动作和 Focus Domain。颜色面板宽度由七列色块与现有间距计算；三个 Focus 面板分别保留 330、190、360pt 宽度。

最新 `build-for-testing` 成功；源码门禁、共享锚定面板、Escape、Task Context、Inspector Focus 子菜单、清单管理、Focus 布局和 Focus Store 共 47 项测试通过。

重启刚构建的 App 后，实机截图确认节奏与颜色面板没有箭头，底层布局不移动。当前已有暂停的专注会话，Overview 的补记与目标入口不可见；没有为验收而结束该会话。这两个入口尚未完成日常 App 实机截图验收，自动测试不替代这项结论。

## `.popover` 分阶段盘点

第一批迁移后剩余 8 处 `.popover(`。验收发现并行新增的 Countdown 图标选择显式箭头后，也仅替换该入口的呈现壳并保留 240pt 内容宽度。下表按当前工作区盘点，不表示全局弹窗改造已经完成。

| 文件 | 数量 | 当前入口 |
| --- | ---: | --- |
| `Features/Tasks/TaskList/TaskListView.swift` | 1 | 导航 |
| `Features/Focus/FocusTaskPickerPopover.swift` | 1 | 专注任务范围选择 |
| `Features/Focus/FocusTimerPane.swift` | 1 | 专注任务选择 |
| `Features/Tasks/Schedule/SchedulePopoverModifier.swift` | 1 | 日程属性面板 |
| `Features/Shell/RootShellView.swift` | 1 | 根导航弹层 |
| `Features/Notes/NotesWorkspaceView.swift` | 1 | 笔记导航弹层 |
| `Features/Tasks/TaskInspector/TaskDatePopover.swift` | 2 | 旧任务日期入口 |
| **合计** | **8** | 按当前工作区源码字面调用盘点 |

本批流程验收期间，门禁发现 `CountdownEditorView.swift` 新增 `arrowEdge:` 的回归。待该并行改动完成后，本轮仅迁移图标入口到共享面板；全局显式箭头重新为零，未放宽允许清单。

## 后续状态

Quick Add、Focus scope / task picker、Schedule、RootShell/Notes 导航、旧 `TaskDatePopover` 仍列在上表，后续按阶段推进；不能据此宣称全局迁移完成。Schedule 最后处理，只换 presentation shell，不改日期 Draft 和提交逻辑。

## 分批迁移与流程验收规则

每一批必须先通过最新构建与流程验收，再推进下一批；只替换 presentation shell，不重排内容或改业务能力。

1. 第一批：Quick Add 属性主层、清单/标签子层、任务行标签呈现壳。
2. 第二批：Focus 任务/范围，以及 Task List、RootShell、Notes 导航。
3. 第三批：Schedule 主层及仍实际使用的旧日期入口；不使用的旧入口先确认再处理。

每个入口按「打开 → 操作 → 取消/确定 → 再打开」检查。父子浮层额外锁定父框与触发行不移动、子层点击不关闭父层、Esc 先子后父、外部点击全部关闭、父窗口移动/关闭时跟随/清理。搜索框必须获得键盘焦点；取消不提交，确定只提交一次；Quick Add 只更新草稿，不直接创建任务。模板入口关闭属性层后再打开 Gallery，不能留下孤立子窗口。

系统文件选择器、原生菜单、系统确认对话框不属于自定义 anchored card 的迁移范围。源码计数只是门禁，不替代实际交互验收。无可触发入口的历史代码必须标注为不可实机验收，不能算已通过流程。

### 第一批实施与验收

Quick Add 属性主层、清单/标签子层已换共享 NSPanel，任务行标签呈现壳也已迁移。保留原草稿回调与内容尺寸。任务行旧标签入口无打开它的赋值路径，不宣称其实机流程通过。

流程测试发现两个呈现缺口并修复：Esc 要沿原生父窗口链路找到最深子层；搜索子层需要显式键盘焦点策略，刷新布局时不得抢回焦点。实机进一步发现标签菜单焦点误落到“确定”，因此初次打开优先选择可编辑 NSTextField，无输入框时才回退 key-view loop，并补初始搜索 responder 断言。默认策略仍保留 presenter 焦点。

最新构建成功，QuickAddArrowlessFlowTests 的 5 项真实窗口流程和 PopupEscapeRoutingTests 的 6 项通过，包括搜索输入后取消、标签取消/再次打开/确定只回调一次、两级 Esc、外部点击和父层关闭清理。全局箭头门禁通过。

最终逐类测试共 72 项全部通过。共享面板 9 项测试包含搜索输入与 responder 在布局刷新后保持。面板只在首次打开时 orderFront，不在每次布局更新时重新抬升。

2026-10-02 重启最新构建实机验收：清单搜索输入、Esc 先子后父、第二次 Esc 焦点回 Quick Add；标签选择后取消再打开无残留、确定后主菜单显示所选标签、再打开选中态正确；恢复空标签草稿；模板入口打开 Gallery、Esc 关闭，未创建任务。截图中父属性菜单在关闭子菜单后位置保持。标签修复版初始 AX 焦点已确认是搜索框，不再是“确定”。外部点击、父窗口关闭清理由真实窗口自动流程覆盖，本次不标作手工通过。

Countdown 图标入口实机检查：打开、Esc 仅关闭图标层保留编辑 sheet、再次打开选择 heart 更新草稿、取消整个编辑后仍只有原来的两张卡片。窗口截图只截到子层落在编辑 sheet 内的部分，完整子层阴影与屏幕边界未获得完整截图，不能据此宣称全局像素验收通过。没有保存或修改已有倒数数据。

本批功能流程可进入下一批；全项目迁移仍未完成。Focus Overview 两个隐藏入口和 Countdown 子层完整截图的视觉项继续保留，不以源码门禁替代。
