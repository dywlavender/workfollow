# 任务列表区（任务栏）与滴答的差距分析

> 范围："任务栏"= 主窗口**中间那一列任务列表**（顶栏 + 快速添加条 + 分组头 + 任务行 + 空态），
> 不含左侧导航栏、右侧详情栏、看板/时间轴（另有审计）。
>
> 证据来源：
> - 静态：`/Applications/TickTick.app` 8.0.80 的 `otool -ov` 类方法表 + NIBArchive 解析
>   （`TTTaskListViewController.nib` / `TTTaskListStandardCell.nib` / `TTTaskListDetailedCell.nib` /
>   `TTTaskListSectionCell.nib` / `TTTaskListInputView.nib` / `TTTaskListCountdownCell.nib`）。
>   解析脚本：`docs/audits/ticktick-rea-2026-10-17/scripts/parse_nibarchive.py`。
>   本目录解析结果：[ticktick-tasklist-nib-inventory.json](ticktick-tasklist-nib-inventory.json)
>   （6 个任务列表区 nib 的 outlet/action 全量 + 空态类的成员表）。
> - 运行态截图：`docs/screenshots/ticktick-reference/00-tasks-today.png`、`15-today-list-no-countdown.png`、
>   `18-countdown-in-today-group.png`。
> - 本地：`Features/Tasks/TaskList/**`、`Application/TaskViewPreferences.swift`。
>
> 优先级：**P0** = 明显影响日常操作；**P1** = 对齐滴答且有实感；**P2** = 细节/长尾。
> 工作量：**S** ≤ 半天；**M** 1–2 天；**L** 3 天以上。

---

## 1. 结论先行

本地任务列表的**骨架是对的**：NSOutlineView 宿主 + SwiftUI 行、分组头、快速添加条、
拖拽排序、Cmd/Shift 多选、子任务层级、日期徽标、标签胶囊、完成动画都已具备，很多细节
（选中行不留分割线、完成行分割线从标题起、行高随预览/标签自适应）还是照着实测逐像素修过的。

真正拉开距离的是**"一屏之内能完成多少操作"**，不是外观。滴答把大量操作放在
**分组头**和**行内悬停**上，本地则下沉到了右键菜单和详情栏。具体六个缺口：

| # | 缺口 | 滴答证据 | 本地现状 | 优先级 |
|---|---|---|---|---|
| 1 | 分组头只有「+」「…」两枚小图标，且只在自定义分组上出现 | `TTTaskListSectionCell`：`addButton`(24×24) + `moreButton`(24×24) + `countLabel` + **`actionButton`(58×18 文字按钮)** | `hoveredSectionID` 才显示 `+` 与 `…`，无文字按钮 | **P0** |
| 2 | 分组头的计数/动作随分组类型变化，本地是固定文案 | `actionButtonClicked:` / `postponeButtonClicked` / `selectAllButtonClicked` 三个动作并存 | 只有「已过期」组有「顺延」文字；没有「全选」 | **P0** |
| 3 | 已完成没有分页/加载更多 | `countToShowOfCompleted`、`didClickLoadMore`、`TTTaskListLoadMoreCell`（详情页同款） | 一次性全渲染 | P1 |
| 4 | 折叠状态不持久化 | `taskCollapseStateChanged:` + `expandedTasksInSmartList` | `TaskGroupExpansionState` 只在内存 | P1 |
| 5 | 无"多选模式"（框选后出现批量动作条） | `isMultipleModeForOneSelected`、`firstModelForMultipleSelection`、`TTTaskListConditionView` 底部动作 | Cmd/Shift 能选，但批量动作要开详情栏面板 | P1 |
| 6 | 空态是通用插画 + 一行文案 | `TTTaskListEmptyHolderView`：`imageView` + `titleLabel` + **`titleWithLinkLabel`** + `subtitleLabel` + **`subtitleWithLinkLabel`** + **`actionButton`** + `actionButtonHandler` | `TaskEmptyStateView(style: .list, message:)` 只有插画 + 一句 | P1 |

另外三个**行为级**差异，属于"滴答有、本地完全没有"：

| # | 缺口 | 滴答证据 | 影响 |
|---|---|---|---|
| 7 | 类型选择（type-select）：打字跳转到匹配行 | `outlineView:typeSelectStringForTableColumn:item:`、`nextTypeSelectMatchFromItem:toItem:forString:`、`shouldTypeSelectForEvent:` | 长列表里定位靠肉眼滚 |
| 8 | 清单名就地改名（顶栏标题） | `projectNameEditBackgroundView` + `projectNameEditBackgroundLeadingLC` + `_updateTitleEditingBackground` | 本地要绕到侧栏菜单 |
| 9 | 顶栏「共享」「AI 推荐任务」 | `shareButtonClicked:` / `aiRecTaskButtonClicked:` / `saveFilterButtonClicked:` | 本地没有对应能力（无云端/AI），**不做** |

