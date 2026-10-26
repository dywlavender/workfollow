# 清单模式落地方案与分阶段验收

日期：2026-10-25。分支：`experiment/macos-native`。范围：任务详情里的“清单”形态（`TaskKind.checklist`），不含独立笔记页、列表/日历/看板本体。

依据：

- 滴答 8.0.80 (492) 的静态证据：`TTChecklistItemEntity`、`TTTaskEntity.checklistItems`、`ZTTCHECKLISTITEM`、`TTTaskDetailCheckItemCell`、`TTTaskDetailProgressView`、`TTChecklistDerivedTaskStatusReducer`。
- 现有差异调查：[editor-gap-analysis.md](../ticktick-rea-2026-10-17/editor-gap-analysis.md)、[ticktick-detail-nib-inventory.md](../ticktick-rea-2026-10-17/ticktick-detail-nib-inventory.md)。
- 参考截图：[09-checklist-mode.png](../ticktick-rea-2026-10-17/walkthrough/09-checklist-mode.png)、[08-kind-menu.png](../ticktick-rea-2026-10-17/walkthrough/08-kind-menu.png)、[13-selection-checkbox.png](../ticktick-rea-2026-10-17/walkthrough/13-selection-checkbox.png)。
- 本地基线：`TaskKind.checklist` 已存在；检查项是文档块；块 ID 通过 Delta 的 `wf-block-id` 往返；列表正文读取走 `DocumentSummary` 延迟加载。

## 0. 结论与范围

本方案不复制滴答的独立实体/独立表模型，而是把“检查事项”继续作为文档块，把条目元数据挂在该块上，并用 `DocumentSummary` 做列表与提醒的快路径投影。

**v1 交付（P0–P3 + P6）**

- 清单项有完成时间；全勾且无未完成子任务时任务自动完成；有未勾项时不能手动完成；取消勾选可重开。
- 活动检查项行尾有“提醒 + 删除”两个控件；提醒可设置、清除并持久化。
- 文本 ↔ 清单切换会提示排版影响；切回时恢复已勾选状态和提醒。
- 列表/看板显示检查项进度，不水合正文。
- 不新增编辑器顶栏进度条。

**v1.1（P4–P5，可按需裁剪）**

- 项级提醒进入系统通知、支持稍后提醒。
- 重复任务、复制/模板、子任务完成联动、键盘调序。

**明确不做**

- 不新增 `checklist_items` 表，不引入第二套任务正文模型。
- 不做项级层级、指派人、评论、附件、独立日历事件。
- 不做会员额度、共享清单权限、Notion 集成。
- 不在编辑器上方恢复常驻进度条（2026-10-25 用户已明确删除）。
- v1 不做拖拽排序；先留键盘调序（可选），拖拽另立。

## 1. 现状基线

| 能力 | 现状 | 证据 |
|---|---|---|
| 任务形态 | `Task.kind`：文本 / 笔记 / 清单 | `Domain/Task/TaskKind.swift` |
| 清单内容 | 文档块 `checklist(Bool)` | `Domain/Document/NativeDocument.swift` |
| 形态切换 | 普通/无序/有序段落 ↔ 检查项；切回文本给已勾选项加删除线 | `Application/TaskActions.swift` `document(_:convertingTo:)` |
| 清单项操作 | 空项退格删除、活动项行尾 × 删除 | `Features/Editor/NativeTextView.swift`、`DocumentChecklistItemTests.swift` |
| 完成框 | 绘制 12.96pt 复选框，点击翻转 | `Features/Editor/DocumentBlockDecorations.swift` |
| 持久化 | Delta 为真源；块 ID 存 `wf-block-id` | `Domain/Document/QuillDeltaCodec.swift` |
| 列表正文 | 延迟文档 + `DocumentSummary`，不读正文 | `Domain/Document/DeferredDocument.swift`、`Infrastructure/Persistence/SQLiteWorkspaceRepository.swift` |
| 进度 | 编辑器进度条已删除；列表有子任务 `n/m` | `TaskSecondaryMetadata.swift`、`TaskWorkspaceModel.subtaskProgress` |
| 检查项元数据 | 只有勾选布尔；无完成时间、无提醒 | 本次基线 |
| 清单派生状态 | 不汇总任务状态 | 本次基线 |

基线测试类（P0 先跑通）：

```text
TaskKindTests
DocumentChecklistItemTests
DocumentContentTests
DeferredDocumentTests
TaskReminderDeliveryTests
TaskInspectorHierarchyRenderTests
TaskInspectorShellContractTests
TaskInspectorRowMetadataTests
```

