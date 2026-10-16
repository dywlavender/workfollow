**滴答清单与 experiment/macos-native：待办、日历、四象限、专注对比**

核对日期：2026-10-13，Asia/Shanghai。项目目录为 `workfollow-macos-native`，当前就在 `experiment/macos-native` 分支；四个模块的审计源码没有未提交修改。本机滴答版本为 8.0.80。

这四个模块已经具备不少业务能力，但“有同名入口”和“实际体验等价”之间仍有明显差距。优先级最高的是日期识别、专注计时与记录、日历可见性、跨视图操作的一致性；其次是补齐规则配置和排期能力。继续只调整布局和颜色，解决不了这些问题。

**判断依据与证据范围**

使用 REA 6.4.0 实际执行了 `inspect-native-dispatch-metadata`、`decode-interface-builder` 和 `inspect-macho`。原生元数据读取目标为滴答主程序及 TTModelsPod；界面解码使用原安装包中37份选定、未修改的 nib 副本，副本没有启动。工具解析到了界面控件、动作连接、类属性及重复任务接口；这是静态结构证据，没有恢复函数体或完整算法。

客户端观察覆盖任务页、四象限、专注页和日历会员演示。快速输入对比只编辑草稿，两个草稿均已清空，未创建测试任务。日历真实任务拖动、付费规则配置和历史专注编辑未完整实测；对应语义用安装包结构与滴答官方说明交叉核对。官方说明可能比本机版本新，本文对已在8.0.80包中找到的入口另列证据。

本项目的正常业务问题用当前 Swift 源码与独立程序复现。专注检查编译了实际 Engine、Store 和 SQLite 持久化实现；待办检查使用实际解析器/领域/投影代码及最小类型或存储适配；规划检查编译了实际投影与日期区间代码。它们确认业务和状态发布问题，不等于已做所有界面交互验收。

可审阅的结构证据见 [REA 选定证据](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/rea-selected-evidence.json)。该文件只保存相关文件名、控件、动作、属性和观察结论，不包含原始安装包。

**先更新旧对比结论**

9月26日的旧文档已经不适合继续作为功能现状表：

- 时间段现在有独立 `dueEndAt`，与安排日 `dueAt`、截止日 `deadlineAt` 分开。见 [Task.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Domain/Task/Task.swift:159)。
- 清单文件夹、清单分组、看板、关键词过滤器、农历重复、艾宾浩斯、番茄与正计时均已有实现。
- 时间线有源码，但 `exposedCases` 只开放列表与看板，不能按“已能使用时间线”计算。见 [TaskViewPreferences.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/TaskViewPreferences.swift:59)。
- 当前日历主入口只有月、周两个模式；旧表里“年视图已对齐”的说法与当前路由不符。见 [CalendarWorkspaceView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Planning/CalendarWorkspaceView.swift:1406)。
- 滴答当前客户端有“已放弃”和“顺延”入口；不能把它们当作本项目独有优势。
- 源码注释中的“原版”“Flutter 对齐”大多指本项目 Flutter 实现，不是滴答原始实现的证明。

**四个模块的实际差异**

| 模块 | 本项目已经有 | 与滴答的主要差异 | 建议优先补齐 |
| --- | --- | --- | --- |
| 待办 | 子任务、独立时间段、多提醒、多类重复、模板、文件夹/分组、过滤器、列表/看板、全局快速录入 | 重复以到期日推进，规则只持有单个星期几/月日；缺完成日起算、多选日期与周期例外。看板的处理入口和拖动语义较少；时间线未开放 | 修日期解析、重复后分组、看板排序，再补重复模式、看板直接处理、过滤器范围 |
| 日历 | 月网格、七列周卡片、跨天色带、改期、完成、锚定编辑器 | 滴答桌面周视图有全天栏与时间轴，能拖动任务和边缘调整时间；有待安排任务区、未来重复周期、显示范围及专注记录。本项目周视图主要按起始日装任务 | 先修可见性，再做周时间轴、全天区、待安排区、未来周期投影 |
| 四象限 | 四格、按清单分组、完成/新建、跨象限拖动、共用任务数据 | 本项目重要=高/中，紧急=安排日不晚于今天+3天，规则固定。滴答有优先级映射、时间+优先级及自定义清单/标签/时间/优先级范围 | 可配置规则与范围；拖动一次完整撤销，规则允许时保留原安排日 |
| 专注 | 番茄/正计时、暂停/恢复、短长休息、任务关联与换绑、专注笔记、预设、记录分页、会话恢复 | 本项目会话模式与记录类型不完整，已有计时/记账问题；历史没有完整编辑入口，补记日期不可选。缺任务预估与实际投入展示、统计筛选 | 先修计时与统计，再补历史编辑、任务投入及按日/任务统计 |