---

## 2. 逐项详述

### 2.1 分组头：把三个动作还回去（P0，S）

**滴答**（`TTTaskListSectionCell.nib`，宽 596 的实测几何）：

| outlet | 类型 | frame | 作用 |
|---|---|---|---|
| `triangleImageView` | `TTHoverableImageView` | `{{16,0},{16,26}}` | 折叠箭头，**整行高等的竖条命中区** |
| `iconImageView` | `NSImageView` | `{{31,5},{17,17}}` | 分组图标（日期/优先级/自定义） |
| `titleLabel` | `TTLabel` | `{{50,6},{412,14}}` | 标题，**可双击就地改名**（`controlTextDidEndEditing:` 在 cell 自身） |
| `countLabel` | `TTLabel` | `{{471,7},{11,13}}` | 计数 |
| `addButton` | `TTThemeButton` | `{{492,1},{24,24}}` | 在此分组建任务 |
| `moreButton` | `TTThemeButton` | `{{516,1},{24,24}}` | 分组菜单 |
| `actionButton` | `TTThemeButton` | `{{548,4},{58,18}}` | **文字动作**（顺延 / 全选），宽度随文案 |

动作池（`TTTaskListSectionCell` 的选择器 + 主控制器的对应实现）：

- `postponeButtonClicked` → `postponeOverdue`
- `selectAllButtonClicked` → 选中该分组全部任务
- `addButtonClicked:` / `moreButtonClicked:`

**本地**（`TaskListView.swift:994`、`:1014`、`:1032`）：

```swift
if let sectionID = group.sectionID, hoveredSectionID == sectionID { /* + 按钮 */ }
if let sectionID = group.sectionID, hoveredSectionID == sectionID || activeSectionMenuID == sectionID { /* … 按钮 */ }
if let note = TaskListViewDefaults.groupTrailingNote(for: group.kind) { Button(note) { postponeOverdue } }
```

三个问题：

1. **只有自定义分组有按钮**。按日期/优先级/标签分出来的分组没有 `sectionID`，因此
   永远没有 `+`。但滴答的 `addButton` 是 cell 的固定 outlet——**每个分组头都有**，
   点它在该分组条件下建任务（比如「今天」组里建的任务自动排今天）。
2. **没有 `selectAllButtonClicked` 的对应物**。本地 `visibleRowOrder()` 已经存在
   （`TaskListView.swift:1119`），`workspace.extendBulkSelection` 也在，缺的只是一个
   把"这个分组的任务 id 全部并进批量选择"的入口。
3. **动作区宽度随分组类型变**，本地 `+`/`…` 是 18×18 的裸图标，没有统一的 24pt
   命中格（滴答两者都是 24×24）。悬停时两个 18pt 图标在一行里会显得比标题轻。

**建议**：

- 抽 `TaskGroupHeaderActions`：按 `group.kind` 决定动作位（`overdue` → 「顺延」；
  其它 → 「全选」；自定义分组额外有 `+`/`…`），渲染成和滴答同尺寸的
  `actionButton`（58×18，文字，`WFType.supporting`，`WFColors.accent`）。
- `+` 提到所有分组：非自定义分组走"预填该分组条件的快速添加条"（
  `quickAddScheduleOverride` / `quickAddPriorityOverride` 已有对应 override 机制）。
- 命中格统一 24×24，悬停整组淡入（现在 `+` 和 `…` 各自判断 hover，会出现只出现一个的中间态）。

### 2.2 已完成分组分页（P1，M）

**滴答**：`TTTaskListViewController` 有 `countToShowOfCompleted` 与 `didClickLoadMore`；
加载行是 `TTListLoadMoreCell`（`progressIndicator` + `loadMoreLabel` + `leadingLC`，
另有 `startLoading` / `endLoading` —— 点一下变转圈，加载完再收起）。

**本地**：`groups` 一次性把已完成全部算出来（`TaskListView.swift:155`），
`collapseNewCompletedGroups()` 只负责默认折叠（`:1092`）。任务多时：
- 折叠前要先把 N 行全部建出来（`nativeTextEditing` 走 NSHostingView，每行一个宿主视图）；
- 展开后整段渲染，没有"再加载 30 条"。

