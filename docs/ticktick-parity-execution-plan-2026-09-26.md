# 滴答对齐执行计划（2026-09-26）

原则：**先实现功能，再对齐 UI 与操作；每波结束集成构建+测试；最终实机验收。**
基线：2026-09-26 `xcodebuild test` 136 项全部通过（分支 `experiment/macos-native`）。
并行安全：Xcode 工程使用 fileSystemSynchronizedGroups，新增 Swift 文件自动纳入构建；每个子任务只拥有分配给自己的文件，**共享文件一律由主线或指定唯一子任务修改**。

## Wave 0 —— 并行底座（主线完成）

| 改动 | 文件 |
| --- | --- |
| 导航新增 `.focus` / `.habits` / `.summary` | `App/AppNavigation.swift` |
| 模块路由 + 侧栏/图标栏入口 | `Features/Shell/RootShellView.swift`、`Features/Sidebar/SidebarViews.swift` |
| 三个模块的 Store 桩（可编译、签名冻结） | `Application/FocusStore.swift`、`Application/HabitStore.swift`、`Application/SummaryStore.swift` |
| 通用 JSON 持久化助手（原子写+防抖） | `Infrastructure/Persistence/JSONFileStore.swift` |
| 验收截图入口：启动参数 `--wf-destination <case>` 直达任意视图 | `App/WorkFollowApp.swift` |

冻结的构造契约（子任务不得更改）：
- `FocusStore(clock:directory:)`、`HabitStore(clock:directory:)`、`SummaryStore(clock:directory:)`（均为 ObservableObject）
- `FocusWorkspaceView(store:)`、`HabitsWorkspaceView(store:)`、`SummaryWorkspaceView(store:)`

## Wave 1 —— 五大功能模块（5 个并行子任务）

| # | 模块 | 拥有的文件（新建除注明外） | 验收 |
| --- | --- | --- | --- |
| F1 | 专注（番茄） | `Domain/Focus/PomodoroEngine.swift`、`Application/FocusStore.swift`（替换桩）、`Features/Focus/FocusWorkspaceView.swift`、`WorkFollowTests/PomodoroEngineTests.swift` | 引擎状态机测试覆盖 开始/暂停/继续/放弃/完成→休息→下一轮；专注 5 分钟以下不记录；可关联任务；当日累计与最近记录展示 |
| F2 | 习惯打卡 | `Domain/Habit/Habit.swift`、`Application/HabitStore.swift`（替换桩）、`Features/Habits/HabitsWorkspaceView.swift`、`WorkFollowTests/HabitTests.swift` | 每日/指定星期几计划；打卡/撤销；连续天数与打卡率纯函数测试；归档/恢复；打卡日志（心得） |
| F3 | 摘要 | `Domain/Summary/DailySummary.swift`、`Application/SummaryStore.swift`（替换桩）、`Features/Summary/SummaryWorkspaceView.swift`、`WorkFollowTests/SummaryStoreTests.swift` | 今日摘要编辑自动保存；按月浏览历史；当日唯一 |
| F4 | 模板 | `Domain/Templates/TaskTemplate.swift`、`Application/TemplateStore.swift`、`Features/Tasks/Templates/TemplatePickerView.swift`、`WorkFollowTests/TaskTemplateTests.swift`；**唯一允许**增量修改 `TaskInspectorShell.swift`（更多菜单"保存为模板"）与 `TaskListView.swift`（工具栏"从模板添加"） | 模板保存标题/正文/标签/优先级/清单/子任务结构；应用模板生成新任务；重名替换确认；管理（删除）入口 |
| F5 | 过滤器 | `Domain/Filter/SavedFilter.swift` + `FilterEvaluator.swift`、`Application/FilterStore.swift`、`Features/Filters/FilterEditorView.swift`、`WorkFollowTests/FilterEvaluatorTests.swift`；**唯一允许**增量修改 `TaskWorkspaceModel.swift`（activeFilter 应用）与 `SidebarViews.swift`（过滤器分组） | 条件：清单/标签/优先级/日期范围（任意组合，先 AND）；求值器纯函数测试；保存/重命名/删除；侧栏点击切换过滤 |

