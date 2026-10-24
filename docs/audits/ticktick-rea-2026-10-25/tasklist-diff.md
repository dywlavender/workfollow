# 任务栏（任务列表区）差异分析 · 增量复核

> 日期：2026-10-25　目标：`/Applications/TickTick.app` 8.0.80
> 二进制 sha256 `752e2c0521b67a37a4442b9ef6f3c06cafd078a16be55d0301042ac7ad14f92d`（arm64 切片）
>
> 范围：主窗口**中间那一列任务列表** —— 顶栏 + 快速添加条 + 条件栏 + 分组头 + 任务行 + 空态。
> 不含左侧导航栏、右侧详情栏、看板、时间轴（另有审计）。
>
> 本次定位：**增量复核**。`ticktick-rea-2026-10-24/task-list-gap-analysis.md` 的 9 项里，
> 6 项已于提交 `9b91fba` 落地。本文只写**验证结果 + 新增发现 + 修正**，不重述已修好的细节。

---

## 0. 证据来源与方法

| 侧 | 手段 | 产出 |
|---|---|---|
| 滴答 | rea `decode_interface_builder`（迷你 bundle 绕开 64 文档上限） | 8 个任务栏 nib，**947 nodes / 517 edges**（outlet 157、action 27、target_action 81、objc_selector 26），8 个 nib 全部 `hierarchy_complete: true` |
| 滴答 | arm64 切片符号表（`lipo -thin arm64` + `strings`） | selector / outlet 是否**真有实现**的独立佐证（nib 连接不证明实现存在） |
| 本地 | 源码直读 | `Features/Tasks/TaskList/**` 36 文件 8158 行 + `Application/TaskViewPreferences.swift` |
| 本地 | 既有测试 | `TaskGroupHeaderActionsTests` / `TaskBulkActionBarTests` / `TaskListBatchOptimizationTests` |

可复现命令见 §10。

---

## 1. 结论先行

10-24 那批（`9b91fba`）**确实修对了**，本次逐条验证全部成立：
分组头三枚固定 outlet 已覆盖所有非已完成分组、已完成分页 30 条、折叠持久化、批量动作条、空态动作。

但把 nib 全量解出来后，暴露出 **6 个 10-24 没看到的缺口**，其中 3 个是"整块功能缺席"而非细节：

| # | 缺口 | 性质 | 优先级 |
|---|---|---|---|
| **N1** | **条件栏常驻缺席** —— 滴答在「快速添加条」与列表之间有一条 40pt `TTTaskListConditionView`，内含 4 枚筛选 chip（All Dates / All Lists / All Tags / All Status） | 整块功能 | **P0** |
| **N2** | **空态是 12 套变体，本地 1 套** —— 滴答 `TTTaskListEmptyHolderView` 有 `allEmptyView`/`filterEmptyView`/`searchEmptyView`/`n7dEmptyView`/`inboxEmptyView`/`completedEmptyView`/`habitEmptyView`/`archivedEmptyView`/`abandonedEmptyView`/`activityEmptyView`/`assignEmptyView`/`arrangeEmptyView` | 整块功能 | **P1** |
| **N3** | **标准 / 详细是两套 cell 类** —— 滴答 `TTTaskListStandardCell`(117 obj) 与 `TTTaskListDetailedCell`(156 obj) 是不同类 + `isDetailedPlaceholder` 运行时切换；本地是同一个 `TaskRowView` + 布尔开关 | 架构级 | **P1** |
| **N4** | **分组头缺①拖拽手柄②类型图标** —— `dragIndicatorView`(12×12) 与 `iconImageView`(17×17)，本地两者皆无 | 补齐 | P1 |
| **N5** | **详细行缺「搜索命中副标题」** —— `secondarySearchContainerView` + `secondarySearchLabel` + `secondarySearchImageView` 三者只在 Detailed cell 里 | 补齐 | P1 |
| **N6** | **列表内特殊行类型**：`TTTaskListHabitCell`(49 obj) 本地无对应；`TTTaskListCountdownCell`(28 obj) 本地已有 | 部分 | P2 |

