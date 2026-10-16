# 专注复刻方案：界面、会话、记录与任务投入

设计日期：2026-10-13，Asia/Shanghai。适用分支：`experiment/macos-native`。本文件是实现方案，本轮不修改产品代码、不操作用户任务或专注记录。

目标是让专注页、任务入口、菜单栏、历史与统计围绕同一条会话工作，再按同版本滴答的实际控件与操作冻结视觉。现有页面的布局基线可以复用；仅靠复制计时器外观，无法达到复刻效果。

## 1. 证据与未确认规则

本机滴答 8.0.80 的基础 REA 结果覆盖 37 份未修改 Interface Builder 资源，整合方案时扩展为 56 份，补充在 [REA 设计证据](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/design/ticktick-replica-2026-10-14/rea-design-evidence.json)。资源证明控件、动作连接和原生通知存在，不证明动作具体算法、控件运行时可见性或像素尺寸。

当前证据文件：[REA 选定证据](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/rea-selected-evidence.json)。项目现状及复现：[对比审计](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/ticktick-rea-audit-2026-10-13.md)、[专注验证输出](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-rea-2026-10-13/FocusAuditHarness.output.txt)。

| 能力 | 滴答证据 | 可以据此设计的部分 | 尚需同版本补测的部分 |
| --- | --- | --- | --- |
| 当前计时及操作 | `TTFocusViewController`：modeButtonView、countDownView、三个 actionButton、durationAdjustContainer、minusButton/plusButton；dispatch 有 focusTypeChanged、focusStateChanged、focusTimeIntervalChanged | 独立模式、阶段、时间状态；计时数字周围的本次时长调整控件 | 各阶段动作的文案/显隐、每次加减步长、减少到已用时附近的行为 |
| 任务关联和笔记 | `TTFocusAssociation*` 有清单选择/搜索；`TTFocusDetailViewController` 有 associateButton、focusTimelineView、noteTextView | 任务搜索、关联、更换关联任务、运行中的时间轴与笔记 | 更换关联是否拆分记录、是否保留最后任务、选中预设的具体启动方式 |
| 预计投入 | `TTFocusEstimateViewController`：typePopUpButton、小时/分钟输入、pomoGoalTextField/Stepper、确认/取消 | 按番茄或时长设置预计投入；草稿确认后提交 | 范围、默认值、子任务汇总与重复任务继承口径 |
| 记录详情/编辑 | `TTFocusRecordDetail*` 有时间区间、时长、关联、笔记、deleteButton；`TTFocusRecordEdit*` 有类型、任务、开始/结束、笔记、保存/取消 | 独立记录详情、编辑草稿和时间选择器；补记复用编辑表单 | 类型列表实际选项、开始/结束约束、暂停如何体现、桌面删除的运行时状态 |
| 自动流程 | `TTPomoPreferenceViewController` 有 autoBreakSwitchButton、autoPomoSwitchButton、autoFocusCycleTextField、长短休息及长休息间隔 | 自动休息与自动下一番茄分开设置；保留自动轮数模型入口 | 开关默认值、自动轮数含义/范围、未关联任务的自动开始行为 |
| 完成呈现和时长修正 | `TTFocusViewController`/`TTFocusImmersiveViewController` 有 harvestContainer、harvestClickView；`TTFocusDurationEditViewController` 有时长选择、保存、取消 | 完成总结、已有记录时长修正；为额外时间留出入口 | 自动休息开启时完成总结如何显示、额外时间具体计数和舍入 |
| 统计 | `TTPomoStatisticsViewController`、记录日期/记录/加载更多等资源；任务详情有 FocusSummaryCell | 概览、分页记录、任务投入摘要、统计入口 | 本机图表顺序、统计周期、番茄计数/舍入与多任务归属 |

