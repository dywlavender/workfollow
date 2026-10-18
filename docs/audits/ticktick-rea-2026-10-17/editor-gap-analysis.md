# 编辑栏差异审计：本地 vs 滴答清单 8.0.80（2026-10-17）

日期：2026-10-17。分支：`experiment/macos-native`。范围：**任务详情编辑栏**（右栏 / 规划浮层 / 回收站复用的 `TaskInspectorShell`），含顶栏、标题、正文、标签、子任务、进度/专注、评论/动态、底栏与「更多」。不含列表、日历、四象限、专注页本体、快速添加栏。

参考：本机滴答 macOS 8.0.80（`/Applications/TickTick.app`），rea 静态证据线（`docs/audits/ticktick-rea-2026-10-13/`、`docs/audits/ticktick-tasks-2026-10-16/`）+ 本轮新增 NIBArchive / ObjC 元数据 / 资源名 / 本地化键证据。方法见第 1 节，逐项证据见附录与 [nib 清单](ticktick-detail-nib-inventory.json)。

---

## 0. 结论摘要

**骨架已对齐**：顶栏（返回/完成框/分隔线/日期/重复/优先级）、标题（19pt、占位符）、正文（Markdown 渲染期解析 + Slash 12 项 + 格式工具条 15 控件）、子任务（NSOutlineView 树、40pt 行、19pt 完成框、行内改名、回车续加）、底栏 8 出口（实际渲染 6 槽）、更多菜单 15 项、日期/重复面板、评论/动态面板——这些在 2026-10-16/17 两轮里都已按滴答实测收敛。

**真正的差距是"编辑栏是什么"这层定义**：滴答把任务详情当成**多形态内容编辑器**（任务 / 笔记 / 清单三种 kind，正文是带附件、标签集合、检查项行内操作、进度条、沉浸书写的 Markdown 编辑器），本地仍是**单形态文本编辑器 + 属性面板**。差异集中在 6 个能力簇：

| 簇 | 滴答有、本地没有 | 影响 |
|---|---|---|
| ① 第二日期 | 顶栏 `secondaryDateLabel` + 可设截止日期 | 本地 `deadlineAt` 有字段、有面板分支，**但没有任何入口**（死代码） |
| ② 属性可视化 | 正文下方的标签 chips 行（可增删改）、顶栏进度条 | 标签只能开面板看；进度只能回列表看 |
| ③ 附件 | 正文附件 cell（高度随附件）、拖文件到详情、粘贴文件、附件占位符（文件/图片） | 本地「上传附件」存得进去，**但详情里看不见、点不开** |
| ④ 任务形态 | 标题右侧 `kindButton`（任务↔笔记↔清单）+ 清单模式的逐项提醒/删除/拖拽 + 模式切换保留内容 | 本地只有文本 + 「转换为笔记」（单向、离开详情） |
| ⑤ 子任务交互 | 拖拽排序、折叠状态持久化/计数、`loadmore` 分页、行内 tags/迷你图标 | 本地只能靠删除重建调序；长列表一次全渲染 |
| ⑥ 编辑辅助 | `#` 标签补全、清单补全、链接悬停菜单、H4–H6、工具条「更多」溢出、沉浸书写、草稿恢复 | 本地 Slash 之外没有输入期补全；崩溃/切走无草稿兜底 |

优先级建议见第 4 节，逐项落点见第 5 节。**最划算的一笔**是 ①（字段和面板都已存在，只差入口与一处标签），**最贵的一笔**是 ④（要动 Domain 的 kind 与编辑器形态）。

**如果只做三件事**：① 补截止日期入口（S）、② 加标签 chips 行（M）、③ 让附件在详情可见可拖（M）——三项都在 `TaskInspectorShell` 的纵向栈里，互不冲突，做完编辑栏的"信息可见性"就和滴答齐了。

---

## 1. 方法与证据

### 1.1 本轮新增的静态证据

| 证据 | 工具/来源 | 产出 |
|---|---|---|
| 详情相关类与 selector | `otool -ov TickTick`（ObjC 元数据） | **52 个** `TTTaskDetail*` / `TTSubtasks*` / `TTSingleTaskDetail*` 类；主控制器 `baseMethods count 418` |
| 详情 nib 结构 | 自写 NIBArchive 解析（[scripts/parse_nibarchive.py](scripts/parse_nibarchive.py)） | **29 个** nib、2902 对象、158 连接、**128 outlet / 30 action**、44 个自定义类、128 个控件；[JSON](ticktick-detail-nib-inventory.json) |
| 图标语义 | `assetutil --info Assets.car` | 1187 个资源名，其中详情相关约 40 个（`detail_mode_text`/`detail_mode_checklist`/`checkbox_checklist`/`md_*`/`checklist_show|hide`/`detail_side_peek`/`detail_popup` 等） |
| 文案与本地化 | `zh-Hans.lproj/Localizable.strings`（287 KB）+ nib 内文本 | `comments_show|hide`、`md_checkItem`、`Immersive Writing`、`md_attachment_placeholder_file|image` 等 |
| 运行态截图 | 既有 `docs/audits/ticktick-rea-2026-10-16/*.png` | 详情、子任务、更多菜单、多选态、Slash 菜单、属性菜单 |

`otool` 的 selector 与 nib 的 outlet/action 是**结构证据**：能证明"控件存在、出口存在"，不能单独证明"运行态何时出现"。文中凡属行为推断均标注「推断」，并汇总到第 7 节待实测。

### 1.2 限制

1. **AX 不可用**：本机 `AXIsProcessTrusted()` 返回 `false`，`System Events` 报 `-10004`，无法像 2026-10-17 那轮做同窗口 AX 实测。因此本轮**不做**像素级几何结论，只做结构与能力对照；几何沿用既有实测值（Header 62 / Footer 48 / 子任务行 40 / 完成框 19）。
2. **nib 是设计态**：`TTTaskDetailTopView` 设计尺寸 766×145、`BottomActionView` 480×40，与运行态不同窗口宽度不可直接换算；本轮只用**相对位置与控件清单**，不据此改本地几何。
3. **rea CLI 未在本轮跑通**：`npx rea-agents` 受 npm 缓存权限阻塞（`EPERM ~/.npm/_cacache`），本轮改用与 rea 同一类静态手段（ObjC 元数据 + nib 解码）自采，并**与既有 rea 证据做交叉校验**：37 份 nib 逐份比对 outlet/action，**全部一致**（`TopView` = 18 outlet / 6 distinct action，其中 `assigneeButtonClicked:` 有 2 条连接，与 `rea-selected-evidence.json` 的 6 action 口径吻合）。校验明细见 [ticktick-detail-nib-validation.json](ticktick-detail-nib-validation.json)。

4. **本地盘点独立成文**：[local-inspector-inventory.md](local-inspector-inventory.md)（26 + 16 个文件、约 1.1 万行、17 个测试文件 189 个用例），本文第 3 节与各条"本地现状"均以该盘点为准。

---

## 2. 滴答编辑栏的实际结构（证据）

### 2.1 容器与区块