**建议**：已完成分组默认只放 `TaskListMetrics.completedPageSize`（30）条 + 一行
「显示更多（还有 N 条）」，点一次 `+30`，点击后先转圈再追加（对齐
`startLoading` / `endLoading` 的观感）。折叠状态下不建行（现在的
`displayedNodes` 仍会算出来，可以顺手短路）。这条同时也是性能优化。

### 2.3 折叠状态持久化（P1，S）

**滴答**：`taskCollapseStateChanged:` + `expandedTasksInSmartList`（ivar）→
分组展开态跟着账号走，重启后保持。

**本地**：`TaskGroupExpansionState` 是 `@State`（`TaskListView.swift:121`），
`TaskViewPreference`（`TaskViewPreferences.swift:136`）只有
`sortMode` / `grouping` / `sortDescending` / `hidesCompleted` / `hidesDetails` /
`hiddenFields` / `viewMode`，**没有折叠态**。

**建议**：`TaskViewPreference` 加 `collapsedGroups: [String]?`（optional，
旧档案缺键 = 默认行为）。键用现有 `TaskViewScopeKey.key(...)` + 分组 id，
和排序/分组偏好同一套作用域。注意已完成分组有"首次出现自动折叠"的逻辑
（`seenCompletedGroupIDs`），持久化后要让它只在**没有存档记录时**才自动折叠，
否则用户手动展开的会被一次次折叠回去。

### 2.4 多选模式与批量动作条（P1，M）

**滴答**：`isMultipleModeForOneSelected` / `firstModelForMultipleSelection`
说明多选是一个**显式模式**（不只是修饰键）：选中多于一条时顶栏/底栏换成批量动作。

**本地**：`workspace.bulkSelection` + Cmd/Shift 点击已实现
（`TaskListView.swift:1371-1373`），但批量动作只能通过 `TaskBatchPanelView`
打开——而它挂在 `RootShellView.swift:218`，是**右侧详情栏位置**的面板，
列表区自己没有入口。

**建议**：`bulkSelection.count > 1` 时，在快速添加条位置（或列表底部浮层）
显示一条批量动作条：完成 / 改日期 / 移动 / 加标签 / 删除 / 取消选择。
直接复用 `TaskBatchOperation`（`TaskActions.swift:1917`）——操作语义已经全有了，
这里只是把入口从右侧挪到"手边"。

### 2.5 空态：补动作与链接（P1，S）

**滴答** `TTTaskListEmptyHolderView`（无独立 nib，成员从 ObjC 方法表读全）：

```
$__lazy_storage_$_imageView / $_titleLabel / $_titleWithLinkLabel
$__lazy_storage_$_subtitleLabel / $_subtitleWithLinkLabel
$__lazy_storage_$_actionButton  +  actionButtonClicked:  +  actionButtonHandler
```

即空态有**主副两行文案 + 可点链接 + 一个动作按钮**（比如"今天没有任务 → 去看看未来 7 天"）。

**本地** `TaskEmptyStateView(style: .list, message:)`：只有插画 + `emptyStateMessage`
一句话（`TaskListView.swift:1826`）。文案质量其实不错（"今天的事情都做完了"），
但**没有下一步动作**。

**建议**：`TaskEmptyStateView` 加 `actionTitle` / `action` 两个可选参数；
列表侧按 destination 给：
- `.today` 空 → 「看看未来 7 天」→ `.nextSevenDays`
- `.inbox` 空 → 「新建第一个任务」→ 聚焦快速添加条
- `.trash` 空 → 不给动作

### 2.6 快速添加条（对比结论：已经对齐，不再动）

这一块是本项目**已经做到位**的部分，写在这里是为了避免后续再"优化"：

| 滴答 (`TTTaskListInputView.nib`) | 本地 |
|---|---|
| `inputContainerHeightLC` + `contentView` 上下留白 | `TaskListMetrics.quickAddHeight = 42`，`QuickAddBarStyle` 统一留白 |
| `dateButton` / `priorityButton` / `tagButton` / `listButton` / `moreButton`（各 24×24） | 展开后「日历」「▾更多属性」两枚 + `QuickAddPropertiesPopover` 里的优先级/清单/标签/附件/模板 |
| `addButton` 29×24 | 回车提交、`⌘N` 角标提示 |
| `enterTipsLabel`（"↵"提示） | `Text("⌘N")`（快捷键提示，语义等价） |
| `calendarButton` / `repeatImageView` / `dateRepeatImageView`（日期+重复叠加小图标） | 日期 badge 上叠重复标记，`quickAddBadgeColor` 按过期/今天/未来着色 |

