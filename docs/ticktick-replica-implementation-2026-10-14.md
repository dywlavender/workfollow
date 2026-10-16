# 滴答四模块原生实施与验收

分支：`experiment/macos-native`。参考客户端：本机滴答 macOS 8.0.80，REA 6.4.0。实施日期：2026-10-14。

四模块的主要功能链已经接入原生应用。真实窗口中的安排池排期、象限移动、时间块移动与边缘调整及一步撤销已补验。2026-10-15继续修复全天区投放、重复例外、专注完成页及提前结束流程；最终全量回归1281条、0失败、5跳过，新版独立验收包的完成页和提前结束流程也已实测。尚未将它标成完整的1:1复刻：全状态视觉对照，以及参考客户端尚未实测的计数/重复细节仍须补验。

## 2026-10-15 后续对齐

REA 与 CUA 在当前滴答临时验收数据中确认：5分钟番茄自然结束后先保留基础记录，等待期间额外秒数单独累计；悬停番茄出现追加入口，点击后改写同一记录并停止追加计时，番茄数仍为1。将48分钟草稿改回5分钟时，预览立即调整结束时刻，保存后统计恢复为1个番茄、5分钟。另一轮实际测到15有效秒后暂停并结束，未保存记录、未增加番茄数。

据此完成以下修正：

- 完成态放到左侧计时区，自绘番茄、时长入口和休息/退出按钮；右侧保留时间轴与可编辑的同记录笔记。时长弹层宽240pt，修改分钟时更新起止预览；草稿未改值时保留已存精确秒数。额外时间只在明确追加后写入同一记录，不重复计番茄。
- Mini与沉浸窗口接收主应用外观，并随设置更新。用户“结束”的主窗口、Mini和菜单入口共用动作；短番茄回概览且不留记录，较长番茄先显示“结束并保存 / 放弃 / 取消”。保存回概览并计1个番茄，不进入自然完成页或休息；放弃不留记录；取消保留当前会话。正计时仍保存有效秒数和暂停事实。5分钟分界暂沿用项目已有最短记录门槛；客户端已实测15秒结束和5分20秒后的结束，准确分界尚未证实。
- 范围改期保留各真实期次独立内容与组织字段，未来虚拟期使用原有投影模板。日期操作不把选中的中间期正文升级为系列模板；当前头任务编辑后的正文继承规则保持。
- 完成周期时跳过当前已删除、跳过、转换或结束的周期，包括范围改期之后才删除的下一期。缩短重复次数/结束日期后，超出范围的已落地任务保留原内容与日期并转为普通任务；取消重复时也不把所有日期压到所选日期。这是本项目明确采用的处理方式，未宣称已验证为滴答的相同策略。

解锁后，原先10分钟测试已经自然到点，因此只登记为自然完成。另一次在滴答运行5分20秒后暂停、点击结束，确认三选项弹窗、保存后直接回概览并增加1个番茄。该条记录显示7分钟，与暂停前的有效时长不同；未把显示值当作内部计时规则复制。参考客户端最终为3个番茄、22分钟，无运行会话，主题已恢复“默认”。当前免费账户的日历仍展示会员示例数据，无法实测测试任务未来期次的范围编辑。[运行事实与边界](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/runtime-findings.json)和[自然完成截图](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/reference-focus-natural.png)已保存。

新版 WorkFollow 中实际运行5分钟至自然完成，完成后修改笔记、将同条记录从5改为6分钟、重启后再改回5分钟，记录身份与笔记均保留，统计随之更新。已检查任务、周日历、四象限的深色页面，完成页深浅色、同一Mini窗口的浅色→深色更新及深色沉浸窗口。最后使用预置的320有效秒暂停快照检查提前结束：取消后04:40暂停状态保持；保存后直接回概览，同会话记录为320有效秒、1番茄，笔记完整保留。该快照验收没有被记成另一次真实5分钟运行。

完成页截图：[浅色](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/native-focus-completion-light.png)、[深色](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/native-focus-completion-dark.png)；[时长修正数据](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/native-focus-after-duration-edit.json)；[提前结束落库结果](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/native-focus-early-end.json)与[概览截图](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/native-focus-early-result.png)。

## 已实施的功能