## 2. 方案选择

### 方案 A：滴答式独立实体（不采用）

新增 `ChecklistItem` 领域实体 + 独立 SQLite 表 + 独立编辑器宿主。

- 优点：与滴答结构最接近；项级查询、提醒、排序天然独立。
- 缺点：正文要拆成“文档 + 条目”两套真源；模式切换、撤销、自动保存、IME、剪贴板、附件、标签、子任务都要各接一遍；成本 L，风险高。

### 方案 B：块内元数据 + 摘要投影（采用）

- 检查项仍是 `DocumentBlock`，新增 `ChecklistItemMeta` 挂在块上。
- 持久化仍在 Delta 行属性里，新增 `wf-checklist-*`；旧档缺键即 nil。
- `DocumentSummary` 增加清单投影（总数、完成数、未来提醒），列表和提醒调度只读摘要，不水合正文。
- `TaskActions` 在文档提交时统一做状态派生，保证所有编辑入口一致。

优点：

1. 单一真源，撤销/自动保存/IME/剪贴板沿用现有链路。
2. 加法式持久化，不改表结构；回退版本会忽略未知属性。
3. 列表和提醒不读正文，符合现有 `DocumentSummary` 设计。
4. 模式切换可以保留条目元数据，切回时恢复勾选/提醒。

代价：

1. 清单不再是“纯清单”，文档里可以同时有标题、附件等块；这是有意的本地差异。
2. 块 ID 在整行移动时可能重绑；v1 用测试锁定行为，拖拽排序另做。
3. 项级数据仅适合当前量级；若未来要跨任务查询条目，再迁移到独立表。

### 关键决策

| 编号 | 决策 | 理由 |
|---|---|---|
| D1 | 元数据挂在 `DocumentBlock`，不建 Task 侧字典 | 避免块 ID 变动时元数据串行；复制/删除天然跟随块 |
| D2 | Delta 行属性持久化 `wf-checklist-*` | 与 `wf-block-id` 同层；旧档兼容 |
| D3 | `DocumentSummary` 增加清单投影 | 列表/提醒不水合正文，复用现有快路径 |
| D4 | 完成状态由 `TaskActions` 派生，不在编辑器里改任务 | 所有入口（标题框、列表勾选、菜单）一致 |
| D5 | 不恢复顶栏进度条；进度只进列表/看板 | 遵从 2026-10-25 用户删除决定 |
| D6 | v1 不做拖拽排序 | 先保证元数据不串行；键盘调序可选 |
| D7 | 重复任务下一周期清空完成时间；项提醒随任务日期平移，落点在过去则清空（已确认） | 避免旧提醒落在过去；P5 锁定测试 |

## 3. 目标模型

### 3.1 领域

```swift
struct ChecklistItemMeta: Equatable, Codable {
    var completedAt: Date?
    var reminderAt: Date?
    var allDay: Bool
}

struct DocumentBlock {
    // 现有字段…
    var checklist: ChecklistItemMeta?
}
```

- `kind = .checklist(checked)` 仍是勾选真源；`completedAt` 只记录时间。
- 勾选：`checked = true` 且 `completedAt = now`；取消：`checked = false` 且 `completedAt = nil`。
- 提醒：绝对时间；全天提醒按现有 `ScheduleSemantics.allDayAnchorHour`（09:00）落点。
- 非清单块即使带有 `checklist` 值也不参与投影；切换形态时保留值，便于切回恢复。

### 3.2 Delta

行属性新增：

```text
wf-checklist-completed-at: number   // 毫秒时间戳，可选
wf-checklist-reminder-at:  number   // 毫秒时间戳，可选
wf-checklist-all-day:      bool     // 可选
```

- `QuillDeltaCodec.delta` 只对 `.checklist` 块写入。
- `document(from:)` 读回 `DocumentBlock.checklist`；未知/缺失键 → nil。
- 旧 `{blocks}` 存档由 `DocumentBlock` Codable 自动兼容。

### 3.3 摘要投影

```swift
struct ChecklistSummary: Codable, Equatable {
    var total: Int
    var done: Int
    var reminders: [ChecklistReminderSummary] // 未完成项的未来提醒
}

struct ChecklistReminderSummary: Codable, Equatable {
    var blockID: UUID
    var title: String
    var fireDate: Date
}
```

- `DocumentSummary` 增加 `checklist: ChecklistSummary?`。
- 计算口径：只统计 `.checklist` 块；`total > 0` 才有效；已勾选项不进入 `reminders`。
- 访问器：

