# 滴答清单 macOS 8.0.80 · 任务详情/编辑栏 nib 结构清点

> 审计日期：2026-10-17 · 目标：`/Applications/TickTick.app` (CFBundleShortVersionString **8.0.80**) · 资源目录 `Contents/Resources`
>
> 全部结果为**只读静态解析**：未启动、未修改 TickTick，未改动仓库其它文件。
>
> 机器可读数据：[ticktick-detail-nib-inventory.json](ticktick-detail-nib-inventory.json) · 校验数据：[ticktick-detail-nib-validation.json](ticktick-detail-nib-validation.json) · 解析器：[scripts/parse_nibarchive.py](scripts/parse_nibarchive.py) · 校验器：[scripts/validate_against_evidence.py](scripts/validate_against_evidence.py) · 报告生成：[scripts/build_report.py](scripts/build_report.py)

## 0. 结论摘要

| 指标 | 数值 |
| --- | --- |
| 目标 nib | 29 个，解析成功 **29 / 29**（失败 0） |
| 原始 NIBArchive 对象 | 2902 个（含 NSString/NSNumber/NSArray 等辅助对象） |
| 连接 | 158 条 = 128 outlet + 30 action（另有 2 条编译期提示，非连接） |
| 自定义类（`_TtC8TickTick*`） | **44 个**；另有 3 个应用类 `TTCollectionViewLeftAlignedFlowLayout`、`JWCTableView`、`TTSingleTaskDetailViewController` |
| 设计期可见文本 | 22 条（去重） |
| 图片资源名 | 27 个（Assets.car 中可解析 25 个） |
| 控件记录 / 表 B 可见行 | 128 / **88** |

- **TopView 校验通过**：18 outlet / 6 个不同 action（7 条 control connector，`assigneeButtonClicked:` 被两个按钮共用，去重后 6 个），与 2026-10-13 证据一致。
- **BottomActionView 校验通过**：任务给定 15 个 outlet、8 个 action 全部命中，无缺失、无多余。
- **回归校验**：与 2026-10-13 `ui_archives` 中 37 个可比的 nib 交叉验证，outlet 名集合 37/37 一致、去重 action 集合 37/37 一致。
- 详情页由 **4 个容器 nib + 25 个内容 nib** 组成；最小可复刻单元见第 4、5 节。

## 1. 方法与限制

### 1.1 为什么必须自写解析器

这些 `.nib` 是 Xcode 编译后的 **NIBArchive** 容器，不是 plist：`plutil -p` 报错，`ibtool --objects` 只返回 `com.apple.ibtool.errors`（已实测）。因此本审计用 Python 3 按字节结构解析，不依赖任何私有工具。

### 1.2 容器格式（实测）

```text
Header (50 bytes, little endian)
  char   magic[10]      = "NIBArchive"
  int32  unknown1       = 1        // 格式版本
  int32  unknown2       = 10
  int32  object_count, offset_objects
  int32  key_count,    offset_keys
  int32  value_count,  offset_values
  int32  class_name_count, offset_class_names

vint      : 7-bit little-endian groups; FINAL byte has bit7 set
            (与 LEB128 的继续位语义相反，是本格式最容易踩错的地方)
Key       : vint len + utf8
Value     : vint key_index, uint8 type, payload
            type 0..10 = int8/int16/int32/int64/true/false/float/double/
                         data(vint len+bytes)/nil/object_ref(int32)
Object    : vint class_index, vint value_index, vint value_count
ClassName : vint len, vint extras_count, bytes name, int32 extras[]
```

以 `TTTaskDetailTopView.nib` 为例的实际头部：object 322、key 111、value 1568、class 22、文件 16958 字节。

### 1.3 从对象图还原界面

1. `NSIBObjectData.NSRoot/NSConnections/NSObjectsKeys/NSObjectsValues` 是对象图根；`NSConnections` 指向连接数组。
2. 视图对象以 **`NSClassSwapper`** 编码：`NSClassName` = 真实类（如 `_TtC8TickTick19TTTaskDetailTopView`），`NSOriginalClassName` = AppKit 基类（如 `NSView`）；老式 nib 用 `NSCustomView`，字段含义相同。
3. 几何信息在 `NSFrame`（子视图，字符串 `"{{x, y}, {w, h}}"`）或 `NSFrameSize`（根视图/自动布局视图，`"{w, h}"`）。**它们是 IB 设计值，不是运行时 Auto Layout 结果。**
4. 控件内容：`NSButtonCell`/`NSTextFieldCell` 的 `NSContents` = 可见文本；`NSNormalImage`/`NSImageCell.NSContents` → `NSCustomResource.NSResourceName` = 图片名。
5. 连接：`NSNibOutletConnector{NSSource, NSDestination, NSLabel}`（outlet）、`NSNibControlConnector{NSSource, NSDestination, NSLabel}`（action，`NSLabel` 以 `:` 结尾）。**目的类**由 destination 对象反查：`NSClassSwapper`→真实视图类，`NSLayoutConstraint`→布局约束（无宿主视图信息）。

### 1.4 覆盖率 / 字段可得性

| 字段 | 是否取得 | 来源 / 说明 |
| --- | --- | --- |
| 根类名 | ✅ 29/29 | `NSClassSwapper.NSClassName`、`NSCustomView.NSClassName`、`NSWindowTemplate.NSWindowClass` |
| 设计尺寸 | ✅ 29/29 | `NSFrameSize`（视图）/ `NSFrame`（子视图）/ `NSWindowRect`（窗口） |
| 全部自定义/系统类 | ✅ | 视图 + cell + 连接两端 |
| 可见文本 | ✅（设计期） | cell `NSContents` / `NSWindowTitle` |
| 图片资源名 | ✅ 27 个 | `NSCustomResource.NSResourceName` + `IBDesignSize` |
| outlet 名 + 目标类 | ✅ | `NSNibOutletConnector` destination 反查 |
| action selector + 源控件 | ✅ | `NSNibControlConnector` source 反查 |
| 控件 frame（按对象顺序） | ✅ 视图级 | cell 自身无 frame，归属控件 frame 代替 |
| 文本占位符（placeholder） | ❌ | 归档内**不存在** `NSPlaceholderString` 键 |
| 约束常量/宿主 | ❌ | 只解出 outlet 指向约束对象，未解析 `NSFirstItem/NSSecondItem/NSConstant` |
| 运行态文案 | ❌ | nib 内是设计期占位（如 “Label Label…”），真实文案在代码/本地化表 |

### 1.5 限制

- `NSFrame` 是 IB 画布值；`{480, 272}` 反复出现在 DescriptionCell / SpaceCell / BottomView / DetailContainer 上，是 **IB 默认画布**，不能当作运行时行高。
- 任务描述里提到的 `{250, 750}` 在本批 nib 中**不是尺寸**：它出现在 TopView 的 `NSHuggingPriority`（内容 hugging 优先级 250/750），不是 frame/设计尺寸。
- outlet 指向 `NSLayoutConstraint` 时，归档不记录“约束属于哪个视图”，只能给出约束名 + 约束类。
- 编译期提示 `NSNibConnector`（2 条，见 2.4）不是界面连接，已从计数中剔除。
- 本地化表是 **App 级**（3457 个 key），不是 nib 级；只能用来确认按钮文案候选。

## 2. 校验（必须项）

### 2.1 TTTaskDetailTopView.nib：18 outlet / 6 action

| 指标 | 2026-10-13 证据 | 本次解析 | 结论 |
| --- | --- | --- | --- |
| outlet 数 | 18 | **18** | ✅ 一致 |
| action（去重 selector） | 6 | **6** | ✅ 一致 |
| control connector 原始条数 | — | 7 | 其中 `assigneeButtonClicked:` 出现 2 次 |
| connections 总数 | 25 | 25（18 + 7） | ✅ 一致 |
| objects | 95 | 322（原始归档对象） | ⚠️ 口径不同，见 2.4 |

18 个 outlet：

```text
assigneeAvatarButton, assigneeIconButton, assigneeLeadingLC, checkButton, checkboxLeadingLC, checkboxTopLC, dateButton, iconDivider, noteInfoButton, noteInfoLeadingLC, priorityButton, priorityLeadingLC, progressView, repeatIcon, repeatIconTrailingLC, returnButton, returnButtonTailingLC, secondaryDateLabel
```

6 个 action：`checkboxButtonClicked:`, `assigneeButtonClicked:`, `notesInfoButtonClicked:`, `priorityButtonClicked:`, `returnButtonClicked:`, `dateButtonClicked:`。