差别只在**入口密度**：滴答是 5 枚常显图标平铺，本地是「日期 + 更多」两枚折叠。
本地这个选择是刻意的（顶栏 `moreMenu` 的注释里记了用户反馈"功能太多、不实用"），
维持现状。**不建议**为了像素对齐把 5 枚图标摊开。

### 2.7 类型选择（P2，S）

**滴答**：`outlineView:typeSelectStringForTableColumn:item:` +
`nextTypeSelectMatchFromItem:toItem:forString:` + `shouldTypeSelectForEvent:withCurrentSearchString:`
—— 标准 AppKit type-select，打字跳到下一个标题匹配的行。

**本地**：`NativeTaskOutline` 是 SwiftUI 包装的 NSOutlineView 宿主，没有类型选择；
`handleOutlineKey` 只处理上下/回车/空格/Esc（`TaskListView.swift:1208`）。

**建议**：快速添加条**未聚焦**时，把可打印字符转成 type-select 前缀缓冲
（1.2s 超时重置），在 `visibleRowOrder()` 里按标题前缀匹配并 `select`。
不必上 NSTableView 原生实现——列表已经是 SwiftUI 行，自己维护一个
小状态机更可控，也避开 TextKit 焦点冲突。

### 2.8 清单名就地改名（P2，S）

**滴答**：顶栏 `titleLabel`(119 宽) + `projectNameEditBackgroundView`(127×36)
+ `_updateTitleEditingBackground` —— 清单页点标题直接在原位变成输入框。

**本地**：`headerTitle` 是只读 `Text`（`TaskListView.swift:330`），改名要绕
侧栏的清单菜单。

**建议**：`workspace.activeList != nil` 时标题可双击 → 变 `TextField`，
提交走已有的 `workspace.saveList(_:replacing:)`（`TaskWorkspaceModel.swift:447`，
已含空名/重名/收集箱保护 + `activeList` 跟随改名）。注意要挡掉
"智能清单 / 过滤器 / 标签 / 收集箱"这几种不该就地改名的标题。

### 2.9 明确不做（写清楚原因，避免反复讨论）

| 滴答能力 | 为什么不跟 |
|---|---|
| `shareButtonClicked:` / 协作成员 | 本地是单机单用户，没有账号与同步；加个假按钮比不加更糟 |
| `aiRecTaskButtonClicked:` | 无云端模型；本地有命令面板，语义不同不硬套 |
| `saveFilterButtonClicked:`（条件栏的"保存为过滤器"） | 本地过滤器已经在侧栏以编辑器形式建立，条件栏本就没有（见下） |
| `TTTaskListConditionView`（日期/清单/标签/状态四段条件栏） | 本地"所有任务"用侧栏 + 分组/排序菜单表达同一件事，条件栏是另一套入口。**除非**要做"智能清单在线编辑"，否则不做 |
| 看板/时间轴相关 | 另有审计 |

---

## 3. 建议落地顺序

按"改动小 × 每天都能感到"排序，四批：

**第一批（P0，都是 S，可同一笔提交）**
1. 分组头 `actionButton`：「已过期 → 顺延」「其它 → 全选」。
2. `+` 提到所有分组（非自定义分组用 override 预填条件）。
3. `+`/`…` 命中格统一 24×24、悬停整组一起淡入。

**第二批（P1，S+M）**
4. 折叠状态持久化（`TaskViewPreference.collapsedGroups`）。
5. 空态补动作按钮。
6. 已完成分组分页（默认 30，加载更多 +30）。

**第三批（P1，M）**
7. 多选模式：`bulkSelection.count > 1` 时列表区出批量动作条。

**第四批（P2，S）**
8. 类型选择（打字跳转）。
9. 清单名就地改名。

快速添加条（§2.6）经比对**已经对齐**，不在任何一批里——别为了像素一致把
5 枚图标摊开，那正是用户反馈"功能太多"而收掉的东西。

---

## 4. 与既有审计的关系

- 编辑栏相关的差距见 `docs/audits/ticktick-rea-2026-10-17/editor-gap-analysis.md`
  （已落四批：块菜单六级标题 / 代码着色 / 图片预览 / 富文本粘贴 / 保存重试 /
  评论回复编辑 / 焦点接力 / `~` 清单补全 / 进度条可拖）。
- 看板规则见 `docs/audits/ticktick-kanban-rules-2026-10-19/`。
- 日期面板见 `docs/audits/ticktick-date-panel-2026-10-19/`。
- 本文只覆盖**列表区本体**，不含左侧导航与右侧详情。