```swift
extension NativeDocument {
    var checklistSummary: ChecklistSummary? {
        // 延迟文档只信摘要；摘要为 nil 时也不能回落读正文，否则列表会水合。
        if let deferredSummary { return deferredSummary.checklist }
        return ChecklistSummary(blocks) // 只有内存文档才从块计算
    }
}
```

- 列表行、提醒调度只读它；读取不得触发 `DeferredDocument.resolve()`。
- v2 旧摘要没有 `checklist` 时返回 nil，依赖 P1 的 v3 迁移回填；不在读取路径里懒加载正文。

### 3.4 派生状态

`ChecklistDerivedStatus` 纯函数，输入：

```text
当前任务状态
本次文档变更前/后的清单投影
是否存在未完成直接子任务
任务是否手动完成/取消完成
```

规则：

1. 活动任务 + 清单项 > 0 + 全部勾选 + 无未完成子任务 → 任务完成。
2. 活动任务手动完成，但存在未勾选项 → 拒绝，返回 `checklistItemsIncomplete`，UI 提示“还有未完成的检查事项”。
3. 已完成任务取消勾选一项，且取消前其余项全部勾选 → 任务回到活动。
4. 已完成任务尝试直接取消完成，但清单项仍全勾 → 拒绝，返回 `checklistItemsCompleted`，UI 提示“取消勾选任一检查事项以重新打开”。
5. 清单项为 0 → 不自动完成、不拦截手动完成。
6. 有未完成子任务 → 不自动完成；子任务全部完成后是否补触发，见 P5。

所有派生与文档提交放在同一 `store.transaction`，一步撤销。

## 4. 分阶段计划

| 阶段 | 内容 | 预估 | 退出条件 |
|---|---|---:|---|
| P0 | 设计定稿与基线 | 0.5d | 决策 D1–D7 记录；基线测试通过 |
| P1 | 模型、持久化、派生状态 | 2–3d | 模型/迁移/状态机测试全绿 |
| P2 | 编辑器交互与模式切换 | 2–3d | 提醒/删除/完成时间/切模式验收通过 |
| P3 | 进度与列表集成 | 1–1.5d | 列表不水合正文且进度正确 |
| P4 | 项级提醒（v1.1） | 2–3d | 通知排程/取消/稍后提醒通过 |
| P5 | 重复/复制/子任务联动（v1.1） | 1–2d | 边界用例通过 |
| P6 | 回归、迁移、发布验收 | 1–2d | 定向回归 + 手动脚本 + 包校验 |

### P0 设计定稿与基线

工作项：

- 把 D1–D7 记录在本文件；确认 v1/v1.1 边界。
- 建测试夹具：20 项清单、200 项清单、3 标签 + 2 子任务 + 附件、延迟文档列表。
- 跑基线测试，记录用例数与耗时。

验收：

- [x] P0-A1：基线 8 个测试类全部通过，且执行用例数 > 0（零用例视为失败）。
- [x] P0-A2：测试夹具只存在于测试目录，未写入真实工作区。
- [x] P0-A3：D1–D7 无未决项；D7 的最坏情况已有处理方案。
- [x] P0-A4：本阶段不修改生产代码。

### P1 模型、持久化与派生状态

工作项：

- `Domain/Document/NativeDocument.swift`：`ChecklistItemMeta`、`DocumentBlock.checklist`。
- `Domain/Document/QuillDeltaCodec.swift`：`wf-checklist-*` 编解码。
- `Domain/Document/DeferredDocument.swift`：`ChecklistSummary`、`DocumentSummary.checklist`。
- `Infrastructure/Persistence/SQLiteWorkspaceRepository.swift`：`user_version=3`，一次性重算全部 `document_summary`。
- `Domain/Document/NativeDocument.swift`：`replacingPlainText` 保留原块的 checklist 元数据；新行不继承。
- `Features/Editor/DocumentTextCodec.swift`：`decode` 按保留的块身份回填元数据。
- `Application/TaskActions.swift`：形态映射恢复勾选/提醒；文档提交后的派生状态；完成/取消完成守卫。
- `Application/TaskActionResult.swift`：新增 `checklistItemsIncomplete`、`checklistItemsCompleted`。
- `Application/TaskChangeSet.swift`：识别 `.kind`；清单任务的 `.document` 变更视为提醒相关。

验收：