重复连接明细：`assigneeButtonClicked:` 同时来自 `assigneeIconButton`（TTThemeButton 28×28）与 `assigneeAvatarButton`（TTToolTipNSButton 20×20），因此 7 条 control connector 去重后是 6 个 action —— 这正是证据口径。

### 2.2 TTTaskDetailBottomActionView.nib：15 outlet / 8 action

| 检查项 | 结果 |
| --- | --- |
| 任务给定 15 个 outlet 是否齐全 | ✅ 全部命中，无缺失、无多余（15 条 outlet connector） |
| 任务给定 8 个 action 是否齐全 | ✅ 全部命中，无缺失、无多余（8 条 control connector） |

outlet：`commentButton`, `commentButtonLeading`, `deleteButton`, `deleteButtonLeading`, `deleteForeverButton`, `deleteForeverButtonLeading`, `mdEditButton`, `mdEditButtonLeading`, `mergeButton`, `mergeButtonLeading`, `moreButton`, `moreButtonLeading`, `projectButton`, `tagButton`, `tagButtonLeading`

action：`tagButtonClicked:`, `moreButtonClicked:`, `mergeButtonClicked:`, `deleteTaskButtonClicked:`, `mdEditButtonClicked:`, `moveToProjectButtonClicked:`, `commentButtonClicked:`, `deleteForeverButtonClicked:`

### 2.3 全量回归（对 2026-10-13 `ui_archives`）

| 项目 | 结果 |
| --- | --- |
| 可比 nib | 37 个（其中本批详情 nib 2 个，其余 35 个为同名 nib 的宽样本） |
| outlet 名集合 | 37/37 一致（证据按去重名记录；本解析按连接逐条记录后同样去重比较） |
| 去重 action 集合 | 37/37 一致 |
| 图片资源存在性 | 27 个名字中 25 个可在 `Assets.car` 命中；缺 `menu_calendar`, `set_repeat` |

说明：证据的 outlets/actions 是**去重后的名字集合**，本解析按连接逐条记录；例如 `TTFocusDetailRecordsViewController.nib` 有 22 条 outlet connector 但只有 14 个不同名字（多个 cell 复用 `titleLabel`/`conentLabel`），按去重名比较后 37/37 一致。

### 2.4 与证据对不上的地方（如实记录，不猜测）

1. **objects 数量**：证据 TopView = 95，本解析 `object_count` = 322。证据文件没有给出 objects 的统计口径。95 恰好等于 “视图 13 + cell 9 + 连接 25 + 约束 48”，但同一公式在 `TTCalendarArrangeCell` 上得 31（证据 36）、在 `TTFocusSummaryCell` 上得 1（证据 5），**规则不成立**，因此 95 只能视为“口径未知”，不能据此修改解析结果。
2. **action 条数**：证据 action 是去重后的 selector 列表（6），原始 control connector 是 7；两者都对，取决于是否去重。本报告同时给出两个数。
3. **图片名**：`menu_calendar`、`set_repeat` 在 `Assets.car` 中没有同名 rendition（最接近的是 `detail_calendar`、`repeat`/`set_repeat_large`）。推断是 IB 里的旧资源引用，运行期由代码替换；**未运行验证，仅记录差异**。

## 3. 逐 nib 表（类名 / 尺寸 / 子控件类与图片 / 文本 / outlet / action）

> 类名一列省略了 `_TtC8TickTick<长度>` 的 Swift mangling 前缀（完整符号见 JSON）。尺寸为 IB 设计值；`{480, 272}` 为默认画布。

| # | nib | 根类 | 尺寸 | 子控件类 / 图片名 | 文本 | outlet | action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `TTSingleTaskDetailViewController` | TTSingleTaskDetailView | {464, 470} | NSView×2, NSClipView×2, TTScroller×2, NSScroller×2, TTScrollView, … | Text Cell | bottomMarginConstraint、bottomViewHeightConstraint、containerForBottomView、containerForTopView、tableView …(9) | — |
| 2 | `TTTaskDetailWindowController` | NSWindow | {479, 381} | NSView | Window | window、delegate | — |
| 3 | `TTDetailContainerViewController` | TTBlockEventView | {480, 272} | — | — | view | — |
| 4 | `TTTaskDetailHolderViewController` | NSView | {456, 578} | NSImageView | — | emptyImageView、view | — |
| 5 | `TTTaskDetailTopView` | TTTaskDetailTopView | {766, 145} | TTThemeButton×6, NSView×2, TTToolTipImageView, TTToolTipNSButton, TTLabel, … ｜ 图: checkbox, close_detail, menu_calendar, set_repeat, assign_menu, priority_stroke… | Set Date / Label Label Label… | assigneeAvatarButton、assigneeIconButton、assigneeLeadingLC、checkButton、checkboxLeadingLC …(18) | checkboxButtonClicked:、assigneeButtonClicked:、notesInfoButtonClicked:、priorityButtonClicked: …(6) ［7 条连接］ |
| 6 | `TTTaskDetailTitleCell` | TTTaskDetailTitleCell | {362, 70} | TTThemeButton×2 ｜ 图: detail_mode_text, checkbox_abandoned | — | checkboxButton、kindButton | kindButtonClicked:、checkboxButtonClicked: |
| 7 | `TTTaskDetailContentCell` | TTTaskDetailContentCell | {207, 47} | — | — | — | — |
| 8 | `TTTaskDetailDescriptionCell` | TTTaskDetailDescriptionCell | {480, 272} | — | — | — | — |
| 9 | `TTTaskDetailBottomView` | TTTaskDetailBottomView | {480, 272} | NSView×4 | — | subContainer1、subContainer2、subContainer3、subContainer4、subContainerHeightConstraint1 …(8) | — |
| 10 | `TTTaskDetailBottomActionView` | TTTaskDetailBottomActionView | {480, 40} | TTThemeButton×8, NSView ｜ 图: move_task, tag, comment, sidebar_trash, more, combination… | Inbox | commentButton、commentButtonLeading、deleteButton、deleteButtonLeading、deleteForeverButton …(15) | tagButtonClicked:、moreButtonClicked:、mergeButtonClicked:、deleteTaskButtonClicked: …(8) |
| 11 | `TTTaskDetailSubtaskCell` | TTTaskDetailSubtaskCell | {354, 80} | — | — | — | — |
| 12 | `TTTaskDetailCheckItemCell` | TTTaskDetailCheckItemCell | {456, 140} | TTThemeButton×3, TTHoverableImageView ｜ 图: drag_indicator, checkbox, reminder, delete | — | checkBoxButton、checkboxLeadingLC、checkboxTopLC、deleteButton、deleteButtonTailingLC …(9) | checkBoxButtonClicked:、deleteButtonClicked:、reminderButtonClicked: |
| 13 | `TTTaskDetailParentTaskCell` | TTTaskDetailParentTaskCell | {346, 18} | TTThemeButton | Button | titleButton | titleButtonClicked: |
| 14 | `TTTaskDetailTagCollectionCell` | TTTaskDetailTagCollectionCell | {480, 165} | NSScroller×2, DisableScrollView, NSClipView, TTTaskDetailTagCollectionView | — | collectionView、leftMarginLC、rightMarginLC | — |
| 15 | `TTTaskDetailTagCollectionViewItem` | TTTaskDetailTagCollectionViewItemView | {318, 24} | NSImageView, NSView, TTTaskDetailTagCollectionViewItemTextField, TTThemeButton ｜ 图: add_sidebar, x_mark | It's sunny today | addImageView、backgroundView、deleteButton、inputTextField、view …(6) | deleteButtonClicked: |
| 16 | `TTTaskDetailSpaceCell` | TTTaskDetailSpaceCell | {480, 272} | — | — | — | — |
| 17 | `TTTaskDetailNotionBlockCell` | TTTaskDetailNotionBlockCell | {387, 292} | NSView×2, TTThemeButton, NSStackView, NSImageView, TTLabel | Button / Notion | containerView、notionButton、notionDivider、notionIconView、notionNameLabel …(6) | openInNotionButtonClicked: |
| 18 | `TTTaskDetailNotionBlockShortTextView` | TTTaskDetailNotionBlockShortTextView | {390, 36} | TTLabel×2 | LabelLabelLabelLa… / LabelLabelLabelLa… | keyLabel、keyLabelWidthLC、valueLabel | — |
| 19 | `TTTaskDetailNotionBlockLongTextView` | TTTaskDetailNotionBlockLongTextView | {371, 102} | TTLabel×2 | Label / 昔人已乘黄鹤去，此地空余黄鹤楼。黄… | keyLabel、valueLabel | — |
| 20 | `TTTaskDetailNotionBlockOptionView` | TTTaskDetailNotionBlockOptionView | {480, 36} | TTLabel×2 | Label / +3 | countLabel、keyLabel | — |
| 21 | `TTTaskDetailNotionBlockPeopleView` | TTTaskDetailNotionBlockPeopleView | {480, 36} | TTLabel×2, NSView | Label / User Name | avatarContainer、avatarContainerTailingLC、keyLabel、usernameLabel | — |
| 22 | `TTTaskDetailFocusSummaryCell` | TTTaskDetailFocusSummaryCell | {461, 32} | — | — | — | — |
| 23 | `TTTaskDetailPresetTaskActionCell` | TTTaskDetailPresetTaskActionCell | {346, 20} | TTHyperlinkLabel | You can choose to… | titleLabel | — |
| 24 | `TTTaskDetailActivitiesCell` | TTTaskDetailActivitiesCell | {316, 318} | NSView×2, TTLabel×2, TTThemeButton ｜ 图: x_mark | Task Activities / 0 | containerView、countLabel、dismissButton、titleContainerView、titleLabel | dismissClicked: |
| 25 | `TTTaskDetailCommentCell` | TTTaskDetailCommentCell | {388, 257} | TTThemeButton×3, TTLabel×3, NSStackView, NSStackViewContainer, NSImageView ｜ 图: edit, sidebar_trash, default_avatar_image, arrow_down | Label Label Label… / Label Label Label… | avatartImageView、commentTitleLabel、commnetTitleHeightConstraint、editButton、expandButton …(10) | expandAction:、replyOrRemoveButtonClicked:、editButtonClicked: |
| 26 | `TTTaskDetailCommentExpandCell` | TTTaskDetailCommentExpandCell | {300, 47} | TTThemeButton ｜ 图: arrow_down | Expand | expandButton | expandClicked: |
| 27 | `TTTaskDetailCommentHeaderView` | TTTaskDetailCommentHeaderView | {300, 36} | TTLabel×2 | Comment / 0 | countLabel、titleLabel | — |
| 28 | `TTTaskDetailAddCommentView` | TTTaskDetailAddCommentView | {489, 134} | TTThemeButton×2, TTScroller×2, NSStackView, TTLabel, NSStackViewContainer, … ｜ 图: comment_add_emoji, comment_add_image | 1024 | buttonsContainer、buttonsContainerBottomLC、countLabel、emojiButton、imageButton …(9) | emojiButtonClicked:、imageButtonClicked: |
| 29 | `TTTaskDetailNoteInfoViewController` | NSView | {128, 148} | TTLabel×6 | Label | countHintLabel、countLabel、createHintLabel、createLabel、modifyHintLabel …(7) | — |