| 模块 | 本轮落地 | 主要实现位置 |
| --- | --- | --- |
| 待办 | 列表/全局共用录入会话；真实光标候选与中文组合输入保护；人工属性覆盖；批量单次撤销；自然周及时间组合修正；看板排序、完成框、右键、列内添加；稳定组织引用；业务重做；预计/实际投入 | `QuickCaptureSession`、`QuickAddParser`、`TaskWorkspaceModel`、`TaskActions`、`WorkspaceStore`、`TaskFocusEstimateEditor` |
| 重复 | 到期日/完成日/自选日期，多星期几、月序数、结束条件；系列、名义周期及本期例外；未来只投影，编辑或开始专注才落地；三种修改范围；继承分组、子任务、提醒及预计投入 | `RecurrenceRule`、`TaskSeries`、`TaskOccurrenceProjection`、`TaskDateDraftModel` |
| 日历 | 月/周/日；全天、跨天、重叠分道；单击时间点、拖选范围、移动保时长、边缘调整、取消；安排池；+N 完整清单；统一浏览锚点及显示设置；未来周期范围选择 | `CalendarPlanningModel`、`CalendarInteractionController`、`CalendarTimelineView`、`CalendarWorkspaceView` |
| 四象限 | 保留旧三天规则；优先级/时间预设及自定义条件；名称、颜色、分组、排序与布局；跨区最少属性提案、一次提交/撤销；同区不强改日期；配置独立历史 | `MatrixConfiguration`、`MatrixDropPlanner`、`MatrixWorkspaceView`、`PlanningSettingsStore` |
| 专注 | 当前会话固定真实模式/目标；秒级刷新和暂停区间；当前调整与下次预设分开；完成总结、同记录追加及修正；补记、详情、编辑、历史和统计；菜单栏、Mini、沉浸共用 Store；铃声映射及静默 | `PomodoroEngine`、`FocusModels`、`FocusStore`、`FocusRecordEditor`、`FocusCompletionPane`、`FocusStatisticsPane` |
| 联动 | 日历/象限共用任务详情和领域动作；虚拟周期进入专注时取得稳定任务关联；记录链接正确打开任务；转换笔记成对撤销/重做并保持同一身份 | `AppEnvironment`、`RootShellView`、`NotesWorkspaceModel`、`ReplicaWorkflowTests` |

旧任务与旧专注记录保持兼容读取。旧专注的分钟、既有次数和记录身份保留；无法证明的模式、结束时间和暂停事实保持未知。新增精确秒数的聚合通过 SQLite 元数据升级重建，没有将旧记录重新猜成新记录。

## 原生 UI 与运行观察

运行观察用于冻结已知参数：导航栏 212pt；当前参考窗口中的专注区域约558pt、计时环238pt、开始按钮123×48pt、概览卡72pt；补记表单440×446pt，字段为任务、开始、结束、类型、笔记，番茄数默认0。任务栏仍允许拖动并保留原宽度偏好；参考客户端某次任务栏370pt的布局没有被当作固定默认值。

以下截图来自本次编译后的 WorkFollow 原生窗口，使用独立验收数据、1512×859pt窗口、浅色主题与2026年10月13日的持续推进时钟：

- [待办与共享详情](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-tasks.png)
- [周日历、全天区与安排池](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-calendar.png)
- [按优先级的四象限](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-matrix.png)
- [专注概览与当日记录](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-focus.png)

已实际观察的正常流程：

| 操作 | 可见及数据结果 |
| --- | --- |
| 任务日期草稿点14日，再按Esc | 草稿显示新日期；关闭后任务仍13日09:00，没有提前写入 |
| 周时间块10:00–11:30向下移动一小时，再⌘Z | 显示11:00–12:30，时长不变；一步恢复10:00–11:30 |
| 象限切换“按优先级” | 中优先级任务进入第二象限，日期保持 |
| 正计时→写笔记→暂停→结束 | 完成总结与存储均为115有效秒、23暂停秒、0番茄；笔记完整保留 |
| 昨天10:00–10:30补记，关联“需求评审”，番茄数0 | 今日保持65分钟、累计由65变95分钟、总番茄保持1；记录进入昨天；任务实际投入由25变55分钟 |
| 补记表单与日期字段操作 | 字段顺序和0次默认可见；日期、时间、任务和笔记可编辑并保存 |
| 安排池拖入周三时间轴12:00 | 保存为10月14日12:00、无虚构结束时间；安排池移出、时间块与详情可见；一步撤销恢复原任务 |
| 安排池拖入周三全天区中部空白 | 修复后整列接收，保存为10月14日、无时间；一步撤销恢复原任务 |
| 安排池拖入月视图22日日期格 | 保存为10月22日、无时间，任务显示在对应格；一步撤销恢复原任务 |
| “按优先级”中从第四象限拖到第一象限 | 提案仅将优先级改为高；提交后进入第一象限，日期仍为空；一步撤销恢复完整任务与正文 |
| 周三时间块的结束边缘向下拖30分钟 | 10:00–11:30变为10:00–12:00，开始时间保持；一步撤销恢复原时段 |

