# Native 迁移交付记录（2026-09-25）

## 本轮范围

- 工作分支：`experiment/macos-native`；未提交、未推送。
- 按优先级继续 Task List 微契约：修正 Flutter Inbox 的已完成分组清单泄漏（`TASK-LIST-004`）；Native 修正 Shift 区间多选锚点，改为沿用最近一次普通/Command 点选（`TASK-LIST-013`）。
- 复核日期重复保存：Native Preview 中选择“每天”并确认，退出应用后重启，再打开同一任务日期弹层，值仍为“每天”。独立 Preview JSON 的 recurrence 字段也为 `daily`。
- 真窗口复核父子完成：在 Today 点击父任务完成框，父项与两个活动孩子进入 Completed，计数变化为 Today 7→4、Completed 1→4；Undo 后 Today/Completed 恢复为 7/1。验收操作已撤销。

## 自动化验证

| 验证 | 结果 |
| --- | --- |
| `xcodebuild test -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/workfollow-native-build -quiet` | 83 passed，0 failed，0 skipped；macOS 27.0 / arm64 |
| `flutter test test/task_list_projection_test.dart test/task_tree_rules_test.dart`（`desktop/`） | 51 passed：Task List 25，Task Tree 26 |
| `git diff --check` | 通过 |

Xcode result bundle：`/private/tmp/workfollow-native-build/Logs/Test/Test-WorkFollow-2026.09.25_10-39-15-+0800.xcresult`。

## 运行与数据

- 本轮构建的 Native Preview：`/private/tmp/workfollow-native-build/Build/Products/Debug/WorkFollow.app`
- 独立预览数据：`~/Library/Application Support/WorkFollowNativePreview/workspace.json`
- 没有读取、写入或迁移 Flutter 正式数据；没有申请系统通知权限。
- 为验证重复持久化，Preview 中保留了验收任务、清单、标签、正文和“每天”重复设置。这些仅属于 Native Preview。

## UI 截图状态与未验收项

重启后的日期弹层及父子完成/Undo 已通过 CUA 的 Native Preview 真窗口截图和辅助功能树检查。该自动化窗口截图显示在本任务的工具记录中，但没有成功导出成可复用的 PNG 文件，因此本轮没有独立截图文件路径；仓库 `docs/screenshots/task-date-repeat.png` 是历史参考图，不作为本轮验收证据。

尚未通过真实窗口验证的高优先级项包括：deadline-only Today 行、逾期组、All 分组与置顶、Command/Shift 鼠标多选路径、清单/标签筛选组合、Context Menu、Quick Add 的完整属性。故 `Task List` 仍是 `NOT PARITY VERIFIED`，Inspector/Editor/Trash 主链也未整体验收。Notes、Matrix、Calendar 仍是 prototype；尚无 Flutter→Native 正式数据迁移、签名或发布。

本轮只提交主控审核，没有执行 Git commit 或 push。

## 2026-09-25 后续纠偏：TASK-LIST-007

- 按 Flutter 当前产品行为移除 Native 独立“过期”导航目的地与对应列表 scope；逾期任务继续通过 Today、最近 7 天、所有任务里的“已过期”分组查看。没有删除逾期分组本身。
- 最新 `xcodebuild test`：84 passed，0 failed，0 skipped；结果包：`/private/tmp/workfollow-native-build/Logs/Test/Test-WorkFollow-2026.09.25_10-53-54-+0800.xcresult`。
- 最新 Flutter Task List/Tree 定向测试：51 passed。`git diff --check` 通过。
- 本轮真实窗口复核受阻：CUA 检测到 Mac 已锁定且不能自动解锁；因此侧栏与 `⌘K` 快速打开面板的最新状态未核对，契约保持 `UI BLOCKED / NOT PARITY VERIFIED`。
- 未提交、未推送；Native Preview 数据与 Flutter 正式数据均未操作。

## 2026-09-25 后续纠偏：Quick Add 与日期清除语义

- 修正 Quick Add 星期编号偏移；补周一、周五、下周三、周日对照 Flutter 的固定时钟用例。
- 识别 chip 的关闭现在仅停用该 token 的解析、原文字面保留为任务标题；打开完整创建表单也沿用该选择。取消表单保留草稿，创建成功才清空。
- 分开日期面板“清除”和列表右键“清除日期”：面板清除安排日期、提醒、重复，保留独立截止日期；右键仅清安排日期并保留独立提醒、截止日期和重复。两者均保持单步撤销。
- 最新完整 `xcodebuild test`：96 passed，0 failed，0 skipped；macOS 27.0 / arm64。XCTest 结果：`/private/tmp/workfollow-native-build/Logs/Test/Test-WorkFollow-2026.09.25_12-33-15-+0800.xcresult`。
- Flutter 参考验证：日期解析/菜单/计划 34 项通过；任务动作与日期弹层 26 项通过，共 60 项。Flutter Quick Add 焦点专测未在本轮运行。
- `git diff --check` 通过。Mac 锁定，新增交互未完成真实窗口截图验收；仍未提交或推送。

## 2026-09-25 后续纠偏：TASK-LIST-014 全局搜索与命令面板