- [x] P1-A1：旧 `{ops}` 与旧 `{blocks}` 存档无 `wf-checklist-*` 时可解码，元数据为 nil。
- [x] P1-A2：新存档保存/重开/再保存后，`completedAt`、`reminderAt`、`allDay` 不变。
- [x] P1-A3：v2 数据库升级到 v3 后，所有任务的 `document_summary.checklist` 已回填；正文只读一次且升级失败可回滚。
- [x] P1-A4：同一行内输入不丢元数据；回车新建的下一项没有上一项的提醒/完成时间。
- [x] P1-A5：删除检查项后，其元数据不再出现在摘要里。
- [x] P1-A6：文本→清单→文本→清单往返后，已完成项恢复勾选，提醒仍在；富文本块内容不丢。
- [x] P1-A7：`setKind`、`setDocument` 派生状态均为一步撤销。
- [x] P1-A8：零检查项不自动完成；有未完成子任务不自动完成。
- [x] P1-A9：有未勾项时 `complete` 返回 `checklistItemsIncomplete`；全勾时 `restore` 返回 `checklistItemsCompleted`。
- [x] P1-A10：非清单任务的文档变更不会触发提醒重排。

测试类：

```text
ChecklistModelTests
ChecklistPersistenceTests
ChecklistEditorRoundTripTests
ChecklistModeSwitchTests
ChecklistDerivedStatusTests
TaskChangeSetChecklistTests
```

### P2 编辑器交互与模式切换

工作项：

- `Features/Editor/DocumentBlockDecorations.swift`：活动检查项行尾绘制“铃铛 + ×”；有提醒的非活动项常驻小铃铛。
- `Features/Editor/NativeTextView.swift`：`checklistReminderHitRect`、点击打开面板、勾选时写 `completedAt`；回车新项不继承元数据。
- 新增 `ChecklistItemReminderPanel`（NSPanel + SwiftUI）：今天 09:00 / 今天 18:00 / 明天 09:00 / 自定义 / 清除；Esc 关闭，Return 确认。
- `Features/Editor/DocumentProfile.swift`：宿主回调
  - `checklistItem: (UUID) -> ChecklistItemMeta?`
  - `setChecklistReminder: (UUID, Date?) -> Void`
- `Features/Editor/DocumentEditorCoordinator.swift`：区分“正文变化”和“仅元数据变化”；仅元数据变化不重建 text storage，保留光标与面板。
- `Features/Tasks/TaskInspector/TaskInspectorShell.swift`：切到清单前计算影响并弹确认；完成失败显示反馈。
- `Application/TaskActions.swift`：`ChecklistConversionImpact` 纯函数（受影响的结构块数、会保留的富文本块数）。

交互口径：

- 勾选框按滴答 nib `checkBoxButton` 的 17×17 绘制；检查项行距约 30pt（18pt 行盒 + 12pt 段间距），相邻检查项之间有 1 物理像素的浅灰分隔线。
- 勾选完成只把文字变灰（与已完成任务同档 `taskCompletedColor`），不加删除线；切回文本时才补删除线。
- 行尾控件按滴答 `TTTaskDetailCheckItemCell`：铃铛/删除各 24×24 命中区，铃铛在删除左侧、间隔 2pt；图标 16/14pt，`secondaryLabelColor`。
- 鼠标悬停哪一行就在哪一行显示铃铛与 ×（滴答 `TTHoverableImageView`）；没有悬停时退回光标所在行。有提醒的任意行常驻小铃铛作为状态。
- 提醒面板沿用日期提醒子卡片的选项行/确认按钮样式（34pt 行高、强调色勾选、取消/确定）；草稿确认后立即落库，以行为锚点，不抢编辑器焦点。
- 切到清单时，仅当存在标题/引用/代码/分割线这些"保留但不计入检查项与进度"的结构才弹确认；文案沿用"切换模式后，当前排版格式将失效，是否继续？"，正文说明这些结构会保留但不计入进度。
- 附件、流程图与缩进项随检查项保留，不触发确认。
- 取消确认不改变任何状态；确认是一步撤销。

验收：

- [x] P2-A1：点击勾选框立即翻转；`completedAt` 写入/清除；已勾选样式不变。
- [x] P2-A2：铃铛和 × 命中区不重叠；点击铃铛打开面板，点击 × 删除整项。
- [x] P2-A3：设置提醒后面板关闭、行上出现铃铛、重开任务仍在；清除后消失。
- [x] P2-A4：回车新建的下一项没有提醒；删除带提醒的项后摘要不再包含它。
- [x] P2-A5：内部复制/粘贴检查项会保留勾选状态、清除提醒；外部纯文本/HTML 粘贴不产生元数据。
- [x] P2-A6：仅设置提醒时不重建正文、不丢光标/选区/输入法组合串。
- [x] P2-A7：切换模式确认框出现/取消/确认路径正确；确认后一步撤销。
- [ ] P2-A8：320pt 与 880pt 宽度下铃铛、× 不裁切、不压正文（需 GUI 手动验收）。
- [ ] P2-A9：中文输入法组合期间勾选/设置提醒不丢字；失焦/切任务触发最终保存（需 GUI 手动验收）。
- [ ] P2-A10：VoiceOver 能读出“检查事项：<标题>，已完成/未完成，有提醒”（描述与自定义动作已实现，需 VoiceOver 手动验收）。

