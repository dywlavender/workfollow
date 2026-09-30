# Native 产品对齐契约

更新日期：2026-09-29
基准产品：仓库内 `desktop/` Flutter 当前行为。本文记录可从源码、测试和截图核对的事实；不把 Native 当前实现或历史迁移清单当成产品规范。

## 状态约定

- `MATCH（代码级）`：目前 Native 代码/测试表达了相同规则；尚不等于真实窗口验收。
- `DIFF`：Flutter 与 Native 的当前行为有可定位差异。
- `FLUTTER GAP / 待决策`：Flutter 当前实现缺失、内部矛盾或测试未覆盖；Native 不应盲目复制可疑行为。
- `NO FLUTTER EQUIVALENT`：Native 有该入口，Flutter 当前没有对应产品入口。
- 所有契约验收状态先记为 `NOT VERIFIED`。只有补齐 Native 定向测试，并完成需要的真实 UI 操作/截图核对后，才可改为 `PARITY VERIFIED`。

优先级：`P0` 是任务在当前范围内消失、计数与可见行矛盾或可能操作错对象；`P1` 是主流程语义、分组或操作路径不一致；`P2` 是辅助入口、排序和批量便利性差异。

初版审计基于源码、既有测试和截图。2026-09-25 最新 Native XCTest 103/103；Flutter 日期解析、任务菜单、任务右键菜单和计划行为测试 34/34，另有任务动作与日期弹层测试 26/26。P0-012 有 Native Preview 真窗口点击/撤销验收；Today 完成后分组迁移和 Recent 新构建窗口分组也已真实操作/截图核对。逾期组目前由固定时钟投影测试覆盖，真实窗口尚无逾期样例，所以 P1-005 暂不标记 `PARITY VERIFIED`。

2026-09-29 增量验收：当前 macOS 27.0 `xcodebuild test` 全量 479/479 通过，覆盖本轮日期失效通知与相对提醒映射/展示；它只证明代码和 XCTest，不代表真实窗口视觉验收。清单与文件夹迁移元数据也已补上往返用例。Native 仍写入 Preview 数据目录，未切换正式存储。

## P0：第一批纠偏目标

### TASK-LIST-001 — Today 中仅有截止日期的任务必须有可见行，计数必须与列表一致