`TTSingleTaskDetailView`（464×470，nib）由三块组成：`containerForTopView` / `tableView`（`JWCTableView`）/ `containerForBottomView`。`TTTaskDetailWindowController` 另有 479×381 窗口模板；`TTTaskLinkDetailWindow` 提供"独立窗口"形态；`containerType` 属性 + 资源 `detail_side_peek` / `detail_popup` 说明详情至少有两种容器形态（右侧栏 / 弹窗）。

`tableView` 按行装以下 cell（nib 均在 `Contents/Resources`）：

| 区块 | 类 / nib | 静态证据要点 |
|---|---|---|
| 顶栏 | `TTTaskDetailTopView` | 18 outlet / 7 条 action 连接（6 个 distinct selector，`assigneeButtonClicked:` 有两条），见 2.2 |
| 标题 | `TTTaskDetailTitleCell` | 362×70；`checkboxButton` + `kindButton`（`detail_mode_text`） |
| 父任务（面包屑） | `TTTaskDetailParentTaskCell` | `titleButton`（346×18） |
| 正文（Markdown） | `TTTaskDetailMarkdownCell` | `textView`、`leadingButtonClicked:`、`shouldShowQuickTag`、`shouldShowQuickList`、`hideLinkHoverMenu`、`cellHeightWithWidth:text:` |
| 正文（纯文本/描述） | `TTTaskDetailTextCell` + `TTTaskDetailTextView` + `TTTaskDetailDescriptionCell` | `scrollView/clipView/textView` + `didSelectTag/Date/PriorityHandler`、`existedTagNamesForTagCandidate`、`insertNewline` |
| 正文（清单模式） | `TTTaskDetailCheckItemCell` | 456×140；`checkBoxButton`(17×17) + `reminderButton` + `deleteButton` + `dragIndicator`（可拖） |
| 附件 | `APMDAttachmentView`、`heightForAttachmentCellAt:`、`TTTaskDetailDropFileView` | 附件 cell 有独立高度；拖放层 `performDragOperation:` |
| 标签 | `TTTaskDetailTagCollectionCell` + `Item.nib` | 480×165；chip 内是 `inputTextField` + `addImageView` + `deleteButton`（可增删改） |
| 子任务 | `TTSubtasksViewController` + `TTSubtasksCell` + `TTSubtasksLoadmoreCell` | `NSOutlineView`（`numberOfChildrenOfItem`）+ 拖拽（`pasteboardWriterForItem`/`writeItems`）+ 折叠（`containsCollapsedSubtasks`）+ `loadmore` + 行内 tags/迷你图标/右箭头 |
| 进度 | `TTTaskDetailProgressView` | 766×40；`isProgressChangable`、`progressChangedHandler`、`expectedProgress`、`updateProgress:completed:animated:` |
| 专注摘要 | `TTTaskDetailFocusSummaryCell` | 461×32 |
| 评论 | `TTTaskDetailCommentCell` / `CommentExpandCell` / `CommentHeaderView` / `AddCommentView` | 评论 cell 388×257（头像/昵称/时间/回复或删除/编辑/展开）；输入框 489×134（表情 + 图片 + 1024 字数） |
| 动态 | `TTTaskDetailActivitiesCell` | 316×318；`titleLabel "Task Activities"` + `countLabel` + `dismissButton`，内容走 **WebView** |
| 模板/推广 | `TTTaskDetailPresetTaskActionCell` | `HyperlinkLabel`，文本是付费引导（"You can choose to pay ¥16.00 per month…"）→ **不是任务功能** |
| Notion | `TTTaskDetailNotionBlockCell` + 4 种子视图（ShortText/LongText/Option/People） | `openInNotionButtonClicked:` → 第三方集成，非核心 |
| 空位 | `TTTaskDetailSpaceCell` | 弹性空白行 |
| 底栏容器 | `TTTaskDetailBottomView` | 480×272，`subContainer1..4` 四个 50pt 槽位 + 高度约束 |
| 底栏动作条 | `TTTaskDetailBottomActionView` | 480×40；8 个出口、15 outlet、8 action；按钮 24×24 @y=8、x=247…439（间距 32），项目按钮 63×24 @x=17，见 2.9 |

### 2.2 顶栏（`TTTaskDetailTopView`，18 outlet）

按 nib 顺序与 frame：

| 控件 | 类 / 图片 | 动作 | 本地对应 |
|---|---|---|---|
| `returnButton`（24×24，`close_detail`） | TTThemeButton | `returnButtonClicked:` | ✅ `AppKitIconButton(chevron.left)`，仅窄列显示 |
| `checkButton`（17×17，`checkbox`） | TTThemeButton | `checkboxButtonClicked:` | ✅ 15pt 完成框 |
| `iconDivider`（1×16） | NSView | — | ✅ 1×20 |
| `dateButton`（77×24，`menu_calendar`） | TTThemeButton | `dateButtonClicked:` | ✅ 日期 chip |
| `repeatIcon`（16×16，`set_repeat`） | TTToolTipImageView | —（子视图） | ✅ `repeat` 按钮（条件显示） |
| `secondaryDateLabel`（412×14） | TTLabel | — | ❌ **无** |
| `assigneeIconButton`（28×28）+ `assigneeAvatarButton`（20×20） | TTThemeButton | `assigneeButtonClicked:` | ❌ 协作类，不做 |
| `priorityButton`（28×28，`priority_stroke`） | TTThemeButton | `priorityButtonClicked:` | ✅ 旗子 + 自绘浮层 |
| `noteInfoButton`（28×28，`notes_information`） | TTThemeButton | `notesInfoButtonClicked:` | ❌ **无** |
| `progressView`（766×40） | TTTaskDetailProgressView | — | ❌ **无** |

`refreshForModeChanged` / `refreshForCompletionChanged` / `refreshForPriorityChanged` / `refreshForProgressChanged:` / `refreshReturnButton:` 说明顶栏随 kind、完成态、优先级、进度、容器类型重排——本地顶栏是静态三元组（完成框/日期/优先级），无重排逻辑。

### 2.3 标题 cell（`TTTaskDetailTitleCell`）

- 组件只有两枚按钮：`checkboxButton`（`checkbox_abandoned`，16×16）+ `kindButton`（`detail_mode_text`，24×24）。
- `configureWithKind:switchable:isCompleted:isAbandoned:isInSticky:containerType:text:` → kind 决定图标，`switchable` 决定是否可切换。
- 结合 `updateKind:` / `updateKind:needsRefresh:` / `isTextKind` / `isNoteKind` / `isChecklistKind` / `isModeSwitchable`，以及 `originalContentAtTextMode` / `originalContentAtChecklistMode`：**任务有三种形态，文本↔清单切换时内容互留**。
- 标题还挂 NLP 日期解析：`dateReferee`、`hasParsedDate`、`removeParsedDateStringInTitle`、`disableDateParseIfNeededWhenDeleteBackwords`，协议 `TTNLPDateParseable`；`nlp_macOS.framework` 在包内。

**本地**：`AppKitTaskTitleField`（`AppKitTaskTitleField.swift:1`）只有文本；Return/Esc 结束编辑（`:105`）；无 kind、无 NLP、无标题行内按钮。