另有 **3 处对 10-24 报告的修正/补强**（§4），以及 **4 条证据不足、不能当结论用的待确认项**（§5）。

---

## 2. 新增发现（10-24 未覆盖）

### N1 条件栏：列表上方常驻的 4 枚筛选 chip（P0，M）

**滴答侧**（`TTTaskListViewController.nib`，根视图 596×744，从下往上）：

| 区域 | 类 | frame |
|---|---|---|
| `outlineView` | `TTTaskListOutlineView` | `596×584` @ y=0 |
| **`conditionBar`** | **`TTTaskListConditionView`** | **`{0,588},{595,40}`** |
| `inputContainer` | `NSView` | `{0,628},{595,58}` |

即顺序：**标题栏 → 快速添加条(inputContainer) → 条件栏(conditionBar) → 任务列表**。
条件栏内含 4 枚 chip（`TTThemeButton`，y=6 居中于 40pt 条内）：

| outlet | frame | 文案 | 图标资源 |
|---|---|---|---|
| `dateButton` | `{20,6},{80,24}` | `All Dates` | `detail_calendar` |
| `listsButton` | `{110,6},{74,24}` | `All Lists` | `normal_project` |
| `tagsButton` | `{194,6},{74,24}` | `All Tags` | `tag` |
| `statusButton` | `{278,6},{84,24}` | `All Status` | `priority_stroke` |

**可伸缩的硬证据**：二进制里有 `conditionBarHeightConstraint`（`NSLayoutConstraint` outlet）与
`conditionView:shouldChangeHeight:` / `conditionView:didChangeConditionWith:` 两个 delegate 方法 ——
说明这条**高度会随条件数量变化**，不是固定 40。

**本地**：`grep "All Dates|全部日期|All Lists|全部清单"` → 0 命中。
`TaskListView.swift:310 headerBar` 只有 ☰ + 标题 + 排序(`viewMenu`) + 更多(`moreMenu`)，**没有条件栏**。
筛选只能通过侧栏选已保存的 `activeFilter`，**不能在列表视图内直接调 日期/清单/标签/状态 四个维度**。

**差距**：滴答的「今天」视图可以就地改成"今天 + 某清单 + 某标签"，本地必须先做一条筛选再去侧栏选。这是**操作路径长度**的差距，不是外观。

**建议**：`TaskListConditionBar`，四枚 chip + 高度约束随激活条件数增长（0 条件时整条高 0 或收起）。
数据源用 `TaskListQuery` 现有维度；条件写回 `TaskListQuery` 而非新建模型——避免与 `FilterEditor` 语义打架。

---

### N2 空态：12 套变体 vs 本地 1 套（P1，M）

**滴答侧**：`TTTaskListEmptyHolderView` 的 outlet 声明里有 12 个并列的 `emptyView`（二进制符号确认）：

```
allEmptyView       arrangeEmptyView   assignEmptyView    completedEmptyView
filterEmptyView    habitEmptyView     inboxEmptyView     n7dEmptyView
searchEmptyView    archivedEmptyView  abandonedEmptyView activityEmptyView
```

即**每种视图/状态有专门一套空态**，不是同一套换文案。
二进制里的实际文案样本：`No tasks for today. Enjoy your day.` / `No tasks left in "%@".`

**本地**：`TaskEmptyStateView` 一套 + `TaskListView.swift:352 emptyStateAction` 给 3 条文案
（今天→「看看未来 7 天」、收集箱→「新建第一个任务」、最近7天/明天→「回到今天」），其余 `default: nil`。

**差距**：本地在**已完成 / 搜索无结果 / 筛选无结果 / 归档 / 已放弃**这 5 个场景下拿到的是通用插画 + 一句，
且**没有下一步动作**。而这些正是用户会愣住的地方——"我筛完了什么都没有"。

**建议**：不照抄 12 个类。改 `TaskEmptyStateView` 的入参为 `EmptyStateKind`（`allTasks` / `today` /
`search` / `filter` / `completed` / `archived` / `abandoned`），每 kind 给 title / subtitle / 可选动作。
现在 3 条硬编码的映射搬进去，新增 `search` / `filter` / `completed` 三类即可覆盖 80% 场景。