- **Flutter 代码：** [`task_projection.dart`](../desktop/lib/features/tasks/application/task_projection.dart#L13) 的 Today 过滤会纳入 `deadlineAt <= 今天`，其 Today badge 在第 127 行也会计入；[`task_list_projection.dart`](../desktop/lib/features/tasks/application/task_list_projection.dart#L233) 随后只按 `dueAt` 分组，而 Today 分支不输出 `undated` 组。故 `dueAt == null`、截止日期已到的任务会进入 Today 计数/过滤范围，却无法从 Today 分组渲染出来。这是 Flutter 当前实现的内部矛盾，不应作为 Native 的目标行为照抄。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart#L113) 新增 deadline-only 行与 Today count 一致的断言；当前定向 projection suite 25/25 通过。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png) 是普通日期分组参考，不覆盖 deadline-only；无此边界截图。
- **Native 当前行为：** [`TaskListProjection.swift`](../macos-native/WorkFollow/Application/TaskListProjection.swift#L23) 按 due 或 deadline 纳入 Today，分组时将非 due-overdue 项放入 Today，因此 deadline-only 项会显示；[`TaskWorkspaceModelTests.swift`](../macos-native/WorkFollowTests/TaskWorkspaceModelTests.swift#L91) 新增 count 与可见行一致的用例。
- **产品决定：** 用户确认“只有 deadline、没有 due”的任务在截止日期到达后应显示在 Today。
- **实现：** Flutter Today 分组现在会收纳已到期且无 due 的任务，使分组行与 Today 计数一致；Native 原本已有对应分组行为。两边都新增了只含 deadline 的回归测试。
- **验收：** `IMPLEMENTED / TESTS PASSED`；Flutter projection suite 25/25、Native XCTest suite 83/83 通过；暂未对 deadline-only 边界做真实窗口截图验收。

### TASK-LIST-002 — Today / Recent 父任务匹配时，展开后仍显示其一级子任务

- **Flutter 代码：** [`task_tree_projection.dart`](../desktop/lib/features/tasks/application/task_tree_projection.dart#L23) 从可见根节点通过 `childrenOf(parentId)` 取子任务；[`workspace_controller.dart`](../desktop/lib/state/workspace_controller.dart#L1867) 明确 Today / Recent 遵循匹配父任务，`childRowsFor` 在第 1874 行不重新套用父列表日期过滤。子任务不会被重复提升成根行。
- **Flutter 测试：** [`task_tree_rules_test.dart`](../desktop/test/task_tree_rules_test.dart#L447) `SUB-133` 明确验证：Today 中父任务命中时，未安排日期的孩子仍作为其子行显示。
- **Native 测试：** [`TaskWorkspaceModelTests.swift`](../macos-native/WorkFollowTests/TaskWorkspaceModelTests.swift#L74) 新增 Today 与 Recent 中未排期孩子继续显示的用例。
- **Flutter 截图：** [`subtask-list-expanded.png`](screenshots/subtask-list-expanded.png)；折叠参考为 [`subtask-list-collapsed.png`](screenshots/subtask-list-collapsed.png)。
- **Native 修正前行为：** [`TaskWorkspaceModel.swift`](../macos-native/WorkFollow/Features/Tasks/TaskWorkspaceModel.swift#L98) 将 scope 匹配 ID 交给 [`TaskTreeProjection.swift`](../macos-native/WorkFollow/Application/TaskTreeProjection.swift#L10)，后者会过滤 children。原有 `testParentAndMatchingChildrenFlattenOnceAndExpandFromProjection` 给父子都设置了 Today 日期，未覆盖漏行场景。
- **实现：** Native 在 Today / Recent（Native scope 名为 `nextSevenDays`）父行匹配时不再按日期过滤其一级子行；原生搜索仍保留对孩子自身文本匹配的过滤。新增 Today 与 Recent 未排期子任务的回归测试。
- **验收：** `IMPLEMENTED / TESTS PASSED`；Flutter tree rules 26/26、Native XCTest suite 83/83 通过。All/Inbox/Completed 不套用这条规则。

### TASK-LIST-012 — 行点击选中任务；完成框只完成/恢复，不触发详情

- **Flutter 代码：** [`task_row.dart`](../desktop/lib/widgets/task_row.dart#L86) 行打开/选择；第 177 行处理行点击，完成框在第 260 行以后单独调用完成/恢复。
- **Flutter 测试：** [`ticktick_plan_widget_test.dart`](../desktop/test/ticktick_plan_widget_test.dart#L293) 测试多选态完成框会完成任务；第 318 行测试行点击/Enter 选择及 Space 完成。但这些断言没有确认完成框操作后 Inspector/选中态不变。
- **Flutter 截图：** 没有覆盖两个点击热区的静态截图。
- **Native 当前行为：** [`TaskListView.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift#L98) 将选中与完成分别传入；[`TaskRowView`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift#L199) 用分离的 SwiftUI Button。
- **差异与实现：** Flutter 将整行设为可点区域，但完成框、展开按钮和日期仍各自执行动作。Native 现在将标题/正文和右侧静态元数据都设为独立选中入口；完成框、展开按钮及日期 chip 仍各自独立，不会被行选择手势吞掉。
- **验收：** `MATCH（代码结构 + Native 真窗口操作）`；2026-09-24 在 Native Preview 窗口点击父任务完成框，Inspector 仍显示同一任务，父项和两个一级孩子按级联规则完成；随后通过应用 Undo 恢复，确认选择、计数、任务状态回到原样。2026-09-25 重启最新构建后点击任务行右侧清单元数据，Inspector 打开了该行任务；自动 UI test 仍缺。

## P1：主列表语义与操作路径

### TASK-LIST-003 — Today 的 overdue / today / completed 分组及完成、恢复

- **Flutter 代码：** [`task_list_projection.dart`](../desktop/lib/features/tasks/application/task_list_projection.dart#L250)；Today 使用 `已过期 → 今天 → 已完成`，已完成分组只收纳符合该视图范围的 closed task。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart#L95) `LIST-001`、`LIST-006`；完成/恢复行为另由 [`task_tree_rules_test.dart`](../desktop/test/task_tree_rules_test.dart#L14) 起的规则测试覆盖。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png)。
- **Native 当前行为：** [`TaskListProjection.swift`](../macos-native/WorkFollow/Application/TaskListProjection.swift#L62) 有 overdue/today/closed 分组；[`TaskWorkspaceModelTests.swift`](../macos-native/WorkFollowTests/TaskWorkspaceModelTests.swift#L28) 覆盖完成后 count 减一、Today closed group 出现、恢复后返回。
- **差异：** 普通 due date 与完成/恢复的模型路径基本一致；截止日期单独命中 Today 的边界归 `TASK-LIST-001`。
- **Native 新增测试：** [`TaskDomainTests.swift`](../macos-native/WorkFollowTests/TaskDomainTests.swift#L42) 覆盖 overdue → today → completed 顺序、Tomorrow 排除和 Today 计数。
- **验收：** `MATCH（投影 + Native/Flutter 定向测试 + 部分真实 UI 操作）`；在最新 Preview 构建的 Today 页面选中父任务后点完成框，Inspector 仍为该任务，Today badge 从 5 变 2、Completed 从 1 变 4；随后 Undo 恢复原状。没有自动 UI test，逾期组没有真实数据截图，故仍不标记 `PARITY VERIFIED`。

### TASK-LIST-004 — Inbox 只展示收集箱范围内任务

- **Flutter 代码：** [`task_projection.dart`](../desktop/lib/features/tasks/application/task_projection.dart#L30) 的活动行只取收集箱；但 [`task_list_projection.dart`](../desktop/lib/features/tasks/application/task_list_projection.dart#L192) 的 closed-group scope 对 `inbox` 没有清单条件，可能把其他清单的已完成任务也并入 Inbox 完成组。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart) 的 `TASK-LIST-004` 验证其他清单的已完成任务不会混入 Inbox 完成组。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png) 不是 Inbox 截图；无跨清单完成分组截图。
- **Native 当前行为：** [`TaskListProjection.swift`](../macos-native/WorkFollow/Application/TaskListProjection.swift#L27) 先按 `task.list == .inbox` 限定匹配结果，再生成 closed group。
- **实现：** Inbox 的 closed 分组也按当前页面作用域过滤。Flutter `_hits('inbox', ...)` 现在要求任务属于“收集箱”；Native `TaskListProjection.matches(.inbox, ...)` 本来已限制为收集箱。两端均有“其他清单已完成任务不得泄漏进 Inbox”回归覆盖。
- **验收：** `IMPLEMENTED / TESTS PASSED`；Flutter Task List/Tree 定向测试 51 项通过，最新 Native XCTest 84/84 通过。尚未真实窗口构造跨清单已完成任务场景，不标记 `PARITY VERIFIED`。

### TASK-LIST-005 — 最近 7 天保留逾期项，并按日期升序分组

- **Flutter 代码：** [`task_projection.dart`](../desktop/lib/features/tasks/application/task_projection.dart#L302) 以 `dueAt < 今天 + 7 天` 过滤，因而逾期和今天都在范围内；[`task_list_projection.dart`](../desktop/lib/features/tasks/application/task_list_projection.dart#L260) 先列逾期，再按每天升序分组。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart#L111) `LIST-002` 和第 125 行的窗口边界用例。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png) 仅展示分组形态；其中有一个测试字体方框伪影，不能当作精确视觉验收图。
- **Native 修正前行为：** [`TaskListProjection.swift`](../macos-native/WorkFollow/Application/TaskListProjection.swift#L31) 只取今天至第七天前的 due/deadline，并将结果放入一个 plain group；逾期不在此 scope，deadline 也会改变入选范围。
- **已消除的差异：** Native 原先不包含 Flutter Recent 的逾期项、没有逐日分组，并错误地用 deadline 扩大范围；本轮已按 Flutter 的 due-day 口径修正。
- **实现：** Native Recent 现在只依据 due day，以“今天往前不设下界、今天 + 7 天不含当天”为命中范围；活动任务先显示逾期组，再按日期升序显示今天/逐日组，最后显示已完成组。deadline-only 任务不进入 Recent，与 Flutter 当前投影一致。新增固定时钟测试覆盖逾期、逐日顺序、第 7 天边界、仅截止日期和已完成任务分组。
- **验收：** `IMPLEMENTED / TESTS PASSED + PARTIAL UI CHECK`；Native XCTest 最新 83/83、Flutter projection 25/25 通过。Native Preview 窗口已核对“今天 → Sep 25 → 已完成”分组顺序；逾期组暂无真实窗口样例，故不标记 `PARITY VERIFIED`。

### TASK-LIST-006 — All 的分组、置顶和组内顺序

- **Flutter 代码：** [`task_list_projection.dart`](../desktop/lib/features/tasks/application/task_list_projection.dart#L159) 置顶组优先；All 其后按 `已过期 / 今天 / 最近 7 天 / 更远 / 无日期 / 已完成` 分组，见第 233 行起。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart#L131) `LIST-003`、第 226 行 `LIST-012`。
- **Flutter 截图：** [`tasks-list.png`](screenshots/tasks-list.png)；该图有明显测试字体替代方框，只作结构参考。分组较清晰的参考图为 [`task-list-groups.png`](screenshots/task-list-groups.png)。
- **Native 修正前行为：** [`TaskListProjection.swift`](../macos-native/WorkFollow/Application/TaskListProjection.swift#L62) 将所有 open task 放在一个 plain group，再接 completed；Native `Task`/group 没有 `isPinned`/pinned group，也没有置顶操作。
- **实现：** Native All 已按 `置顶 → 已过期 → 今天 → 最近 7 天 → 更远 → 无日期 → 已完成` 投影；最近窗口取今天之后且早于第七天，恰好第七天归入“更远”。日期比较只看 `dueAt`，deadline-only 仍归“无日期”，与 Flutter 的 All 分组一致。已置顶活动任务在 Today、Recent 和 Inbox 也先于普通分组；置顶入口放在任务行右键菜单，行内保留图钉标记。清单/标签筛选维持普通 plain 组，置顶项仍独立置顶组。Native 搜索没有 Flutter 对等筛选契约，当前保留命中结果的日期分组，这是 Native 既有搜索体验，不据此宣称 Flutter parity。新增测试覆盖 All 顺序、最近窗口边界、同日稳定顺序、deadline-only、清单/标签筛选、Today/Inbox 置顶顺序及旧快照缺失 `isPinned` 时的默认值。
- **Native 定向测试：** [`TaskDomainTests.swift`](../macos-native/WorkFollowTests/TaskDomainTests.swift) 新增投影、置顶筛选与快照兼容用例；Flutter `task_list_projection_test.dart` 当前 25/25 通过。
- **验收：** `IMPLEMENTED / TESTS PASSED / UI NOT CHECKED`；最新 Native XCTest 83/83 通过。当前真实窗口未操作置顶右键入口或 All 分组，所以不标记 `PARITY VERIFIED`。

### TASK-LIST-007 — Overdue 是分组，不是独立导航目的地

- **Flutter 代码：** [`workspace_controller.dart`](../desktop/lib/state/workspace_controller.dart#L26) `WorkspaceView` 没有 overdue；逾期任务由 Today/Recent 投影分组，另有 `overdueTasks` getter。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart#L395) `LIST-007/008` 明确断言任务导航不提供“过期”入口。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png) 展示逾期组。
- **修正前：** Native `AppNavigation` 和 `TaskListScope` 都暴露独立 `.overdue` 目的地，并将 due/deadline 任一过期作为入口过滤条件；Flutter 只有 Today/Recent/All 等列表中的逾期分组，没有“过期”导航页。
- **实现：** 移除 Native 独立 overdue destination/scope；任务导航清单现在与 Flutter 一样不提供该入口。逾期任务仍按 due date 出现在 Today/Recent/All 对应分组中；Today 的 deadline-only 可见规则保留在 `TASK-LIST-001`，不再因单独 overdue 页扩展口径。
- **测试：** `NativeSmokeTests.testTaskNavigationMatchesFlutterWithoutStandaloneOverdueDestination` 校验任务导航目的地清单且无“过期”入口。
- **验收：** `IMPLEMENTED / TESTS PASSED / UI BLOCKED`；Native XCTest 84/84、Flutter Task List/Tree 51/51 通过。当前 Mac 已锁定且 CUA 无法自动解锁，尚未真实窗口确认侧栏和 `⌘K` 均不再出现“过期”，因此不标记 `PARITY VERIFIED`。

### TASK-LIST-008 — Completed 按关闭日期分组，包含的 closed 状态需一致

- **Flutter 代码：** [`task_list_projection.dart`](../desktop/lib/features/tasks/application/task_list_projection.dart#L317) 按完成/放弃时间倒序分组，同一天内部也按关闭时间倒序；可合并 completed 与 abandoned。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart#L160) `LIST-004`，并有第 175 行 abandoned 日期用例。
- **Flutter 截图：** [`task-list-completed-rows.png`](screenshots/task-list-completed-rows.png)；字体替代问题见截图测试代码注释。
- **Native 当前行为：** [`TaskListProjection.swift`](../macos-native/WorkFollow/Application/TaskListProjection.swift#L65) 按 `closedAt` 倒序分组；[`Task.swift`](../macos-native/WorkFollow/Domain/Task/Task.swift#L61) 以独立 `abandonedAt` 表达放弃状态，不扩充完成状态枚举。
- **差异与 Flutter 口径：** Flutter 的普通任务视图会把 completed 与 abandoned 纳入 closed；Skipped/converted 在进入普通列表投影前已被排除，因此本条只需补 abandoned，不应引入额外 closed 状态。Today 特别排除 abandoned；已完成按完成/放弃时间分组、同日按关闭时间倒序，无关闭时间的任务落入“无日期”。
- **Native 实现：** `isClosed` / `closedAt`、放弃/恢复动作、Today 排除与 Completed 日期分组已补；All/Inbox 等普通范围的 closed group 也包含放弃任务。
- **验收：** `IMPLEMENTED / TESTS PASSED / UI NOT CHECKED`；macOS 27.0 XCTest 最新 83/83 通过，固定时钟用例覆盖 abandoned 的 Today 排除、恢复回原范围、Completed 日期分组和同日排序。尚未对 abandoned 真实窗口截图验收。

### TASK-LIST-009 — 分组可折叠，默认展开；完成组可统一折叠/展开

- **Flutter 代码：** [`today_screen.dart`](../desktop/lib/screens/today_screen.dart#L83) 默认所有组展开；第 99 行可切换单组，第 105 行起统一切换所有完成组。
- **Flutter 测试：** [`task_group_fold_postpone_test.dart`](../desktop/test/task_group_fold_postpone_test.dart#L85) 与第 114 行；与 [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart) 合跑 30/30 通过。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png)、[`task-list-groups-folded.png`](screenshots/task-list-groups-folded.png)。
- **Native 当前行为：** [`TaskListView.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift#L150) 标题点击可折叠对应任务树；[`TaskGroupExpansionState`](../macos-native/WorkFollow/Application/TaskListProjection.swift#L43) 以稳定 ID 保留折叠状态，并提供已完成组统一开合。
- **实现：** 所有有标题的组默认展开；Completed 日期组使用日期 ID，标签变化不会换组；已完成页打开某个任务时自动展开其日期组。列表更多菜单的“展开/收起已完成”只作用于当前投影中的 closed 组，混合状态时统一折叠、全折叠时统一展开。
- **验收：** `IMPLEMENTED / TESTS PASSED / REAL WINDOW CHECKED`；macOS 27.0 XCTest 83/83 通过。Native 窗口已实际验证 Today 的已完成组折叠/菜单展开，以及 Completed 页日期组折叠/菜单展开；未验证跨页面保留折叠状态，因此不提升为 `PARITY VERIFIED`。

### TASK-LIST-010 — 子任务默认展开，并限制一级层级

- **Flutter 代码：** [`workspace_controller.dart`](../desktop/lib/state/workspace_controller.dart#L1931) 新父任务默认展开；[`task_tree_projection.dart`](../desktop/lib/features/tasks/application/task_tree_projection.dart#L27) 默认深度上限为 1。
- **Flutter 测试：** [`task_tree_test.dart`](../desktop/test/task_tree_test.dart#L330) `SUB-012/013/016`。
- **Flutter 截图：** [`subtask-list-expanded.png`](screenshots/subtask-list-expanded.png)、[`subtask-list-collapsed.png`](screenshots/subtask-list-collapsed.png)。
- **Native 当前行为：** [`TaskWorkspaceModel.swift`](../macos-native/WorkFollow/Features/Tasks/TaskWorkspaceModel.swift#L16) 现在只记录 `collapsedTaskIDs`；未手动收起的父任务默认展开。创建子任务后不需额外插入展开状态；[`TaskTreeProjection.swift`](../macos-native/WorkFollow/Application/TaskTreeProjection.swift#L12) 仍只投影一级孩子。
- **差异：** 已纠正新建/加载父任务默认折叠的问题；手动折叠状态仍由 UI 模型保留。Native 的旧 `TaskListQuery.search` 树筛选路径只保留在模型/基础设施测试中，任务页已不再提供对应输入；⌘K 是全局结果列表，只负责路由并选中任务，不会触发树搜索展开。
- **验收：** `IMPLEMENTED / TESTS PASSED / REAL WINDOW CHECKED`；Flutter `task_tree_test.dart` 19/19、Native XCTest 83/83 通过。Native 窗口中父任务默认显示向下箭头及两个子任务；点击收起后子行消失，再次点击恢复；子任务行没有继续展开入口，层级仍为一级。

### TASK-LIST-011 — 父子完成/恢复语义

- **Flutter 代码：** Task 完成/恢复统一走 `TaskActions`；任务行勾选入口见 [`task_row.dart`](../desktop/lib/widgets/task_row.dart#L333)。
- **Flutter 测试：** [`task_tree_rules_test.dart`](../desktop/test/task_tree_rules_test.dart#L14) `SUB-080/081/136`：完成子项不影响父项；完成父项带动孩子；恢复父项不强制恢复孩子。
- **Flutter 截图：** 无专门完成父子级联交互截图；[`subtask-list-expanded.png`](screenshots/subtask-list-expanded.png) 只作结构参考。
- **Native 当前行为：** [`TaskDomainTests.swift`](../macos-native/WorkFollowTests/TaskDomainTests.swift#L66) 与第 75 行覆盖上述核心规则。
- **差异：** Domain 规则与 Flutter 一致；本轮在 Native Preview Today 真实窗口中点击父任务完成框，父项和两个活动孩子同时完成且进入 Completed；点击 Undo 后 Today/Overdue/Completed 计数及父子状态恢复。
- **验收：** `MATCH（Domain + REAL WINDOW CHECKED）`；macOS 27.0 XCTest 83/83 通过。该 Preview 数据操作已撤销；暂无自动化 UI Test。

### TASK-LIST-013 — 键盘选择、多选与批量操作

- **Flutter 代码：** [`task_row.dart`](../desktop/lib/widgets/task_row.dart#L156) Enter、Space、上下键；[`task_selection_controller.dart`](../desktop/lib/features/tasks/application/task_selection_controller.dart#L4) Meta/Ctrl 多选及 Shift 区间选择；TodayScreen 有批量操作栏。
- **Flutter 测试：** [`ticktick_plan_widget_test.dart`](../desktop/test/ticktick_plan_widget_test.dart#L318) 覆盖 Enter/Space；[`task_actions_test.dart`](../desktop/test/task_actions_test.dart#L58) 覆盖相邻及区间选择；[`workspace_behavior_test.dart`](../desktop/test/workspace_behavior_test.dart#L629) 覆盖批量完成/删除。Meta/Ctrl 与 Shift 修饰键的完整 UI 焦点路径仍缺专门测试。
- **Flutter 截图：** 无键盘焦点或多选态截图。
- **Native 当前行为：** [`TaskListView.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift#L116) 支持上下键和 Return；无 Space 完成、Meta/Ctrl 多选、Shift 区间选择或批量栏。
- **差异：** Native 现已提供 Up/Down、Return、Space、Command/Ctrl 点选、Shift 区间选择和批量操作栏。此前 Shift 范围错误使用 Inspector 选中任务作为锚点；现在按 Flutter `TaskSelectionController` 以最近一次普通/Command 点选为锚点。区间修改保留原 Inspector 选择；方向键选择则清除批量选择并更新 Inspector。
- **Native 测试：** [`TaskWorkspaceModelTests.swift`](../macos-native/WorkFollowTests/TaskWorkspaceModelTests.swift) 的 `testBulkShiftRangeUsesMostRecentSelectionAnchorLikeFlutter` 验证锚点、区间和 Inspector 选择分离。
- **验收：** `IMPLEMENTED / TESTS PASSED / UI MODIFIERS NOT VERIFIED`；Native XCTest 83/83、Flutter Task List/Tree 51/51 通过。修饰键鼠标路径尚未通过真实窗口验证，暂不标记 `PARITY VERIFIED`。

### TASK-LIST-014 — 当前页筛选与全局搜索必须区分

- **Flutter 代码：** [`task_projection.dart`](../desktop/lib/features/tasks/application/task_projection.dart#L75) 标签筛选可与 view 组合；清单筛选只在 `all` 应用。任务搜索入口是全局 [`command_palette.dart`](../desktop/lib/widgets/command_palette.dart#L103)，不是列表内实时过滤；选择结果通过 `openTask` 打开归属任务。
- **Flutter 测试：** [`workspace_behavior_test.dart`](../desktop/test/workspace_behavior_test.dart#L1289) 覆盖 ⌘K 搜索和打开；清单/标签与各 View 组合没有找到完整矩阵测试。
- **Flutter 截图：** 无任务列表筛选态截图；`⌘K` 是全局面板而非 List filter。
- **Native 当前行为：** [`CommandPaletteView.swift`](../macos-native/WorkFollow/Features/Shell/CommandPaletteView.swift) 与 [`CommandPaletteProjection.swift`](../macos-native/WorkFollow/Features/Shell/CommandPaletteProjection.swift) 提供全局搜索：空查询显示 9 个导航/外观命令；有查询时依次提供创建任务、至多 7 条活动任务、至多 5 条活动笔记及匹配命令。点击或键盘确认任务结果会路由到收集箱/所属清单并选中任务；笔记结果切到笔记并选中命中笔记。任务行已移除 Flutter 没有的页内搜索/清单/标签筛选控件；清单与标签筛选只通过导航列进入“所有任务”应用。
- **剩余差异：** Flutter 搜索字段还包含旧任务 `description`/`note` 和笔记 `preview`；Native 的对应数据结构没有这些独立字段，因此搜索 Native `document.plainText`。真实窗口已核对 ⌘K 查询、任务命中后路由到所属清单并选中、Escape 关闭；笔记命中和完整键盘导航仍未逐项截图核验。搜索结果不是列表过滤，不定义父子树提升/自动展开行为。
- **Native 测试：** [`CommandPaletteTests.swift`](../macos-native/WorkFollowTests/CommandPaletteTests.swift) 覆盖空查询命令集合、创建优先级、任务/笔记字段搜索与上限、排除删除内容、命令搜索、路由选中、创建清单及 Today 日期默认值。
- **验收：** `IMPLEMENTED / TESTS PASSED / PARTIAL REAL-WINDOW CHECK`；Native XCTest 102/102 通过。任务查询、打开路由与 Escape 已通过真窗口验收；笔记命中和完整键盘路径尚缺，暂不标记 `PARITY VERIFIED`。

### TASK-LIST-015 — Context Menu 操作集合

- **Flutter 代码：** [`task_context_menu.dart`](../desktop/lib/widgets/task_context_menu.dart#L13) 与 [`task_menu_actions.dart`](../desktop/lib/widgets/task_menu_actions.dart#L24) 支持日期快捷项/自定义/清除、优先级、清单、标签、子任务、置顶、放弃/恢复、跳过重复、转笔记、删除等。
- **Flutter 测试：** [`ticktick_plan_widget_test.dart`](../desktop/test/ticktick_plan_widget_test.dart#L806) 验证行右键菜单属性操作；第 842 行验证日期、完成、优先级动作；[`task_context_menu_panel_test.dart`](../desktop/test/task_context_menu_panel_test.dart#L26) 覆盖菜单面板选项。
- **Flutter 截图：** [`task-menu-light.png`](screenshots/task-menu-light.png) 与 [`task-menu-dark.png`](screenshots/task-menu-dark.png) 是菜单外观参考。
- **Native 当前行为：** [`TaskListView.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift) 通过次级鼠标点击显示 [`TaskContextMenuPopover.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskContextMenuPopover.swift)：包含日期快捷项、自定义日期/清除、重复任务跳过、优先级、创建子任务、置顶/放弃、清单/标签、转换笔记和删除。清单子面板有搜索，标签继续用可搜索、多选、创建、取消/确认的草稿面板；Native-only 的打开/完成/展开菜单项已移除。点击“添加子任务”保持父任务选中并在 Inspector 聚焦新孩子标题。
- **剩余差异：** 菜单 popover 目前以任务行作为锚点，Flutter 按右键指针位置锚定；Native 的日期快捷项排列、菜单留白和优先级/日期控件仍需与 Flutter 截图逐像素比较。真窗口已确认右键触发自绘面板、清单与标签子面板打开、子面板 Escape 关闭且主菜单仍在；尚未实点执行菜单动作、验收焦点/完整键盘导航和日期选择后的切换。日期弹层另由日期契约核对。Flutter 右键菜单不含其 Inspector 专属的提醒、重复、截止日期、附件、关联笔记操作，Native 也未加入这些动作。
- **Native 测试：** [`TaskWorkspaceModelTests.swift`](../macos-native/WorkFollowTests/TaskWorkspaceModelTests.swift) 验证右键“添加子任务”创建空孩子、保留父任务选择并发出内联标题编辑请求。最新完整 `xcodebuild test` 已通过；菜单面板目前无独立 UI 自动化用例。
- **验收：** `IMPLEMENTED / PARTIAL ACTION PARITY / PARTIAL REAL-WINDOW CHECK`；Flutter 菜单面板/动作参考测试此前 34 项通过。真实窗口验收覆盖右键、清单搜索面板和标签草稿面板的开启及 Escape 关闭；动作提交与精确菜单位置/焦点仍未核验，不标记 `PARITY VERIFIED`。

### TASK-LIST-016 — Quick Add 的目标、默认值和属性输入

- **Flutter 代码：** [`quick_add.dart`](../desktop/lib/widgets/quick_add.dart#L106) 有实时自然语言解析、日期/时间、重复、标签、清单、优先级、提醒等草稿属性；Today 默认安排今天，Inbox 和其他视图默认不安排日期（见 [`workspace_controller.dart`](../desktop/lib/state/workspace_controller.dart#L3214)）。TodayScreen 中除 Completed 外的任务列表提供 Quick Add。
- **Flutter 测试：** [`quick_add_focus_test.dart`](../desktop/test/quick_add_focus_test.dart#L18) 及第 78 行验证目标文案和日期/属性操作后焦点；创建行为也由 `task_actions_test.dart` 中 `QUICK-*` 覆盖。
- **Flutter 截图：** 没有可靠的 Quick Add 全属性交互截图；`tasks-list.png` 的测试字体存在方框伪影。
- **Native 当前行为：** [`QuickAddParser.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/QuickAddParser.swift) 已解析常用相对/绝对日期、时间、星期、日/周/月重复、标签、已存在清单和优先级；Today 默认今天，Inbox/All/最近 7 天默认无日期。聚焦 Quick Add 后显示固定日期入口，可在就地草稿面板设置日期、时间、提醒和重复；清除会把这组安排属性恢复为空，取消不写入草稿，确认后回到标题输入。手动日期选择保存在草稿中，回车创建和打开完整表单创建都沿用该值；移除被识别的日期/时间 chip 后不会再偷偷注入 Today 默认日期。
- **剩余差异：** Flutter 在输入框内高亮 token，并从日期 chip、属性 disclosure 打开不同 picker；Native 仍显示输入框下方 chips，属性 disclosure 的菜单结构与焦点/弹层路径仍未完全复刻。Flutter 和 Native 都只把已有清单名作为列表标记识别；目前没有确认两端在这一点上存在行为差异。移除 token 后原文作为标题的规则及星期映射有 Native parser 回归测试。
- **验收：** `PARTIAL IMPLEMENTATION / TESTS PASSED / PARTIAL REAL-WINDOW CHECK`；Native XCTest 通过，Flutter `quick_add_focus_test.dart` 此前 3/3 通过。2026-09-25 真窗口截图核对了 Quick Add 属性面板、清单子 picker 与 Escape 关闭；全属性创建、标签路径、键盘焦点/完整 Escape 链仍未核验，不标记 `PARITY VERIFIED`。

### TASK-DATE-001 — 右键“清除日期”和日期面板“清除”的副作用范围不同

- **Flutter 代码：** 右键 `clear-date` 走 [`workspace_controller.dart`](../desktop/lib/state/workspace_controller.dart#L1159) 的 `updateTaskDue(id, null)`，移除安排日期/日期范围与相对提醒，但保留重复和独立绝对提醒；日期面板底部“清除”返回空 `TaskScheduleSettings`，会一并清除安排日期、提醒与重复，截止日期是独立属性。
- **Flutter 测试：** [`task_editor_popovers_test.dart`](../desktop/test/task_editor_popovers_test.dart#L308) 覆盖清理后撤销能还原日期范围、提醒和重复；右键清除对独立提醒/重复的完整组合无单测。
- **Native 实现：** 右键清除走 `clearDueDate`，保留 `reminderAt`、截止日期和重复；日期面板清除走 `clearScheduledProperties`，清除安排日期、提醒和重复，但保留独立截止日期。两种路径均作为单步 Undo 操作。
- **差异/限制：** Native `TaskSchedule.dueEndAt` 和 `Task.reminderOffsets` 已有独立字段；迁移边界分别保留日期区间，并将 Flutter 的正数“提前分钟”转换成 Native 的负分钟偏移。右键清除仍保留独立绝对提醒与重复。弹层操作路径尚未完成真实窗口验收。
- **验收：** `IMPLEMENTED / TESTS PASSED / PARTIAL REAL-WINDOW CHECK`；Native 对应清除和 Undo 回归包含在 XCTest 96/96 中，Flutter 日期弹层及 task action 测试 26/26 通过。真实窗口已打开日期弹层并用 Escape 关闭，未提交日期更改；各自清除按钮和撤销路径尚未真窗口验收，不能标记 `PARITY VERIFIED`。

### TASK-DATE-002 — 日期派生视图随时钟推进刷新

- **Flutter 代码：** [`app.dart`](../desktop/lib/app.dart#L283) 每分钟调用 [`WorkspaceController.refreshDates`](../desktop/lib/state/workspace_controller.dart#L2111)，使 Today、逾期组与日期徽标跨日更新。
- **Native 实现：** [`AppEnvironment.swift`](../macos-native/WorkFollow/App/AppEnvironment.swift) 每分钟、收到系统日历换日通知及应用重新激活时调用 `TaskWorkspaceModel.refreshDates()`；独立 `dateRevision` 触发 SwiftUI 重新计算日期投影，不改变任务 `revision`，不触发持久化。
- **Native 测试：** [`TaskWorkspaceModelTests.swift`](../macos-native/WorkFollowTests/TaskWorkspaceModelTests.swift) 将固定时钟推进一天，验证任务从 Today 组进入 overdue 组，同时任务数据修订号不变。
- **验收：** `IMPLEMENTED / TESTS PASSED / EVENT WIRING CODE-REVIEWED`；当前全量 XCTest 479/479 通过。没有做跨午夜实时时间等待；计时器、系统日历换日和应用激活通知的接线已代码核对，但未做长时间窗口观察。

### TASK-LIST-020 — 相对提醒必须显示行标记并保持迁移语义

- **Flutter 代码：** [`task.dart`](../desktop/lib/models/task.dart#L72) 将正数 `reminderOffsets` 解释为提前分钟；[`task_metadata_trail.dart`](../desktop/lib/widgets/task_list/task_metadata_trail.dart#L96) 只要 `reminderTimes` 非空就显示提醒标记。
- **Native 实现：** [`MigrationSnapshot.swift`](../macos-native/WorkFollow/Infrastructure/Persistence/MigrationSnapshot.swift) 在 Flutter/Native 边界反转分钟符号，导入的提前量成为负偏移，导出再转回 Flutter 正数；[`TaskListView.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift) 对绝对提醒与非空相对偏移都显示铃铛。
- **Native 测试：** [`MigrationSnapshotTests.swift`](../macos-native/WorkFollowTests/MigrationSnapshotTests.swift) 覆盖导入偏移及导出 JSON 正数语义；[`TaskListViewDefaults.swift`](../macos-native/WorkFollowTests/TaskListViewDefaults.swift) 覆盖相对、绝对和无提醒三种标记条件。
- **验收：** `IMPLEMENTED / TESTS PASSED / VISUAL NOT CHECKED`；当前全量 XCTest 479/479 通过。任务行铃铛未在真实窗口用仅含相对提醒的样例截图核验，不标记 `PARITY VERIFIED`。

### TASK-LIST-018 — 导航徽标和组标题计数的统计范围

- **Flutter 代码：** [`task_projection.dart`](../desktop/lib/features/tasks/application/task_projection.dart#L127) 的导航计数按 view 统计所有匹配任务；[`task_list_projection.dart`](../desktop/lib/features/tasks/application/task_list_projection.dart#L40) 的 group.tasks 是根行，组标题计数因此不重复计算嵌套孩子。
- **Flutter 测试：** [`task_list_projection_test.dart`](../desktop/test/task_list_projection_test.dart#L131) 校验分组成员；专门覆盖“导航徽标含子任务、组计数只数根行、筛选不改全局徽标”的组合测试未找到。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png) 可参考组标题计数；部分字符受测试字体影响。
- **Native 当前行为：** [`TaskListView.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift#L41) 页面标题显示 scope 总数，第 151 行显示根 group.tasks 数量；[`TaskWorkspaceModel.swift`](../macos-native/WorkFollow/Features/Tasks/TaskWorkspaceModel.swift#L87) 的 scope count 不接收 query。
- **差异：** 基本统计口径接近，但 Native 页标题额外显示 count（Flutter `TaskListHeader` 不显示），且 Native 的 Recent/Overdue 范围、Flutter 的 abandoned/skipped/converted 状态会影响徽标值。两端缺少同一组固定数据的跨筛选断言。
- **验收：** `MATCH（根行组计数）/ DIFF（徽标范围与位置待核）`；`NOT VERIFIED`。

## P2：辅助列表行为

### TASK-LIST-019 — 行元数据右对齐、主要属性保留，次要属性最多显示三个

- **Flutter 代码：** [`task_metadata_trail.dart`](../desktop/lib/widgets/task_list/task_metadata_trail.dart) 先显示置顶/放弃/清单/优先级，再按子任务数、重复、提醒、标签、描述、附件顺序最多显示三个次要标记；截止与安排日期随后固定保留。元数据列上限由 `TaskListMetrics.metadataMaxWidth` 控制。
- **Native 当前行为：** [`TaskListView.swift`](../macos-native/WorkFollow/Features/Tasks/TaskList/TaskListView.swift) 使用相同主要/次要顺序与三个标记上限；静态元数据区域也能选中所属任务，日期 chip 保持单独编辑入口。
- **本轮修正：** Native 原先不限制次要标记数量，且静态元数据点选不会打开任务。现已限制次要标记数，并将元数据区域接入任务选择。
- **验收：** `IMPLEMENTED / TESTS PASSED / PARTIAL REAL-WINDOW CHECK`；当前 Preview 真窗口存在三枚次要标记的行，可核对布局；点击另一行的清单元数据后，Inspector 显示该行任务。当前数据没有超过三个次要标记的任务，故上限的截断外观未通过真实样例验证，不标记 `PARITY VERIFIED`。相对提醒和安排日期区间仍受 `TASK-DATE-001` 所述 Native 字段差异限制。

### TASK-LIST-017 — 逾期组顺延与列表排序菜单

- **Flutter 代码：** [`today_screen.dart`](../desktop/lib/screens/today_screen.dart#L371) 列表头提供排序/更多操作；第 446 行保持 Completed 关闭时间顺序，第 473 行起为逾期组提供“顺延”。
- **Flutter 测试：** [`task_group_fold_postpone_test.dart`](../desktop/test/task_group_fold_postpone_test.dart#L137) 覆盖整组顺延、保留时间与 Undo。
- **Flutter 截图：** [`task-list-groups.png`](screenshots/task-list-groups.png) 可参考 overdue 组操作位；无排序弹层截图。
- **Native 当前行为：** `TaskListView` 暂无逾期整组顺延入口或同等排序菜单。
- **差异：** 辅助批量入口缺失。
- **验收：** `DIFF`；`NOT VERIFIED`。

### EDITOR-001 — `/` 与中文顿号 `、` 都可唤起文字格式命令弹框

- **Flutter 基准：** `SlashCommandSession` 仅识别新插入的 `/`。中文顿号触发器是用户新增的 Native 需求，不作为 Flutter parity 声明。
- **Native 要求：** 在任务和笔记正文编辑器中，`/` 或 `、` 仅在文档首位或前一个字符为空白（空格、换行等）时打开现有文字格式命令弹框；紧贴普通文字时仅插入字符。中文输入法提交的单个 `、` 遵循同一边界。用任一触发符替换选中文本时仍按普通文本编辑，不弹框。选择命令只移除触发符/查询并执行原有格式动作；Escape 关闭弹框但保留输入文本。
- **测试：** Native `SlashSessionTests` 覆盖任务/笔记两种 profile、两个触发符、首位/空格/换行边界、紧贴文字不触发、替换选区不触发、IME 标记文本提交及执行格式命令。
- **验收：** `IMPLEMENTED / TESTS PASSED / REAL WINDOW NOT CHECKED`；macOS 27.0 全量 XCTest 546/546、SlashSession 定向测试 19/19 通过。测试覆盖标记文本提交路径，但尚未在真实中文输入法和窗口中确认弹框显示与位置；不宣称 Flutter parity。

## 本轮审计结论与施工顺序

### Task Inspector Round 1 — 外框 / Header / 父级上下文（2026-09-30）

> 以下为历史 Flutter 对齐记录。当前 Task surface 改用 [TickTick Task Surface Parity](ticktick-task-surface-parity.md)：Header 不显示 Reminder，空 Inspector 不显示操作文字；后续 breadcrumb/Footer 等按新契约分笔修正。

- **Flutter 基准：** `desktop/lib/widgets/task_detail.dart` 的 Header、Footer 与父任务上下文。读取实际尺寸后，`TaskInspectorMetrics` 锁定 Header 58pt、Footer 52pt、水平 padding 20pt、竖分隔线 1×20pt；没有采用建议起点 54pt。Breadcrumb 高度 30pt 是本轮 Native 结构契约。
- **TASK-INSPECTOR-001：** Header 为窄屏 Back、Completion、Divider、可横向滚动的 Schedule/Reminder/Repeat、固定右侧 Priority。提醒包含相对 offsets，重复包含 recurrenceRule；点击复用 `TaskDatePopoverV2` 对应页面。移除 Header 的 Focus/Pin，保留专注能力与 More 中的置顶；没有修改 More 内容、日期面板内部或 Shell breakpoint。
- **TASK-INSPECTOR-002：** 子任务父级 breadcrumb 在标题之前，显示实际父任务名称，点击选择父任务。本轮按用户要求使用左 chevron，不将该方向声称为 Flutter 原样复刻。
- **TASK-INSPECTOR-003：** `TaskEmptyInspectorView` 独立呈现居中图标、选择任务标题与说明。
- **TASK-INSPECTOR-004：** 新增结构 Metrics；Footer 浮层 inset 从 Footer 高度推导，避免更高 Footer 遮住原有操作面板。正文、子任务区与富文本实现保持不变，细部垂直几何留待 Round 2。
- **自动验收：** `TaskInspectorShellContractTests` 通过 NSWindow/NSHostingView 验证 320/760pt Header、长日期滚动区与固定 Priority、条件属性图标、窄屏 Back、Breadcrumb 先于标题及空状态居中；`TaskInspectorPresentationTests` 验证 Reminder/Repeat 的 Escape 先于编辑结束和窄屏返回。定向 XCTest 与构建通过。
- **真实窗口：** 退出旧进程并重新启动本轮构建，宽屏选任务后列表保留；Reminder/Repeat 点击进入对应页面并可 Escape 关闭；子任务顶部显示父名，点击可回父任务；宽屏非编辑 Escape 保留 Inspector。未选任务显示新空状态说明。截图见本轮工具输出。
- **验收状态：** `IMPLEMENTED / TESTS PASSED / WIDE WINDOW CHECKED`。窄屏真窗口返回与完整逐像素对照尚未验收，不标记整个 Inspector 为 `PARITY VERIFIED`。

### Task List Round 3 — 树几何 / 折叠 / 拖拽（2026-09-30）

- **Flutter 基准：** `desktop/lib/widgets/task_row.dart`、`widgets/task_list/task_list_row.dart` 和 `theme/workfollow_theme.dart`。所有行保留 disclosure 22pt + gap 2pt，子行右移 24pt；正文预览只取自身 document，折叠只停止输出 children。
- **Native：** 移除原来的 14pt 根行槽、44pt 子行补偿与合成子任务预览。根任务独占 drag source/drop target，原生 pointer drag 保留；标题拖拽卡宽 360pt，插入条高 3pt。
- **分隔线决定：** Flutter 现有 dividerLeftInset 实值是 6pt，与本轮“贴近 checkbox 列”的明确要求不同。Native 本轮按该要求从 rowHorizontalPadding + disclosureWidth + disclosureTitleGap 推导根 checkbox X = 32pt，dividerLeading = 30pt；父子行使用同一个起点，不随展开状态漂移。这是用户本轮指定的几何，不宣称与 Flutter 6pt 常量一致。
- **自动验收：** `TaskTreeGeometryContractTests` 挂载真实 NSHostingView/NSWindow，验证父行与普通根行 checkbox X 一致、子行偏移 24pt、disclosure 22pt/gap 2pt、折叠无合成预览但自身正文保留、拖拽卡 360pt 和 marker 3pt。现有 `ListMetaTests.testReorderBoundariesFirstLastAndChildren` 验证 drop-before 得到 A/C/B，以及跨父子重排拒绝；TaskWorkspaceModelTests 与 TaskListViewDefaultsTests 同步回归。
- **实机验收：** 已重新启动本轮构建，检查父任务折叠时子行隐藏而自身正文预览保留，截图见本次工具输出。自动鼠标拖拽未触发可观察到的重排；原生 drag preview/marker 的鼠标全过程与实际 drop 仍待人工验证，不能标记实机通过。

### Task List Round 2 — 分组 / Quick Add / 行焦点（2026-09-30）

本轮需求中的 004/005/006 与上文既有业务契约编号重叠，因此以下按 Round 2 子项记录，不覆盖原契约。

- **分组几何：** Flutter `desktop/lib/theme/workfollow_theme.dart` 与 `widgets/task_list/task_group_header.dart` 为基线。Native `TaskListMetrics` 独立定义 18pt group gap、30pt header、11pt chevron；标题与计数垂直居中，顺延靠右，标题及剩余空白点击折叠，顺延按钮保持独立操作。
- **Quick Add：** Flutter `widgets/quick_add.dart` 的单行基线为 42pt、圆角 10pt。Native 标题行固定 42pt，不再叠加纵向 padding；未聚焦显示 ⌘N，展开后显示日期和 chevron-down。描述、识别结果继续按原逻辑增加高度。
- **行焦点：** Flutter `theme/workfollow_theme.dart` 的 `focusRing = accent × .35` 为基线。Native 在选中背景之外单独描边；Quick Add/描述框持焦时不显示行描边，选中任务保留。Quick Add 的 Escape 收起后向列表交还焦点，随后 ↑↓ 可以导航。
- **验证：** 最新构建通过 TaskListViewDefaultsTests、QuickAddCompositionTests。真实窗口已检查未展开/展开 Quick Add、行 focus ring、输入框持焦时行描边消失、Escape 后 ↓ 选择下一项与描边恢复、分组点击收起/再展开；截图在本次工具输出中。未新增自动像素差分测试，不据此声明整个 Task List 已完全对齐。

1. P0-001 的产品决定已确认，代码和测试已补；P0-002 的 Native 修正和测试已补；P0-012 已完成 Native Preview 真窗口点击与撤销验收。
2. P1-005 的投影实现和回归测试已完成；Recent 新分组的真实窗口截图仍待验收。P1-007 已删除 Native 独立“过期”目的地，保留 Today/Recent/All 内的逾期组；真实窗口检查待 Mac 解锁后补做。后续继续按优先级处理非待决策项；P1-004 已按页面作用域隔离完成项。
3. P1-014 已按源码实现全局搜索与路由，并移除列表页搜索/筛选扩展；测试通过，真实窗口/键盘验收仍欠缺。只有对应契约的 Flutter 行为、Native 定向测试和真实 UI 验收都一致后，才把 Task List 标为 `PARITY VERIFIED`。

截图说明：`docs/screenshots` 中既有 Flutter 测试图可作结构参考，但部分图使用测试引擎替代字体，存在方框/字形缺失；它们不是所有交互的验收凭证。本轮另采集 Native Preview 完成框操作后的还原状态、Today 选择与 Inspector 状态，以及最新构建的 Recent 分组窗口截图；均用于本轮人工验收，未作为仓库文件提交。