测试类：

```text
ChecklistEditorInteractionTests
ChecklistMetadataRerenderTests
ChecklistModeSwitchUITests
ChecklistAccessibilityTests
```

### P3 进度与列表集成

工作项：

- `Features/Tasks/TaskList/TaskSecondaryMetadata.swift`：清单任务显示 `done/total`，读 `task.document.checklistSummary`。
- `Features/Tasks/TaskList/TaskListView.swift` / `TaskKanbanCardView.swift`：传入或直接读取清单进度。
- `Features/Tasks/TaskWorkspaceModel.swift`：如需缓存，按 revision 缓存 `UUID -> ChecklistSummary`，不得触发正文加载。
- 搜索/预览继续使用 `plainText`，不改。
- 不新增顶栏进度条、不恢复 `.progressBar` 渲染锚点。

显示规则：

1. `task.kind == .checklist` 且 `total > 0` → 显示清单进度。
2. 非清单任务即使正文有复选框 → 不显示清单进度。
3. 清单任务同时有子任务 → 清单进度优先；子任务进度仍在详情内显示。
4. `total == 0` → 不占位。

验收：

- [x] P3-A1：清单任务列表行显示 `2/3`；勾选/删除后即时更新。
- [x] P3-A2：文本任务正文里的复选框不被当作清单进度。
- [x] P3-A3：清单 + 子任务并存时，列表显示清单进度，详情仍显示子任务区。
- [x] P3-A4：100 个清单任务的列表渲染后 `documentReadCount == 0`。
- [x] P3-A5：搜索仍能命中检查项文字；首行预览不变。
- [x] P3-A6：`InspectorRenderAnchor.progressBar` 与 `TaskInspectorProgressBar` 保持删除状态。
- [x] P3-A7：看板卡片的进度与列表一致；隐藏详细时按现有规则隐藏。
- [x] P3-A8：VoiceOver 读“检查事项进度：2/3”。

测试类：

```text
ChecklistListProgressTests
DeferredDocumentChecklistTests
TaskInspectorShellContractTests
TaskInspectorRowMetadataTests
```

### P4 项级提醒（v1.1）

工作项：

- `Infrastructure/Notifications/TaskReminderPlan.swift`：
  - `ReminderDelivery.Kind` 增加 `.checklistItem`。
  - `ReminderDelivery` 增加可选 `checklistItemID: UUID?`。
  - 从 `task.document.checklistSummary?.reminders` 生成投递；仅 `kind == .checklist`、任务未关闭、项未勾选。
  - 标识符：`checklist.<taskID>.<blockID>.at.<unix>`。
- `Infrastructure/Notifications/NotificationCoordinator.swift`：`pendingManagedIDs` 纳入 `checklist.` 前缀。
- `Infrastructure/Notifications/NativeReminderService.swift`：打开通知时选中任务；可选滚动/闪烁到条目。
- 提醒变更、勾选、删除、切模式、完成任务都通过现有 reconcile 取消/重排。

验收：

- [x] P4-A1：设置项提醒后系统队列出现 `checklist.` 通知；清除后消失（假客户端自动用例锁定投递与清理；真机队列待手动复核）。
- [x] P4-A2：勾选该项后通知取消；取消勾选后若提醒仍在未来，重新排入。
- [x] P4-A3：删除项、切到文本、完成任务后无孤儿通知。
- [x] P4-A4：稍后提醒/停止本次提醒对项提醒生效；重启后仍生效（与任务提醒共用决策存档）。
- [x] P4-A5：同一时间多个项提醒按 ID 稳定排序；重复日期去重。
- [x] P4-A6：全局 256 条上限下，任务提醒与项提醒不互相删除（按标识前缀分别裁剪）。
- [ ] P4-A7：打开通知选中对应任务；若实现定位，滚动到条目并短暂高亮（已选中任务；行定位留待手动复核）。
- [x] P4-A8：未授权/拒绝通知时，设置提醒仍保存，提醒面板底部显示授权状态。

测试类：

```text
ChecklistReminderNotificationTests
TaskReminderDeliveryTests
TaskReminderInvalidationTests
```