---

### N3 标准 / 详细是两套 cell（P1，L）

**滴答侧**：两个独立类是事实，不是同一类的两种配置：

| nib | objects | connections | 独有 outlet |
|---|---|---|---|
| `TTTaskListStandardCell` | 117 | 31 | `checkboxWidthLC`, `tagsViewLeading` |
| `TTTaskListDetailedCell` | 156 | 39 | `checkboxTopLC`, `subtitleLabel`, `subtitleTopLC`, `noteDateLabel`, `subtaskProgressLabel`, `tagsViewBottomLC`, `secondarySearchContainerView(+HeightLC/ImageView/Label)` |

27 个 outlet 共有。二进制有 `isDetailedPlaceholder` / `setIsDetailedPlaceholder:`（`TB,N,V…` 说明是 Bool property）。

**本地**：单一 `TaskRowView`（`TaskListView.swift:1531`）+ `hidesDetails: Bool`
（`TaskViewPreferences.swift:144`）+ `TaskRowDetailField` 逐字段开关（`:115`，5 个字段
`date`/`list`/`priority`/`tags`/`indicators`）+ `TaskListView.swift:483` 的「隐藏详细」Toggle、
`:484` 的「显示设置」子菜单。

**关键差异**：本地的详细态是"在标准态上加东西"，滴答是"换一个 cell"。
本地多出来的 `subtitleLabel`（正文预览）/ `noteDateLabel` / `subtaskProgressLabel` 在详细态才出现，
但本地的 `TaskSecondaryMetadata` 只给 `symbol`/`value`，**没有"副标题占一整行"的布局位**。

**建议**：**不要**拆成两个类（本地 SwiftUI 行不需要 `NSCell` 复用语义，拆了是净增复杂度）。
真正的动作是把 Detailed 独有的三件东西补进现有行：**① 独立副标题行 ② 子任务进度文字 ③ 搜索命中副标题**（见 N5）。
`hidesDetails` 的语义保持不变。

---

### N4 分组头缺拖拽手柄与类型图标（P1，S）

**滴答侧**（`TTTaskListSectionCell.nib`，629×34，完整 outlet 表）：

| outlet | 类 | frame | 本地 |
|---|---|---|---|
| `dragIndicatorView` | `TTHoverableImageView` | `{3,7},{12,12}` | ❌ 无 |
| `triangleImageView` | `TTHoverableImageView` | `{16,0},{16,26}` | ✅ `TaskListView.swift:1080` chevron |
| `iconImageView` | `NSImageView` | `{31,5},{17,17}` | ❌ 无 |
| `titleLabel` | `TTLabel` | `{50,6},{412,14}` | ✅ |
| `countLabel` | `TTLabel` | `{471,7},{11,13}` | ⚠️ 有，但紧跟标题 |
| `addButton` | `TTThemeButton` | `{492,1},{24,24}` | ✅（`:1098`） |
| `moreButton` | `TTThemeButton` | `{516,1},{24,24}` | ✅（`:1111`） |
| `actionButton` | `TTThemeButton` | `{548,4},{58,18}` | ✅ 文字按钮（`:1127`） |

两处实质差异：

1. **`dragIndicatorView`（12×12，`TTHoverableImageView`）** —— 分组可拖拽排序的抓取点。
   本地 `grep dragIndicator|onDrag.*group|Draggable` 在列表区 **0 命中**：分组顺序只能靠「管理分组」弹窗拖。
2. **`iconImageView`（17×17）** —— 分组类型图标。二进制资源名里有 `section_icon_pinned`（置顶分组）、
   `normal_project`（普通分组）。本地分组头**只有文字**，看不出这组是"日期型/优先级型/自定义"。
3. **`countLabel` 位置** —— 滴答固定在 x=471（紧邻按钮组左侧），本地 `Text("\(count)")` 紧跟标题。
   长标题（如自定义分组名）时本地计数会被推远，滴答不会。这是 **P2** 的观感差异。

另外 **`groupHeaderHeight` 30 vs 滴答 34**（`TaskListMetrics.swift:6`）—— P2，一次性对齐即可。