### 2.4 正文

三种形态共用的基础能力（selector 证据）：

| 能力 | 证据 | 说明 |
|---|---|---|
| 格式条开关 | `showMarkdownEditBar` / `hideMarkdownEditBar`、`TTMDActionButtonsViewController`（`mdElementButtonClicked:` / `moreButtonClicked:`） | 底栏 A 开关的是**浮层格式条**（与本地口径一致）；工具条资源含 `md_header1..6`、`md_more` |
| 行首块手柄 | `TTTaskDetailMarkdownCell.leadingButtonClicked:` / `refreshLeadingIcon`、资源 `md_vertical_body` / `md_vertical_header1..6` / `md_vertical_list` / `md_vertical_orderList` / `md_vertical_quote` / `md_vertical_horizontal` / `md_vertical_checkbox` / `md_vertical_attachment` + `md_arrow_down_alpha57` | 竖排块类型菜单（只含块级项、不含行内标记）→ 行首手柄点开改段落类型（推断） |
| 输入期补全 | `shouldShowQuickTag` / `shouldShowQuickList`、`existedTagNamesForTagCandidate` | `#` 标签、清单候选浮层 |
| 链接菜单 | `hideLinkHoverMenu`、`TTMarkdownLinkViewController`、`md_link_copy` / `md_link_edit` | 悬停链接出"复制/编辑"菜单 |
| 日期/标签/优先级识别 | `markdownText:didSelectDate:` / `didSelectTag:` / `didSelectPriority:` | 选中文本可直接转成属性（推断） |
| 附件 | `markdownTextViewDidChangeAttachmentSize:`、`markdownTextCanAddAttachments`、`heightForAttachmentCellAt:`、`APMDAttachmentView`、`md_attachment_placeholder_file/image` | 附件是**正文里的块**，有高度与占位符 |
| 文件拖放/粘贴 | `singleTaskDetailView:didDropFiles:`、`TTTaskDetailDropFileView`、`handleTextViewDidPasteFiles:files:range:` | 拖文件到详情、粘贴文件即附件 |
| 检查项行内操作 | `checklistItemCell:didClickCompleteButton:` / `didClickRemindButton:` / `didClickDeleteButton:`、`insertNewChecklistItemsAt:newTextItems:`、`deleteChecklistItemCell:viaBackspace:viaClick:` | 清单模式逐项：完成 / 提醒 / 删除 / 回车新建 / 空项退格删 |
| 沉浸书写 | `TTMDImmersiveViewController`（`returnButton` + `editBar` + `actionButtonsContainer`）、资源 `md_immersive_enter` / `md_immersive_exit`、文案 `Immersive Writing` | 全窗口专注写作 |
| 代码高亮 | 包内 `Highlightr.framework` | 代码块着色（推断） |
| 草稿 | `TTTaskDetailDraftCoordinator` / `EditingSession` / `FinalDraftTransitionCoordinator` + `autoSaveTrigger` / `draftRevision` | 编辑会话草稿与收尾恢复 |
| 搜索高亮 | `highlightForSearchingWithKeywords:`（cell 基类） | 详情内搜索命中高亮 |

**本地**：`DocumentEditor` + `NativeTextView` 已实现 Markdown 输入期/渲染期、Slash、15 控件工具条、块装饰（行首列表标记 + 活动行 H 角标 + 空行「+」）、检查项点击翻转（`NativeTextView.swift:327`）、附件插入（`handle.insertAttachment()` → 编辑器内 `NSTextAttachment`）。**没有**标签/清单补全、链接悬停菜单、正文附件块（附件只做内联 attachment）、拖放文件、沉浸书写、草稿恢复、搜索高亮。

### 2.5 标签集合

`TTTaskDetailTagCollectionCell`（480×165）+ `TTTaskDetailTagCollectionViewItem`：chip = `backgroundView` + `inputTextField` + `deleteButton`（`x_mark`，12×12）+ `addImageView`（`add_sidebar`）。主控制器有 `hasTags` / `orderedTagDisplayNames` / `addTag:` / `removeTag:` / `manageTagsFrom:` / `heightForTagCollectionCell`。

**本地**：无 chips 行。标签只在底栏 `tagButton`（有标签才显示）→ `TaskTagPickerPopover`（搜索/勾选/应用）。列表行有标签文本，但详情内不可见。

### 2.6 子任务

`TTSubtasksViewController` 用 `NSOutlineView`（`numberOfChildrenOfItem` / `isItemExpandable` / `heightOfRowByItem`），并实现 `pasteboardWriterForItem` / `draggingSession:willBeginAtPoint:forItems:` / `writeItems:toPasteboard:` → **拖拽排序/移动**；`taskOrderChangedManually:` 落库。另有：

- 折叠：`containsCollapsedSubtasks`、`tasklistDidFoldTasks:`、`optionKeyHoldingStateChanged:`；资源 `checklist_show` / `checklist_hide`。
- 分页：`TTSubtasksLoadmoreCell`。
- 行内信息：`TTSubtasksCell.shouldShowTags` / `shouldShowMiniIcons` / `shouldShowAssignee` / `showQuoteColor` + `rightArrowButton`（`rightArrowButtonClicked:`）。
- 删除延迟与选中：`delayDeleteStatusChanged:`、`_delayClearSelection`。

**本地**：`AppKitSubtaskOutlineView.swift`（370 行）已是 NSOutlineView，支持多级嵌套、折叠箭头、行内改名、完成框、日期 label、悬停、回车续加；**没有**拖拽排序、折叠状态持久化、分页、行内 tags/迷你图标/右箭头。

### 2.7 进度与专注

- 顶栏 `progressView`（766×40）：`isProgressChangable` + `progressChangedHandler` + `expectedProgress` + `showIfNeeded` + `updateProgress:completed:animated:` → 进度条可交互（拖动改进度，推断），并显示"预期进度"参照线。
- 专注：`showPomoSummary` / `heightForPomoSummaryCell` / `configurePomoSummaryCell:`（正文里的番茄摘要行）+ `focusEstimatePopover` / `startSetPomoEstimate` / `pomoEstimateChanged:` + 底栏动作 `bottomActionViewDidClickStartPomoFocus:` / `StartStopWatchFocus:` / `SetFocusEstimate:`。

**本地**：正文后的专注摘要行（条件显示，`TaskInspectorShell.swift:380`）+ 更多菜单「开始专注」二级菜单 + 「设置预计专注」浮层。**没有**进度条。

### 2.8 评论与动态

- 评论：`TTTaskDetailBottomView` 有 `showAddCommentView:` / `showFloatingCommentView:` 槽位 → **评论在详情底部内联展开**；`commentExpandStatus`、`TTTaskDetailCommentExpandCell`（展开/收起）、`TTTaskDetailCommentHeaderView`（头 + 计数）、cell 支持回复/删除/编辑/展开、评论附件、`highlightForSearchingWithKeywords:`；输入框支持表情与图片、1024 上限。
- 动态：`TTTaskDetailActivitiesCell` 内嵌 WebView，标题 + 计数 + 关闭。