### P5 重复、复制、子任务联动（v1.1）

工作项：

- `TaskActions.makeNextOccurrence`：下一周期文档重置检查项完成状态；项提醒按 D7 决策处理。
- 复制/模板：`resetCompletion` 为真时清空完成时间与提醒。
- 完成最后一个直接子任务后，重新计算父清单任务派生状态。
- 可选键盘调序：`⌥↑` / `⌥↓` 移动检查项，保留元数据，一步撤销。
- 拖拽排序不在本阶段。

验收：

- [x] P5-A1：重复任务完成后，下一实例检查项全部未勾选，完成时间为空。
- [x] P5-A2：项提醒在下一实例上的落点符合 D7（平移或清空），有测试锁定。
- [x] P5-A3：复制任务默认不复制完成时间/提醒；模板实例不复制。
- [x] P5-A4：清单任务只剩最后一个未完成子任务时，完成该子任务后父任务自动完成；一步撤销。
- [ ] P5-A5：键盘调序后元数据跟随条目，不串行；撤销恢复顺序（可选，本轮未实现）。
- [ ] P5-A6：200 项清单输入/勾选/撤销无明显卡顿；列表 100 任务仍不水合正文（待手动性能验收）。

测试类：

```text
ChecklistRecurrenceTests
ChecklistDerivedStatusTests
```

### P6 回归、迁移与发布验收

工作项：

- 定向回归（下节命令）。
- Release 构建与包校验。
- 在隔离副本里跑手动脚本；不改日用安装版。
- 用真实工作区的**副本**做 v2→v3 迁移验证；原库只读。
- 更新本文件与相关 README。

验收：

- [x] P6-A1：定向测试类全部通过，执行用例数 > 0。
- [x] P6-A2：Release 构建通过，包内 Info.plist / 签名 / 资源校验通过。
- [ ] P6-A3：手动脚本 12 项全部通过，记录截图与结果。
- [ ] P6-A4：迁移副本任务数、文档数、清单进度、提醒数与原库一致；原库未被修改。
- [ ] P6-A5：回退版本能打开新存档（忽略 `wf-checklist-*`），不崩溃、不丢正文。
- [x] P6-A6：日用安装版只在用户明确要求时更新（已按要求部署视觉修订版；P4/P5 构建尚未安装）。

## 5. 总验收矩阵（滴答行为 → 本地目标）

| 滴答行为 | 本地目标 | 验收 |
|---|---|---|
| 任务 / 笔记 / 清单三形态 | 保留现有三形态；清单为文档块形态 | P1-A6、P2-A7 |
| 检查项行 + 勾选 + 行尾删除 | 已有；补提醒控件与完成时间 | P2-A1、P2-A2 |
| 项级提醒（会员） | 本地免费实现绝对时间提醒 | P4-A1–A8 |
| 全勾自动完成任务 | 实现；有未完成子任务时阻止 | P1-A8、P5-A4 |
| 有未勾项不能完成 | 实现并给反馈 | P1-A9、P2 |
| 取消勾选重开已完成任务 | 实现 | P1-A7、P1-A9 |
| 进度条 | 不恢复顶栏条；列表显示 `n/m` | P3-A1–A6 |
| 切清单提示排版失效 | 条件确认 + 一步撤销 | P2-A7 |
| 切回文本保留已完成状态 | 删除线 + 元数据恢复勾选 | P1-A6 |
| 检查项拖拽排序 | v1 不做；键盘调序可选 | P5-A5 |
| 检查项与子任务、标签共存 | 保持现有共存 | P3-A3 |
| 重复任务重置检查项 | 下一周期重置完成状态 | P5-A1、P5-A2 |
| 列表/看板显示开关 | 现有显示配置沿用，不新增 | P3-A7 |
| 共享清单权限/额度 | 不做 | 不做清单 |

## 6. 测试与命令

定向回归：

```bash
WORKFOLLOW_DERIVED_DATA=/tmp/wf-dd \
WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 \
macos-native/scripts/run-tests.sh \
  TaskKindTests \
  DocumentChecklistItemTests \
  DocumentContentTests \
  DeferredDocumentTests \
  TaskReminderDeliveryTests \
  TaskInspectorHierarchyRenderTests \
  TaskInspectorShellContractTests \
  TaskInspectorRowMetadataTests \
  ChecklistModelTests \
  ChecklistPersistenceTests \
  ChecklistEditorRoundTripTests \
  ChecklistModeSwitchTests \
  ChecklistDerivedStatusTests \
  TaskChangeSetChecklistTests \
  ChecklistEditorInteractionTests \
  ChecklistMetadataRerenderTests \
  ChecklistModeSwitchUITests \
  ChecklistAccessibilityTests \
  ChecklistListProgressTests \
  DeferredDocumentChecklistTests \
  ChecklistReminderTests \
  ChecklistReminderServiceTests \
  ChecklistRecurrenceTests \
  ChecklistDuplicationTests \
  ChecklistSubtaskDerivationTests \
  ChecklistKeyboardMoveTests \
  ChecklistPerformanceTests
```

