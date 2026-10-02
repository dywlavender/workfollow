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

当前业务源码剩余 12 处 `.popover(`。本轮显式箭头入口迁移已完成；其余入口仍按阶段推进。本盘点不表示全局弹窗改造已经完成，也不承诺所有入口都已验收为无箭头。

| 文件 | 数量 | 当前入口 |
| --- | ---: | --- |
| `Features/Tasks/TaskList/QuickAddPropertiesPopover.swift` | 2 | 快速添加的清单、标签属性 |
| `Features/Tasks/TaskList/TaskListView.swift` | 3 | 导航、快速添加属性、标签选择 |
| `Features/Focus/FocusTaskPickerPopover.swift` | 1 | 专注任务范围选择 |
| `Features/Focus/FocusTimerPane.swift` | 1 | 专注任务选择 |
| `Features/Tasks/Schedule/SchedulePopoverModifier.swift` | 1 | 日程属性面板 |
| `Features/Shell/RootShellView.swift` | 1 | 根导航弹层 |
| `Features/Notes/NotesWorkspaceView.swift` | 1 | 笔记导航弹层 |
| `Features/Tasks/TaskInspector/TaskDatePopover.swift` | 2 | 旧任务日期入口 |
| **合计** | **12** | 按本轮源码字面调用盘点 |

`arrowEdge:` 的本轮业务源码盘点为零；静态契约禁止重新引入显式系统箭头。

## 后续状态

Quick Add、Focus scope / task picker、Schedule、RootShell/Notes 导航、旧 `TaskDatePopover` 仍列在上表，后续按阶段推进；不能据此宣称全局迁移完成。Schedule 最后处理，只换 presentation shell，不改日期 Draft 和提交逻辑。