**本地**：评论是底栏 💬 → `TaskCommentPanel` 浮层（列表 + 输入框，纯文本，无回复/编辑/附件）；动态是 `TaskActivityPanel` 原生列表。功能可达，形态不同。

### 2.9 底栏与「更多」

- `TTTaskDetailBottomActionView`（480×40）：`projectButton`(63×24 @x17) / `mdEditButton`(x247) / `mergeButton`(x279) / `tagButton`(x311) / `commentButton`(x343) / `deleteButton`(x375) / `deleteForeverButton`(x407) / `moreButton`(x439)——**7 个 24×24 图标等距 32pt**，各带 leading 约束（按状态显隐重排）。本地对应的是 34×34 命中区 + 14pt 图标 + `WFSpace.xs` 间距，属不同的密度口径，对齐前需同窗口实测。
- 委托方法远多于 8 个出口：`addSubtask`、`linkParent`、`pin`、`abandon`、`uploadAttachment`、`saveAsTemplate`、`addFromTemplate`、`convertTaskAndNotes`、`print`、`duplicate`、`restore`、`startPomoFocus`、`startStopWatchFocus`、`setFocusEstimate`、`didMoveTaskTo:column:` → 动作条是**随上下文变形的**，不是一个固定「更多」。
- 运行态截图（2026-10-16）：普通态底栏 = 清单 / A / 💬 / …；「更多」**15 项**（截图 `ticktick-detail-more-menu.png`，含「打印」、无「设置预计专注」）。

**本地**：底栏口径 8 出口、**实际 6 个槽位**（常显 4：清单 / A / 评论 / 更多；条件 2：标签 / 合并；删除在「更多」、永久删除在回收站）。「更多」15 项，比滴答多「设置预计专注」、少「打印」；`moreMenu` 固定高 490（`TaskInspectorShell.swift:274`）。

> 关于"6 vs 8"：滴答 nib 里 `deleteButton`/`deleteForeverButton` 也是**条件槽位**（普通态截图里同样只有 清单 / A / 💬 / …），本地把删除放进「更多」、永久删除放回收站，属**形态差异而非缺口**；真正该对齐的是槽位的显隐规则，不是槽位数量。

---

## 3. 本地现状（对照）

| 区块 | 文件 | 规模/要点 |
|---|---|---|
| 外壳 | `Features/Tasks/TaskInspector/TaskInspectorShell.swift` | 823 行；顶栏/正文/子任务/专注行/底栏/更多/优先级/日期面板装配 |
| 顶栏 | `TaskInspectorHeader.swift` | 102 行；back/completion/divider/schedule/repeat/priority |
| 度量 | `TaskInspectorMetrics.swift` | Header 62 / Footer 48 / 行 40 / 完成框 15 / 子任务框 19 |
| 标题 | `AppKit/AppKitTaskTitleField.swift` | 127 行；19pt、多行、Return/Esc 结束 |
| 顶栏控件 | `AppKit/AppKitHeaderControls.swift` | IconButton / ScheduleChip / TextButton（A） |
| 子任务 | `AppKit/AppKitSubtaskOutlineView.swift` | 370 行；树/折叠/改名/完成/日期 |
| 正文 | `Features/Editor/*`（15 文件 3941 行） | MarkdownSyntax、DocumentMarkdownInput、NativeTextView、DocumentFormatCommand、Slash、装饰、选区工具条 |
| 日期面板 | `Features/Tasks/Schedule/TaskDatePopoverV2.swift` | 1379 行；时间/提醒/重复/农历/截止模式 |
| 评论/动态 | `TaskCommentPanel.swift` / `TaskActivityPanel.swift` | 83 / 65 行 |

**已对齐（本轮不重复立项）**：Header/Footer 与内容原点几何、标题 19pt、完成框 15、子任务行 40/框 19、Slash 12 项四节与图标、格式工具条 15 控件与 444×38、优先级四行彩色旗、日期/重复面板、底栏 8 出口口径（渲染 6 槽）、更多菜单顺序（除打印/预计专注外）、Esc 链、窄列返回、Markdown 渲染期解析。

---

## 4. 差异总表与优先级

判定口径：**P0** = 滴答编辑栏的高频能力，本地缺且用户会立刻感到"做不到"；**P1** = 体验形态差异，影响效率但不阻断；**P2** = 细节/生态集成。`成本` 用 S（≤1 天）/ M（2–4 天）/ L（≥1 周）粗估。