---

### N5 详细行缺「搜索命中副标题」（P1，S）

**滴答侧**：`secondarySearchContainerView` + `secondarySearchContainerViewHeightLC` +
`secondarySearchImageView` + `secondarySearchLabel` **只在 `TTTaskListDetailedCell`**，
Standard cell 完全没有（§N3 表已证）。二进制符号齐全（含 `setSecondarySearchLabel:` 等 setter）。

语义推断（**这是推断，非观察**）：搜索时若命中点在**正文**而非标题，行内加一行显示命中的正文片段 +
一个标识图标，高度由 `secondarySearchContainerViewHeightLC` 控制。

**本地**：`grep secondarySearch` → 0 命中。`TaskListView.swift:141 query` 只用于过滤分组内容，
行内没有"命中位置"的展示。

**差距**：本地搜索能**筛出**任务，但看不出**为什么**这条被筛出来——标题没命中的任务会显得"莫名其妙出现在结果里"。

**建议**：`TaskRowMetadataTrail` 旁边加一个可选副标题行，值来自 `TaskListViewDefaults.bodyPreview`
（已存在，`:1734`）的命中片段；只在 `query` 非空且标题未命中时出现。

---

### N6 列表内特殊行类型（P2，S/M）

滴答任务列表里可以插入**非任务行**：

| nib | objects | 本地 |
|---|---|---|
| `TTTaskListCountdownCell` | 28（outlets：`dateLabel`/`dateRightLC`/`iconImageLeadingLC`/`iconImageView`/`nameLabel`/`nameLeadingLC`） | ✅ 已有，`TaskListView.swift:1365` 的 `TaskOutlineHost(store: countdownStore, …)` |
| `TTTaskListHabitCell` | 49（actions：`checkButtonClicked:`；outlets 含 `progressIcon`/`progressLabel`/`progressWidthConstraint`/`dateWidthConstraint`/`reminderIcon`） | ❌ 无习惯模块（`Features/` 下无 `Habit` 目录） |

**建议**：习惯模块是**独立功能线**，不在任务栏优化范围内。若要补，`HabitCell` 的结构
（勾选 + 进度 + 日期 + 提醒）可以复用现有 `TaskRowView` 的骨架 + 一个 `progressLabel`。
标记为「明确不做」（见 §6）比"待办"更合适。

---

## 3. 已验证对齐（10-24 已修，本次确认，不再动）

| 项 | 10-24 主张 | 本次验证 |
|---|---|---|
| 分组头三枚固定 outlet | 已覆盖所有非已完成分组 | ✅ `TaskGroupHeaderActions.resolve` 纯规则 + `TaskListView.swift:1092/1145` 30pt 高；`groupActionHit` 24 = nib 实测 24×24 |
| 文字动作语义 | 已过期→顺延、其它→全选、0 条不给 | ✅ `TaskGroupHeaderActions.swift:55`/`:73` 的 `primary` 纯规则；二进制确认 `postponeButtonClicked` / `selectAllButtonClicked` / `setPostponeButton:` 存在 |
| 已完成分页 | 30 条 + 行尾加载更多 | ✅ `TaskListMetrics.swift:40 completedPageSize=30`、`:42 loadMoreRowHeight=34`；二进制确认 `countToShowOfCompleted` / `didClickLoadMore` |
| 折叠持久化 | `collapsedGroups` 落盘 | ✅ `TaskListView.swift:1074-1075` 写回 + 二进制确认 `taskCollapseStateChanged` / `expandedTasksInSmartList` |
| 批量动作条 | 多选时替换快速添加条 | ✅ `TaskListView.swift:201-202`；二进制确认 `isMultipleModeForOneSelected` / `firstModelForMultipleSelection` |
| 快速添加条 7 动作 | 已对齐 | ✅ nib 里 7 个 selector：`addButtonClicked:` `dateButtonClicked:`(×2) `priorityButtonClicked:` `tagButtonClicked:` `listButtonClicked:` `moreButtonClicked:` `triangleButtonClicked:`；本地 `TaskListView.swift:526 quickAddBar` 结构一致 |

---