- ⌘K 现在按 Flutter 顺序提供创建任务、匹配任务、匹配笔记、匹配命令；保留空查询的 9 个导航/外观命令、任务 7 条和笔记 5 条上限，以及上下键、Enter、Escape 操作。
- 打开任务命中项会跳转到所属清单/收集箱并选中；打开笔记命中项会切到笔记并选中准确条目。快速创建沿用当前清单，只有 Today 创建默认安排今天。
- 移除 Native 任务列表额外的页内搜索、清单和标签筛选控件；导航列中的清单/标签选择仍保留，并只进入 All 任务范围。
- 新增 6 项 `CommandPaletteTests`，覆盖结果投影、限额、过滤、创建默认值及任务/笔记路由。最新完整 Native XCTest：102 passed，0 failed，0 skipped；macOS 27.0 / arm64，结果包：`/private/tmp/workfollow-native-build/Logs/Test/Test-WorkFollow-2026.09.25_20-19-20-+0800.xcresult`。Flutter 原有命令面板行为专测 1/1 通过。
- `git diff --check` 通过。⌘K 面板视觉、真实窗口键盘焦点及 Escape 路径仍未截图验收，`TASK-LIST-014` 不标记 `PARITY VERIFIED`。未提交、未推送。

## 2026-09-25 后续纠偏：TASK-LIST-015 Context Menu

- 右键菜单移除了 Native-only 的“打开任务”“完成/恢复”“展开/收起”项；重复任务的“跳过此周期”按 Flutter 菜单显示，并对已关闭/无下个周期的任务禁用。
- 右键“添加子任务”现在创建空孩子后保持父任务选中，并通过 Inspector 的内联标题框接收输入；Inspector 的加号与正文创建子任务命令也共用该流程。新增模型测试覆盖父子关系、父选择和待编辑请求。
- “标签”改为可搜索、多选、创建标签且支持取消/确认的草稿 popover，避免菜单中即时切换、无法撤销到取消前状态；清单仍走系统子菜单。
- 最新完整 Native XCTest：103 passed，0 failed，0 skipped；macOS 27.0 / arm64，结果包：`/private/tmp/workfollow-native-build/Logs/Test/Test-WorkFollow-2026.09.25_20-32-11-+0800.xcresult`。`git diff --check` 通过。
- 原生系统 context menu 与 Flutter 自绘网格菜单仍有结构差异；清单搜索、菜单锚点、标签弹层位置、指针/键盘焦点均未真实窗口验收。`TASK-LIST-015` 仅部分动作对齐，不标记 `PARITY VERIFIED`；未提交、未推送。

## 2026-09-25 后续纠偏：TASK-LIST-016 Quick Add 日期草稿入口

- 聚焦列表 Quick Add 时显示固定日期入口，原位打开草稿面板设置安排日期、时间、提醒和重复；确认更新草稿，取消不改动草稿，清除重置这组属性。回车创建与打开完整新建表单的路径都会沿用已确认的日期草稿。
- 移除已识别的日期/时间 token 后，Today Quick Add 不再错误地重新套用默认“今天”；手动清除也保留为显式未安排状态。
- Native XCTest：105 passed，0 failed，0 skipped；结果包：`/private/tmp/workfollow-native-build/Logs/Test/Test-WorkFollow-2026.09.25_21-05-28-+0800.xcresult`。Flutter `quick_add_focus_test.dart`：3/3 通过。`git diff --check` 通过。
- 剩余差异：token 仍以输入框下方 chip 呈现，完整属性 disclosure 仍走新建表单；Native 真实窗口的弹层锚点、焦点与 Escape 行为未截图验收。`TASK-LIST-016` 仅部分实现，不标记 `PARITY VERIFIED`；未提交、未推送。

## 2026-09-25 后续纠偏：TASK-LIST-015 自绘右键菜单

- 将任务行的系统 `contextMenu` 替换成紧凑的应用内 Popover，日期/优先级快捷操作及子任务、置顶、放弃、移动清单、标签、转笔记、删除沿用既有 TaskWorkspaceModel 动作；清单子面板可搜索，标签保留草稿多选与取消/确认。
- 真实窗口通过右键打开自绘菜单；清单与标签子面板可打开，Escape 关闭子面板并保留主菜单，再次 Escape 关闭主菜单。未提交动作，Preview 任务数据未改变。
- Native `xcodebuild build` 通过；首次沙箱内 XCTest 被 macOS `testmanagerd` 通信限制，获准在沙箱外重跑后 `xcodebuild test` 通过。测试结果未提取精确用例数。
- `TASK-LIST-015` 更新为 `PARTIAL REAL-WINDOW CHECK`，仍不是 `PARITY VERIFIED`：菜单目前锚定任务行而非精确指针坐标；日期/优先级排列、焦点导航和动作提交尚未逐项比对 Flutter。真实窗口截图显示在本任务工具记录中，没有独立导出的图片文件。
- `TASK-LIST-014` 的 ⌘K 任务查询/路由/Escape，以及 `TASK-DATE-001` 的日期面板打开/Escape，也在契约中登记为部分真实窗口验收；未触碰正式 Flutter 数据，不提交、不推送。