| ID | 差异 | 滴答证据 | 本地现状 | 判定 | 优先级 | 成本 |
|---|---|---|---|---|---|---|
| TI2-01 | 截止日期无入口、顶栏无第二日期 | `dateButton` + `secondaryDateLabel`(412×14)；面板 `deadline` 分支 | `ScheduleField.deadline` 存在但**从未被实例化**（`TaskInspectorShell.swift:809`），`deadlineAt` 只在列表行显示 | 缺 | **P0** | S |
| TI2-02 | 标签 chips 行 | `TTTaskDetailTagCollectionCell`（可编辑 chip、增删） | 仅底栏 tag 按钮 + 浮层面板 | 缺 | **P0** | M |
| TI2-03 | 附件在详情不可见 | 附件 cell + `heightForAttachmentCellAt:` + 拖放层 + 粘贴文件 | 「上传附件」可存入；详情无渲染（`AttachmentListView` 只用于笔记：`NotesWorkspaceView.swift:259`） | 缺 | **P0** | M |
| TI2-04 | 子任务拖拽排序 / 折叠持久化 / 分页 | `pasteboardWriterForItem:` 等 + `containsCollapsedSubtasks` + `TTSubtasksLoadmoreCell` | NSOutlineView 无 drag/drop；折叠是临时 UI 态；一次全渲染 | 缺 | **P0（拖拽）/P1（其余）** | M |
| TI2-05 | 任务形态（任务/笔记/清单）与清单模式逐项操作 | `kindButton` + `updateKind:` + `CheckItemCell`（完成/提醒/删除/拖拽） | 只有文本；检查项是段落类型，无逐项按钮 | 缺 | **05a P0 / 05b P1** | M / L |
| TI2-06 | 标题 Return 行为 | `focusOnContentIfNeeded`（推断：Return 进正文） | Return = 结束编辑（`AppKitTaskTitleField.swift:105`） | 差异 | P1 | S |
| TI2-07 | 顶栏进度条 | `progressView` + `expectedProgress` + 可改 | 无；只有列表行的 `subtaskProgress` 文本 | 缺 | P1 | M |
| TI2-08 | 输入期补全与链接菜单 | `shouldShowQuickTag/List`、`hideLinkHoverMenu` | 仅 Slash；无 `#`/清单补全、无链接悬停菜单 | 缺 | P1 | M |
| TI2-09 | 评论内联化 | 底栏 `showAddCommentView:` + 展开/收起 + 回复/编辑/附件 | 浮层面板、纯文本 | 差异 | P1 | M |
| TI2-10 | 专注三入口位置 | 底栏/摘要区 `StartPomoFocus` / `StartStopWatchFocus` / `SetFocusEstimate` | 更多菜单二级 + 更多菜单项 | 差异 | P1 | S |
| TI2-11 | 更多菜单对齐 | 15 项；无「设置预计专注」；有「打印」 | 15 项；多「设置预计专注」；缺「打印」 | 差异 | P1 | S |
| TI2-12 | 子任务行信息密度 | tags / mini icons / 右箭头 | 仅日期 | 缺 | P1 | S–M |
| TI2-13 | 草稿恢复 | `DraftCoordinator` / `EditingSession` / `autoSaveTrigger` | 每次变更即写 store；无草稿兜底 | 缺 | P1 | M |
| TI2-14 | 沉浸书写 | `TTMDImmersiveViewController` + 资源 | 无 | 缺 | P2 | M |
| TI2-15 | 笔记信息（字数/创建/修改） | `TTTaskDetailNoteInfoViewController`（128×148） | 无 | 缺 | P2 | S |
| TI2-16 | H4–H6、工具条「更多」 | `md_header1..6`、`md_more` | `heading(1...3)`，无溢出菜单 | 部分 | P2 | S |
| TI2-17 | 容器形态（侧栏/弹窗） | `containerType`、`detail_side_peek`/`detail_popup`、`TTTaskLinkDetailWindow` | 右栏 + 规划浮层 + 回收站 | 部分 | P2 | L |
| TI2-17 | **部分完成** | 宽布局顶栏加「在独立窗口打开」（`arrow.up.forward.app`）：复用同一个 `TaskInspectorShell` 与工作区，重复点击只前置；窗口关掉即销毁。**未做**：滴答的"侧栏 ↔ 弹窗"容器切换与卡片形态 `{}` | `TaskDetailWindowTests` 2 项（宽/窄入口显隐 + 控制器复用同一窗口） |
| TI2-18 | 多选详情面板 | `TTMultiTaskDetailViewController` + `TTMultiTaskDetailItemView` | `TaskBatchPanelView`（已有） | 差异 | P2 | M |
| TI2-19 | 动态 WebView | `TTTaskDetailActivitiesCell` + WebView | 原生列表 | 有意不同 | 不做 | — |
| TI2-20 | Notion / 模板推广行 | `TTTaskDetailNotionBlockCell`、`PresetTaskActionCell` | 无 | 生态集成 | 不做 | — |
| TI2-21 | 行首块手柄 + 竖排块类型菜单 | `leadingButtonClicked:` / `refreshLeadingIcon` + `md_vertical_*` 一组资源 | 装饰层只有列表标记与活动行 H 角标/「+」，**无手柄、无块菜单**（`grep 拖拽/折叠` 在 Editor 无命中） | 缺 | P1 | M |
| TI2-22 | 焦点接力（新建/切任务聚焦标题、标题→正文） | `focusOnTaskTitle` / `focusOnContentIfNeeded` / `focusOnView` | `titleEditing` 没有程序化置 true 的入口（`TaskInspectorShell.swift:15`，只能靠用户点进字段）；标题 Return 只结束编辑 | 缺 | P1 | S |
| TI2-23 | 格式快捷键（⌘B/⌘I/⌘U） | 未取得证据 | 编辑栏自身未注册任何 ⌘ 组合；格式只能点工具条或输入 Markdown | 待实测 | P2 | S |

---

## 5. 优化建议（逐项落点）

### TI2-01 截止日期入口（P0，S）

**问题**：域模型、草稿模型、面板分支（`TaskDateDraftModel.swift:427` / `:461`）都支持 `deadlineAt`，唯独没有 UI 入口——`ScheduleField` 里 `deadline` 分支永远走不到。

**建议**：
1. 顶栏日期 chip 右侧按滴答加一个**次要日期文本**（`TaskInspectorMetrics` 新增 `secondaryDateLabelHeight`），有 `deadlineAt` 时显示"截止 M月d日"、逾期红字；无则不占位。
2. 日期面板主面板加一行「截止日期 ›」，展开 `deadline` 子面板（复用现有 `TaskDatePopoverV2(deadline: true)`）。
3. `ScheduleField.deadline` 接上 `secondaryDateLabel` 的点击 → `openSchedulePanel(.deadline)`，让现有分支不再是死代码。

**验收**：设了截止日期的任务，顶栏出现第二日期且颜色随逾期变化；清空后消失；面板改动写回 `deadlineAt`。

### TI2-02 标签 chips 行（P0，M）

**问题**：标签是任务的核心属性之一，滴答在正文下方用一行可编辑 chip 展示；本地只有浮层入口，关掉面板就看不见。

**建议**：
1. 新增 `TaskTagStrip`（SwiftUI `Layout` 流式或 `NSCollectionView`），放在子任务区上方 / 专注摘要行之下，间距沿用 `childSectionTopGap`。
2. chip 交互对齐滴答：点 chip 删除（hover 出 ×）、末尾 `+` 打开 `TaskTagPickerPopover`、双击改标签名（可选）。
3. 复用 `workspace.setTags`；空标签不占行高。

**验收**：加/删标签即时反映；无标签时零占位；`TaskTagStrip` 有渲染契约锚点与快照测试。

### TI2-03 正文附件（P0，M）

**问题**：`上传附件` 已经能把文件写进 `task.attachments`，但详情里没有渲染，用户看不到"传了什么"。

**建议**：
1. 把已有 `AttachmentListView`（`Features/Editor/AttachmentListView.swift:4`）挂进详情正文尾部（子任务区之前），与笔记面同源，避免第二套实现。
2. 详情加**拖放层**：`NSViewRepresentable` 注册 `registerForDraggedTypes([.fileURL])`，drop 时 `workspace.setAttachments(id, current + files)`（对齐 `TTTaskDetailDropFileView`）。
3. 正文 `paste` 到文件类型时同样转附件（`NativeTextView` 已有 `paste` 覆写，加分支）。

**验收**：上传后详情立即出现文件行、可点开、可删；拖文件到详情任意位置生效；粘贴文件不落成乱码文本。

### TI2-04 子任务拖拽排序（P0，M）+ 折叠持久化/分页（P1）

**问题**：`AppKitSubtaskOutlineView` 是只读树，调序只能删了重建。

**建议**：
1. 实现 `NSOutlineViewDataSource` 的 `pasteboardWriterForItem:` / `validateDrop` / `acceptDrop`，拖拽落点写回 `childOrder`（`TaskActions` 里已有排序写入口）；拖拽时禁止跨父级（滴答同样按树内移动）。
2. 折叠状态：`expansionState` 存 `UserDefaults`（按 `taskID`）或加 `Task` 字段；折叠时在"添加子任务"行上方显示"已折叠 N 项"。
3. 超过 30 个子任务时首屏只渲染 20 条 + "载入更多"，避免长列表一次铺开（对齐 `TTSubtasksLoadmoreCell`）。

**验收**：拖拽后重启 app 顺序保持；折叠状态重启保持；30+ 子任务详情打开不卡。

### TI2-05 任务形态与清单模式（05a P0 / 05b P1，拆两笔）

**建议分两步，避免一次性大改**：