## 4. 对 10-24 的修正与补强

### 4.1 补强：`actionButton` 在 nib 里**没有** target-action 连接（对实现有直接影响）

10-24 §2.1 把 `actionButton` 和 `addButton`/`moreButton` 并列在同一张 outlet 表里，
并另起一段写"动作池（`TTTaskListSectionCell` 的选择器 + 主控制器的对应实现）"。
**这个表述本身是准确的**——它说的是方法名，没说是 IB 连接。本次补的是 nib 层的事实：

- `addButton` 与 `moreButton` 各有**一条 target-action 边**指向 cell 自身
- `actionButton` **一条都没有**

但相关符号在二进制里全在：

```
actionButtonClicked:            ← 带冒号，ObjC selector
actionButtonClicked(_:)
actionButtonClicked(_:for:)
setPostponeButton:              ← property setter
postponeButtonClicked           ← 无冒号，Swift 方法
selectAllButtonClicked          ← 无冒号，Swift 方法
```

即：`addButton`/`moreButton` 走 IB 连到 ObjC selector；`actionButton` 的三态
（顺延 / 全选 / 无）是**代码内部按分组类型分派给三个 Swift 方法**，IB 里看不到。

**对实现的影响**：本地 `TaskGroupHeaderActions.primary` 用枚举在 Swift 侧分支，方向与滴答一致。
但因为这条链**没有任何 nib 兜底**，删改 `primary` 时不会有编译期或 IB 层的提示，
只能靠单测守（`TaskGroupHeaderActionsTests` 11 项已覆盖）。

### 4.2 补强：type-select 的**筛选串重载**比 10-24 描述的更强（P2 → P1）

10-24 §2.7 已列出三个方法名，结论是"标准 AppKit type-select，打字跳到下一个标题匹配的行"，
建议"自己维护一个小状态机"。本次补充一个**影响实现选择的细节**：

```
outlineView:typeSelectStringForTableColumn:item:
outlineView:nextTypeSelectMatchFromItem:toItem:forString:
outlineView:shouldTypeSelectForEvent:withCurrentSearchString:   ← 关键
```

第三个方法带 `withCurrentSearchString:`。这是 `NSOutlineViewDelegate` 里
**独有于"带累积搜索串"场景**的重载（`NSTableView` 的同名方法只有
`shouldTypeSelectForEvent:`，没有 `withCurrentSearchString:` 版本）。

含义：滴答的 type-select **不是"打首字母跳一次"，而是维护一个累积前缀串**，
且能感知"当前已经有搜索串"的状态（用于决定是否把这次按键当成继续累积还是重新开始）。

**对实现的影响**：10-24 建议的"1.2s 超时重置的小状态机"方向正确，
但需要额外处理一件事——**累积串非空时按 Esc / 回车的行为**，
以及**累积串与 `QuickAddTextField` 焦点的互斥**。后者本地已有守卫模式可复用
（`TaskListView.swift:1386 handleOutlineKey` 是唯一的按键入口，
`:1393`/`:1396` 已用 `guard !quickAddFocused` 做过同样的互斥）。
`NativeTaskOutline.swift:213` 的 `Coordinator` 已声明 `NSOutlineViewDelegate` 并实现 5 个方法，
补三个 type-select 是加方法而不是改结构。
优先级从 P2 提到 P1：是本次所有项里投入最小的一个（S）。

### 4.3 补强：清单名就地改名有完整视觉容器

10-24 §2.8 只列了 `projectNameEditBackgroundView` 一个名字。
nib 实测它是 `TTListNameEditBackgroundView`，**frame `{79,6},{127,36}`**，
且 `titleLabel` 是 `{83,10},{119,28}` —— 即改名时在标题位置**浮起一个 127×36 的编辑背景块**，
内边距 4pt 左右，不是原地把 `NSTextField` 变成可编辑。
二进制另有 `_updateTitleEditingBackground`。

**对实现的影响**：本地 `TaskListView.swift:368 headerTitle` 是纯计算属性、`:336` 用 `Text(headerTitle)` 只读渲染。
直接原地换成 `TextField` 会得到"没有容器的裸编辑框"，跟滴答观感差一截。
需要一层带背景的容器 + 127 宽下界 + 4pt 内边距。