本批出现的系统/框架类（去重 23 个）：`NSButton`、`NSButtonCell`、`NSClipView`、`NSCollectionView`、`NSCollectionViewLayout`、`NSImageCell`、`NSImageView`、`NSLayoutConstraint`、`NSObject`、`NSScrollView`、`NSScroller`、`NSStackView`、`NSStackViewContainer`、`NSTableCellView`、`NSTableHeaderCell`、`NSTableView`、`NSTextField`、`NSTextFieldCell`、`NSTextView`、`NSView`、`NSWindow`、`NSWindowTemplate`、`_NSCornerView`。

注意：**没有 `NSOutlineView`** —— 详情正文用的是 `JWCTableView`（`NSTableView` 子类）；`NSCollectionView` 只出现在 SingleTaskDetail 的标签/附件区与 TagCollectionCell。

## 4. 汇总表 A：详情页由哪些 cell 组成（职责为推断）

> 「职责」列**全部是推断**，依据仅限类名、图片名、outlet 名、文本与 frame，未做运行期验证。

| 层 | nib | 类 | 尺寸 | 职责（推断） | 依据 |
| --- | --- | --- | --- | --- | --- |
| 容器 | `TTSingleTaskDetailViewController` | TTSingleTaskDetailView | {464, 470} | 详情页宿主（整页滚动容器）：顶部容器 + 表格 + 标签集合视图 + 底部容器，用高度/边距约束拼装完整详情页 | outlets: containerForTopView / containerForBottomView / tableView / topContainerHeightLC / bottomViewHeightConstraint / topMarginConstraint |
| 容器 | `TTTaskDetailWindowController` | NSWindow | {479, 381} | 把详情页放进独立 NSWindow（弹窗形态）；窗口标题为占位 “Window” | NSWindowRect {{196,240},{479,381}}、NSWindowView 479×381、outlets window/delegate |
| 容器 | `TTDetailContainerViewController` | TTBlockEventView | {480, 272} | 详情容器占位：只有一个 TTBlockEventView，无子控件，推断由代码注入内容 | 唯一 outlet view → TTBlockEventView {480,272} |
| 容器 | `TTTaskDetailHolderViewController` | NSView | {456, 578} | 详情空态/装载态持有者：emptyImageView（0×0，默认隐藏）+ 根 view | outlets emptyImageView / view；NSImageView frame {{228,0},{0,0}} |
| 头部 | `TTTaskDetailTopView` | TTTaskDetailTopView | {766, 145} | 详情头部条：完成勾选、日期、重复、优先级、指派人、备注信息、返回、标题、进度条 | 18 outlets、6 个不同 action、7 张图标（checkbox/close_detail/menu_calendar/set_repeat/assign_menu/priority_stroke/notes_information） |
| 行 | `TTTaskDetailTitleCell` | TTTaskDetailTitleCell | {362, 70} | 标题行：完成勾选按钮 + 类型切换按钮（detail_mode_text / checkbox_abandoned 图标） | outlets checkboxButton / kindButton；actions checkboxButtonClicked: / kindButtonClicked: |
| 行 | `TTTaskDetailContentCell` | TTTaskDetailContentCell | {207, 47} | 正文行容器（207×47，无子控件、无连接）→ 推断正文由代码创建并嵌入 | root only；无 cell、无 outlet |
| 行 | `TTTaskDetailDescriptionCell` | TTTaskDetailDescriptionCell | {480, 272} | 描述/备注区容器（480×272，无子控件）→ 推断备注编辑器由代码注入 | root only；无 cell、无 outlet |
| 底部 | `TTTaskDetailBottomView` | TTTaskDetailBottomView | {480, 272} | 底部区域骨架：4 个等高（50）子容器 + 4 条高度约束，用于挂载底栏/评论/动态等子视图 | outlets subContainer1..4 + subContainerHeightConstraint1..4；frames y=0/50/100/150 |
| 底部 | `TTTaskDetailBottomActionView` | TTTaskDetailBottomActionView | {480, 40} | 底栏操作条（40 高）：清单/项目、标签、Markdown 编辑、合并、评论、删除、永久删除、更多 | 15 outlets、8 个 action、8 张图标（move_task/tag/comment/sidebar_trash/more/combination/md_edit/delete_forever），projectButton 带文本 “Inbox” |
| 行 | `TTTaskDetailSubtaskCell` | TTTaskDetailSubtaskCell | {354, 80} | 子任务行容器（354×80，无子控件）→ 推断子任务标题/勾选由代码绘制 | root only；无 cell、无 outlet |
| 行 | `TTTaskDetailCheckItemCell` | TTTaskDetailCheckItemCell | {456, 140} | 检查事项行：拖拽手柄 + 勾选框 + 提醒按钮 + 删除按钮 | outlets checkBoxButton / dragIndicator / reminderButton / deleteButton + 4 条 LC；actions checkBoxButtonClicked: / reminderButtonClicked: / deleteButtonClicked: |
| 行 | `TTTaskDetailParentTaskCell` | TTTaskDetailParentTaskCell | {346, 18} | 父任务入口行：一个 45×16 的按钮，文本占位 “Button” | outlet titleButton；action titleButtonClicked: |
| 集合 | `TTTaskDetailTagCollectionCell` | TTTaskDetailTagCollectionCell | {480, 165} | 标签集合容器：左/右边距约束 + 内部横向滚动的标签集合视图（440×165） | outlets collectionView / leftMarginLC / rightMarginLC；TTDisableScrollView |
| 集合项 | `TTTaskDetailTagCollectionViewItem` | TTTaskDetailTagCollectionViewItemView | {318, 24} | 标签 chip：可编辑文本框 + 删除按钮 + 添加图标 + 背景视图（318×24） | outlets inputTextField / deleteButton / addImageView / backgroundView / view；action deleteButtonClicked: |
| 占位 | `TTTaskDetailSpaceCell` | TTTaskDetailSpaceCell | {480, 272} | 纯间距占位 cell（480×272 画布，无内容） | root only；无 cell、无 outlet |
| Notion 块 | `TTTaskDetailNotionBlockCell` | TTTaskDetailNotionBlockCell | {387, 292} | Notion 属性块外壳：图标 + 名称 + 分隔线 + 垂直 stack + “打开 Notion” 按钮 | outlets notionIconView / notionNameLabel / notionDivider / stackView / notionButton / containerView；action openInNotionButtonClicked: |
| Notion 块 | `TTTaskDetailNotionBlockShortTextView` | TTTaskDetailNotionBlockShortTextView | {390, 36} | Notion 短文本属性行：key 标签（60 宽）+ value 标签 | outlets keyLabel / keyLabelWidthLC / valueLabel；文本 “LabelLabel…” |
| Notion 块 | `TTTaskDetailNotionBlockLongTextView` | TTTaskDetailNotionBlockLongTextView | {371, 102} | Notion 长文本属性：343×60 多行 value + key 标签 | outlets keyLabel / valueLabel；文本含整段中文占位 |
| Notion 块 | `TTTaskDetailNotionBlockOptionView` | TTTaskDetailNotionBlockOptionView | {480, 36} | Notion 选项属性行：key 标签 + 计数徽标（“+3”） | outlets keyLabel / countLabel；countLabel 20×15 右对齐 |
| Notion 块 | `TTTaskDetailNotionBlockPeopleView` | TTTaskDetailNotionBlockPeopleView | {480, 36} | Notion 人员属性行：key 标签 + 用户名 + 头像容器（407×36） | outlets keyLabel / usernameLabel / avatarContainer / avatarContainerTailingLC |
| 行 | `TTTaskDetailFocusSummaryCell` | TTTaskDetailFocusSummaryCell | {461, 32} | 专注汇总行（461×32，无子控件、无连接）→ 推断由代码绘制文字/图标 | root only |
| 行 | `TTTaskDetailPresetTaskActionCell` | TTTaskDetailPresetTaskActionCell | {346, 20} | 预设动作行：TTHyperlinkLabel 富文本按钮（346×20） | outlet titleLabel（TTHyperlinkLabel）；无 action 连接 |
| 区块 | `TTTaskDetailActivitiesCell` | TTTaskDetailActivitiesCell | {316, 318} | 任务动态区：标题 “Task Activities” + 计数 + 关闭按钮 + 内容容器（316×318） | outlets titleLabel / countLabel / dismissButton / containerView / titleContainerView；action dismissClicked: |
| 评论 | `TTTaskDetailCommentCell` | TTTaskDetailCommentCell | {388, 257} | 单条评论：头像、用户名、时间、正文（两段 Label）、编辑/删除/展开按钮、回复按钮 | 10 outlets、4 个 action（expandAction: / replyOrRemoveButtonClicked: / editButtonClicked:）、4 张图标（edit/sidebar_trash/default_avatar_image/arrow_down） |
| 评论 | `TTTaskDetailCommentExpandCell` | TTTaskDetailCommentExpandCell | {300, 47} | 评论展开/收起行：箭头图标 + “Expand” 按钮（300×47） | outlet expandButton；action expandClicked: |
| 评论 | `TTTaskDetailCommentHeaderView` | TTTaskDetailCommentHeaderView | {300, 36} | 评论区标题行：“Comment” + 计数（300×36） | outlets titleLabel / countLabel；文本 “Comment”“0” |
| 评论 | `TTTaskDetailAddCommentView` | TTTaskDetailAddCommentView | {489, 134} | 评论输入区：滚动文本视图 + 表情/图片按钮 + 字数计数（489×134） | outlets textView / emojiButton / imageButton / countLabel / buttonsContainer / inputBaseView + 3 条 LC；actions emojiButtonClicked: / imageButtonClicked: |
| 浮层 | `TTTaskDetailNoteInfoViewController` | NSView | {128, 148} | 笔记信息浮层：6 个标签两两成对（创建/修改的时间与提示）+ 计数 | outlets countLabel / countHintLabel / createLabel / createHintLabel / modifyLabel / modifyHintLabel / view |