滴答的重复类型和未来周期行为见[设置重复任务](https://help.dida365.com/articles/6950660365923385344)；桌面日历时间轴与待安排区见[周视图](https://help.dida365.com/articles/6950641140068515840)；象限规则见[编辑四象限规则](https://help.dida365.com/articles/6950381682822217728)；专注时长调整见[如何开始专注](https://help.dida365.com/articles/6950408124297641984)。

**待办：最直接的差距在“输入准确、组织保留、菜单生效”**

1. 快速输入的日期和时刻会互相覆盖。单独“下周一”使用“下一次星期一再加7天”的算法：10月13日输入会得到10月26日，而本机滴答草稿预览为10月19日。加上“上午9点”后，时间候选又按最近9点生成完整日期，覆盖星期候选；固定10月13日中午输入“下周一上午9点开会”，实际得到10月14日09:00。先统一自然周计算，再让时刻合并进明确日期。证据：[QuickAddParser.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskList/QuickAddParser.swift:204)、[星期计算](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskList/QuickAddParser.swift:245)、[候选合并](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskList/QuickAddParser.swift:350)。

2. “明天9:00–10:00”未作为区间解析。本项目保留了最后的10:00单点，没有结束时间。本机滴答8.0.80同样没有识别完整区间，只识别开始9:00。因此“智能识别完整时段”属于值得做的本项目改进，不能写成滴答此版本已经有而本项目没有。当前已有时间段模型，可直接承接区间解析。证据：[QuickAddParser.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskList/QuickAddParser.swift:350)。

3. 重复任务会丢失自定义分组。“进行中”列的每日任务完成后，下一期没有复制 `sectionID`，落到“未分组”。应复制稳定的组织归属，避免用户每次重复都重新整理。证据：[TaskActions.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/TaskActions.swift:120)；复现结果为 `doing → nil`。

4. 看板排序菜单不生效。列表按用户排序偏好调用 `orderedTasks`，看板直接画 `group.tasks`。按标题排序的底层结果为 AAA、BBB、ZZZ，而看板读取的原顺序仍为 ZZZ、AAA、BBB。应共享排序投影。证据：[TaskKanbanView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskList/TaskKanbanView.swift:44)、[列表排序](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift:1008)。

5. 部分分组和筛选维护不一致。清单/标签页面开放按日期分组，投影却仍可能只返回平铺组；清单/标签改名后，保存过滤器保留旧名称，原条件失去命中。建议让有效菜单与实际投影一致，并让改名同步维护引用。证据：[TaskListProjection.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/TaskListProjection.swift:259)、[TaskWorkspaceModel.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskWorkspaceModel.swift:293)、[SavedFilter.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Domain/Filter/SavedFilter.swift:91)。

待办的下一轮功能增强可围绕三点：看板卡片直接完成、右键与列内新建；完成日起算及多星期几/多日期重复；过滤器包含/排除与自定义日期范围。标签层级、颜色、手动排序和全局录入属性面板属于后续组织与捕获体验。

REA 在 `TaskRecurringAdapter` 和 `TaskDateTimeReminderRecurringAdapter` 中读取到 `recurrenceFromAsRecurringObject`、`completionDateAsRecurringObject`、`excludedOccurrenceDatesAsRecurringObject` 等属性。属性名本身不证明具体推进算法；与官方重复说明结合，可以确认滴答有本项目当前缺少的起算模式和周期例外体系。

**日历：需要从“看任务日期”进一步支持“安排一天的时间”**

先修下面这些现有行为，再添加新视图：

| 已确认的问题 | 普通使用中的结果 | 修正方向与源码 |
| --- | --- | --- |
| 月网格“+N”只选择日期 | 一天8项只显示3项，点击“+5”仍没有剩余5项的查看入口 | 打开当天完整任务列表。[CalendarWorkspaceView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Planning/CalendarWorkspaceView.swift:976) |
| 隐藏完成只传给月网格 | 切到周视图，已完成任务继续显示 | 统一可见任务投影。[CalendarWorkspaceView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Planning/CalendarWorkspaceView.swift:62) |
| 翻月不更新选中日期 | 从10月翻到11月，工具条加号仍使用10月原选中日；切周也可能回到旧周 | 同步浏览锚点、选中日和新建默认日期。[CalendarWorkspaceView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Planning/CalendarWorkspaceView.swift:241) |
| 周列只按起始日取数 | 10月13–16日的跨天任务在14日周列消失 | 用覆盖日期取数，并提供跨天/全天区。[PlanningProjection.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/PlanningProjection.swift:71) |
| 网格日期固定今天前后30周 | 明年下半年的安排没有对应日期行 | 缓存随浏览窗口扩展。[CalendarWorkspaceView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Planning/CalendarWorkspaceView.swift:476) |

能力增强建议按顺序推进：真正的周时间轴与全天栏；无日期任务拖入安排；拖边缘修改时长；未来重复周期和仅此周期修改；清单/标签显示范围；专注实际记录作为复盘图层。

颜色也有产品差异：当前色带按任务标识派生颜色，无法用颜色稳定识别清单；日历任务保持库中顺序，可能下午4点排在上午9点前。这两项是当前设计选择，不应算程序错误。可增加按清单/优先级着色和按时间排序，同时保留现有彩色风格选项。证据：[CalendarWorkspaceView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Planning/CalendarWorkspaceView.swift:307)、[PlanningProjection.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/PlanningProjection.swift:69)；滴答显示范围与颜色说明见[常见问题](https://help.dida365.com/articles/6950670128287580160)。

REA 解码到 `TTCalendarDisplayOptionsViewController.nib` 的 `completedSwitch`、`cyclesSwitch`、`focusSwitch` 等控件，也解码到 `TTCalendarArrangeViewController.nib` 的筛选及安排类型动作。这些结构与官方的未来周期、专注图层、待安排区说明一致。

**四象限：规则和拖动的副作用比外观更值得调整**

本项目规则固定为“高/中=重要，安排日≤今天+3天=紧急”，页面取全部任务。滴答官方明确提供两套常用规则：四种优先级映射四象限，以及时间+优先级；还可选择清单、标签、日期范围和优先级。当前客户端也能看到过期任务仍在IV，因此不能把本项目三天阈值当作滴答默认规则。源码：[PlanningProjection.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/PlanningProjection.swift:14)、[MatrixWorkspaceView.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Planning/MatrixWorkspaceView.swift:26)。

拖动存在两个确定问题：

- 从IV把“无优先级、下周安排”的任务拖到I，分别提交优先级和日期两次修改；一次撤销只恢复日期，任务停在II，无法回到原来的IV。
- 已在I且安排明天的任务再次落入I，会被无条件改成今天。用户没有表达改期意图时，同象限拖动应保持属性；目标规则已经满足时，也应尽量保留原日期。

证据：[TaskWorkspaceModel.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Tasks/TaskWorkspaceModel.swift:1071)。建议把跨象限修改作为一个动作提交，显示实际改变的日期/优先级，支持一次完整撤销；再增加规则预设、清单/标签范围、象限名称与排序。

本项目 `deadlineAt` 是独立截止字段。是否让它参与紧急判断是本项目的产品选择，不能直接把滴答说明里的“截止日期”词语映射成同一个字段。合理的改进是让用户选择紧急依据，而不是再写死一套阈值。

**专注：应先保证计时、记录和统计表达同一件事**

1. 正计时缺少逐秒刷新信号。实际经过90秒后 `elapsedSeconds=90`，但状态发布次数为0；界面没有来自Store的逐秒重绘驱动，菜单栏又读取剩余秒数。任务详情显式启动正计时后，当前会话没有结束时间，但页面读取的模式偏好仍可能是番茄模式。应让当前会话模式成为展示依据，发布实际经过秒数。证据：[FocusStore.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusStore.swift:333)、[刷新](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusStore.swift:525)、[FocusTimerRing.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusTimerRing.swift:21)。

2. 运行中切换时长预设会记错分钟数。25分钟会话中点50分钟预设，仍在25分钟结束，却保存50分钟记录。预设修改全局设置，而完成记录读取设置，没有使用本次固定时长。建议预设影响下一次会话，本次记录按本次实际/计划时长保存。证据：[PomodoroEngine.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Domain/Focus/PomodoroEngine.swift:191)、[FocusStore.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusStore.swift:402)。

3. 正计时和番茄记录缺少模式区分。当前记录只有分钟数与 completed；正计时90秒从菜单栏完成，会保存2分钟、计一个番茄并进入休息，补记60分钟也计一个番茄。主页面暂停后的“结束”则走放弃逻辑。应该分开番茄数、实际专注时长、补记与中断状态，并统一页面和菜单栏的结束行为。这里已确认本项目内部语义不一致；滴答的具体舍入与计数规则未完整实测，不据此指定必须复制的数值规则。证据：[FocusStore.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusStore.swift:4)、[FocusTimerPane.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusTimerPane.swift:274)。

4. 铃声选择未使用已有系统音名映射。UI保存“清脆”等显示名称，播放时直接传给 NSSound，实际音名应是 Glass 等；关闭铃声时，通知仍无条件使用默认声音。应使用现有映射并让关闭控制通知声音。证据：[FocusStore.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusStore.swift:30)、[FocusNotifier.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusNotifier.swift:23)。

记录与复盘的下一步也很明确：历史支持编辑任务归属、开始/结束时间、时长和笔记；补记支持选昨天等具体日期。当前补记只用“现在减去输入时长”，无法真正补记过去某天；专注笔记虽已保存，结束后没有完整查看/编辑入口。源码：[FocusOverviewPane.swift](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusOverviewPane.swift:303)。

再往后，可补任务预计番茄/预计时长、累计实际投入和时间范围/任务统计。REA在 `TTFocusEstimateViewController.nib` 中读取到小时、分钟、番茄目标控件，在 `TTFocusRecordEditViewController.nib` 中读取到 `startDateButton`、`endDateButton`、`taskButton` 和对应编辑动作。它们与官方专注功能说明互相印证；本项目目前已有每日与任务聚合接口，可以复用。白噪音、沉浸窗口和更多图表可以放在这些问题解决之后。

**建议实施顺序**

| 批次 | 具体内容 | 判断理由 |
| --- | --- | --- |
| 先修现有行为 | 日期识别与组合、专注刷新/模式/时长记录、重复分组保留、看板排序、日历“+N”与完成可见性、象限拖动撤销 | 直接影响用户记录、看到和回顾的结果；已有模型大多可承接 |
| 再补核心能力 | 周时间轴+全天栏+待安排区，象限规则/范围，完成日起算及周期例外，历史专注编辑 | 这是四个模块与滴答主要工作流程的实际距离 |
| 最后增强体验 | 任务预估与实际投入、统计筛选、日历颜色/图层、多日期视图、白噪音与沉浸窗口 | 有助效率和复盘，应建立在准确业务结果上 |

验收应串起来观察同一条任务：快速记录 → 进入正确清单/分组 → 日历安排时段 → 四象限调整 → 开始专注 → 编辑和回顾记录。每一步使用同一份日期、归属和投入数据，比单独比较页面截图更能判断体验是否接近。

**复现文件与运行方式**

已保存五份独立 Swift 检查及输出：[快速输入](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/tasks_quickadd_probe.output.txt)、[重复任务](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/tasks_recurrence_probe.output.txt)、[分组与排序](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/tasks_projection_probe.output.txt)、[规划投影](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/planning_probe.output.txt)、[专注计时与统计](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/FocusAuditHarness.output.txt)。它们没有读写用户任务库。

三份待办检查为独立脚本，可在仓库根目录用 `swift -module-cache-path /private/tmp/workfollow-rea-audit/swift-module-cache <脚本绝对路径>` 运行。源码快照保留了审计时的核心实现；未来产品修改后，应以新源码重新构造对应检查。

专注检查编译命令（在上述仓库目录运行）：

```sh
swiftc -module-cache-path /private/tmp/workfollow-rea-audit/swift-module-cache \
  macos-native/WorkFollow/Domain/Focus/PomodoroEngine.swift \
  macos-native/WorkFollow/Application/FocusStore.swift \
  macos-native/WorkFollow/Application/FocusNotifier.swift \
  macos-native/WorkFollow/Infrastructure/Persistence/SQLiteRecordStore.swift \
  macos-native/WorkFollow/Infrastructure/Persistence/SQLiteDatabase.swift \
  macos-native/WorkFollow/Infrastructure/Persistence/JSONFileStore.swift \
  docs/audits/ticktick-rea-2026-10-13/FocusAuditHarness.swift \
  -o /private/tmp/workfollow-rea-audit/focus-audit-harness
```

本轮只新增审计资料，没有修改产品实现。