---

## 5. 待确认（证据不足，不要当结论用）

| # | 问题 | 现有证据 | 缺什么 |
|---|---|---|---|
| **Q1** | 滴答的 `+` / `…` 是否靠 hover 才显示？ | nib 里 `addButton`/`moreButton`/`actionButton` **都没有 `NSHidden`**，只有 `NSEnabled=false`（IB 设计态常见） | 运行态观察。**本地当前用 `isGroupHovered` 门控（`:1098`/`:1111`），这是我的实现选择，不是从滴答抄来的**。若滴答是常显，本地应去掉门控——但需要截图或 LLDB 证据，nib 推不出来 |
| **Q2** | `conditionBar` 在 0 条件时是隐藏还是高 0？ | 有 `conditionBarHeightConstraint` + `shouldChangeHeight:`，说明可伸缩 | 运行态。影响本地是"整条 `if` 掉"还是"高 0" |
| **Q3** | `secondarySearchLabel` 展示的是正文片段还是匹配计数？ | 有独立 `ImageView` + `Label`，推断是"图标 + 文本" | 搜索态截图 |
| **Q4** | 详细/标准切换是**用户可选**还是**自动判定**（如行高不够时降级）？ | `isDetailedPlaceholder` 的 "Placeholder" 命名暗示占位/降级用途 | 二进制反编译（**当前无引擎，卡住**）。本地 `hidesDetails` 是用户开关，若滴答是自动降级则语义不同 |

**Q4 特别说明**：这条**必须靠伪代码才能定论**，边界是明确的
`decompile(TTTaskListViewController)` —— 当前 Hopper / Ghidra / IDA 全未安装
（`binary_session` 的 `analysis_provider_candidates` 里 ghidra/ida 均 `unavailable`，
hopper 为 `missing_analysis_engine`）。**不要**用 nib 的 outlet 存在性去替代这个结论。

---

## 6. 如果只做三件事

按「投入产出比 × 彼此不打架」排序：

### 第一件：`TaskListConditionBar`（N1，M）
**为什么是它**：这是本次唯一**整块功能缺席**且**每天都会遇到**的缺口。
其余五项都是"有了但不够好"，这项是"根本没有"。而且它复用现有 `TaskListQuery` 维度，
不引入新模型，风险可控。

**注意**：会与 `FilterEditor` 产生语义重叠。要先定一件事——**条件栏改的是"临时条件"还是"当前筛选"**？
建议：条件栏只改内存态 `TaskListQuery`，不落盘；要持久化必须走「保存为筛选」
（正好对应滴答的 `saveFilterButton` 82×32，本地产出 §4.3 之外的第五枚顶栏按钮）。

### 第二件：空态 kind 化（N2，M）
**为什么第二**：与条件栏是**同一件事的另一面**——条件栏让用户能筛，空态告诉用户"为什么筛空了"。
两个一起做才有闭环。单独做条件栏会出现"筛完了还是那句通用文案"的落差。

**改动面小**：`TaskEmptyStateView` 加一个 `kind` 枚举，把 `:352` 的 3 条映射搬进去，新增 3 类。

### 第三件：`type-select`（§4.2，S）
**为什么第三**：**投入最小（S）收益最直接**。三个 delegate 方法是现成的，
`NativeTaskOutline.swift` 已有 delegate 骨架。补齐后长列表里能"打字母跳行"，
这是滴答用户最不会主动说、但一旦用上就回不去的功能。

**风险**：要处理与 `QuickAddTextField` 的按键抢占——`TaskListView.swift:1393/1396` 已有
`guard !quickAddFocused` 的守卫模式，可复用。

---

## 7. 明确不做（写清原因，避免下轮反复讨论）