### 4.1 与本仓库实现的可能差异（推断，非运行验证）

把 nib 证据与本仓库 `macos-native/WorkFollow` 的静态代码对照后，以下控件在仓库里没有对应实现或形态不同（grep 结果，未运行）：

| 控件 / 能力 | nib 证据 | 仓库现状（静态 grep） | 判断 |
| --- | --- | --- | --- |
| Notion 属性块五件套 | `notionIconView`/`notionNameLabel`/`notionButton` + `openInNotionButtonClicked:`、People/Option/Long/Short 四种行 | `macos-native/WorkFollow` 内 **无 “notion” 字符串** | 可能没有 |
| 任务合并按钮 | `mergeButton` + `mergeButtonClicked:`（图标 `combination`） | 只有设置里的数据导入 “merge/合并”，TaskInspectorActionPanel 的 case 为 more/tags/relation/parent/activity/comments | 可能没有 |
| 预设动作行 | `TTTaskDetailPresetTaskActionCell`（`TTHyperlinkLabel`，346×20） | “preset” 仅出现在日期提醒偏移（`TaskDateDraftModel`） | 可能没有 |
| 评论折叠/计数行 | `TTTaskDetailCommentHeaderView`（Comment + 0）、`TTTaskDetailCommentExpandCell`（Expand + arrow_down） | 有 `TaskCommentPanel`（面板），无独立头部/折叠 cell | 形态不同 |
| 内嵌任务动态块 | `TTTaskDetailActivitiesCell`（316×318，标题 + 计数 + dismiss） | 有 `TaskActivityPanel`（独立面板） | 形态不同 |

结构层面还有一处差异：TickTick 详情正文用 **`JWCTableView`（`NSTableView` 子类）**承载全部 13 种 cell，而仓库 `TaskInspector` 用 `AppKitSubtaskOutlineView`（`NSOutlineView`）做子任务树；本批 nib 中**没有** `NSOutlineView`。

另有 2 个“有等价能力但呈现不同”的底栏按钮：`mdEditButton`（nib 用 `md_edit` 图标）在仓库里是字面 “A” 的 SwiftUI 按钮；`deleteForeverButton`（`delete_forever` 图标）在仓库里只出现在垃圾桶页面，不在详情底栏。

## 5. 汇总表 B：详情页全部可见控件与动作（去重）

> 每行 = 一个视图对象（含它自己的 outlet / 图片 / 文本 / action）。同一 outlet 名在不同 nib 中是不同控件，故按 (nib, 对象号) 去重而不是按名字去重。`obj#` 为归档对象序号，便于回查 JSON。

> 收录 88 个可见控件；另有 40 行是纯布局约束/文件所有者等非可视对象，已在表 B 剔除（完整清单见 JSON `controls`）。