约束（对全部子任务）：
- 只写分配的文件；不运行 `xcodebuild`（主线统一构建）；不修改测试以外的共享文件。
- UI 遵循现有设计令牌 `WFColors/WFType/WFSpace/WFMetrics`，中文界面文案，匹配现有代码风格（注释仅说明约束）。
- 持久化统一走 `JSONFileStore`（`directory` 注入，默认 Application Support）；纯逻辑放 Domain 并配 XCTest，测试用注入的临时目录与固定 clock。

## Wave 1 集成（主线）

`xcodebuild test` 全绿 → `git status` 复核只含预期文件 → 修复类型/接线问题。

## Wave 2 —— 系统集成（3 个并行子任务）

| # | 模块 | 拥有的文件 | 验收 |
| --- | --- | --- | --- |
| G1 | 全局快速添加 | `Features/QuickAdd/GlobalQuickAddPanel.swift`（Carbon RegisterEventHotKey + NSPanel + 复用 QuickAddParser）、设置外观页开关（默认关闭）；**唯一允许**增量修改 `App/AppCommands.swift`、`App/WorkFollowApp.swift`、`Features/Settings/SettingsShellView.swift` | 热键唤起无边框面板，回车建任务到收集箱/今天，Esc 关闭；开关与热码可改；不抢占未授权组合键 |
| G2 | 设置数据页 | `Features/Settings/SettingsDataView.swift`；**唯一允许**增量修改 `Features/Settings/SettingsShellView.swift` | 显示数据目录与各文件大小；立即备份（zip 到日期子目录）；打开数据目录；导出 JSON；恢复警告文案 |
| G3 | 日历年视图 | `Application/PlanningProjection.swift` 扩展 + `Features/Planning/PlanningWorkspaceView.swift`（年模式+热力图）；**唯一允许**修改这两个文件 | 12 个月网格+当日任务计数热力；点击某天跳转月视图；纯函数测试 |

## Wave 2 集成（主线）：同 Wave 1。

## Wave 3 —— 实机验收（主线 + 视觉验收子代理）

1. `xcodebuild build` 产出 Debug App，`open` 启动。
2. 用 `--wf-destination` 逐视图启动/切换：today、inbox、allTasks、nextSevenDays、completed、calendar、matrix、notes、trash、focus、habits、summary。
3. `screencapture` 截图归档 `docs/screenshots/acceptance-2026-09-26/`。
4. 调度视觉验收子代理逐图评审（布局/文案/对比度/明显破版），回修后再验。
5. 全量 `xcodebuild test` 回归。

## 后续（本计划外）

日/3日/时间线视图、第三方日历订阅、看板、农历重复、子标签、清单组、macOS 快捷指令、附件增强、邮件/微信提醒渠道、SQLite 迁移（一万条性能目标）。

## 明确不做

团队协作/指派/审批（Web 端）、云同步、账号体系。

---

## 执行结果（2026-09-26 当日完成）

- Wave 0/1/2 全部落地，Wave 3 实机验收完成。
- 测试：基线 136 → **216 项全部通过**（新增 80 项：专注 10、习惯 11、摘要 6、模板 9、过滤器 17、全局快速添加 5、设置数据页 12、年视图 9 等）。
- 新模块：专注（PomodoroEngine 状态机 + 圆环计时 + 统计记录）、习惯打卡（计划日/连续天数/打卡率/归档/日志）、摘要（每日一篇 + 月览）、任务模板（保存/应用/管理）、过滤器（侧栏一键切换、与清单/标签 AND 叠加）。
- 系统集成：全局快速添加（⌘⇧A，Carbon 热键 + 非激活面板，菜单开关默认关闭）、设置数据页（存储位置/立即备份/导出 JSON）、日历年视图（12 月热力图，点击跳月）。
- 实机验收：12 个视图逐界面截图（`docs/screenshots/acceptance-2026-09-26/`），视觉评审发现并修复 4 项——日历月视图右列裁切、月视图首周消失（LazyVGrid 表头与日期格 Date id 冲突的既有 bug）、长标题换行、日期格式中英不一致（统一 zh_CN）。
- 未做（见"后续"章节）：日/3日/时间线视图、第三方日历、看板、农历重复、子标签、清单组、快捷指令。