运行细节：[正计时落库验证](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-focus-runtime.json)、[昨日补记与聚合验证](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-focus-manual.json)、[任务实际投入55分钟截图](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-task-focus.png)。

拖放与撤销结果：[原生拖放数据验证](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-drag-verification.json)、[系统落下回调](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-drag-events.json)。REA截图：[周时间轴](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-calendar-drop.png)、[全天区](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-calendar-all-day-drop.png)、[月日期格](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-calendar-month-drop.png)、[象限移动](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-matrix-drop.png)、[结束边缘调整](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/native-calendar-resize.png)。本轮操作逐次撤销后，数据库中的10条任务及正文与验收前完全一致。

CUA初次拖放只发出约28毫秒的按下、移动和松开序列，部分操作未完成原生拖放会话；随后在同一目标补一次点击，系统落下回调成功进入，排期与象限命令正常写入。月视图单次拖放已直接成功。SwiftUI目标/预览回调时间可能滞后，不能仅凭其时间认定底层会话何时启动。验收副本的被动记录仅在明确配置的Debug副本启用，不记录任务输入文本。

联调中发现并修复了独立详情缺环境导致崩溃、投入面板未使用共享弹层、重复选择多余刷新、日历首月被居中滚动覆盖、周表头被拉高、验收窗口超出屏幕，以及专注“今日统计”和记录日期标签使用不同时间源等问题。

## 自动验证

最新的`build-for-testing`成功。2026-10-15最终整套XCTest统计为1281条：1276条实际执行并通过、0失败、5条跳过。本轮专注流程20条、重复任务合同22条及日历/象限/跨模块回归均通过。

锁屏期间曾有`DocumentDecorationRenderTests`中3条像素绘制断言失败，保留的截图为黑色。解锁后单独重跑整个类11条全部通过，随后最终全量也全部通过；没有为绕过失败更改这些断言。跳过项为4条需要本地Pi环境的会议集成及1条需要前台焦点的面板测试。

此前2026-10-14全量为1261条、0失败、5跳过；全天区修复后另跑过74条相关测试，0失败。最终结果以上述1281条全量为准。

测试集中在正常路径：`TaskReplicaContractTests`22条、`CalendarPlanningTests`8条、`CalendarInteractionTests`4条、`MatrixConfigurationTests`8条、`FocusReplicaFlowTests`20条、跨模块5条，以及渲染/外观、时间标签和选择刷新回归。旧领域、文本编辑器、原生弹层、持久化和其他模块测试一起执行。

[最新测试及实机验收摘要](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-15/verification.json)。[此前通过记录](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-macos-native/docs/audits/ticktick-replica-2026-10-14/verification.json)保留供对照。本次未更改会议、ASR及壁纸等已有工作。

复现命令：

```bash
WORKFOLLOW_DERIVED_DATA=/private/tmp/workfollow-replica-build \
WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 \
bash macos-native/scripts/run-tests.sh

bash macos-native/scripts/prepare-replica-acceptance.sh \
  /private/tmp/workfollow-replica-build/Build/Products/Debug \
  /private/tmp/workfollow-replica-qa-new
```

验收脚本只接受新的数据目录。它生成8个父任务、2个检查项及2条专注记录，等待持久化完成，创建独立应用副本并声明测试窗口/日期。正常应用继续使用真实时间和已保存的布局。

## 仍需完成的复刻对照

1. **全状态视觉。** 当前确认了四个主要页面的浅色/深色表现、完成页和部分参数；常用窗口尺寸、悬停/焦点/空态及全部弹层的逐项≤1pt对照未全部完成。
2. **滴答精确语义。** 15有效秒结束不保存、5分20秒后结束出现三选项并保存计1、自然完成的同记录追加不增加番茄数已实测。准确的最短记录分界、提前结束后的时长显示口径、本次加减步长、自动轮数及三种重复范围对既有例外的精确影响，尚未全部在8.0.80实测。当前集中政策采用5分钟分界和5分钟调整步长；确认弹窗的“放弃”丢弃记录，取消保留会话。

这些条目保持待验状态。通过自动测试代表本项目实现合同成立，不直接证明与参考客户端的全部行为完全相同。

此前完成拖放与撤销验收的副本位于 `/private/tmp/workfollow-replica-qa-final/WorkFollowReplicaQA.app`，其任务已恢复。2026-10-15新版产物在 [WorkFollow Replica Followup QA](/private/tmp/workfollow-replica-qa-2026-10-15/WorkFollowReplicaQA.app)，使用独立应用身份和验收数据。最新编译产物已装入并通过签名校验及上述实机验收；最终停在浅色专注概览，没有运行会话。