| # | 所在 nib | 控件（outlet） | 类 | 图片 | 文本 | action |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `TTSingleTaskDetailViewController` | containerForTopView | NSView | — | — | — |
| 2 | `TTSingleTaskDetailViewController` | view | TTSingleTaskDetailView | — | — | — |
| 3 | `TTSingleTaskDetailViewController` | containerForBottomView | NSView | — | — | — |
| 4 | `TTSingleTaskDetailViewController` | tableView | JWCTableView | — | Text Cell | — |
| 5 | `TTTaskDetailWindowController` | window | NSWindowTemplate | — | — | — |
| 6 | `TTDetailContainerViewController` | view | TTBlockEventView | — | — | — |
| 7 | `TTTaskDetailHolderViewController` | emptyImageView | NSImageView | — | — | — |
| 8 | `TTTaskDetailHolderViewController` | view | NSView | — | — | — |
| 9 | `TTTaskDetailTopView` | iconDivider | NSView | — | — | — |
| 10 | `TTTaskDetailTopView` | repeatIcon | TTToolTipImageView | set_repeat | — | — |
| 11 | `TTTaskDetailTopView` | checkButton | TTThemeButton | checkbox | — | checkboxButtonClicked: |
| 12 | `TTTaskDetailTopView` | assigneeAvatarButton | TTToolTipNSButton | — | — | assigneeButtonClicked: |
| 13 | `TTTaskDetailTopView` | returnButton | TTThemeButton | close_detail | — | returnButtonClicked: |
| 14 | `TTTaskDetailTopView` | dateButton | TTThemeButton | menu_calendar | Set Date | dateButtonClicked: |
| 15 | `TTTaskDetailTopView` | assigneeIconButton | TTThemeButton | assign_menu | — | assigneeButtonClicked: |
| 16 | `TTTaskDetailTopView` | priorityButton | TTThemeButton | priority_stroke | — | priorityButtonClicked: |
| 17 | `TTTaskDetailTopView` | noteInfoButton | TTThemeButton | notes_information | — | notesInfoButtonClicked: |
| 18 | `TTTaskDetailTopView` | secondaryDateLabel | TTLabel | — | Label Label Label Lab… | — |
| 19 | `TTTaskDetailTopView` | progressView | TTTaskDetailProgressView | — | — | — |
| 20 | `TTTaskDetailTitleCell` | checkboxButton | TTThemeButton | checkbox_abandoned | — | checkboxButtonClicked: |
| 21 | `TTTaskDetailTitleCell` | kindButton | TTThemeButton | detail_mode_text | — | kindButtonClicked: |
| 22 | `TTTaskDetailBottomView` | subContainer4 | NSView | — | — | — |
| 23 | `TTTaskDetailBottomView` | subContainer3 | NSView | — | — | — |
| 24 | `TTTaskDetailBottomView` | subContainer2 | NSView | — | — | — |
| 25 | `TTTaskDetailBottomView` | subContainer1 | NSView | — | — | — |
| 26 | `TTTaskDetailBottomActionView` | projectButton | TTThemeButton | move_task | Inbox | moveToProjectButtonClicked: |
| 27 | `TTTaskDetailBottomActionView` | mdEditButton | TTThemeButton | md_edit | — | mdEditButtonClicked: |
| 28 | `TTTaskDetailBottomActionView` | mergeButton | TTThemeButton | combination | — | mergeButtonClicked: |
| 29 | `TTTaskDetailBottomActionView` | tagButton | TTThemeButton | tag | — | tagButtonClicked: |
| 30 | `TTTaskDetailBottomActionView` | commentButton | TTThemeButton | comment | — | commentButtonClicked: |
| 31 | `TTTaskDetailBottomActionView` | deleteButton | TTThemeButton | sidebar_trash | — | deleteTaskButtonClicked: |
| 32 | `TTTaskDetailBottomActionView` | deleteForeverButton | TTThemeButton | delete_forever | — | deleteForeverButtonClicked: |
| 33 | `TTTaskDetailBottomActionView` | moreButton | TTThemeButton | more | — | moreButtonClicked: |
| 34 | `TTTaskDetailCheckItemCell` | dragIndicator | TTHoverableImageView | drag_indicator | — | — |
| 35 | `TTTaskDetailCheckItemCell` | checkBoxButton | TTThemeButton | checkbox | — | checkBoxButtonClicked: |
| 36 | `TTTaskDetailCheckItemCell` | reminderButton | TTThemeButton | reminder | — | reminderButtonClicked: |
| 37 | `TTTaskDetailCheckItemCell` | deleteButton | TTThemeButton | delete | — | deleteButtonClicked: |
| 38 | `TTTaskDetailParentTaskCell` | titleButton | TTThemeButton | — | Button | titleButtonClicked: |
| 39 | `TTTaskDetailTagCollectionCell` | collectionView | TTTaskDetailTagCollectionView | — | — | — |
| 40 | `TTTaskDetailTagCollectionViewItem` | deleteButton | TTThemeButton | x_mark | — | deleteButtonClicked: |
| 41 | `TTTaskDetailTagCollectionViewItem` | addImageView | NSImageView | add_sidebar | — | — |
| 42 | `TTTaskDetailTagCollectionViewItem` | inputTextField | TTTaskDetailTagCollectionViewItemTextField | — | It's sunny today | — |
| 43 | `TTTaskDetailTagCollectionViewItem` | backgroundView | NSView | — | — | — |
| 44 | `TTTaskDetailTagCollectionViewItem` | view | TTTaskDetailTagCollectionViewItemView | — | — | — |
| 45 | `TTTaskDetailNotionBlockCell` | stackView | NSStackView | — | — | — |
| 46 | `TTTaskDetailNotionBlockCell` | notionDivider | NSView | — | — | — |
| 47 | `TTTaskDetailNotionBlockCell` | notionNameLabel | TTLabel | — | Notion | — |
| 48 | `TTTaskDetailNotionBlockCell` | notionIconView | NSImageView | — | — | — |
| 49 | `TTTaskDetailNotionBlockCell` | containerView | NSView | — | — | — |
| 50 | `TTTaskDetailNotionBlockCell` | notionButton | TTThemeButton | — | Button | openInNotionButtonClicked: |
| 51 | `TTTaskDetailNotionBlockShortTextView` | valueLabel | TTLabel | — | LabelLabelLabelLabelL… | — |
| 52 | `TTTaskDetailNotionBlockShortTextView` | keyLabel | TTLabel | — | LabelLabelLabelLabelL… | — |
| 53 | `TTTaskDetailNotionBlockLongTextView` | keyLabel | TTLabel | — | Label | — |
| 54 | `TTTaskDetailNotionBlockLongTextView` | valueLabel | TTLabel | — | 昔人已乘黄鹤去，此地空余黄鹤楼。黄鹤一去不… | — |
| 55 | `TTTaskDetailNotionBlockOptionView` | countLabel | TTLabel | — | +3 | — |
| 56 | `TTTaskDetailNotionBlockOptionView` | keyLabel | TTLabel | — | Label | — |
| 57 | `TTTaskDetailNotionBlockPeopleView` | usernameLabel | TTLabel | — | User Name | — |
| 58 | `TTTaskDetailNotionBlockPeopleView` | keyLabel | TTLabel | — | Label | — |
| 59 | `TTTaskDetailNotionBlockPeopleView` | avatarContainer | NSView | — | — | — |
| 60 | `TTTaskDetailPresetTaskActionCell` | titleLabel | TTHyperlinkLabel | — | You can choose to pay… | — |
| 61 | `TTTaskDetailActivitiesCell` | titleContainerView | NSView | — | — | — |
| 62 | `TTTaskDetailActivitiesCell` | containerView | NSView | — | — | — |
| 63 | `TTTaskDetailActivitiesCell` | titleLabel | TTLabel | — | Task Activities | — |
| 64 | `TTTaskDetailActivitiesCell` | countLabel | TTLabel | — | 0 | — |
| 65 | `TTTaskDetailActivitiesCell` | dismissButton | TTThemeButton | x_mark | — | dismissClicked: |
| 66 | `TTTaskDetailCommentCell` | timeLable | TTLabel | — | Label | — |
| 67 | `TTTaskDetailCommentCell` | userNameLabel | TTLabel | — | Label Label Label Lab… | — |
| 68 | `TTTaskDetailCommentCell` | avatartImageView | NSImageView | default_avatar_image | — | — |
| 69 | `TTTaskDetailCommentCell` | commentTitleLabel | TTLabel | — | Label Label Label Lab… | — |
| 70 | `TTTaskDetailCommentCell` | expandButton | TTThemeButton | arrow_down | Expand | expandAction: |
| 71 | `TTTaskDetailCommentCell` | replyOrRemoveButton | TTThemeButton | sidebar_trash | — | replyOrRemoveButtonClicked: |
| 72 | `TTTaskDetailCommentCell` | editButton | TTThemeButton | edit | — | editButtonClicked: |
| 73 | `TTTaskDetailCommentExpandCell` | expandButton | TTThemeButton | arrow_down | Expand | expandClicked: |
| 74 | `TTTaskDetailCommentHeaderView` | titleLabel | TTLabel | — | Comment | — |
| 75 | `TTTaskDetailCommentHeaderView` | countLabel | TTLabel | — | 0 | — |
| 76 | `TTTaskDetailAddCommentView` | inputBaseView | NSView | — | — | — |
| 77 | `TTTaskDetailAddCommentView` | buttonsContainer | NSStackView | — | — | — |
| 78 | `TTTaskDetailAddCommentView` | countLabel | TTLabel | — | 1024 | — |
| 79 | `TTTaskDetailAddCommentView` | emojiButton | TTThemeButton | comment_add_emoji | — | emojiButtonClicked: |
| 80 | `TTTaskDetailAddCommentView` | imageButton | TTThemeButton | comment_add_image | — | imageButtonClicked: |
| 81 | `TTTaskDetailAddCommentView` | textView | TTAddCommentTextView | — | — | — |
| 82 | `TTTaskDetailNoteInfoViewController` | countHintLabel | TTLabel | — | Label | — |
| 83 | `TTTaskDetailNoteInfoViewController` | countLabel | TTLabel | — | Label | — |
| 84 | `TTTaskDetailNoteInfoViewController` | createHintLabel | TTLabel | — | Label | — |
| 85 | `TTTaskDetailNoteInfoViewController` | createLabel | TTLabel | — | Label | — |
| 86 | `TTTaskDetailNoteInfoViewController` | modifyHintLabel | TTLabel | — | Label | — |
| 87 | `TTTaskDetailNoteInfoViewController` | modifyLabel | TTLabel | — | Label | — |
| 88 | `TTTaskDetailNoteInfoViewController` | view | NSView | — | — | — |