## 第二轮：UI/操作对齐（2026-09-26 晚）

用户反馈：功能有了但"界面堆叠、操作奇怪、布局乱、展示不对"，要求截屏滴答做基准对比。

- **滴答参照截图**（`docs/screenshots/ticktick-reference/`）：任务列表+详情检查器（00）、四象限（02）、摘要周报（03）、日历付费墙月网格预览（01）。截图方式：系统截屏 + 辅助功能菜单导航（电脑控制通道仅部分可用，期间滴答崩溃过一次已恢复；涉及录屏授权的系统弹窗**未代用户授权**，已清除）。专注/习惯两页因免费版导航受限未拿到实机图，以语言包 3457 条字符串 + 产品公开布局推断。
- **5 个并行子任务完成**（T1 任务视图/侧栏/详情检查器、T2 日历+四象限、T3 专注、T4 习惯、T5 摘要概念重定位）。关键产品决策：滴答"摘要"实为**自动生成的周回顾**（已完成/已放弃/未完成 + AI 优化），非日记——打勾已同步重定位（周回顾 + 手记模式并存），SummaryReviewBuilder 纯逻辑接入任务数据。
- 测试：216 → **251 项全部通过**（新增 35 项视图逻辑测试）。
- 待办：屏幕锁定，实机复验截图与视觉对比未执行（构建产物 /tmp/wf-dd/.../WorkFollow.app 已就绪，解锁后重跑 `--wf-destination` 截图脚本 + 视觉评审即可）。

### 实机复验结果（解锁后完成）

10 个视图全部重截（`docs/screenshots/after-ticktick-align-2026-09-26/`），两个视觉评审结论：任务模块骨架与规划/新模块达到滴答布局水准，7/10 直接过。修复 4 项必须项后复验全过：
1. 任务行日期徽标被元数据挤压截断 → 日期徽标 fixedSize + 最高布局优先级，清单名降级压缩（40pt 上限）
2. 快速添加框灰底不可见（controlBackgroundColor 浅色模式下即白色）→ 改 canvas 底 + 细边框
3. 日历头部"视图"标签竖排换行 → Picker labelsHidden
4. 月网格两侧大片留白 → 去掉横向滚动轴，网格随内容区满宽拉伸；四象限已完成组不再沉底、卡底留白防裁切

复验通过后回归：252 项测试全部通过。

---

# 第三轮：Flutter 个人版剩余功能迁移（2026-09-26 晚）

基准：`workfollow-flutter-personal/desktop/lib`（个人分支）全量功能盘点（24 模块 + 易漏清单）；对照原生版现状核对后，迁移缺口如下。已确认原生版已有：放弃/恢复、置顶+置顶组、手动/日期/优先级排序、重复 endDate、笔记 folder/favorite/linkedTaskIDs、批量选择、垃圾桶完整交互。

## 缺口包与文件归属