注意：

- 类名必须写全；零用例脚本会返回非零，不能把“0 tests”当通过。
- 提醒类测试使用现有 `FakeTaskNotificationClient`，不依赖系统授权。
- 渲染类测试用隔离窗口与假数据；不触碰真实工作区。
- 性能类测试设明确阈值（例如 200 项勾选 < 50ms、列表 100 项不水合），阈值写入测试常量，避免“看起来不慢”。

### 实施状态（2026-10-25）

- P0/P1 完成：基线 8 类 + P1 6 类；清单与相邻回归 113 用例 0 失败。
- P2 完成：`ChecklistEditorInteractionTests`、`ChecklistMetadataRerenderTests`、`ChecklistModeSwitchUITests`、`ChecklistAccessibilityTests` 共 19 用例 0 失败。
- P3 完成：`ChecklistListProgressTests` 6 用例 + 列表/看板回归 48 用例 0 失败；100 个延迟清单任务的列表进度读取 `documentReadCount == 0`。
- 全量 2047 用例：7 skipped、1 failure（`QuickAddScheduleWindowTests` 的 NSPanel 查找）；该类在清单改动前的全量运行中同样失败，属本机窗口/渲染环境限制。`DocumentDecorationRenderTests`、`TaskKanbanDropTests` 在本轮通过，进一步说明其像素类失败是环境抖动。
- P2-A8/A9/A10 仍需在 GUI 与 VoiceOver 下手动验收；本 worktree 未启动日用版应用，也未改动本机已安装的 WorkFollow。
- 2026-10-25 视觉修订：勾选框改为滴答 nib 的 17×17，清单行距约 30pt，相邻项加 1px 浅灰分隔线；勾选后只变灰、不划删除线；铃铛/删除改为 24×24、颜色加深，并按滴答 `TTHoverableImageView` 随鼠标悬停行显示；项提醒弹框改用日期提醒子面板的选项行与取消/确定样式。已部署日用版 0.2.0 (24)。
- 2026-10-26 P4 完成：`ReminderDelivery` 新增 `.checklistItem` 与 `checklistItemID`；按 `checklist.<taskID>.<blockID>.at.<unix>` 生成投递；256 条容量按标识前缀分别裁剪；勾选/删除/切模式/完成任务经现有 `affectsReminders` 对账自动取消与重排；打开通知选中任务；未授权时项提醒面板显示提示。`ChecklistReminderNotificationTests` 8 用例通过。
- 2026-10-26 P5 完成（除可选键盘调序与性能验收）：重复任务下一实例重置勾选、项提醒按月日平移并在落点过去时清空（D7）；复制与模板实例清空检查项完成时间/提醒；完成最后一个未完成子任务后父清单自动完成且与子任务完成合成一步撤销。`ChecklistRecurrenceTests` 5 用例通过。
- 2026-10-26 全量 2074 用例：7 skipped、1 failure（既有 `QuickAddScheduleWindowTests` NSPanel 环境限制）。Release 构建 0.2.0 (26) 通过并完成包校验（仅构建，未安装）；P4/P5 尚未部署到日用版。
- 2026-10-25/26 两次日用版部署均由用户明确要求：0.2.0 (25) 含清单视觉与勾选跳转/光标/分隔线修复。
- 2026-10-26 清单视觉二次对齐（对照滴答与本地截图逐像素测量）：行节距 30→37pt；复选框可见框 17→15pt（命中区仍 17pt），未勾选描边 #A3A3A3、勾选填充 #E8E8E8；相邻分隔线压到 #F5F5F5 并延伸到距右缘 12pt；行尾删除改为垃圾桶，铃铛/删除图形缩到 13pt。受影响测试 34 项通过；渲染快照核对一致。
- 2026-10-26 检查项提醒“自定义”复用日期面板月历：`AppKitMonthGridView` + `CalendarAnnotationOverlay`（休/班徽标、节日小字、紫色选中圈、今天描边）+ 半小时时间行；预设页与日历页切换时面板按内容高度重新贴回铃铛锚点。`ChecklistEditorInteractionTests` 13 项通过，日历页渲染快照 252×327 核对一致。