## 6. 几何数字（IB 设计值）

### 6.1 头部条 `TTTaskDetailTopView` —— 766 × 145（IB 画布）

| outlet | 类 | frame | 图标 / 文本 | 备注（推断） |
| --- | --- | --- | --- | --- |
| `iconDivider` | NSView | `{{72, 115}, {1, 16}}` | — | 1 px 竖分隔线（分组用） |
| `repeatIcon` | TTToolTipImageView | `{{163, 115}, {16, 16}}` | set_repeat（原图 {24, 24}） | 重复图标（点击态可能由 dateButton 代理） |
| `checkButton` | TTThemeButton | `{{44, 114}, {17, 17}}` | checkbox（原图 {24, 24}） | 完成勾选 |
| `assigneeAvatarButton` | TTToolTipNSButton | `{{664, 113}, {20, 20}}` | — | 指派人头像（叠在 assigneeIconButton 上） |
| `returnButton` | TTThemeButton | `{{12, 111}, {24, 24}}` | close_detail（原图 {20, 20}） | 返回 / 关闭详情 |
| `dateButton` | TTThemeButton | `{{80, 111}, {77, 24}}` | menu_calendar（原图 {18, 18}） / “Set Date” | 日期按钮，标题占位 “Set Date” |
| `assigneeIconButton` | TTThemeButton | `{{660, 109}, {28, 28}}` | assign_menu（原图 {24, 24}） | 指派人入口 |
| `priorityButton` | TTThemeButton | `{{694, 109}, {28, 28}}` | priority_stroke（原图 {24, 24}） | 优先级 |
| `noteInfoButton` | TTThemeButton | `{{728, 109}, {28, 28}}` | notes_information（原图 {22, 22}） | 备注/笔记信息 |
| `secondaryDateLabel` | TTLabel | `{{104, 93}, {412, 14}}` | — / “Label Label L…” | 长文本标签（占位 Label…，412 宽，推断是任务标题） |

- 顶部 8 px 留白：主行控件占 `y = 109…137`（高 16–28）；`secondaryDateLabel` 在其下方 `y = 93…107`（412×14）；`progressView` 只有尺寸 766×40，**没有坐标**，推断贴在头部底边（0…40）。
- 水平排布（左→右）：`returnButton` x=12、`checkButton` x=44、`iconDivider` x=72、`dateButton` x=80（77 宽）、`repeatIcon` x=163；右侧簇 `assigneeIconButton` x=660 / `assigneeAvatarButton` x=664、`priorityButton` x=694、`noteInfoButton` x=728（最右 756，距 766 边 10）。
- 145 是 IB 画布高度：可视控件只占顶部 `y = 93…137`（工具行 28 + 标题行 14）与进度条 40，中间大段留白由约束在运行时消耗——**不能**直接当作运行时 header 高度。

### 6.2 底部操作条 `TTTaskDetailBottomActionView` —— 480 × 40

| x | outlet | 尺寸 | 图标 | action |
| --- | --- | --- | --- | --- |
| 17 | `projectButton` | 63×24 | move_task | `moveToProjectButtonClicked:` |
| 247 | `mdEditButton` | 24×24 | md_edit | `mdEditButtonClicked:` |
| 279 | `mergeButton` | 24×24 | combination | `mergeButtonClicked:` |
| 311 | `tagButton` | 24×24 | tag | `tagButtonClicked:` |
| 343 | `commentButton` | 24×24 | comment | `commentButtonClicked:` |
| 375 | `deleteButton` | 24×24 | sidebar_trash | `deleteTaskButtonClicked:` |
| 407 | `deleteForeverButton` | 24×24 | delete_forever | `deleteForeverButtonClicked:` |
| 439 | `moreButton` | 24×24 | more | `moreButtonClicked:` |

- 8 个按钮全部 `y = 8`、高 24：`8 + 24 + 8 = 40`，即 40 高底栏内上下居中。
- 7 个图标按钮 24×24，x = 247 / 279 / 311 / 343 / 375 / 407 / 439，间距 32（= 24 宽 + 8 空隙），最右 `moreButton` 右边缘 463（距 480 边 17）。
- `projectButton` 是唯一带文字的按钮：x=17、63×24，文本占位 “Inbox”（运行时是清单名）。
- 左→右语义：清单(`projectButton`) → Markdown 编辑(`mdEditButton`) → 合并(`mergeButton`) → 标签(`tagButton`) → 评论(`commentButton`) → 删除(`deleteButton`) → 永久删除(`deleteForeverButton`) → 更多(`moreButton`)。

### 6.3 各 cell / 区块的设计尺寸

| nib | 根尺寸 | 关键子视图 frame | 备注 |
| --- | --- | --- | --- |
| `TTTaskDetailTitleCell` | {362, 70} | TTThemeButton @(321,35) 24×24；TTThemeButton @(12,49) 16×16 | 行高候选（IB 设计值） |
| `TTTaskDetailContentCell` | {207, 47} | 无子视图 | 无子视图，内容由代码注入 |
| `TTTaskDetailDescriptionCell` | {480, 272} | 无子视图 | IB 默认画布，非运行时行高 |
| `TTTaskDetailBottomView` | {480, 272} | NSView {480, 50}；NSView @(0,50) 480×50；NSView @(0,100) 480×50；NSView @(0,150) 480×50 | IB 默认画布，非运行时行高 |
| `TTTaskDetailSubtaskCell` | {354, 80} | 无子视图 | 无子视图，内容由代码注入 |
| `TTTaskDetailCheckItemCell` | {456, 140} | TTHoverableImageView @(0,114) 12×12；TTThemeButton @(20,111) 17×17；TTThemeButton @(389,108) 24×24；TTThemeButton @(415,108) 24×24 | 行高候选（IB 设计值） |
| `TTTaskDetailParentTaskCell` | {346, 18} | TTThemeButton @(20,0) 45×16 | 行高候选（IB 设计值） |
| `TTTaskDetailSpaceCell` | {480, 272} | 无子视图 | IB 默认画布，非运行时行高 |
| `TTTaskDetailNotionBlockShortTextView` | {390, 36} | TTLabel @(14,10) 60×16；TTLabel @(78,11) 298×15 | 行高候选（IB 设计值） |
| `TTTaskDetailNotionBlockLongTextView` | {371, 102} | TTLabel @(14,76) 37×16；TTLabel @(14,10) 343×60 | 行高候选（IB 设计值） |
| `TTTaskDetailNotionBlockOptionView` | {480, 36} | TTLabel @(14,10) 37×16；TTLabel @(448,11) 20×15 | 行高候选（IB 设计值） |
| `TTTaskDetailNotionBlockPeopleView` | {480, 36} | TTLabel @(14,10) 37×16；TTLabel @(399,11) 67×15；NSView @(57,0) 407×36 | 行高候选（IB 设计值） |
| `TTTaskDetailFocusSummaryCell` | {461, 32} | 无子视图 | 无子视图，内容由代码注入 |
| `TTTaskDetailPresetTaskActionCell` | {346, 20} | TTHyperlinkLabel @(18,3) 310×14 | 行高候选（IB 设计值） |
| `TTTaskDetailCommentExpandCell` | {300, 47} | TTThemeButton @(64,20) 60×15 | 行高候选（IB 设计值） |
| `TTTaskDetailCommentHeaderView` | {300, 36} | TTLabel @(18,10) 67×17；TTLabel @(87,10) 13×17 | 行高候选（IB 设计值） |
| `TTTaskDetailNoteInfoViewController` | {128, 148} | TTLabel @(10,122) 33×14；TTLabel @(10,104) 33×14；TTLabel @(10,76) 33×14；TTLabel @(10,58) 33×14 | 浮层视图，不是表格行 |