**05a 检查项行内操作（M）**：在现有 `checklist` 段落类型上，光标所在检查项行显示 hover 操作（提醒/删除），`Return` 新建下一项、空项退格删除——对齐 `checkItemCell` 的完成/提醒/删除/`insertNewChecklistItems`。只动 `NativeTextView` 的装饰层与键盘处理，不动 Domain。

**05b 形态切换（L）**：`TaskKind { text, note, checklist }` 进 Domain；标题右侧加 `kindButton`（`detail_mode_text` / `detail_mode_checklist`），菜单三项；切换时把正文按"段落 ↔ 检查项"互相转换并保留原文（对齐 `originalContentAtTextMode/ChecklistMode`）。清单模式下正文渲染为逐项 cell（可复用 05a 的行内操作）。

**风险**：05b 触及存储迁移与全部编辑器宿主；建议先做 05a，用 `TaskKind` 只读字段做灰度（默认 text）。

### TI2-06 标题 Return 进正文（P1，S）

`AppKitTaskTitleField.swift:105` 现在是 Return/Esc 都结束编辑。建议 Return 改为 `onSubmitToBody`：结束标题编辑并把焦点交给正文首行（`editorHandle.focusEditor()`），Esc 仍结束。需先按第 7 节实测确认滴答行为。

### TI2-07 顶栏进度条（P1，M）

有子任务（或清单模式）时，在顶栏下沿画一条 40pt 区：左侧"3/8"、右侧 expectedProgress 刻度；点击/拖动写回进度。数据可取 `workspace.subtaskProgress(for:)` 的数字部分（列表行已在用）。若暂不做交互，至少先做只读条（S）。

### TI2-08 补全与链接菜单（P1，M）

- `#` 触发标签候选（复用 `TaskTagPickerPopover` 的标签源），`Return/点击` 插入并 `setTags`；
- 清单候选（现有 `availableListNames`）；
- 链接 hover：光标进入 link 属性范围时出小浮层（复制/编辑/移除），复用 `DocumentToolbarTooltip` 的坐标方案。

### TI2-09 评论内联化（P1，M）

把 `TaskCommentPanel` 的列表形态搬到底栏上方的一个槽位（对齐 `subContainer` 思路）：默认收起为"评论 n"一行，点击展开列表 + 原位输入框；补回复/编辑/删除与附件。若短期不做，至少把现有面板入口从图标改为"评论 n"计数（S）。

### TI2-10 专注三入口前移（P1，S）

滴答把「番茄 / 正计时 / 预计专注」放在底栏与摘要区；本地「开始专注」藏在更多菜单二级。建议：专注摘要行右侧加一枚 `more`（或直接把「开始专注」做成底栏图标），「设置预计专注」从更多菜单移到该入口，更多菜单恢复滴答 15 项顺序。

### TI2-11 更多菜单对齐（P1，S）

- 去掉「设置预计专注」（随 TI2-10 前移）；
- 补「打印」需先有打印能力（`NSPrintOperation` 包一个 `TaskPrintService`，S–M）；不做则保持"无假按钮"并在菜单里留空位说明；
- 菜单高度别写死 490（`TaskInspectorShell.swift:274`），按项数算。

### TI2-12 子任务行信息密度（P1，S–M）

行尾按滴答顺序补迷你图标：日期（已有文本可换图标+文本）→ 提醒 → 重复 → 附件 → 评论数；标签以 chip 形式显示在行尾或第二行。全部来自现成 `Task` 字段，不需新存储。

### TI2-13 草稿恢复（P1，M）

现状是"每次变更即 `setDocument`"，没有会话概念。建议加轻量 `TaskInspectorDraftCoordinator`：进入详情记 `editingSession`，正文/标题变更先落内存草稿（n秒节流），切任务/关窗时 flush；异常退出后下次打开若发现未 flush 草稿则提示恢复（对齐 `FinalDraftTransitionCoordinator` 的语义，但不必做同构实现）。

### TI2-21 行首块手柄 + 竖排块类型菜单（P1，M）

**证据**：`TTTaskDetailMarkdownCell.leadingButtonClicked:` / `refreshLeadingIcon`（行首图标随块类型变），配套资源 `md_vertical_{body,header1..6,list,orderList,quote,horizontal,checkbox,attachment}` + `md_arrow_down_alpha57`——竖排菜单只含**块级**项，不含行内标记，说明它是"改段落类型"的块菜单。

**本地**：`DocumentBlockDecorations` 已画列表标记、活动行 H1–H3 角标、空行「+」（`NativeTextView.swift:314` 打开空行菜单），但**没有**行首手柄、没有块类型竖排菜单、块不能拖拽/折叠。能力上都已具备（`format.paragraph`/`heading1..3`/`bullet`/`ordered`/`checklist`/`quote`/`code`），缺的是入口。

**建议**：在装饰层给**光标所在行**补一个行首手柄（复用 `decorationMarkerX`），点开竖排块菜单（H1–H3 / 正文 / 列表 / 有序 / 检查项 / 引用 / 分割线 / 附件），选中即 `applyFormat`。拖拽/折叠本轮不做（滴答是否有块拖拽无直接证据）。

### TI2-22 焦点接力（P1，S）

**证据**：`focusOnTaskTitle` / `focusOnContentIfNeeded` / `focusOnView`。

**本地**：`titleEditing` 没有程序化置 true 的入口（新建/切任务不会自动聚焦标题）；标题 Return 只结束编辑（`AppKitTaskTitleField.swift:105`）；标题与正文是两套焦点系统，无 Return/Tab 接力。

**建议**：新建任务（`requestChildTitleEditor` 同款机制）时聚焦标题；标题 Return → `editorHandle.focusEditor()` 进正文；切任务不抢焦点（保留现状）。

### TI2-14 ~ TI2-18（P2）

沉浸书写（全窗口写作壳 + Esc 退出）、笔记信息浮层（字数/创建/修改）、H4–H6 与工具条溢出、容器形态（先做"在独立窗口打开"最省力：`NSWindowController` 复用 `TaskInspectorShell`）、多选面板对齐（属性行 + 9 批量操作已在 `TaskBatchPanelView`，逐项比对即可）。

---

## 6. 不建议对齐

| 项 | 理由 |
|---|---|
| 指派/协作（`assignee*`、评论权限、共享清单） | 个人本地版边界，缺省正确；滴答这两个按钮在纯本地账号下也不出现 |
| 动态 WebView | 本地原生列表已覆盖信息，换 WebView 是负收益 |
| Notion 集成块 | 第三方集成，不属于编辑栏能力 |
| 模板付费推广行（`PresetTaskActionCell`） | 商业化素材，不是功能 |
| 任务面选区工具条 | 本地组件在、任务 profile 关着；滴答也没有"选中出浮条"的证据（`md_*` 资源只够支撑底栏浮条），维持关闭是对的 |
| 照搬 nib 设计尺寸（766×145 / 480×40） | 设计态与运行态不同容器宽度，几何须按同窗口 AX 实测 |

---

## 7. 待实测（AX 恢复后按此清单补证）