**Round A（并行 3）**
| # | 包 | 拥有文件 |
| --- | --- | --- |
| A1 | 重复/提醒引擎+调度面板（法定工作日节假日、重复结束=日期/次数、完成后生成下一实例含子任务携带+撤销链+选中跳新实例、跳过此周期、提醒偏移多值、时间段 dueEndAt、今晚快捷、发生日预览、节假日角标） | `Domain/Task/RecurrenceRule.swift`、新增 `Domain/Task/ChineseWorkCalendar.swift`、`Application/TaskActions.swift`、`Infrastructure/Notifications/NativeReminderService.swift`、`Features/Tasks/TaskInspector/TaskDatePopoverV2.swift`（最小增量）、`Features/Tasks/TaskInspector/TaskDateDraftModel.swift` + 测试 |
| A2 | 数据迁移与备份（导入 workfollow-personal-migration v1/v2/v3 合并/替换+预览计数、导出含附件 base64、每日自动备份保留 7 天、恢复备份） | `Features/Settings/SettingsDataView.swift`、`Infrastructure/Persistence/NativePreviewRepository.swift`、`PersistenceCoordinator.swift`、新增 `Infrastructure/Persistence/MigrationSnapshot.swift` + 测试 |
| A3 | HUD 反馈+系统集成（五类优先级仲裁 HUD、撤销按钮、合并计数、完成提示音+节流、菜单栏 StatusItem、⌘1/2/9/4/5/6/⌘\ 快捷键、任务菜单） | `Features/Tasks/TaskWorkspaceModel.swift`（反馈埋点）、`App/AppEnvironment.swift`、`App/AppCommands.swift`、`App/WorkFollowApp.swift`、`Features/Shell/RootShellView.swift`、新增 `Features/Feedback/*`、`Features/QuickAdd/StatusItemController.swift` + 测试 |

**Round B（并行 3 + 1）**
| # | 包 | 拥有文件 |
| --- | --- | --- |
| B1 | 清单元数据与列表交互（清单颜色/置顶/删除回收集箱、侧栏拖放目标、行拖拽重排、⌘/Shift 多选、顺延动作、复制任务入口） | `Application/WorkspaceStore.swift`、`Application/TaskListProjection.swift`、`Features/Tasks/TaskManagementViews.swift`、`Features/Sidebar/SidebarViews.swift`、`Features/Tasks/TaskList/TaskListView.swift`、`Features/Tasks/TaskList/TaskContextMenuPopover.swift` |
| B2 | 笔记与编辑器补全（字数统计、复制正文、纯文本副本、富文本保护、笔记关联任务区；工具栏补高亮/链接/插入时间/代码/引用、选区创建任务、图片粘贴） | `Features/Notes/*`、`Features/Editor/*` |
| B3 | 命令面板与快速添加打磨（首项"新建任务「query」"、命令全集、搜索范围；识别摘要行、chip 删除语义、@清单识别已有清单） | `Features/Shell/CommandPalette*.swift`、`Features/Tasks/TaskList/QuickAdd*.swift` |
| B4 | 日历跨天色带（lane 布局整体拖动）与周视图增强 | `Features/Planning/PlanningWorkspaceView.swift`、新增 `Features/Planning/CalendarSpans.swift` |

明确不迁移：看板⌘7/习惯⌘8/统计菜单（Flutter 端为死菜单项）、演示模式（开发工具）。

迁移完成后：逐功能与滴答对比，产出 `docs/ticktick-feature-parity-2026-09-26.md`。

### 迁移实机验收（2026-09-26 晚，屏幕解锁后完成）

新构建逐项实机验证（`docs/screenshots/migration-acceptance-2026-09-26/`）：
- 日历：满宽 7 列 + 单日清单色条 + **跨天 lane 色带**（25→28 横跨）+ 今天圆点（B4）✅
- 侧栏：清单 14 色色点生效（B1）✅
- 菜单栏：清单/任务/视图三个新菜单 + 状态栏对勾图标（A3）✅
- 设置数据页：存储位置/模块文件清单/导入导出（打勾备份格式）/每日备份与恢复（A2）✅
- ⌘K 命令面板：首项"新建任务 · 保持当前视图 · 安排到今天"+命令全集+提示条（B3）✅
- HUD 反馈条/StatusItem 菜单为交互态 UI，静态截图无法呈现，由 16 项 FeedbackCenter 单测与启动存活烟测覆盖。

过程备注：`open -a WorkFollow` 会解析到 Xcode DerivedData 的旧构建（导致一次误截），验收一律用完整路径启动；显示器实际为 2560×1320pt，截图区域已修正。