官方桌面说明同时确认运行中悬停计时数字可调整时间、运行中的笔记及结束后修正/追加时间；本方案因此必须区分“修改下一次默认值”和“明确调整本次会话”。[如何开始专注](https://help.dida365.com/articles/6950408124297641984)。

官方统计说明确认右侧概览、记录补记、记录详情及更多统计入口；当前说明的更多统计跳转网页。本项目可用本地统计页面承接同样流程，这是实现方式选择。[专注数据统计](https://help.dida365.com/articles/6950408300395495424)。另一篇 FAQ 对桌面删除的说明与该页冲突；本机有 deleteButton 的结构证据，是否显示及生效应以 8.0.80 实测为准。

官方说明支持预计番茄/预计时长，以及常用专注关联、编辑、归档、记录与分布统计；本项目先接任务，习惯关联随对应模块集成。[常见问题](https://help.dida365.com/articles/6950670128287580160)、[常用专注](https://help.dida365.com/articles/7031082644146225152)。

**仍需补测的滴答规则**：正计时是否增加番茄数；提前结束的准确保存门槛及分钟显示口径；秒数如何汇总；补记如何计数；暂停次数/时长限制；长休息计数在结束/退出后如何延续。这些集中在 `FocusAccountingPolicy` 和流程设置中实现，不散落到 View。

2026-10-15运行补测已经确认：自然完成后的额外时间需明确点击才追加到同一记录，番茄数保持1，追加后额外计时停止；时长编辑实时更新起止预览。15有效秒后结束不留记录；另一轮5分20秒后暂停再结束，出现“结束并保存 / 放弃 / 取消”，保存增加1个番茄并直接回概览，不进入自然完成页。准确5分钟分界仍沿用项目口径，未当作已验证的客户端边界。客户端该条时长显示7分钟，内部计时规则未知。事实、截图与新版验收结果见[实施与验收](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/ticktick-replica-implementation-2026-10-14.md)。

## 2. 一个会话事实来源与一个命令入口

保留现有 Engine → FocusStore → View 的方向。页面、任务菜单、菜单栏和将来的沉浸/Mini 展示只发同一组命令，读取同一份只读 `FocusPresentation`。

建议的会话信息：

- `sessionID` / `recordID`：开始时生成并持久化，结束与后续时长编辑都对应同一记录。
- `mode`：番茄或正计时，明确存在于当前会话；偏好只用于下一次开始。
- `phase`：专注、短休息、长休息；另有运行/暂停/等待开始状态。
- `startedAt`、`accumulatedActiveSeconds`、`activeSegmentStartedAt`、`pausedAt`、已闭合暂停区间。
- `targetSeconds`：番茄计划时长；正计时为空。进入会话时从草稿复制，之后只有“调整本次”命令能改变。
- `taskID`、`presetID`、`note`、本轮休息设置及下一轮配置。
- 独立 `cycleProgress`：完成轮数、自动轮数进度；会话回到空闲后仍可持久化。
- `completionContext`：对应的记录、完成时间、可追加时间起点，支撑完成总结和重开应用后的回顾。

计时器仅触发刷新，秒数由时间锚点计算：运行 elapsed = 已积累秒数 + 当前时间 − 本段开始时间；暂停时关闭本段、elapsed 冻结；恢复时开启新段。番茄 remaining = max(target − elapsed, 0)，正计时显示 elapsed。Store 必须发布 elapsed/remaining 和必要的当前时间变化，计时数字、时间轴、菜单栏使用同一输出。

自然到点的基础记录结束时刻取本次计划结束时刻，基础有效时长取本次 target；晚到的刷新不会把默认偏好或等待时间当作已专注时间。计划结束之后的额外时间单独展示，用户明确追加后再写进同一记录。

`FocusPresentation` 至少提供：mode、phase、displaySeconds、progress、isPaused、taskTitle、phaseTitle、availableActions、completionSummary。View 不自行根据 `preferences.stopwatchMode` 推断当前会话，也不自行给统计加减次数。

## 3. 会话状态机与关键交互

下表是可落地的本项目目标流程；其中计数、门槛和自动流程细节由补测规则决定。它不是声称滴答内部采用同名状态。

| 触发 | UI 状态 | 提交及计时 | 退出/重开后的恢复 |
| --- | --- | --- | --- |
| 空闲切换模式 | 模式分段及数字切换；右侧保留概览 | 修改下次开始草稿/偏好，不产生记录 | 恢复最近使用的草稿模式 |
| 空闲选择任务或常用专注 | 标题、清单色点、模式与时长同步；明确的开始按钮 | 未开始前不写专注记录；常用专注关系由 presetID 表达 | 恢复选择和偏好，不伪造运行会话 |
| 任一入口开始番茄/正计时 | 番茄倒计时或正计时；右侧进入时间轴/笔记；动作读取 availableActions | 捕获 mode、target、任务、预设，建立会话；写“开始专注”活动 | 恢复该会话真实 mode 和时钟，偏好不覆盖它 |
| 运行中暂停 | 数字冻结，显示暂停；动作变为继续/结束 | 关闭有效计时段，记暂停锚点，立即保存 | 仍处于暂停；关闭应用的时间不追加到有效专注 |
| 暂停后继续 | 恢复数字和时间轴 | 新计时段从继续时刻开始；番茄预计结束顺延 | 按新锚点恢复 |
| 点其他预设/改默认设置 | 当前数字和 mode 保持；明确说明设置用于下一次 | 改下次草稿；不改当前 target/record | 当前会话不受新偏好影响 |
| 悬停当前计时数字，点本次 +/- | 出现本次时长控件，数字和预计结束时间同步 | 发 `adjustCurrentTarget`，显式修改当前 target；保存会话 | 用调整后的 target 接续；步长和允许阶段以滴答补测冻结 |
| 用户结束番茄 | 短会话直接回概览；达到当前保存门槛后显示保存/放弃/取消 | 保存以同会话身份写有效秒数和暂停事实，计1个番茄后回空闲；取消保留会话；5分钟门槛仍是项目口径 | 保存记录恢复；不建立自然完成上下文或自动进入休息 |
| 确认弹窗中放弃 | 返回空闲概览 | 不写记录、不增加番茄；主窗口、Mini和菜单共用 Store 命令 | 不恢复已放弃会话 |
| 番茄自然到点 | 完成总结；休息按设置进入待开始或运行状态；选定铃声提醒一次 | 保存一次完成记录，更新轮数；同时提交新的休息/总结元数据 | 恢复完成结果及当前休息/待开始状态 |
| 完成总结点击追加时间 | 先展示额外时长，点击后反映到同一条记录并停止额外计时 | 从完成锚点计算，一次更新 endedAt/activeSeconds，番茄数保持 | 保存后的记录可查看和再次编辑 |
| 完成总结编辑时长 | 当前时长填入编辑草稿，保存/取消明确 | 保存更新已有记录，不新建一条“补记”；取消不改变统计 | 保存版本恢复 |
| 短/长休息开始、暂停、继续 | 休息色与标题、倒计时和对应动作 | 休息单独计时，不进入专注时长或番茄数 | 恢复实际休息阶段与暂停状态 |
| 跳过休息 | 结束本次休息，呈现待下一番茄或按设置开始 | 发 `skipBreak`，不复用含义含混的 giveUp | 恢复下一状态 |
| 休息结束，自动下一番茄开启 | 新会话采用本轮保留的任务/预设和下一轮配置 | 统一 `start` 命令开始新会话；任务可为空，不用 taskID 的存在作为技术条件 | 应用关闭期间是否继续自动轮转，按补测结果决定；正常在运行应用内只开始真实的一轮 |
| 自动下一番茄关闭/达到自动轮数 | 显示开始下一番茄，回到待开始状态 | 保存轮数，不新增专注记录 | 重开后仍等待开始 |

本项目建议正计时结束进入完成总结，用户选择下一次开始，不直接进入番茄休息；这属于待同版本实测冻结的流程选择。

已有 Escape/空格操作统一调用这些命令：文本输入时不抢空格，弹出编辑器时 Escape 先取消草稿，计时页面的暂停/继续才处理空格。主页面与菜单栏对于同一 phase 必须提供同名、同后果动作。

自动休息、自动下一番茄、自动轮数应分开：关闭自动休息时先停在完成总结/待休息；开启时进入真正的休息计时。具体默认值及完成总结是否折叠要补测后冻结。新的偏好字段迁移旧用户时保留当前产品的流程，不用“滴答默认”替换未经验证的值。

## 4. 记录、暂停、统计与时长编辑

保留现有 `PomodoroRecord` 的 ID、taskID、startedAt、minutes、completed、note 键，增加可选的 `details`，逐步把新逻辑迁到以秒为单位的数据：

| 新信息 | 用途 |
| --- | --- |
| mode：pomodoro / stopwatch / legacy | 正计时与番茄明确分开；旧记录不猜模式 |
| source：timer / manual / legacy | 区分实际计时与补记，允许筛选 |
| termination：targetReached / manuallyEnded / abandoned / manualEntry / legacy | 结束原因不再只有 completed 一个布尔值 |
| endedAt、activeSeconds、pausedSeconds、pauseRanges | 展示真实区间、扣除暂停、支持时间轴；可编辑字段保持相互一致 |
| targetSeconds、presetID | 回顾本次计划和常用专注来源 |
| creditedPomodoros、accountingPolicyVersion | 统计按明确口径处理，避免所有完成记录都计一个番茄 |
| durationPrecision：second / legacyMinute | 精确新记录与只有分钟的旧记录分开 |

原始有效秒数始终保留；UI 分钟显示舍入和统计单位转换分别由 policy 处理。休息永远从专注统计剔除。新记录的番茄数按 mode、结束原因和补测计数规则计算；本方案暂定正计时计时长而不自动计番茄，补记要求选择记录类型。这是建议口径，不宣称是滴答数值规则。

编辑器以类型、任务、开始、结束、笔记等确认存在的字段组成。原始计时记录保留暂停信息，修改开始/结束时同步重算区间与有效时长；仅修改有效时长时保留真实起止，将手工校正值记录在 details 内，不能伪造暂停历史。补记没有自动推断的暂停，按填写的起止计时。字段顺序、类型选项、可编辑范围与最短时长在同版本客户端补测后冻结。

历史列表行打开记录详情；详情显示类型、任务、起止、实际时长、暂停及笔记。关联任务是独立按钮，再跳转任务详情，不能继续把整条记录的点击当作“打开任务”。记录详情提供编辑和删除；删除是否对本机全部记录开放按补测结果冻结。

补记按钮打开同一记录编辑器，默认日期是今天、默认结束是现在，同时允许明确选择昨天等日期。取消不写数据；保存一次 upsert，按时间归位，同时刷新今日、累计、任务与统计。不要继续用“现在减去分钟数”代替可选择的历史区间。当前 Store 的 7 天范围是本项目规则，不能当作已经确认的滴答限制。

统计复用现有按日/按任务的全库查询，新增模式、来源、关联状态、日期范围过滤；分页历史只决定看到哪些行，不决定总量。概览、记录详情、任务实际投入、更多统计和日历记录图层读同一查询口径。编辑/删除从旧值替换成新值，以同一事务更新聚合数据，View 不维护额外的“次数缓存”。

## 5. 任务预计/实际与常用专注

Task 增加可选 `focusEstimate`：用户选择预计番茄数或预计时长，各自保留原单位，不根据后来变化的默认番茄时长偷偷换算。自定义 Codable 使用 `decodeIfPresent`，未设置时没有额外标签。

任务列表右键与详情开始专注子菜单提供：开始番茄、开始正计时、预计番茄/时长。预计编辑器从当前值初始化草稿，切换类型显示对应输入，确认后一次提交，取消不变；输入范围以补测为准。任务行摘要和详情专注摘要使用同一个展示投影。

任务详情显示预计投入、累计实际有效时长及已记番茄数；点击实际投入打开已按 taskID 筛选的记录。记录完成、时长编辑、任务换绑、补记和删除都更新该聚合。开始/结束专注本身不自动完成任务。父子任务/重复任务预计与实际的汇总/继承规则需与待办方案统一，不在专注 View 临时实现。

TimerPreset 增加可选 taskID、archivedAt、sortOrder，保留现有 emoji/name/stopwatch/minutes。常用专注的记录通过 presetID 归集，名称改动不破坏历史。右键提供编辑、添加记录、归档、删除；归档项退出快捷区、记录保留。常用专注选择与启动的点击行为先补测，再冻结；不可用运行中的 chip 点击隐式改本次计时。

## 6. UI 复用与视觉验收

保留 RootShell rail + 左计时 pane + 右内容 pane。左侧继续复用现有 `FocusTimerPane`、`FocusTimerRing`、`FocusStopwatchDial`、任务 picker 与时长 popover；右侧根据展示路由切换概览/活动详情/完成总结/记录详情/统计，切换路由不改变计时。

| 区域 | 实现方向 | 保留的基线 |
| --- | --- | --- |
| 空闲计时 | 模式分段、任务标题、环形倒计时或刻度正计时、开始按钮 | 当前 FocusLayoutMetrics 中的 pane 宽度算法、header、segment、ring、footer |
| 活动计时 | 使用当前会话 mode 标题与数字；番茄悬停数字出现 +/-；暂停后的继续/结束动作统一 | timerRing、focusTimerDigits、focusPauseButton/focusResumeButton/focusEndButton anchors |
| 活动右侧 | 模式标题、可点击的关联按钮、时间轴、专注笔记 | activeTimeline 系列、activeFocusNote、activeSessionTomatoIcon；正计时不强画番茄结束区间 |
| 完成总结 | 收获/本次实际时间、任务/笔记、额外时间入口、编辑时长与下一步动作 | 复用现有主题/排版，新增 completionSummary / extraTime / editCompletedDuration anchors；具体布局待客户端测量 |
| 概览与记录 | 保留四张卡片、每日目标、按天记录；记录行打开详情，+ 打开完整补记编辑器 | overviewFirstCard、recordsHeader、emptyRecords 系列；现有行高/字号在重新测量前不散改 |
| 详情/编辑/统计 | 使用现有 AnchoredPropertyPanel 或现有 pane 路由；明确返回和保存/取消 | 新增记录详情/起止/类型/笔记/保存，以及筛选/图表 anchors，不往旧锚点赋不同含义 |
| 菜单栏与沉浸/Mini | 始终显示同一 mode/phase 的数字与 availableActions；关闭展示面不等于结束会话 | StatusItemController 接同一 presentation；沉浸/Mini 复用同一命令和会话，不另建计时器 |

当前 `FocusLayoutMetrics` 的 430/650/680、620、0.37、236 等值是本项目基线，不是 REA 解码得到的滴答尺寸。尺寸只从同版本客户端、同窗口内容区/显示缩放的实际截图测量获取；将测得的变化集中回写 Metrics，再验证 contracts。新面板不先填一组未经测量的“滴答宽高”。

补齐按钮/输入的 accessibilityIdentifier，与 render anchor 对应。现有 FocusOverview/Timer/ActiveSession/Duration/TaskPicker 的布局与交互契约继续保留，增加完成总结、活动中调整、记录详情/编辑、预计投入及菜单栏状态的契约。亮/暗模式与现有视口集合同时验收；不要仅比空闲截图。

铃声偏好转为稳定 bellID，读取旧中文名称时映射到现有 FocusBell；显示文案与系统 soundName 分开。关闭选项令应用声音和通知 sound 都为空；播放和通知仍由同一阶段事件驱动。选铃声可预听，但预听不发系统通知。

## 7. 领域与 SQLite 的 additive 迁移

1. Archive 增加可选 `sessionV2`、`completionContext`、`cycleProgress` 与偏好字段；旧 `session` 保留兼容读取。新会话优先读 sessionV2，没有时读旧快照。旧 focusing/pausedFocus 可用 phaseEnd 是否为空判断当前 mode；休息来源的 mode 无法可靠恢复时保留 legacy 信息，不根据记录分钟数猜测。
2. 旧记录解码为 mode/source=legacy，activeSeconds=minutes×60、precision=legacyMinute，原 completed 的计数保持原值。旧数据没有 endedAt/暂停区间，就保持未知；不能把 startedAt+minutes 写成真实结束时刻，也不能凭空判断哪些旧记录其实是正计时。当前已误记的旧时长需要用户或实测证据修正，迁移不猜。
3. SQLite 在现有 records payload 旁增加可空的 active_seconds、focus_mode、source_kind、termination、credited_pomodoros 等查询列；现有 occurred_at/task_id 索引继续使用。保留当前 metric_value 的兼容含义，新聚合使用明确的秒数和 credited_pomodoros。旧行一次填充 legacy 值，历史总量在迁移前后保持一致。
4. 结束会话的 record upsert、sessionV2/总结/轮数更新在同一事务提交。每秒刷新只更新 Published presentation；阶段改变即时保存，活动快照和笔记继续使用已有节流/去抖。记录编辑保留 ID，一次提交旧/新聚合差值与列表 revision。
5. Task 增加可选预计字段；TimerPreset 增加可选关联/归档/排序字段。旧数据不用重建任务或预设。JSON 导入导出、SQLiteModuleExport 和预览初始化都走同一 decoder，新增字段缺失有明确默认。

## 8. 实施文件与顺序

| 现有落点 | 工作 |
| --- | --- |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Domain/Focus/PomodoroEngine.swift` | 明确 mode/会话时钟、当前调整、独立结束/放弃/跳过休息、完成总结与轮数 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusStore.swift` | Published presentation、统一命令、记录 details/编辑/统计、session/record 原子提交、迁移 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusWorkspaceView.swift` | 右侧路由及完成总结、统计入口，保留全局计时 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusTimerPane.swift` | 主动作、设置与预设分离，当前调整入口 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusTimerRing.swift` | 用 session mode 选数字/刻度，活动时悬停 +/- |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusOverviewPane.swift` | 完整补记、记录详情/编辑入口，统一统计读数 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusActiveSessionPane.swift` | 真实可点击关联、按模式标题、时间轴/笔记投影 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/QuickAdd/StatusItemController.swift` | 同一个 presentation 的时间与动作，正计时显示 elapsed |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Domain/Task/Task.swift` 及 TaskInspector/TaskContextMenu | 预计字段、草稿编辑、预计/实际摘要、按任务跳转记录 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Infrastructure/Persistence/SQLiteRecordStore.swift` | additive 查询列、精确聚合、记录更新 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Application/FocusNotifier.swift` | stable bellID 到系统 soundName，关闭无声，统一阶段提醒 |
| `/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/macos-native/WorkFollow/Features/Focus/FocusLayoutMetrics.swift` 与 FocusRenderContract.swift | 只接入实际测量值；新增状态 anchors 和正常路径契约 |

建议顺序：先补测并登记数值规则/主要状态截图；然后完成会话、记录和迁移；随后让计时页、任务入口、菜单栏统一；再补记录编辑、预计实际和统计；最后复用同一引擎做完成呈现、沉浸/Mini 并校准视觉。新页面可分别开发，但联调和验收必须使用同一个会话/记录链条。

## 9. 正常路径验收

| 场景 | 必须看到的结果 |
| --- | --- |
| 任务详情启动正计时，经过 90 秒 | 主页/菜单栏逐秒同步，都表达正计时；重开后仍是同一模式和会话 |
| 番茄工作 10 分钟、暂停 2 分钟、继续 5 分钟 | 实际有效 15 分钟，暂停 2 分钟，番茄剩余与预计结束一致 |
| 25 分钟番茄中选择 50 分钟预设 | 本次仍按 25 分钟；下一次默认 50 分钟；记录不误记为 50 |
| 同一会话显式 +/- 调整本次时间 | 当前数字/时间轴/完成记录采用新的 target；每个入口看到同一结果 |
| 正计时结束、番茄提前结束、放弃 | 三者 reason/type 明确；主页和菜单栏产生同后果；计数符合登记过的补测规则 |
| 番茄自然结束、短/长休息、下一轮 | 记录只生成一次；休息不计专注；自动开关和轮数得到明确结果 |
| 完成总结追加 3 分钟，随后编辑时长 | 修改原记录，同一个 ID；详情、今日总量和任务实际一致 |
| 给昨天的任务补记起止及笔记 | 记录归入昨天；取消不写；保存后在详情能读笔记，按任务可查 |
| 编辑一条记录的日期、任务、时长 | 从旧日/旧任务扣除，计入新日/新任务；历史列表位置与统计同时正确 |
| 设置预计时长/番茄，完成一轮专注 | 预计单位保持用户选择；实际投入能进入记录；专注不擅自完成任务 |
| 切换概览/统计/记录详情或关闭 Mini 展示 | 当前计时持续；页面恢复时状态一致；不会隐式新建/结束会话 |
| 铃声选择与关闭 | 选择能预听相应声音；到点按设置提醒；关闭不发有声通知 |
| 从旧数据库打开后开始新会话 | 旧记录分钟、既有番茄累计保持原值；新记录有精确 mode/秒数；暂停快照与笔记接续 |
| 同一任务贯穿全链路 | 任务选择/预计 → 开始 → 暂停/继续 → 结束 → 记录编辑 → 任务实际 → 统计/日历复盘，看到同一份归属和投入 |

验收分为功能结果与视觉结果：功能先确认时间/记录/统计一致；视觉按空闲番茄、空闲正计时、两种运行、暂停、休息、完成总结、选择任务、记录详情/编辑、预计、统计的实际客户端状态逐一对照。对尚未补测的计数和舍入，不写一个看似精确的期望数字；登记滴答实测结果后再冻结该断言。