| 功能 | 滴答证据 | 不做的原因 |
|---|---|---|
| 共享清单 | `shareButtonClicked:` + `shareButton` 28×28 | 依赖云端账号体系，本地无后端 |
| AI 推荐任务 | `aiRecTaskButtonClicked:` + `ai_rec_task` 图标 | 同上，需服务端模型 |
| 保存为筛选（顶栏 82×32 文字按钮） | `saveFilterButtonClicked:` + `saveFilterButton` + 文案 `Save as filter` | **本次不做**，但 N1 落地后应作为下一步——否则条件栏改的条件无处可存 |
| 清空回收站（顶栏） | `emptyTrashButtonClicked:` | 本地已有 `TaskTrashView.swift:60` 的入口，位置不同但不是缺口 |
| 习惯模块 | `TTTaskListHabitCell` 49 obj | 独立功能线，不在任务栏范围 |
| 打印 | 10-24 已确认滴答也没有 | 双方都没 |
| 详细/标准拆成两个 cell 类 | 真实存在 | 见 N3：SwiftUI 下拆类净增复杂度，收益全在补字段 |

---

## 8. 建议落地顺序

| 批次 | 内容 | 预估 |
|---|---|---|
| 一 | N4 分组头补齐（拖拽手柄 + 类型图标 + 34pt 高 + count 固定位） | S，1 天 |
| 一 | §4.2 type-select（三 delegate 方法） | S，1 天 |
| 二 | N1 条件栏（含 §5 Q2 的隐藏/高0 决策） | M，1–2 天 |
| 二 | N2 空态 kind 化 | M，1 天 |
| 三 | N5 搜索命中副标题 + N3 的副标题行/子任务进度 | M，1–2 天 |
| 待引擎 | §5 Q4 详细/标准切换语义（需反编译） | 阻塞 |
| 待决策 | 保存为筛选（N1 的后续） | S，但需先定存储语义 |

---

## 9. 本次覆盖与限制

**已覆盖**
- 8 个任务栏 nib 的**全部** outlet / action / target-action / view frame（947 nodes / 517 edges，8/8 `hierarchy_complete`）
- 关键 selector 在 arm64 二进制里的**存在性**独立验证（不止 nib 连接）
- 本地 36 个 TaskList 源文件的 grep 级 + 定点读取

**未覆盖 / 限制**
- **无分析引擎**：Hopper / Ghidra / IDA 均未安装 → 无伪代码、无 xrefs、无函数追踪。
  所有"某 selector 被调用后会怎样"的结论都**没有**证据支撑，§5 Q4 因此阻塞。
- nib 只反映**编译期**对象图：运行期创建的 UI、动态约束、真机像素几何都不在其中。
- 「target-action selector 存在」**不证明**二进制里有对应实现（rea 自身的 limitation 明确写了这一点）；
  本文对 §4.1 的「运行期动态挂 selector」判断依赖 `setPostponeButton:` 这个**命名推断**，属推断而非观察。
- 截图仅用了 `docs/screenshots/ticktick-reference/00-tasks-today.png` 一张，
  该图**未显示**条件栏与多选态（该账号下这两条都不活跃），所以 N1 的视觉细节仍以 nib 几何为准。

---

## 10. 复现命令

```bash
# 1. 迷你 bundle（绕开 decode_interface_builder 的 64 文档上限；TickTick 共 442 个 nib）
mkdir -p .probe/TaskListProbe.app/Contents/{MacOS,Resources}
cp /Applications/TickTick.app/Contents/MacOS/TickTick .probe/TaskListProbe.app/Contents/MacOS/
cp /Applications/TickTick.app/Contents/Info.plist .probe/TaskListProbe.app/Contents/
cp /Applications/TickTick.app/Contents/Resources/TTTaskList*.nib .probe/TaskListProbe.app/Contents/Resources/

# 2. 解码（rea CLI，输出可编程消费）
rea decode-interface-builder .probe/TaskListProbe.app \
  --max-documents 8 --max-objects 20000 --max-connections 40000 --format json > /tmp/nib.json

# 3. 符号佐证
lipo -thin arm64 /Applications/TickTick.app/Contents/MacOS/TickTick -output /tmp/tt-arm64
strings -a /tmp/tt-arm64 | grep -E "^(countToShowOfCompleted|didClickLoadMore|isMultipleModeForOneSelected)$"

# 4. 收尾
rm -rf .probe
```