- `TTTaskDetailTitleCell` 362×70：勾选框 16×16 @(12,49)，类型按钮 24×24 @(321,35)。
- `TTTaskDetailCheckItemCell` 456×140：拖拽柄 12×12 @(0,114)、勾选框 17×17 @(20,111)、提醒 24×24 @(389,108)、删除 24×24 @(415,108) —— 行内控件统一底对齐。
- `TTTaskDetailParentTaskCell` 346×18：按钮 45×16 @(20,0)。
- `TTTaskDetailPresetTaskActionCell` 346×20：超链接 label 310×14 @(18,3)。
- `TTTaskDetailFocusSummaryCell` 461×32：无子视图（内容代码绘制），是“行高”最可信的候选之一。
- `TTTaskDetailCommentHeaderView` 300×36；`TTTaskDetailCommentExpandCell` 300×47（按钮 60×15 @(64,20)）。
- **行高候选汇总**（IB 设计值，仅供参照，运行时需以 table 的 rowHeight 为准）：Title 70 / Content 47 / Subtask 80 / CheckItem 140 / ParentTask 18 / Preset 20 / FocusSummary 32 / CommentHeader 36 / CommentExpand 47 / NotionShort 36 / NotionLong 102 / NotionOption 36 / NotionPeople 36 / Comment 257 / AddComment 134；ActivitiesCell 318 是区块高度，不是行高。
- 每个 nib 的**全部**对象 frame（按归档对象顺序、含 superview 引用）在 JSON 的 `nibs[].frames` 中；本表只列代表性子视图。

## 7. 未取得 / 不确定清单

1. **placeholder 文案**：本批归档无 `NSPlaceholderString` 键，输入框占位文案不可得；nib 里的 “Label…/Button/Inbox/Window” 是 IB 占位，不代表运行文案。
2. **cell 自身 frame**：cell 对象没有 frame（`NSControlView` 指向宿主视图），表里给的是宿主视图 frame；table 行高需运行期或约束推导。
3. **约束归属**：37 个 `*LC` outlet 指向 `NSLayoutConstraint`，归档不记录约束的宿主视图；本报告只能给出“约束类 + outlet 名”。约束常量未解码。
4. **`{480, 272}`** 是 IB 默认画布，出现在 DescriptionCell / SpaceCell / BottomView / DetailContainer，不能当运行时尺寸。
5. **`{250, 750}`** 是 TopView 的 `NSHuggingPriority`（内容 hugging 优先级 250/750），不是设计尺寸；任务描述把它与 `{480, 40}` 并列举例，实际本批 nib 中没有任何视图是这个尺寸。
6. **图片资源**：27 个资源名中 25 个在 `Assets.car` 命中；`menu_calendar`、`set_repeat` 无同名 rendition（相近有 `detail_calendar`、`repeat`、`set_repeat_large`），**推断**为 IB 旧引用、运行期替换，未运行验证。
7. **证据 objects 口径未知**（95 vs 322；`TTFocusSummaryCell` 5 vs 26）；仅 outlet/action/connection 作为契约项校验，全部一致。
8. **两条 `NSNibConnector` 编译期提示**（CommentCell priority 999990、AddCommentView 999980）是 Xcode 对 NSStackView 解码顺序的提示，不是界面连接，已剔除。
9. **File's Owner 异常**：`TTTaskDetailPresetTaskActionCell.nib` 的 owner 类是 `TTTaskDetailParentTaskCell`（复制 nib 的残留），不影响控件但说明该 nib 是复制改的。
10. **窗口标题**是 “Window” 占位；`TTTaskDetailWindowController` 仅 2 条连接（window/delegate），内容全部来自代码挂载。
11. **文本与动作的对应关系**是“同一宿主视图”粒度：一个按钮的 title 与 action 可以确认，但按钮点击后的业务语义（如 md 编辑到底编辑什么）只能靠命名/本地化推断。
12. 未解析：`NSAccessibility*`、`NSViewConstraints` 的约束常量、`NSFont`/`NSColor` 细节、`NSWindowStyleMask` 的位含义；这些不影响本清单的控件级结论。

## 8. 附：详情/编辑栏相关本地化字符串

来源：`Contents/Resources/en.lproj/Localizable.strings` 与 `zh-Hans.lproj/Localizable.strings`（UTF-16LE，各 3457 个 key）。脚本用“白名单 + 关键词”抽到 85 组中英对照，下表节选常用项（App 内没有独立的“详情”strings 文件；key 本身多为英文原文）。

| key | en | zh-Hans |
| --- | --- | --- |
| `Add Subtask` | Add Subtask | 添加子任务 |
| `Add subtask` | Add subtask | 添加子任务 |
| `Subtask` | Subtask | 子任务 |
| `Expand/Collapse all subtasks` | Expand/Collapse all subtasks | 展开/折叠所有子任务 |
| `Comments` | Comments | 评论 |
| `Write a comment` | Write a comment | 添加评论 |
| `comments_show` | Show More | 展开评论 |
| `comments_hide` | Show Less | 收起评论 |
| `edit_comment` | Edit Comment | 编辑评论 |
| `Can Comment` | Can Comment | 可评论 |
| `Merge` | Merge | 合并 |
| `Merge Tags` | Merge Tags | 合并标签到… |
| `New merged task` | New merged task | 新合并任务 |
| `Notes` | Notes | 备注 |
| `Note` | Note | 笔记 |
| `add_note` | Add Note | 添加笔记 |
| `add_note_to__press_enter_to_save` | Add note to \"%@\". Press Enter to save. | 添加笔记至“%@”，回车即可创建 |
| `placeholder_add_note` | Add note | 添加笔记 |
| `note_detail` | Note Detail | 笔记详情 |
| `More` | More | 更多 |
| `Task Activities` | Task Activities | 任务动态 |
| `Activities` | Activities | 活动 |
| `Delete` | Delete | 删除 |
| `Delete Forever` | Delete Forever | 永久删除 |
| `Duplicate` | Duplicate | 复制 |
| `Expand` | Expand | 展开 |
| `Priority` | Priority | 优先级 |
| `Assignee` | Assignee | 指派人 |
| `Set Date` | Set Date | 设置日期 |
| `Repeat` | Repeat | 重复 |
| `Tag` | Tag | 标签 |
| `Attachment` | Attachment | 附件 |
| `Pin` | Pin | 置顶 |
| `Focus` | Focus | 专注 |
| `task_detail_layout` | Task Detail Layout | 任务详情样式 |
| `task_detail_layout_side_peek` | Side peek | 侧边栏 |
| `task_detail_layout_popup` | Pop-up | 弹窗 |
| `task_detail_layout_desc` | If the window is too narrow, the task details will appear according to your choice. | 当窗口宽度不足时，任务详情将根据你的选择显示。 |
| `open_in_notion` | Open in Notion | 打开 Notion |
| `click_to_add_template_desktop` | Click \"…\" in the lower right corner of the task/note detail page. Select \"Save as Template\" to create a task/note as a template. | 在任务/笔记详情页中先编辑好内容，再点击右下角“…”，选择“保存为模板”，输入标题即可将任务/笔记创建为模板 |
| `empty_task_template_desc` | You can select to have a task saved as a template in its detail view. | 你可以在任务详情内，将任务保存为模板 |
| `Content or details of the task` | Content or details of the task | 任务的内容或详情 |
| `Can't drag subtasks to other priority.` | Can't drag checklist item to other priority. | 不能将检查事项拖动到其他优先级 |
| `List Activities` | List Activities | 清单动态 |
| `Show Check Item` | Show Checklist Item | 显示检查事项 |
| `Hide Check Item` | Hide Checklist Item | 隐藏检查事项 |
| `Reminder for Check Item` | Reminder for Checklist Items | 检查事项提醒 |
| `%@ commented on \"%@\": %@` | %@ commented on \"%@\": %@ | %@ 在任务 %@ 中添加了评论：%@ |
| `%@ replied to your comment on \"%@\": %@` | %@ replied to your comment on \"%@\": %@ | %@ 在任务 %@ 中回复了你：%@ |
| `Break the most difficult one into small sub-tasks` | Break the most difficult one into small sub-tasks | 确定今天最难的事情，把它拆分成子任务 |
| `More Check Items` | More Checklist Items | 更多检查事项 |
| `Check Item` | Checklist | 检查事项 |
| `No matching check items.` | No matching checklist item. | 没有符合条件的检查事项提醒。 |
| `No changes on the task activities yet.` | No changes on the task activities yet. | 还没有任务变更动态 |
| `Create reminder for check items.` | Create reminder for checklist items. | 为每一个检查事项设置提醒 |
| `Only unfinished tasks without subtasks can be converted` | Only unfinished tasks without subtasks can be converted | 只能转化没有子任务并且未完成的任务 |
| `Tasks with subtasks cannot be converted into notes` | Tasks with subtasks cannot be converted to notes | 有子任务，无法转化为笔记 |
| `Note_Activities` | Note Activities | 笔记动态 |