| # | 待确认 | 为什么重要 | 建议探针 |
|---|---|---|---|
| 1 | 标题 Return 是否进正文 | TI2-06 的唯一依据 | 详情 → 标题末尾回车 → AX 看 firstResponder/焦点 |
| 2 | `kindButton` 菜单三项文案与切换后正文形态 | TI2-05b 的对齐目标 | 建任务 → 点 ≡ → 截图 + 逐项切换看正文 |
| 3 | 清单模式逐项按钮的出现条件（hover？选中行？） | TI2-05a | 清单任务 → 鼠标移入某行 → 截图 |
| 4 | `progressView` 出现条件与是否可拖 | TI2-07 | 清单任务/多子任务任务 → 顶栏截图 + 拖动 |
| 5 | `secondaryDateLabel` 文案与位置 | TI2-01 | 同时设安排日期与截止日期 → 顶部截图 |
| 6 | 附件 cell 的形态（文件名/图标/大小/删除） | TI2-03 | 传两个附件（图片+PDF）→ 详情截图 |
| 7 | 评论是否真的内联在详情底部 | TI2-09 | 详情点💬 → 全屏截图看是否在详情内 |
| 8 | `#` 标签补全的触发字符与候选样式 | TI2-08 | 正文输入 `#` → 截图 |
| 9 | 折叠子任务后的计数呈现 | TI2-04 | 3 子任务 → 折叠 → 截图 |
| 10 | 更多菜单在已完成/回收站态的差异 | TI2-11 | 两态各截一张 |
| 11 | 行首手柄的出现时机（hover 行首？光标行常驻？）与竖排菜单形态 | TI2-21 | 正文多行 → 悬停行首/光标行 → 截图 |
| 12 | 新建任务与切任务是否自动聚焦标题；标题 Return 的落点 | TI2-22 | 新建 → AX 看 firstResponder；标题回车 → 再看 |

---

## 8. 与既有计划的关系

- `docs/editor-optimization-plan-2026-10-16.md` 的 ED-OPT-1/2/3/4/6 已收口，**ED-OPT-5（子任务折叠/进度/类型按钮/备注信息/次要日期）本轮拿到了结构证据但仍是"运行态未实测"** → 拆成 TI2-01/05/07/15 四条，按第 7 节补证后再实施。
- 本轮不改代码；建议按 TI2-01 → TI2-11 → TI2-10 → TI2-06 → TI2-22 → TI2-02 → TI2-03 → TI2-04 → TI2-21 的顺序落，前六项都是 S 且互不冲突。
- 涉及 Domain 的只有 TI2-05b（kind）与 TI2-13（草稿），其余都在 UI/Application 层。
- 配套盘点：[local-inspector-inventory.md](local-inspector-inventory.md) 提供本地每个控件的 file:line 与 189 个测试用例的覆盖清单，落每一项前先看该文件对应小节。
- 批量建议：TI2-01 / TI2-02 / TI2-03 / TI2-11 / TI2-10 都改 `TaskInspectorShell` 的纵向栈与底栏，可合成一笔「属性层」提交；TI2-06 / TI2-22 / TI2-21 都改编辑器焦点与装饰，合成一笔「编辑流」提交；TI2-04 与 TI2-12 同属子任务区，合成一笔。

---

## 9. 实施记录（2026-10-18）

按第 8 节的顺序先落"证据已足、互不冲突"的五项；未动 Domain，全部在 UI / Infrastructure 层。

| ID | 状态 | 改动 | 测试 |
|---|---|---|---|
| TI2-01 | **已完成** | ① `TaskInspectorShell` 顶栏加 `deadlineLabel`（有 `deadlineAt` 才占位、逾期红字、点击改截止日期）；② `TaskDatePopoverV2` 新增 `onRequestDeadline` + 属性行「截止日期」（仅在详情宿主出现，行尾 › 不是 ×）；③ 截止日期面板改锚到日期 chip（原来误挂在「更多」按钮的 footer 浮层上，且无调用点）；④ 面板高度 +1 行；⑤ 顺手删 `TaskDateButton`（无引用的死代码）与 `childRowRadius/childRowHorizontalPadding/childRowGap`（AppKit 化后的残留常量） | `TaskInspectorDeadlineEntryTests` 8 项（面板行显隐 / 截止面板不自指 / 顶栏显隐 / 清除后消失 / 高度 / **真机路径：面板里点「截止日期」→ 切面板 → 回车确定写回 `deadlineAt`**）+ 既有相关 63 项 |
| TI2-02 | **已完成** | 新增 `TaskTagStrip`（流式 chip：点 × 直接 `setTags` 移除、点 chip 或 + 打开既有标签面板），放在正文与子任务之间 | `TaskInspectorPropertyRowsTests` 标签 2 项（存在性 / 顺序） |
| TI2-03 | **部分完成** | ① 正文后挂载既有 `AttachmentListView`（打开 / Finder / 移除 / 再加，与笔记面同源）；② 详情整体接受文件拖放（`onDrop` + `AttachmentDropImport` 按拖入顺序收集 + `NativeAttachmentFiles.importFiles` 统一落盘），拖拽时有「松开以添加附件」提示。**未做**：粘贴文件转附件（`NativeTextView.paste` 的 file 分支） | `TaskInspectorPropertyRowsTests` 附件/导入 4 项（存在性、顺序、拖放顺序、落盘规则） |
| TI2-04 | **部分完成** | ① 子任务行支持**同父级拖拽排序**（`pasteboardWriterForItem` / `validateDrop` / `acceptDrop` + `TaskActions.reorder(_:toSiblingIndex:)`，支持拖到末尾，位移为 0 时不产生撤销点）；② **折叠状态持久化**（`SubtaskFoldStore` 按子任务 id 存 `UserDefaults`，重开/切任务后恢复；用户折叠/展开时写回）。**未做**：`TTSubtasksLoadmoreCell` 的分页（一次全渲染在 30 条以内够用） | `SubtaskOrderAndFoldTests` 10 项（前移/后移/拖到末尾/钳制/无位移/只动同父级 + 落点判定 + 下标换算 + 折叠存取 + 视图恢复） |
| TI2-08 | **部分完成** | ① `#` 标签补全：行首/空白后输入 `#` 列出宿主已有标签，↑↓/回车/Esc，选中落成 `#tag ` 并把标签挂到任务；代码块/`a#b` 不触发。② 链接悬停菜单：悬停链接出「复制 / 编辑 / 移除」，点击/移出/Esc/编辑文本都收起。**未做**：清单候选（`shouldShowQuickList`） | `DocumentTagCompletionTests` 6 项 + `DocumentLinkHoverTests` 5 项（命中范围/目标、普通文字不弹、复制、移除标记、面板显隐） |
| TI2-05a | **部分完成** | 检查项整项操作：空项行首退格删掉该项、活动项行尾 × 删除整项（含换行、可撤销）。**未做**：逐项提醒、清单模式与形态切换（05b，需 Domain `TaskKind`） | `DocumentChecklistItemTests` 5 项（空项退格 / 非空不退 / 删中间项 / 删末项 / 行尾按钮几何） |
| TI2-16 | **部分完成** | 标题级别 H4–H6：命令 + 工具条 H 选择器补到六级（Assets.car `md_header4..6`），选择器行徽标补 `H₄–H₆`、面板高 264；Slash 保持滴答实测的 12 项不扩。**未做**：工具条「更多」溢出（`md_more`） | `HeadingLevelTests` 3 项 + `DocumentProfileTests` 选择器契约更新 |
| TI2-11 | **已完成** | 补「打印」（`TaskPrintService`：标题/属性/正文按块排版/子任务 ☐☑ 清单，`NSPrintOperation` 走系统面板）；顶层菜单恢复滴答 15 项顺序 | `TaskPrintServiceTests` 2 项（完整稿 / 空正文）+ `TaskMoreMenuRoundTwoTests` 顺序断言更新 |
| TI2-21 | **已完成** | 行首块手柄：空行「+」、标题 H 角标、正文六点手柄共用同一条沟槽命中区，点开都是块类型菜单（Slash 空查询态）；列表/检查项/引用/代码行不接管（`openBlockMenu` 取代 `openEmptyBlockMenu`，检查项勾选不受影响） | `DocumentBlockMenuTests` 4 项 + `DocumentDecorationRenderTests` 手柄渲染 1 项（原"沟槽为空"守卫反转） |
| TI2-07 | **部分完成** | 顶栏下沿 2pt **只读**子任务进度条（`TaskInspectorSubtaskProgress` 解析 "2/5"，`fraction` 进度）；不改 Header 高度。**未做**：可拖动 / `expectedProgress` 参照线 | `TaskInspectorProgressBarTests` 3 项（解析 / 比例 / 有无子任务的显隐） |
| TI2-12 | **已完成** | 子任务行迷你标记：重复 / 提醒 / 描述 / 附件（数据源与列表行同构 `TaskSecondaryMetadata`，标签不重复显示；cell 复用时清空，不会留下上一行的图标） | `SubtaskRowMetadataTests` 2 项（空任务无标记 / 顺序 + 复用清空） |
| TI2-09 | **基本完成** | ① 底栏评论条数角标；② **评论内联化**：正文流里出现「评论 n」折叠区，展开是列表（内容 + 时间 + 悬停删除）+ 原位输入框（回车/发送），底栏 💬 展开收起；删除浮层面板 `TaskCommentPanel`。**未做**：回复、编辑、评论附件、表情 | `TaskCommentBadgeTests` 1 项 + `TaskCommentSectionTests` 2 项（有评论才出现/删完收起、计数随 store） |
| TI2-10 | **已完成** | 「预计专注」从顶层「更多」移入「开始专注」子菜单（番茄 / 正计时 / 设置预计专注同属 focus 出口），焦点面板仍锚在「更多」按钮上 | `TaskFocusSubmenuTests.testEstimateEntryLivesInFocusSubmenuAndOpensTheEstimatePanel` |
| TI2-11 | **部分完成** | 顶层「更多」恢复滴答 15 项顺序（去掉自加的「预计专注」项）；「打印」仍缺席（无打印能力，保持"无假按钮"） | `TaskMoreMenuRoundTwoTests`（新增「预计专注」不得出现在顶层菜单的断言） |
| TI2-06 / TI2-22 | **待实测** | 标题 Return 落点、新建/切任务是否自动聚焦标题——第 7 节 AX 探针未恢复，不凭推断改行为 | — |
| TI2-05b / TI2-08 / TI2-13 / TI2-14~18 | **未开始** | 见第 5 节逐项落点（TI2-15 笔记信息、TI2-17 独立窗口仍在其中） | — |