## 7. 风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| 整行移动导致块 ID 重绑，元数据串行 | 提醒挂到错误条目 | P1 锁定“行内编辑保留、换行新建清空”；v1 不做拖拽；P5 键盘调序用块级移动绕过文本 diff |
| 仅元数据变化触发编辑器重建 | 光标/面板丢失 | P2 区分 content 与 metadata 变化，metadata-only 不重建 |
| v2 摘要未回填 | 老任务无进度/提醒 | P1 升 v3 一次性重算；失败回滚；迁移副本验收 |
| 自动完成触发重复任务派生 | 误生成下一实例 | 先测零项/子任务/重复三类；失败可回退 `TaskActions` 单点 |
| 项提醒与任务提醒互相清理 | 通知丢失 | 独立 `checklist.` 前缀；P4-A6 前缀隔离测试 |
| 摘要体积增长 | 列表加载变慢 | 只存未完成项的提醒；100/200 项性能测试；必要时后续改为独立表 |
| Quill 端不保留未知行属性 | 跨编辑器编辑丢元数据 | 任务清单只走原生编辑器；P1 加 Delta 往返测试；文档标注限制 |

回滚：

- 代码回退后，旧版本忽略 `wf-checklist-*`，正文与勾选状态仍可读。
- 不删除任何现有表/列；v3 只重算摘要，可重复执行。
- 若派生状态行为有问题，仅回退 `TaskActions` 与 `TaskChangeSet`，不触碰文档/摘要。

## 8. 手动验收脚本（隔离副本，假数据）

1. 新建任务，切到“清单”，确认出现排版提示；取消后形态不变。
2. 再次切换并确认；输入 3 条检查事项。
3. 勾选第 1 条；检查完成时间落库，列表行显示 `1/3`。
4. 给第 2 条设今天 18:00 提醒；铃铛出现，重开任务仍在。
5. 勾选第 3 条；任务自动完成，无未完成子任务。
6. 取消勾选第 1 条；任务回到活动。
7. 保留一条未勾选，点任务完成框；出现“还有未完成的检查事项”，任务仍活动。
8. 添加子任务；勾满所有检查项，任务仍活动；完成子任务后任务自动完成（P5）。
9. 切回“文本”：已完成项带删除线；再切回“清单”：勾选状态和提醒恢复。
10. 删除带提醒的检查项；等待提醒时间，确认没有通知；系统通知列表无孤儿项。
11. 重复任务完成一次；下一实例检查项全部未勾选，提醒落点符合 D7。
12. 打开 200 项清单，连续勾选/输入/撤销；同时打开 100 任务列表，观察无正文加载、无明显卡顿。

## 9. 变更文件索引

| 层 | 文件 |
|---|---|
| 领域 | `Domain/Document/NativeDocument.swift`、`Domain/Document/QuillDeltaCodec.swift`、`Domain/Document/DeferredDocument.swift` |
| 编辑器 | `Features/Editor/DocumentTextCodec.swift`、`Features/Editor/NativeTextView.swift`、`Features/Editor/DocumentBlockDecorations.swift`、`Features/Editor/DocumentProfile.swift`、`Features/Editor/DocumentEditorCoordinator.swift`、新增 `ChecklistItemReminderPanel` |
| 应用 | `Application/TaskActions.swift`、`Application/TaskActionResult.swift`、`Application/TaskChangeSet.swift`、`Application/TaskWorkspaceModel.swift` |
| 详情 | `Features/Tasks/TaskInspector/TaskInspectorShell.swift` |
| 列表 | `Features/Tasks/TaskList/TaskSecondaryMetadata.swift`、`TaskListView.swift`、`TaskKanbanCardView.swift` |
| 持久化 | `Infrastructure/Persistence/SQLiteWorkspaceRepository.swift` |
| 提醒 | `Infrastructure/Notifications/TaskReminderPlan.swift`、`NotificationCoordinator.swift`、`NativeReminderService.swift` |
| 测试 | 上述各阶段测试类 + 现有 `TaskKindTests`、`DocumentChecklistItemTests`、`DeferredDocumentTests`、`TaskReminderDeliveryTests` |

## 10. 已确认决策

用户已于 2026-10-25 确认按以下默认值执行：

1. **D7 重复任务项提醒**：“随任务日期平移”，如果新日期已过去则清空。
2. **内部复制检查项**：“保留勾选状态、清除提醒”。
3. **列表进度优先级**：“清单进度优先于子任务进度”。