与底栏按钮的对应（推断）：`mdEditButton` ← 无独立 “Markdown” 文案（图标按钮 `md_edit`）；`commentButton` ← “Comments/评论”“Write a comment/添加评论”；`moreButton` ← “More/更多”；`mergeButton` ← “Merge/合并”；`deleteForeverButton` ← “Delete Forever/永久删除”；`tagButton` ← “Tag/标签”；`projectButton` ← 清单名（运行时数据，非固定文案）。

## 9. 附录：44 个 `_TtC8TickTick*` 自定义类

| # | 类 | 出现在 |
| --- | --- | --- |
| 1 | `_TtC8TickTick10TTScroller` | `TTSingleTaskDetailViewController`, `TTTaskDetailAddCommentView` |
| 2 | `_TtC8TickTick12TTScrollView` | `TTSingleTaskDetailViewController`, `TTTaskDetailAddCommentView` |
| 3 | `_TtC8TickTick22TTSingleTaskDetailView` | `TTSingleTaskDetailViewController` |
| 4 | `_TtC8TickTick28TTTaskDetailWindowController` | `TTTaskDetailWindowController` |
| 5 | `_TtC8TickTick16TTBlockEventView` | `TTDetailContainerViewController` |
| 6 | `_TtC8TickTick31TTDetailContainerViewController` | `TTDetailContainerViewController` |
| 7 | `_TtC8TickTick32TTTaskDetailHolderViewController` | `TTTaskDetailHolderViewController` |
| 8 | `_TtC8TickTick13TTThemeButton` | `TTTaskDetailTopView`, `TTTaskDetailTitleCell`, `TTTaskDetailBottomActionView`, `TTTaskDetailCheckItemCell`, `TTTaskDetailParentTaskCell`, `TTTaskDetailTagCollectionViewItem`, `TTTaskDetailNotionBlockCell`, `TTTaskDetailActivitiesCell`, `TTTaskDetailCommentCell`, `TTTaskDetailCommentExpandCell`, `TTTaskDetailAddCommentView` |
| 9 | `_TtC8TickTick17TTToolTipNSButton` | `TTTaskDetailTopView` |
| 10 | `_TtC8TickTick18TTToolTipImageView` | `TTTaskDetailTopView` |
| 11 | `_TtC8TickTick19TTTaskDetailTopView` | `TTTaskDetailTopView` |
| 12 | `_TtC8TickTick24TTTaskDetailProgressView` | `TTTaskDetailTopView` |
| 13 | `_TtC8TickTick7TTLabel` | `TTTaskDetailTopView`, `TTTaskDetailNotionBlockCell`, `TTTaskDetailNotionBlockShortTextView`, `TTTaskDetailNotionBlockLongTextView`, `TTTaskDetailNotionBlockOptionView`, `TTTaskDetailNotionBlockPeopleView`, `TTTaskDetailActivitiesCell`, `TTTaskDetailCommentCell`, `TTTaskDetailCommentHeaderView`, `TTTaskDetailAddCommentView`, `TTTaskDetailNoteInfoViewController` |
| 14 | `_TtC8TickTick21TTTaskDetailTitleCell` | `TTTaskDetailTitleCell` |
| 15 | `_TtC8TickTick23TTTaskDetailContentCell` | `TTTaskDetailContentCell` |
| 16 | `_TtC8TickTick27TTTaskDetailDescriptionCell` | `TTTaskDetailDescriptionCell` |
| 17 | `_TtC8TickTick22TTTaskDetailBottomView` | `TTTaskDetailBottomView` |
| 18 | `_TtC8TickTick28TTTaskDetailBottomActionView` | `TTTaskDetailBottomActionView` |
| 19 | `_TtC8TickTick23TTTaskDetailSubtaskCell` | `TTTaskDetailSubtaskCell` |
| 20 | `_TtC8TickTick20TTHoverableImageView` | `TTTaskDetailCheckItemCell` |
| 21 | `_TtC8TickTick25TTTaskDetailCheckItemCell` | `TTTaskDetailCheckItemCell` |
| 22 | `_TtC8TickTick26TTTaskDetailParentTaskCell` | `TTTaskDetailParentTaskCell`, `TTTaskDetailPresetTaskActionCell` |
| 23 | `_TtC8TickTick17DisableScrollView` | `TTTaskDetailTagCollectionCell` |
| 24 | `_TtC8TickTick29TTTaskDetailTagCollectionCell` | `TTTaskDetailTagCollectionCell` |
| 25 | `_TtC8TickTick29TTTaskDetailTagCollectionView` | `TTTaskDetailTagCollectionCell` |
| 26 | `_TtC8TickTick33TTTaskDetailTagCollectionViewItem` | `TTTaskDetailTagCollectionViewItem` |
| 27 | `_TtC8TickTick37TTTaskDetailTagCollectionViewItemView` | `TTTaskDetailTagCollectionViewItem` |
| 28 | `_TtC8TickTick42TTTaskDetailTagCollectionViewItemTextField` | `TTTaskDetailTagCollectionViewItem` |
| 29 | `_TtC8TickTick21TTTaskDetailSpaceCell` | `TTTaskDetailSpaceCell` |
| 30 | `_TtC8TickTick27TTTaskDetailNotionBlockCell` | `TTTaskDetailNotionBlockCell` |
| 31 | `_TtC8TickTick36TTTaskDetailNotionBlockShortTextView` | `TTTaskDetailNotionBlockShortTextView` |
| 32 | `_TtC8TickTick35TTTaskDetailNotionBlockLongTextView` | `TTTaskDetailNotionBlockLongTextView` |
| 33 | `_TtC8TickTick33TTTaskDetailNotionBlockOptionView` | `TTTaskDetailNotionBlockOptionView` |
| 34 | `_TtC8TickTick33TTTaskDetailNotionBlockPeopleView` | `TTTaskDetailNotionBlockPeopleView` |
| 35 | `_TtC8TickTick28TTTaskDetailFocusSummaryCell` | `TTTaskDetailFocusSummaryCell` |
| 36 | `_TtC8TickTick16TTHyperlinkLabel` | `TTTaskDetailPresetTaskActionCell` |
| 37 | `_TtC8TickTick32TTTaskDetailPresetTaskActionCell` | `TTTaskDetailPresetTaskActionCell` |
| 38 | `_TtC8TickTick26TTTaskDetailActivitiesCell` | `TTTaskDetailActivitiesCell` |
| 39 | `_TtC8TickTick23TTTaskDetailCommentCell` | `TTTaskDetailCommentCell` |
| 40 | `_TtC8TickTick29TTTaskDetailCommentExpandCell` | `TTTaskDetailCommentExpandCell` |
| 41 | `_TtC8TickTick29TTTaskDetailCommentHeaderView` | `TTTaskDetailCommentHeaderView` |
| 42 | `_TtC8TickTick20TTAddCommentTextView` | `TTTaskDetailAddCommentView` |
| 43 | `_TtC8TickTick26TTTaskDetailAddCommentView` | `TTTaskDetailAddCommentView` |
| 44 | `_TtC8TickTick34TTTaskDetailNoteInfoViewController` | `TTTaskDetailNoteInfoViewController` |

另有 3 个非 Swift mangling 的应用类：`JWCTableView`、`TTCollectionViewLeftAlignedFlowLayout`、`TTSingleTaskDetailViewController`。

## 10. 复现命令

```bash
cd docs/audits/ticktick-rea-2026-10-17
python3 scripts/parse_nibarchive.py --out ticktick-detail-nib-inventory.json
python3 scripts/validate_against_evidence.py
python3 scripts/build_report.py
```

---

*本报告由 `scripts/build_report.py` 从 JSON 生成；解析与校验脚本均为只读，未对 TickTick.app 做任何写操作。*