口径说明：

- 五项改动都不触碰存储格式；`deadlineAt` 早已在 `TaskSchedule` 与 `TaskDateDraftModel` 里，本轮只补入口。
- 新增的渲染契约锚点：`InspectorRenderAnchor.deadlineLabel / attachments / tagStrip / focusEstimate`、`ScheduleRenderAnchor.deadlineRow`（测试与实现共用同一套锚点，不另建口径）。
- 回归（第一批，截至 TI2-12）：全量 **1431 项：1424 通过 / 6 跳过 / 1 个与本轮无关的 flaky**（`FocusTaskPickerPanelFlowTests`，单独复跑通过）。
- 回归（第二批，TI2-21 / TI2-07）：全量套件在本次会话后段被**测试宿主的源码读取门控**拖慢（读 `#filePath` 的契约测试单次约 2 分钟，与代码无关；沙箱/TCC 行为），改为**分组回归**并全部通过：inspector 组 32 项、子任务/专注/进度组逐个类通过（10 + 6 + 2 + 3）、文档组 23 项（块菜单 4 + 装饰 11 + 层级 5 + 进度 3）；`TaskMoreMenuRoundTwoTests` 2 项在门控下 138s 后通过。
- 新增测试累计 **60** 个方法（截止 8 + 属性行 6 + 专注入口 1 + 排序折叠 10 + 行标记 2 + 角标 1 + 块菜单 4 + 进度 3 + 标题级别 3 + 打印 2 + 检查项整项 5 + 标签补全 6 + 链接悬停 5 + 内联评论 2 + 独立窗口 2），另反转 1 条既有断言（非空正文行沟槽从"必须干净"改为"必须有块手柄"）、扩充 1 条移除清单、1 处测试支撑锚点映射、2 处选择器/目录计数断言随 H4–H6 更新。
- 测试环境注意：`AppEnvironment` + 承载 `NSHostingView` 的窗口在 XCTest 内存检查里"关窗后释放"会过释放（与本轮功能无关，最简 `Text` 复现）；内联评论的渲染断言因此不关窗，真机关窗路径未自动化复核。
- 真机路径已由测试覆盖面板切换与写回（`testDeadlineRowSwitchesPanelAndWritesDeadlineThroughTheRealInspector`）；仍未做的是**视觉像素级复核**（AX 不可用），下次开 app 时按第 7 节顺手看一眼即可。

## 附录：证据索引

- nib 结构 JSON：[ticktick-detail-nib-inventory.json](ticktick-detail-nib-inventory.json)（29 nib / 128 outlet / 30 action）+ 可读报告 [ticktick-detail-nib-inventory.md](ticktick-detail-nib-inventory.md)
- 解析器：[scripts/parse_nibarchive.py](scripts/parse_nibarchive.py)
- 既有 rea 证据：`docs/audits/ticktick-rea-2026-10-13/rea-selected-evidence.json`（`TTTaskDetailTopView` 18 outlet / 6 action）、`docs/audits/ticktick-tasks-2026-10-16/rea-task-declarations.json`（主控制器 selector 子集）
- 运行态截图：`docs/audits/ticktick-rea-2026-10-16/`（detail / subtasks / more-menu / multiselect / slash / attr-menu）
- 本地代码：`Features/Tasks/TaskInspector/**`、`Features/Editor/**`、`Features/Tasks/Schedule/TaskDatePopoverV2.swift`
- 方法说明：`otool -ov /Applications/TickTick.app/Contents/MacOS/TickTick`、`assetutil --info Assets.car`、`plutil -p zh-Hans.lproj/Localizable.strings`
