# 本地任务详情编辑栏（TaskInspector）只读盘点

> 仓库：`workfollow-macos-native`，分支 `experiment/macos-native`。
> 盘点方式：逐文件 `read`（未运行 App、未跑测试）。凡源码未直接证明的，标「未确认」。
> 路径约定：正文路径相对 `macos-native/WorkFollow/`；测试路径相对 `macos-native/WorkFollowTests/`。

---

## 0. 一句话结论 + 代码规模

**一句话**：本地右栏不是"详情页 + 若干属性行"，而是一个**把标题、富文本正文、子任务树、专注摘要、6 个出口底栏串成一条纵向编辑流**的 SwiftUI 外壳，所有浮层都走自绘无箭头 `NSPanel`；正文是 AppKit `NSTextView`（TextKit 2），子任务是 `NSOutlineView`，标题是 `NSTextField` —— 三者都是原生控件，但**没有**滴答那种"标签 chips / 截止日期 chip / 选区工具条 / 块拖拽"这一层。

**代码规模**（本盘点实际读过）：

| 范围 | 文件数 | 行数 |
|---|---|---|
| `Features/Tasks/TaskInspector/`（含 `AppKit/` 4 个） | 26 | 2842 |
| `Features/Editor/` | 16 | 3941 |
| 强相关：`TaskWorkspaceModel` + `TaskActions` + `TaskDatePopoverV2` + `TaskTagPickerPopover` + `AnchoredPropertyPanel` | 5 | 4806 |
| 锁定编辑栏行为的测试（17 个文件，189 个 `test` 方法） | 17 | 4144 |
| 测试支撑 `InspectorPanelTestSupport.swift` | 1 | 247 |

**计数口径**（下文均按此）：

- **可见控件 20 个**（不含浮层内部）：顶栏 5 + 面包屑 1 + 标题 1 + 正文 2（编辑器、空行 `+`）+ 子任务区 3（完成框、标题/行内改名、添加行）+ 专注行 2 + 底栏 6。
- **正文格式工具条 15 个按钮** + 4 条分组竖线。
- **Slash 菜单 12 条目**（任务 profile；4 组、3 条细线）。
- **底栏 6 个出口**（常显 4，条件显示 2）；源码注释自称对齐"滴答 8 出口"。
- **浮层 11 类**：日期/重复、优先级、标签、清单菜单、父任务、关联任务、评论、动态、更多、专注子菜单、预计专注。

---

## 1. 顶栏（Header）

实现：`Features/Tasks/TaskInspector/TaskInspectorHeader.swift`，由 shell 在 `TaskInspectorShell.swift:102-114` 组装。

### 1.1 控件清单

> 下表 7 行中 #3（弃用标记）与 #4（竖线）是装饰，**可交互控件为 5 个**（#1、#2、#5、#6、#7）。

| # | 控件 | 实现 | 显示条件 | 行为 |
|---|---|---|---|---|
| 1 | 返回 | `AppKitIconButton(symbol: "chevron.left")` (`TaskInspectorHeader.swift:18-24`) | `showBack == true`（窄列 / 日历浮层） | `workspace.select(nil)`（`TaskInspectorShell.swift:104`） |
| 2 | 完成框 | `AppKitCompletionBox` 15pt，外套 24×34 命中区 (`TaskInspectorHeader.swift:25-47`) | 恒显 | `workspace.changeStatus(task)`：已关闭→`restore`，否则→`complete`（`TaskInspectorShell.swift:105`、`TaskWorkspaceModel.swift:1098-1100`） |
| 3 | 弃用标记 | 完成框 overlay `xmark` 10pt (`TaskInspectorHeader.swift:32-37`) | `task.isAbandoned` | 纯展示，不可点 |
| 4 | 竖分隔线 | `Rectangle` 1×20 (`TaskInspectorHeader.swift:48-52`) | 恒显 | 装饰 |
| 5 | 日期 chip | `AppKitScheduleChip`（图标+文案）`TaskInspectorShell.swift:400-412` | 恒显（空态文案「设置日期」） | 打开日期面板 `.schedule`；文案/颜色由 `TaskInspectorSchedulePresentation` 推导 |
| 6 | 重复按钮 | `AppKitIconButton(symbol: "repeat")` (`TaskInspectorHeader.swift:57-61`, 75-81) | `task.recurrence != .never || task.recurrenceRule != nil`（`TaskInspectorHeader.swift:12-14`） | 打开日期面板的「重复」子卡（`openSchedulePanel(.recurrence)`，`TaskInspectorShell.swift:106`） |
| 7 | 优先级旗 | `AppKitIconButton`，`flag`/`flag.fill` (`TaskInspectorShell.swift:694-711`) | 恒显，固定在 HStack 最右 | 切换自绘优先级浮层（`showPriorityMenu.toggle()`） |

- 日期 + 重复被包在**横向 `ScrollView`** 里（`TaskInspectorHeader.swift:53-66`），长日期时先压缩这一段，优先级永远贴右；`scheduleViewport` 锚点锁的就是这个视口。
- 顶栏**没有**提醒 chip：`InspectorRenderAnchor.reminder` 只在枚举里声明（`TaskInspectorRenderContract.swift:5`），全仓无使用；测试显式断言 `frames[.reminder] == nil`（`TaskInspectorShellContractTests.swift:30,40`）。

### 1.2 几何常量

`Features/Tasks/TaskInspector/TaskInspectorMetrics.swift`：

| 常量 | 值 | 行 |
|---|---|---|
| `headerHeight` | 62 | `:7` |
| `completionSize` | 15 | `:8` |
| `horizontalPadding` | 20（内容原点距左缘；距分栏线约 21） | `:13` |
| `headerDividerWidth/Height` | 1 / 20 | `:20-21` |
| `breadcrumbHeight` | 30 | `:22` |
| `childSectionTopGap` | 20 | `:31` |
| `footerHeight` | 48 | `:9` |
| `footerOverlayInset` | `footerHeight + 4` = 52 | `:32` |

- HStack `spacing: 8`（`TaskInspectorHeader.swift:17`）；返回按钮 24×34（`:22`）；完成框外层 24×34（`:41`）；优先级 34×34（`TaskInspectorShell.swift:700`）。
- 日期 chip 高度 = `WFMetrics.controlHeight`（34，`DesignSystem/Metrics.swift:113`）；chip 文字 13pt medium（`AppKit/AppKitHeaderControls.swift:81-84`）。
- 整个 Header 只在 `workspace.selectedTask != nil` 时出现；空态走 `TaskEmptyInspectorView`（`TaskInspectorShell.swift:34-50`，空态插画宽 176，`TaskInspectorShellContractTests.swift:86`）。

### 1.3 交互细节

- 完成状态由 `AppKitCompletionBox` 自绘：圆角 = 边长×0.25，已勾选填 `taskCompletedCheckbox`、勾色取内容底色；未勾选 `secondaryText` 描边（`AppKit/AppKitCompletionBox.swift:38-63`）。
- 已完成/已放弃的日期 chip 仍可点（文案颜色由 tone 决定：overdue→danger、scheduled→accent、empty→tertiaryText，`TaskInspectorShell.swift:414-422`）。
- 顶栏**不显示**截止日期（deadline）chip；`ScheduleField.deadline` 分支（`TaskInspectorShell.swift:809-821`）在 shell 里没有任何调用点，见 §9。

---

## 2. 标题

实现：`Features/Tasks/TaskInspector/AppKit/AppKitTaskTitleField.swift`，装配在 `TaskInspectorShell.swift:344-356`。

### 2.1 控件

- **原生 `NSTextField`**（`HeightTrackingTextField`，`:114-127`），无边框、透明背景、无 focus ring（`:24-31`）。
- 字体：`.systemFont(ofSize: 19, weight: .medium)`（`:32`）；与 `WFType.taskTitle` 同值但未复用常量（`DesignSystem/Typography.swift:9`）。
- 占位符：`task.parentID == nil ? "任务标题" : "准备做什么？"`（`TaskInspectorShell.swift:346`，`AppKitTaskTitleField.swift:34`）。
- 无障碍标签固定「任务标题」（`:38`）。
- 宽度：`setContentHuggingPriority(.defaultLow)` / `compressionResistance(.defaultLow)`（`:35-36`）；外层只给左右 `horizontalPadding`（20）与 `titleTopPadding`（10）（`TaskInspectorShell.swift:349-350`）。
- 每个任务强制重建：`.id(task.id)`（`TaskInspectorShell.swift:347`）。

### 2.2 回车 / Esc

- Return 与 Esc 都**只结束标题编辑**：`doCommand(by:)` 命中 `insertNewline` 或 `cancelOperation` → `isEditing = false` + `makeFirstResponder(nil)`，返回 `true` 吞掉事件（`AppKitTaskTitleField.swift:95-108`）。
- 因此标题里的 Esc **不会**触发 shell 的 `handleEscape()` 链（`TaskInspectorShell.swift:614-646`）；注释明确"换行不再由 Return 承担，长标题靠软换行显示"（`AppKitTaskTitleField.swift:97-98`）。
- Return **不会**把焦点交给正文：没有 `insertNewline` → `focusEditor` 的接力（全文件无此调用）。

### 2.3 自动高度

- `intrinsicContentSize` 用 `cell.cellSize(forBounds:height: .greatestFiniteMagnitude)` 量高后 `ceil`（`AppKitTaskTitleField.swift:115-121`）。
- `layout()` 里 `invalidateIntrinsicContentSize()`（`:123-126`）。
- 宽度变化时把 `preferredMaxLayoutWidth = bounds.width` 并失效 intrinsic size（`:46-50`），否则长标题裁切。
- 软换行：`usesSingleLineMode = false`、`lineBreakMode = .byWordWrapping`、`cell?.wraps = true`、`maximumNumberOfLines = 0`（`:27-31`）。

### 2.4 焦点流

- 焦点真值在 shell：`@State titleEditing`（`TaskInspectorShell.swift:15`），`AppKitTaskTitleField` 只负责"外部说编辑就聚焦、外部说结束就失焦"（`AppKitTaskTitleField.swift:54-70`）。
- 进入编辑：`controlTextDidBeginEditing` → `isEditing = true`（`:82-85`）；结束：`controlTextDidEndEditing` → `isEditing = false`（`:87-93`）。
- shell 侧 `onChange(of: titleEditing)` 把 `presentation.editingTarget` 设为 `.title` / `.none`（`TaskInspectorShell.swift:58-64`）。
- 正文侧对应 `.body`（`TaskInspectorShell.swift:655-661`）。
- **没有自动聚焦**：`titleEditing` 在 shell 里从未被置 `true`（仅 `:68`、`:639` 置 `false`），新建/切换任务后标题不自动进入编辑态。
- 标题 → 正文的 Tab / Return 接力：源码未实现；系统 key view loop 是否把 Tab 送到正文 **未确认**。

### 2.5 标题草稿

- `presentation.titleDraft` 为编辑缓冲，`stopEditing` 时由 `workspace.setTitle` 落库（`TaskInspectorShell.swift:351-353`；`TaskActions.swift:340-343` 会 trim）。
- 外部标题变化只在非编辑态回填（`TaskInspectorShell.swift:354-356`）。
- 换任务时 `synchronizeTitle` 重置草稿；同一任务不覆盖用户正在输入的草稿（`TaskInspectorPresentationState.swift:30-34`，测试 `TaskInspectorPresentationTests.swift:55-69`）。

---

## 3. 正文编辑器

实现：`Features/Editor/DocumentEditor.swift`（SwiftUI 包装）+ `NativeTextView.swift`（AppKit 编辑面），任务侧 profile 在 `Features/Tasks/TaskInspector/TaskDocumentProfile.swift`。

### 3.1 段落类型

- 模型：`DocumentBlockKind` = `.paragraph` / `.heading(Int)` / `.bullet` / `.ordered` / `.checklist(Bool)` / `.quote` / `.code` / `.divider`（token 映射见 `DocumentTextCodec.swift:10-34`）。
- UI 可达：正文、H1/H2/H3、无序、有序、检查项（未勾选/勾选由点击框翻转）、引用、代码块（仅 Markdown 围栏输入）、分割线（工具条按钮 / `---` 输入）。
- **H4–H6 只在 Markdown 输入期可达**（`MarkdownSyntax` 支持 1–6 级，`DocumentMarkdownInput.swift:202-205` 用临时 descriptor 构造），工具条/斜杠没有入口。
- 字阶（实测口径）：H1 18 / H2 16 / H3 14（H3–H6 同字号）、正文 14、标题 Bold（`DocumentTextCodec.swift:81-96`）；行盒 H 1.6×字号、列表/引用 18、正文 21（`:99-104`）。
- 行首沟槽统一 20pt（`DocumentEditorGeometry.decorationLane`，`DocumentEditor.swift:135`），靠 `headIndent` 留在文本容器内（`DocumentTextCodec.swift:105-124`）。

### 3.2 Markdown：输入期 + 渲染期

输入期（`DocumentMarkdownInput.swift`）：

- 入口：`insertText` 落字后调 `applyTypedMarkdownInput`（`NativeTextView.swift:112-116`，`DocumentMarkdownInput.swift:27-40`）。
- 四类触发：
  1. **空格结尾块级前缀**：`# `–`###### `、`* `/`- `/`+ `、`1. `、`- [ ] `/`- [x] `、`> `（文档 `:3-22`；实现 `:108-132`）。
  2. **整行分割线**：整行恰 3+ 个 `-`/`*`/`_`（`:46-71`、`MarkdownSyntax.isDividerLine`）。
  3. **整行围栏代码块**：整行恰 3+ 个反引号（行首最多 3 空格）（`:79-104`）。
  4. **闭合行内标记**：`**粗**`、`*斜*`、`~~删除线~~`、`~下划线~`、`::高亮::`、`` `码` ``、`[文字](url)`（`:221-250`）。
- 语义：标记串从正文**移除**（符号隐藏），按"设值"应用格式；与工具条共用 `applyFormat(lineStart:)` / `applyFormat(inlineRange:)`，一次撤销回到敲标记前（`:198-212`、`:252-268`）。
- 代码段/分割线内保持字面（`:125`、`:237`、`:329`）。

渲染期（2026-10-17 口径）：

- `reparseInlineMarkdown(paragraphs:registeringUndo:)` 对段落内**所有已闭合**行内标记做加性、幂等转换（`DocumentMarkdownInput.swift:283-383`）。
- 触发点：加载/切文档后异步整篇重解析（`DocumentEditorCoordinator.swift:116-127`，`registeringUndo: false`）；每次输入后重解析当前段落（`NativeTextView.swift:119-121`）。
- 覆盖"历史字面"、粘贴中段、编辑后揭示；代码段/分割线跳过。

### 3.3 格式工具条（15 个控件 + 4 条竖线）

实现：`Features/Editor/DocumentSelectionToolbar.swift:86-295`（`DocumentFormatToolbarView`），壳内入口 A 在底栏（`TaskInspectorShell.swift:521-529`）。

| 槽 | 控件 | 命令 ID / 动作 | 激活态 |
|---|---|---|---|
| 1 | `H`（字面字母 16pt） | 打开标题选择器（正文/H1/H2/H3，宽 150）`DocumentSelectionToolbar.swift:113-116` | 当前段是标题 |
| 2 | 粗体 | `format.bold` (`:117`) | `style.has(.bold)` |
| 3 | `A`（黄色高亮底） | `format.highlight` (`:119-128`) | `has(.highlight)` |
| — | 竖线 1 | `:129` | — |
| 4 | 检查项 | `format.checklist` (`:130`) | block == checklist |
| 5 | 无序列表 | `format.bullet` (`:131`) | block == bullet |
| 6 | 有序列表 | `format.ordered` (`:132`) | block == ordered |
| — | 竖线 2 | `:133` | — |
| 7 | 斜体 | `format.italic` (`:134`) | `has(.italic)` |
| 8 | 下划线 | `format.underline` (`:135`) | `has(.underline)` |
| 9 | 删除线 | `format.strikethrough` (`:136`) | `has(.strikethrough)` |
| 10 | 分割线 | `handle.insertDivider()` (`:137-140`)，自绘 glyph | 恒 false |
| 11 | 插入当前时间 | 打开时间选择器（宽 222，4 个格式）`:141-144` | picker 打开时 |
| — | 竖线 3 | `:145` | — |
| 12 | 链接 | `handle.editLink()` (`:146-149`)，`NSAlert` 输入 URL | 恒 false |
| 13 | 行内代码 | `format.inlineCode` (`:150`) | `has(.code)` |
| 14 | 引用 | `format.quote` (`:151`) | block == quote |
| — | 竖线 4 | `:152` | — |
| 15 | 上传附件 | `handle.insertAttachment()` (`:153-156`) | 恒 false |

- 顺序与注释"4 条竖线"一致（`:108-110`）。
- 几何：按钮 26×28（`DocumentFormatToolbarMetrics.controlWidth/Height`，`:8-9`），条高 38（`:10`），圆角 8（`:11`），最大宽 444（`:91`），图标 14（`:7`），高亮填充 `systemYellow 0.45`（`:15`），阴影 10/3（`:16-17`）；竖线 1×17、左右各 4/5（`:199-205`）。
- 激活态底色 `accentFaint` + 强调色图标；悬停 `listRowHover`（`ToolbarButton`，`:300-324`）。
- 悬停提示是**自绘卡**（系统 `.help` 在底部没位置）：11pt medium、高 22、位于控件上方 6pt（样式 `DocumentToolbarTooltip.swift:36-42,66-82`；定位 `DocumentSelectionToolbar.swift:207-216`）。
- 两个上弹小面板：标题 150 宽、时间 222 宽，行高 36、上下内边距 6（`DocumentToolbarTooltip.swift:108-163`；卡面 `:166-189`）。
- 选择器定位：标题贴按钮左缘、时间贴按钮右缘，再夹进工具条（`:158-162`）；指针离开工具条与面板即收起（`DocumentSelectionToolbar.swift:268-271`）。
- 工具条内部还有一个 `PopupEscapeRouter(depth: 2)`（`:192-196`），Esc 只关小面板。

### 3.4 Slash 菜单（12 条目）

- 触发：输入 `/` 或 `、`，且位于文首或空白之后、非选区覆盖、非输入法组合态（例外：`、` 允许 IME 提交）（`NativeTextView.swift:99-142`）。
- 面板：独立 `NSPanel`（borderless、nonactivating），跟随滚动/窗口移动缩放（`SlashCommandPanel.swift:52-112`、`:114-137`）；宽 160、行高 34、圆角 16（`SlashMenuMetrics`，`:6-20`）。
- 高度算法：行×34 + 分组细线×9 + 上下 8（`:21-30`）；整个任务菜单 12 行 = 443（`DocumentProfileTests.swift:17`）。
- 键盘：↑/↓ 移动，Return 执行，Esc 关闭但**保留查询文本**（`NativeTextView.swift:432-446`，`SlashSessionTests.swift:378`）；指针悬停即选中，与键盘共用一根高亮条（`SlashCommandPanel.swift:151-158`）。
- 条目（任务 profile，顺序被测试锁死，`DocumentProfileTests.swift:336-353`）：

| 组 | 条目 | id / 行为 |
|---|---|---|
| 标题 | 一级标题 / 二级标题 / 三级标题 | `format.heading1..3` → 按行设值 |
| 列表 | 无序列表 / 有序列表 / 检查项 | `format.bullet` / `format.ordered` / `format.checklist` |
| 格式 | 引用 | `format.quote` |
| 格式 | 水平分割线 | `shared.divider`（插入附件式分割线） |
| 插入 | 附件 | `shared.attachment`（`NSOpenPanel`） |
| 插入 | 子任务 | `task.child` → `host.createChild()`，即 `requestChildTitleEditor` |
| 插入 | 标签 | `task.tags` → 打开标签面板 |
| 插入 | 关联任务/笔记 | `task.relation` → 打开关联选择器 |

- 顺序/分组由 `TaskDocumentProfile.make` 的 `slashCommandOverride` 决定：`compactDocumentCommands(formatIDs:) + commands`（`TaskDocumentProfile.swift:11-24`；`DocumentProfile.swift:89-118`）。
- 分组细线出现在组变化处（`SlashCommandList`，`SlashCommandPanel.swift:194-199`）。
- 空行左侧 `+` 也复用同一面板：零长 session、trigger 为 `""`（`NativeTextView.swift:354-378`）。

### 3.5 块装饰（无拖拽手柄、无折叠）

实现：`Features/Editor/DocumentBlockDecorations.swift`（`drawBlockDecorations`，`:11-48`）。

| 装饰 | 出现条件 | 几何/实现 |
|---|---|---|
| 无序圆点 | `.bullet` 段落 | 半径 2.6，强调色，与文字左对齐（`:50-65`） |
| 有序编号 | `.ordered` 段落 | 14pt 强调色，序号向前数连续 ordered 段（`:66-74`，`DocumentTextCodec.swift:61-75`） |
| 检查框 | `.checklist` 段落 | 12.96pt，圆角 4.05，边宽 1.053，勾宽 1.62（`:75-109`），可点翻转（`NativeTextView.swift:312-350`） |
| 引用竖线 | `.quote` 段落 | 2pt `borderStrong`，纵跨整段并桥接相邻引用段（`:208-229`） |
| 标题角标 `H1/H2/H3` | **仅光标所在标题行** | 9–10pt 三级灰（`:196-206`） |
| 空行 `+` | 光标所在空段/文末空段 | 13pt 三级灰（`:181-190`） |
| 文末列表标记 | 文末空段 + 待定/模型为列表 | 常驻补画（`:114-123`） |
| 分割线 | `.divider` 块 | `NSTextAttachment` + `DocumentDividerCell`（`DocumentTextCodec.swift:151-155,231-238`） |

- 标记 x 坐标统一走 `DocumentEditorGeometry.decorationMarkerX(visibleMinX:)`，下限 4pt（`DocumentEditor.swift:139-150`）；任务壳传入 `decorationLane - documentLeadingPadding = 20 - 15 = 5`（`TaskInspectorShell.swift:674`），测试锁定"距 pane 左缘 5.0"（`TaskInspectorHierarchyRenderTests.swift:37-43`）。
- **没有**块级拖拽手柄、没有块折叠、没有块菜单按钮（`grep onDrag|draggable|DragGesture|拖拽|折叠` 在 `Features/Editor/` 下无命中）。

### 3.6 选区工具条

- 组件存在：`DocumentSelectionToolbarView`（`DocumentSelectionToolbar.swift:26-80`），内容 = 宿主动作 + 6 个内联格式（粗/斜/下划线/删除线/高亮/行内代码，`EditorCommandCatalog.selectionFormatIDs`，`DocumentFormatCommand.swift:53-56`）+ 链接。
- 浮于选区上方 6pt，超出屏幕翻到下方；`NSPanel` 子窗口（`NativeTextView.swift:508-542`）；Esc/执行动作后压住直到选区变化（`:474-506`）。
- **任务正文不启用**：`TaskDocumentProfile.make` 传 `selectionToolbarEnabled: false`（`TaskDocumentProfile.swift:21-23`），`compactSlash` 也让 `supportsSelectionToolbar` 为 false（`DocumentProfile.swift:58-66`）；测试断言 `supportsSelectionToolbar == false`、`selectionActions.isEmpty`（`DocumentProfileTests.swift:62-63`）。
- 即：**任务详情里没有选区浮条**（笔记里有）。

### 3.7 粘贴 / 撤销 / 图片 / 附件

- **粘贴**：先尝试图片；纯文本走 `insertText`（从而复用 Markdown 输入期与 Slash 触发）；富文本按纯文本粘贴（`NativeTextView.swift:570-580`）。
- **图片**：剪贴板位图（且不是 Finder 文件）→ 等比缩到最长边 ≤1600 → `data:image/png;base64,...` 存进 `NativeAttachment.storedName`，作为附件 run 插入（`:583-625`）；渲染时识别 data URL 画真图，上限 480×320（`DocumentTextCodec.swift:160-169,240-263`）。
  - `NativeDocument` **没有独立图片块类型**，图片寄居在附件 run 里（注释 `NativeTextView.swift:584-585`）。
- **附件**：`insertDocumentAttachment` 走 `NativeAttachmentFiles.choose`，插入 `📎 name` 附件 run + 空格（`DocumentContentActions.swift:80-111`）；双击附件打开文件（`DocumentEditorCoordinator.swift:89-96`）。
- **撤销**：每个编辑器实例独享 `UndoManager`（`NativeTextView.swift:12-16`），文档重绑时清空（`:70-82`）；⌘Z 优先路由给当前文本响应者（`App/AppCommands.swift:101-121`）；撤销后重发 `didChangeText` 把文档重新提交（`NativeTextView.swift:640-667`）。
- **查找**：`usesFindBar = true`（`:722`），⌘F 打开系统 find bar；find bar 的 Esc 先关 find bar（`:754-784`）。

### 3.8 空正文占位

- `task.document.isEmpty` 时在编辑器上叠 `Text("添加描述…")`，14pt 三级灰，`padding(.top, 4)/.leading, 5)`，`allowsHitTesting(false)`（`TaskInspectorShell.swift:677-684`）。
- `isEmpty` 口径 = 单块且纯文本为空（`Domain/Document/NativeDocument.swift:63`）。
- 编辑器内容自适应高度：最小 48pt（`DocumentEditor.swift:280`），`sizeThatFits` 用 TextKit usageBounds 算高（`:265-284`）；正文不自己滚动（`contentSized`，`:226-231`）。

---

## 4. 子任务区

实现：`Features/Tasks/TaskInspector/AppKit/AppKitSubtaskOutlineView.swift`，装配 `TaskInspectorShell.swift:424-461`。

### 4.1 结构

- **`NSOutlineView` 直接作为宿主 `ScrollView` 的普通内容**，不套 `NSScrollView`（注释 `:28-30`）；行高固定 40（`TaskInspectorMetrics.childRowMinHeight`，`:160-162`）。
- 单列 `NSTableColumn("subtask")`、`headerView = nil`、`rowSizeStyle = .custom`、`indentationPerLevel = 16`、单行选择（`:75-92`）。
- 数据源：全量 `allTasks` 按 `parentID` 建 `childrenByParent` 并按 `childOrder` 排序（`:99-106`）；首次/数据变化 `reloadData` 后 `expandAll`（`:108-119`）。
- 只有"当前任务有可见子任务"才出现（shell 侧 `editorChildren` 过滤 `deletedAt/skippedAt/convertedNoteID`，`TaskInspectorShell.swift:360-366,560-564`）。
- 默认全展开；用户可手动折叠，但**折叠态不持久化**（无 `collapsed` 存储）。
- 高度：`countAllDescendants × 40` 一次性 `frame(height:)`（`TaskInspectorShell.swift:464-470,456`），不内部滚动。

### 4.2 行内组件（`SubtaskRowView`）

| 组件 | 细节 | 行 |
|---|---|---|
| 完成框 | `CompletionBoxView`，尺寸 `childCompletionSize = 19`（`TaskInspectorMetrics.swift:28`）；透明 `NSButton` 盖在上面 30pt 宽接收点击 | `:230,239-246,340-343` |
| 标题 | `SubtaskTitleField`，14pt medium，单行截断；非编辑态 `hitTest` 返回 nil，让点击穿透到 outline 手势 | `:216-221,247-255` |
| 日期 | `NSTextField(labelWithString:)` 12pt 次级灰，宽 90，无值则隐藏 | `:232,257-260,360-367` |
| 悬停 | `NSTrackingArea` + `draw` 自绘圆角 5 底：常态 4% 墨色、悬停 7% | `:271-300` |

- **常态也有 4% 灰底**（不是仅 hover），`configure` 复用时重置 `hovering`（`:302-307`）。
- 完成框点击：`onComplete` → `workspace.changeStatus(child)`（`TaskInspectorShell.swift:437-439`）。
- 单击/双击：都走 `onOpen` → `workspace.select(id)`（`AppKitSubtaskOutlineView.swift:88,191-202`）；**双击不是"改名"**，改名只能由"添加子任务"自动触发或逻辑调用 `beginEditing`。
- 行内改名：`beginEditing()` 打开可编辑 + 全选（`:326-338`）；`controlTextDidEndEditing` → trim → `onRename` → `workspace.setTitle`（`:206-211`，`TaskInspectorShell.swift:443-444`）。
- **续加**：若本次行内编辑来自"添加子任务"，提交且有标题后再次 `requestChildTitleEditor(parentID)`，回车连续加子任务（`TaskInspectorShell.swift:445-453`）。
- 完成后标题变三级灰（`:311-312`）。
- 添加行：`plus` 18pt + "添加子任务" 14pt medium、强调色、最小高 40、悬停 `accentFaint`、左右外扩 8pt 让底色比内容宽（`TaskInspectorShell.swift:474-498`）。
- 子任务区顶部间距 20（`childSectionTopGap`），行与添加行间距 6（`childAddGap`）（`TaskInspectorShell.swift:425,365`）。
- 子任务自身详情显示**面包屑**（父任务标题 + `chevron.right`，高 30，`TaskInspectorHeader.swift:84-102`），可点回父任务；测试锁定面包屑在标题之前（`TaskInspectorShellContractTests.swift:48-59`）。

### 4.3 缺口

- 行内只有完成框/标题/日期；**没有**优先级、标签、备注、删除、拖拽排序、缩进调整入口。
- 没有"子任务计数/进度"显示。
- `childRowRadius` / `childRowHorizontalPadding` / `childRowGap` 三个常量已声明但**全仓无使用**（`TaskInspectorMetrics.swift:25-30`），是 SwiftUI 行改 AppKit 行后的残留。

---

## 5. 专注摘要行

- 显示条件（`TaskInspectorShell.swift:369-373,380-384`）：`task.focusEstimate != nil` **或** `focusStore.taskTotalActiveSeconds(taskID:) > 0`。注释明确"滴答右栏对普通任务不显示专注摘要行（2026-10-17 同窗口实测）"。
- 内容（`TaskFocusSummaryRow` → `TaskFocusEstimateControl`，`TaskFocusEstimateEditor.swift:57-103`）：
  - `timer` 图标（三级灰）+ 按钮文案：`预计 N 分钟` / `预计 N 个番茄` / `设置预计专注`；
  - 有实际记录时追加 `·` + `实际 N 分钟` 按钮，点击 `focusStore.showRecords(taskID:)` + 跳专注页（`TaskInspectorShell.swift:388-393`）；
  - 布局：水平 padding 20、顶部 12（`:369-373`）；字号 `WFType.supporting` 12。
- 没有 `FocusStore` 环境（独立面板/测试）时退化为 `TaskFocusEstimateControl`（`TaskInspectorShell.swift:394-396`）。
- 「设置预计专注」入口在「更多」菜单（`:253`），编辑器宽 280：分段"时长/番茄数" + 数字输入 + Stepper + 清除/取消/保存（`TaskFocusEstimateEditor.swift:17-43`）。

---

## 6. 底栏

实现：`TaskInspectorShell.swift:502-545`。注释自称"滴答 8 出口运行态"（`:500`）。

### 6.1 出口逐项（源码称「8 出口」，本地实际 6 个槽位）

| # | 出口 | 显示条件 | 实现 | 点击行为 |
|---|---|---|---|---|
| 1 | 清单 | 恒显 | 父任务：`Label(list.name, "tray")` 静态、`help("子任务跟随父任务清单")`；顶层：SwiftUI `Menu`（`TaskInspectorShell.swift:743-777`） | 切清单（`workspace.moveToList`）→「新清单…」弹 alert（`:83-92`） |
| 2 | 标签 | `!task.tags.isEmpty`（`:508`） | `AppKitIconButton("tag")`，34×34（`:548-553`） | 打开标签面板 |
| 3 | 合并子任务 | 有子任务（`:512-519`） | `AppKitIconButton("arrow.triangle.merge")` | `workspace.mergeChildrenIntoDocument`：子任务标题按行并入正文后软删子任务（`TaskActions.swift:891-915`） |
| 4 | 格式 A | 恒显 | `AppKitTextButton(title: "A", 15pt)`，28×28（`:521-529`） | 切换格式工具条；**打开时把焦点交给正文**（`editorHandle.focusEditor()`） |
| 5 | 评论 | 恒显 | `AppKitIconButton("bubble.left")`（`:531`） | 打开评论面板 |
| 6 | 更多 | 恒显 | `moreMenu(task)`（`:116-156,533`） | 打开更多面板（宽 208、高 490、向上弹） |

- 出口图标统一 `WFMetrics.controlHeight = 34` 命中区、14pt 图标、`inspectorSecondary` 次级墨色（`:547-553`）。
- 底栏本身高 48、水平 padding 20、元素间距 `WFSpace.xs`（`:536-538`）。
- 与"8 出口"的差额：本地实际只有 6 槽（常显 4：清单/A/评论/更多）。源码与测试都没有补足 8 个的实现；**具体缺哪两个未确认**（滴答侧需另行核对）。

### 6.2 格式工具条浮层定位

- 作为底栏 `.overlay(alignment: .bottom)`：水平 padding 16、距底 `footerOverlayInset = 52`（`TaskInspectorShell.swift:539-544`；`TaskInspectorMetrics.swift:32`）。
- 工具条自身：最大宽 444、高 38、圆角 8、浮层底色 `WFColors.overlay` + 描边 + 阴影（`DocumentSelectionToolbar.swift:163-174`）；窄栏时内部横向滚动（`:107`）。
- Esc 链里格式工具条优先于"退回列表"关闭（`TaskInspectorShell.swift:624-627`）。

---

## 7. 弹出面板（11 类）

呈现壳：`Infrastructure/Presentation/AnchoredPropertyPanel.swift` —— 全部是 borderless `NSPanel` 子窗口（**无箭头、不遮罩**），宽由调用点给定、向上优先、`PopupEscapeRouter(depth:)` 处理 Esc，owner 移动/缩放时跟随（`:73-120`）。

### 7.1 日期 / 重复面板

- **注意**：`TaskInspector/TaskDatePopover.swift` 只有 39 行，内容是一个 `TaskDateButton` 组件，且**全仓无调用点**（死代码）。真正的面板是 `Features/Tasks/Schedule/TaskDatePopoverV2.swift`（1379 行），壳里 `TaskInspectorShell.swift:109-113,407-411` 调用。
- 尺寸：主面板固定宽 260（`ScheduleMetrics.panelWidth`，`Features/Tasks/Schedule/ScheduleMetrics.swift:8`）；高 506，重复时 +30，时间段页 +54，再夹到 `min(..., max(440, 屏幕高-32))`（`Features/Tasks/Schedule/SchedulePopoverContainer.swift:3-14,39`）。
- 结构（`TaskDatePopoverV2.swift:179-248`）：
  - 顶部 pill 分段「日期 / 时间段」（deadline 模式隐藏，`:1145-1175`）；
  - 快捷行：今天 / 明天 / 下周(+7) / 周末（`:1222-1259`）；
  - 自绘月历 `LunarMonthGridView`：年月头 + 上/今天/下 + 周行 + 6×7 格；选中强调圆 26pt、今天描边、区间中段高亮、节日 6pt（`TaskInspector/LunarMonthGridView.swift:30-119`）；叠加未来 occurrence 圆点 / 班休徽标 / 法定节日（`TaskDatePopoverV2.swift:1305-1379`）；
  - 属性行（`:252-306`）：时间、结束时间（仅时间段）、提醒、重复、重复结束；行高 30、选项行 34；
  - 子卡：时间/结束时间 = 48 个半小时选项；提醒 = 当天/提前1/2/3天/1周 + 自定义提前量 + 取消/确定；重复 = 每天/周/月/年 + 工作日/节假日/农历/艾宾浩斯/自定义 + 重复结束（永不/按日期/按次数）（`:410-941`）；
  - 底部「清除 / 确定」（`:1190-1220`），确定有默认回车键（`:1216`）。
- 语义：**草稿态**，确定才写任务；清除应用 clear plan；Esc / 点外丢弃（注释 `:60-67`；测试 20 轮断言取消不改 schedule，`TaskFocusSubmenuTests.swift:97-128`）。
- 重复任务确定时先弹「修改重复任务」范围对话框（仅本次/之后全部…，`TaskDatePopoverV2.swift:163-174`）。
- 从顶栏「重复」进入时 `initialPage: .recurrence`，直接展开重复子卡（`TaskInspectorShell.swift:110-112`；`TaskDatePopoverV2.swift:144-146`）。
- deadline 模式（`deadline: true`）会隐藏分段与属性行；但该模式**当前不可达**（见 §9）。

### 7.2 优先级浮层

- 触发：顶栏旗标按钮 toggle（`TaskInspectorShell.swift:694-711`）；`AnchoredPropertyPanel` 宽 176、`.verticalInOwner`、`focusPolicy: .preservePresenter`、标题「优先级」。
- 内容：`TaskPriority.menuOrder` = 高→中→低→无（`Domain/Task/Task.swift:6-8`），四行「彩色旗 + 文案」，行高 32，**无当前值标记**（注释实测 `TaskInspectorShell.swift:691-693`）；颜色 无=次级灰 / 低=强调蓝 / 中=橙 / 高=红（`:799-806`）。
- Esc 由 `PopupEscapeRouter(depth: 2)` 关闭（`:740`）。

### 7.3 标签面板

- `TaskTagPickerPopover`（`Features/Tasks/TaskList/TaskTagPickerPopover.swift`），264×320（`:85`）。
- 组件：搜索框（自动聚焦，Esc 取消，`:25-34,87-91`）、匹配标签列表（`tag` 图标 + 勾选切换）、「创建「…」」、取消/确定（`:76-83`）。
- 确定 → `workspace.setTags(task.id, tags)`（`TaskInspectorShell.swift:186-192`）；`setTags` 会 trim、去 `#`、去重（`TaskActions.swift:423-434`）。
- 注意：底栏标签出口只在**已有标签**时出现，但面板本身可创建新标签。

### 7.4 清单菜单

- 顶层任务：SwiftUI `Menu`（`.menuStyle(.borderlessButton)`、隐藏指示器、`fixedSize`），列出 `workspace.availableListNames`，当前清单打勾，末尾「新清单…」（`TaskInspectorShell.swift:751-775`）。
- 不可移动时禁用：`.disabled(!workspace.canMoveToList(task.id))`；`canMoveToList` 要求无父任务且未删除（`TaskWorkspaceModel.swift:1126-1129`）。
- 子任务：不显示菜单，改为静态 Label + `help("子任务跟随父任务清单")`（`:745-749`）。
- 这是 inspector 里**唯一仍用系统 NSMenu** 的出口（其余为自绘浮层）。

### 7.5 父任务选择

- `TaskParentPicker`（`TaskInspector/TaskParentPicker.swift`），280×340（`:126`）。
- 组件：标题「关联主任务」、搜索框（自动聚焦）、候选列表（标题 + 清单名、行高 ≥42、选中打勾）、「没有可关联的主任务」空态、错误提示「任务状态已变化，请重新选择」、取消/确定（`:76-135`）。
- 候选过滤：排除自身、排除 `TaskParentPolicy.canAssign` 判不可指派者、排除归档清单、按标题排序（`:24-43,71-74`）。
- 确定 → `workspace.assignParent`（批量变体存在但 inspector 走单条，`:110-125`）。
- Esc：`onExitCommand` + `onKeyPress(.escape)` 双保险（`:134-135`）。

### 7.6 关联任务

- `TaskRelationPicker`（`TaskInspector/TaskRelationPicker.swift`），320×300（`:67`）。
- 组件：搜索框、任务/笔记列表（符号 + 标题 + 副标题 + 笔记自身打勾）、空态「没有匹配的任务或笔记」、失败文案「无法插入关联，请返回正文后重试」、Esc 取消（`:39-72`）。
- 选择 → `TaskRelationSelection.apply`：校验文档身份后把引用作为链接 run 插入正文；笔记还会同步 `sourceNoteID`，并与正文替换共用一次撤销（`TaskRelationSelection.swift:6-29`）。
- 入口：Slash「关联任务/笔记」以及（`TaskInspectorShell.swift:666-669` 的 host action）。

### 7.7 评论

- `TaskCommentPanel`（`TaskInspector/TaskCommentPanel.swift`），320×400（`:69`）。
- 组件：标题「评论」+ 关闭 ×、评论列表（正文 + 年/月/日/时/分）、空态「暂无评论 / 写下第一条评论吧。」、底部输入框「添加评论…」+ 发送按钮（空白禁用）、回车提交（`:11-83`）。
- 存储：`TaskCommentStore`，按创建时间正序；测试锁 append 顺序/按任务隔离/trim/删除/持久化（`TaskCommentStoreTests.swift:6-60`）。

### 7.8 动态

- `TaskActivityPanel`（`TaskInspector/TaskActivityPanel.swift`），高 396（`:59`）。
- 组件：标题「任务动态」+ 关闭 ×、事件列表（标题 + 详情 + 时间）、空态「暂无任务动态 / 仅记录启用后的任务变更，不补造历史记录。」、分页「加载更多」/加载中 spinner/错误重试（`TaskActivityPageModel.swift:41-57`）。
- 每页 50（`TaskActivityPageModel.swift:15`）。

### 7.9 更多菜单

- 触发：`ellipsis` 按钮（`TaskInspectorShell.swift:116-156`）；`AnchoredPropertyPanel` 宽 208、向上、标题「任务详情操作」；内容固定 `frame(width: 208, height: 490)` + 内部 `ScrollView`（`:227-276`）。
- 15 行 + 1 条分隔线（顺序被 `TaskMoreMenuRoundTwoTests.swift:13-31` 逐行锁死）：

| # | 文案 | symbol | 行为 | 禁用条件 |
|---|---|---|---|---|
| 1 | 添加子任务 | `list.bullet.indent` | `requestChildTitleEditor` | — |
| 2 | 关联主任务 | `rectangle.3.group` | 打开父任务面板 | 已关闭 / 跳过 / 已转笔记 / **已有子任务**（`:236-238`） |
| 3 | 置顶 / 取消置顶 | `pin` | `setPinned(!isPinned)` | — |
| 4 | 放弃 / 恢复 | `xmark.square` | `abandon` / `restore` | `status == .completed`（`:246`） |
| 5 | 标签 | `tag` | 打开标签面板 | — |
| 6 | 上传附件 | `paperclip` | `NativeAttachmentFiles.choose` → `setAttachments` | — |
| 7 | 开始专注 › | `circle.inset.filled` | 悬停/点击开子菜单（`:278-313`） | 专注会话忙碌时点击失败弹「无法开始专注」（`:93-97`） |
| 8 | 设置预计专注 | `timer` | 打开预计专注编辑器 | — |
| — | 分隔线 | — | — | — |
| 9 | 任务动态 | `list.bullet.rectangle` | 打开动态面板 | — |
| 10 | 保存为模板 | `doc.badge.plus` | 名称对话框 → `TemplateStore.save`（可覆盖） | — |
| 11 | 创建副本 | `square.on.square` | `workspace.duplicate` | — |
| 12 | 复制链接 | `link` | `TaskLinkClipboard.copy` + 成功/失败反馈 | — |
| 13 | 打开便签 | `note` | `StickyNoteWindowController.open(taskID:)` | — |
| 14 | 转换为笔记 | `doc.text` | `environment.convertTaskToNote` | — |
| 15 | 删除 | `trash` | `workspace.delete` | — |

- 所有行统一普通文本色，**不用 destructive 红**（测试锁定 `TaskMoreMenuRoundTwoTests.swift:48-69`）。
- 行高 32、水平 padding 8、字号 `WFType.menu` 14（`TaskInspectorShell.swift:315-333`）。
- 测试显式确认**不存在**：其他操作、更多属性、截止日期、跳过本周期、打印（`TaskMoreMenuRoundTwoTests.swift:42-45`）。

### 7.10 专注子菜单 / 7.11 预计专注

- 子菜单：宽 176、`placement: .submenu`、两行「开始番茄专注」「开始正计时」，行高 32（`TaskFocusSubmenu.swift:3-23`；`TaskInspectorShell.swift:297-312`）。与主面板保持父子窗口关系，打开子菜单不改 More 尺寸（测试 `TaskFocusSubmenuTests.swift:60-76`）。
- 预计专注编辑器：宽 280（`TaskInspectorShell.swift:142-155`、`TaskFocusEstimateEditor.swift:17-43`）：标题、时长/番茄数分段、数字框 + Stepper、「清除 / 取消 / 保存」，保存禁用条件 `count < 1`。

### 7.12 新建清单 alert（补充）

- `alert("移动到新清单")`：TextField「清单名称」+ 取消/移动；名称为空禁用「移动」（`TaskInspectorShell.swift:83-92`）。

---

## 8. 键盘与焦点

### 8.1 Esc 链

两层：编辑器内部路由 → shell 路由。

`DocumentEditorEscapeRoute.resolve` 的优先级（`Features/Editor/DocumentEditorState.swift:3-15`，`NativeTextView.cancelOperation` 消费，`NativeTextView.swift:754-784`）：

1. 输入法组合中 → 交系统；
2. Slash 面板开着 → 关面板（保留查询）；
3. 选区工具条开着 → 关浮条；
4. find bar 开着 → 关 find bar；
5. 否则交宿主 `onEscape`。

宿主 `TaskInspectorShell.handleEscape()`（`TaskInspectorShell.swift:614-646`）：

1. 专注子菜单 → `dismissSubmenu`；
2. 任意底栏浮层 / deadline → `dismissFooterPopover`；
3. 格式工具条 → 关工具条；
4. 有 `onRequestClose`（日历/四象限浮层）→ 关浮层；
5. `presentation.handleEscape(isNarrow: showBack)`：活动 popover → 结束编辑（title 时同步 `titleEditing = false`）→ 窄列退回列表 / 宽列保持（`TaskInspectorPresentationState.swift:36-46`）。

- 标题字段的 Esc 在字段内部被吞掉（见 §2.2），**不进入**这条链。
- 浮层内部（标签/关联/父任务/更多/日期）各有 `PopupEscapeRouter` / `ScheduleEscapeRouter`，层级式关闭（`TaskInspectorShell.swift:208-210`、`TaskRelationPicker.swift:70-71`、`TaskParentPicker.swift:134-135`）。
- Esc 行为被测试大量锁定：popover 先于编辑、编辑先于窄列返回（`TaskInspectorPresentationTests.swift:5-53`）。

### 8.2 ⌘ 快捷键（编辑栏范围实际注册的）

编辑栏自身**没有注册任何 ⌘ 组合**；能影响它的都在 App 级 `App/AppCommands.swift`：

| 快捷键 | 动作 | 位置 |
|---|---|---|
| ⌘Z / ⌘⇧Z | 撤销 / 重做：文本响应者优先用自己的 UndoManager，否则走工作区 | `AppCommands.swift:14-21,101-121` |
| ⌘F | 查找正文（系统 find bar） | `:22-30` |
| ⌘N | 新建任务 | `:10-13` |
| ⌘K | 快速打开 | `:31-33` |
| ⌘1/2/4/5/6/9 | 今天/收集箱/日历/笔记/四象限/最近7天 | `:82-94` |
| ⌘\ | 显示/隐藏侧栏 | `:95-97` |

- **没有** ⌘B / ⌘I / ⌘U / ⌘⇧X / ⌘⇧H 等格式快捷键；格式只能点工具条或输入 Markdown。
- 日期面板的「确定」绑 `.keyboardShortcut(.defaultAction)`（回车），预计专注的保存/取消绑 default/cancel（`TaskFocusEstimateEditor.swift:34-38`）。
- 标题 Return/Esc、Slash ↑↓/Return/Esc 见前文。

### 8.3 焦点流转

- 标题与正文各自把"是否编辑"上报给 `presentation.editingTarget`（`TaskInspectorShell.swift:58-64,655-661`）。
- 选中任务变化时：`presentation.synchronizeTitle`、`titleEditing = false`、`editingTarget = .none`、关闭所有 popover、关格式工具条（`TaskInspectorShell.swift:65-73`）。
- 文档切换前先 flush 旧文档输入法组合：`selectionWillChange` → `prepareForDocumentChange`（`TaskInspectorShell.swift:54-57`；`DocumentEditor.swift:46-50`；`DocumentEditorCoordinator.swift:98-114`）。
- 点正文：`NativeTextView.mouseDown` 自己抢 first responder，避免焦点留在 SwiftUI 字段（`NativeTextView.swift:345-349`，测试 `DocumentEditorHitTargetTests.swift:42-60`）。
- 点 checkbox 标记：先聚焦再翻转（`NativeTextView.swift:324-343`）。
- 打开格式工具条时焦点回正文（`TaskInspectorShell.swift:524-527`）。
- **没有**标题↔正文的显式接力（Return/Tab），见 §2.2/§2.4。

### 8.4 窗口宽度自适应（showBack 窄列）

- 宽布局：`RootShellView.swift:204` `showBack: false`；窄布局（列表/详情二选一）：`:216` `showBack: true`；日历/四象限浮层编辑：`PlanningWorkspaceChrome.swift:67-69` `showBack: true, onRequestClose: closeEditor`。
- `showBack` 只影响三件事：显示返回按钮、Esc 末级"退回列表" vs "保持"、`presentation.handleEscape(isNarrow:)`。
- 宽度本身：inspector 最小 320（`DesignSystem/Metrics.swift:105`）；标题字体固定 19 不缩；日期+重复进横向滚动、优先级贴右；底栏用 `Spacer` 把 6 个出口分左右两组；正文左右 padding 15/20（`TaskInspectorShell.swift:674,687-688`）。
- 没有断点隐藏底栏文字/图标。

---

## 9. 本地明确「没有」的东西（grep 佐证）

以下均在 `macos-native/WorkFollow` 内 grep，结果为空或仅命中无关模块（注明命中处）：

| 项 | 结论 | 佐证 |
|---|---|---|
| 标签 chips 行（标题下/正文上的标签行） | **没有**。标签只在底栏图标 + 标签浮层里可见 | `grep -rn tag Features/Tasks/TaskInspector` 只命中「标签」菜单行/`setTags`；无 `TagChip`/`chips` |
| 子任务进度视图 / 进度环 | **没有**。`ProgressView` 在 inspector 只用于动态面板的加载 spinner | `TaskActivityPageModel.swift:47`；列表侧的「子任务进度」是行元数据（`TaskSecondaryMetadata.swift:14`），不在详情栏 |
| 标题右侧类型按钮（任务/笔记类型、模板类型） | **没有** | `grep 类型\|taskType\|TaskKind` 在 TaskInspector 无命中 |
| 展开到窗口 / 卡片 / 独立窗口 | **没有** | `grep openInWindow\|expandTo\|全屏\|新窗口\|separateWindow` 在 TaskInspector/Editor 无命中 |
| 附件行（详情里的附件列表/缩略图行） | **没有**。`AttachmentListView` 只被笔记页使用 | `NotesWorkspaceView.swift:259`；inspector 只有「上传附件」与正文内附件 run（`TaskInspectorShell.swift:249,588-594`） |
| 协作 / 指派 / 负责人 / 成员 | **没有** | `grep assignee\|负责人\|成员\|指派\|协作\|collaborat` 在 TaskInspector/Editor 无命中 |
| 日历订阅（ICS/外部日历） | **没有** | `grep calendarSubscri\|订阅` 只命中 Combine 订阅注释，无日历订阅功能 |
| 打印 | **没有** | `grep 打印\|NSPrint` 只命中 `TaskListView.swift:387` 的菜单清单注释；更多菜单测试断言「打印」不存在（`TaskMoreMenuRoundTwoTests.swift:43`） |
| 模板面板/模板选择器（详情内） | **没有**。只有「保存为模板」 | `TaskInspectorShell.swift:257,596-612`；模板选择器在任务列表页（`TaskListView.swift:47`） |
| 截止日期 chip | **没有入口**。`ScheduleField.deadline`、deadline popover 代码都在，但 shell 没有调用点；更多菜单「截止日期」已被移除 | `TaskInspectorShell.swift:107` 只传 `.due`；`:809-821` 无 `.deadline` 调用；测试 `TaskMoreMenuRoundTwoTests.swift:43` |
| 提醒 chip（顶栏） | **没有**。`InspectorPopover.reminder` 与 `.reminder` 锚点残留但不可达/未使用 | `TaskInspectorRenderContract.swift:5`（无使用）；`InspectorPopover.reminder` 只在测试出现（`TaskInspectorPresentationTests.swift:6`） |
| 正文选区工具条（任务） | **没有**（组件存在，任务 profile 关闭） | `TaskDocumentProfile.swift:21-23`；`DocumentProfileTests.swift:62` |
| 块拖拽手柄 / 块折叠 / 块菜单 | **没有** | `grep onDrag\|draggable\|DragGesture\|拖拽\|折叠` 在 `Features/Editor` 无命中 |
| 图片插入按钮（相册/文件选图） | **没有**，只有剪贴板粘贴图片 | `NativeTextView.swift:570-625`；工具条 15 个按钮中无图片按钮 |
| 代码块工具条按钮 / H4–H6 按钮 / 已勾选检查项按钮 | **没有**（代码块只能围栏输入；H4–H6 只能 Markdown；`format.checkedChecklist` 只在目录里，无 UI） | `DocumentFormatCommand.swift:100-117` 16 条命令，工具条只用 10 条 + 5 个非格式按钮；`DocumentSelectionToolbar.swift:113-156` |
| 跳过本周期 / 其他操作 / 更多属性 | **没有** | `TaskMoreMenuRoundTwoTests.swift:43` |
| 评论数 / 动态数角标 | **没有** | 底栏评论出口无 badge（`TaskInspectorShell.swift:531`） |
| 撤销/重做按钮（底栏） | **没有**（只走 ⌘Z / 菜单） | 底栏 6 出口列表 |
| 标题自动聚焦 | **没有**（`titleEditing` 从未置 true） | `TaskInspectorShell.swift:15,68,639` |
| 无关残留（可作为"实现痕迹"证据） | `TaskDateButton` 全仓无调用；`childRowRadius`/`childRowHorizontalPadding`/`childRowGap` 无使用；`InspectorPopover.reminder` 不可达；`InspectorRenderAnchor.reminder` 未使用 | `TaskDatePopover.swift:3`；`TaskInspectorMetrics.swift:25-30`；`TaskInspectorPresentationState.swift:9-14`；`TaskInspectorRenderContract.swift:5` |

---

## 10. 代码注释里标注的已知取舍 / 坑

按主题摘录（原文注释，行号为注释附近）：

### 10.1 几何与"实测"口径

- `TaskInspectorMetrics.swift:3-5`：结构尺寸来自 2026-10-17 同窗口 AX 实测（滴答 8.0.80，1512×859，窗顶 y=33；内容顶 96 / 底 843 / 标题 y=106 / 正文 y=145），"不按缩放截图推断"。
- `TaskInspectorMetrics.swift:10-12`：内容原点到左缘 20，"距分栏线"实测约 21 —— 两条线要分开理解。
- `TaskInspectorMetrics.swift:16-18`：`NSTextContainer` 默认 fragment padding 5 会叠加在宿主 inset 上，必须在 Task 边界补偿；Note/TextKit 布局不动。
- `TaskInspectorMetrics.swift:23,27`：子任务行高 40、完成框 19 均为 2026-10-16 AX 实测（原 42 是上一轮来源尺寸）。
- `DocumentEditor.swift:136-139`：装饰标记几何 5.0，因抗锯齿墨迹会再向右约 0.5；下限 4 来自 `task-inspector-content-alignment.md`。

### 10.2 TextKit / AppKit 的坑

- `AppKitTaskTitleField.swift:46-50`：宽度变化必须同步 `preferredMaxLayoutWidth`，否则高度算错。
- `AppKitTaskTitleField.swift:54-55`：只在状态不符时改 firstResponder，避免每次 SwiftUI 更新都重设（会打断输入法）。
- `NativeTextView.swift:730-736`：行首沟槽必须靠段落 `headIndent`，不能靠 `textContainerInset` —— NSTextView 会把绘制裁剪到容器内，"实测"画在 inset 留白里的装饰不可见。
- `DocumentBlockDecorations.swift:4-9`：滴答 `NSTextList` 0 处；macOS 14+ TextKit 2 会自绘 NSTextList 标记，与视图层标记叠成"双点/1.1"，所以段落样式绝不挂 `textLists`。
- `DocumentFormatCommand.swift:261-291`：替换富文本时 TextKit 会**合并字体 trait**（标题套到 14pt 行上仍是 14pt + Bold；"实测 2026-10-16，工具条与输入期两条路都中招"），所以替换后按渲染结果重设精确属性。
- `DocumentFormatCommand.swift:316-326`：段落分隔符的字体被 TextKit 修正回基础字体，导致"选完标题当场没变化、切走再回来才变"，编辑后要再写一次字号/段落样式。
- `DocumentFormatCommand.swift:193-201`：文末空段（文档以换行结尾）定位段落必须走"无字符段落"分支，否则列表格式会跑到上一行（斜杠先删 `/` 再应用会触发）。
- `DocumentTextCodec.swift:99-104`：标题 3–6 同字号、"实测三级到六级墨水质量完全相同"，不按级别继续收窄。
- `NativeTextView.swift:627-631`：撤销闭包里 `setSelectedRange` 会被 TextKit 随后的插入点吸附覆盖，"实测"只能登记意图、`undo()` 返回后统一补写。

### 10.3 产品口径 / 对齐滴答

- `TaskInspectorShell.swift:10-12`：浮层里的详情 Esc 要关浮层而不是清选中，对齐 Flutter `TaskInspector._escape()` 的 `_isPopup` 分支。
- `TaskInspectorShell.swift:251-253`：专注摘要行改"有数据才显示"后，「设置预计专注」入口留在更多菜单 —— **滴答无此入口**，属本地保留能力的可达性处理。
- `TaskInspectorShell.swift:265`：更多菜单「打开便签」是滴答「…」第 12 项，"实测 2026-10-16"。
- `TaskInspectorShell.swift:367-368`：滴答右栏对普通任务**不显示**专注摘要行（2026-10-17 同窗口实测）。
- `TaskInspectorShell.swift:691-693`：滴答优先级是四行彩色旗、**无当前值标记**；SwiftUI `Menu` 桥接 NSMenu 不渲染菜单项图标（实测 2026-10-17），所以改自绘浮层。
- `TaskInspectorShell.swift:445`：行内改名提交后回车续加子任务，"对齐滴答"。
- `TaskInspectorShell.swift:491-493`：添加子任务悬停底色比内容宽 8，让图标落在勾选框竖线上、底色像原版宽一圈。
- `TaskDocumentProfile.swift:16`：放开嵌套（2026-10-17）后子任务正文也可插"子任务"（孙任务）。
- `TaskDocumentProfile.swift:21-23`：任务正文显式关闭选区工具条。
- `DocumentProfile.swift:87-88`：斜杠分节"对齐滴答实测（2026-10-16）：标题｜列表｜格式｜插入"。
- `DocumentProfile.swift:162-163`：原版鼠标进入某行会把键盘高亮也移到那行（共用一根高亮条）。
- `SlashCommandPanel.swift:21-23`：面板高度算法与原版 `DocumentSlashMenu.heightFor` 一致（行×34 + 线×9 + 8）。
- `SlashCommandPanel.swift:244-246`：任务 compact 菜单选中底用中性灰而不是强调色（菜单是中性表面）。
- `DocumentSelectionToolbar.swift:82-85`：工具条是原版 4 条竖线的全集顺序。
- `DocumentSelectionToolbar.swift:296-299`：按钮 26×28、激活 `accentFaint`、悬停走列表行中性底（不是强调色）。
- `DocumentToolbarTooltip.swift:30-35`：不用系统 `.help` 的三个原因（位置在下方没空间、延迟约 1 秒、每个按钮都要有）。
- `AppKitSubtaskOutlineView.swift:28-30`：不用 `NSScrollView` 包 outline，否则与宿主滚动冲突、坐标错乱。
- `AppKitSubtaskOutlineView.swift:89`：单击手势挂在 NSOutlineView 上，避免被 cell 子视图拦截。
- `AppKitSubtaskOutlineView.swift:290`：悬停高亮用 `draw` 而不是 layer 背景，因为 cell 复用会丢 layer。

### 10.4 输入期 / 渲染期 Markdown 的口径变更

- `DocumentMarkdownInput.swift:3-22`：2026-10-16 产品口径修订（对齐滴答 8.0.80），行内与围栏是同日的补充口径；触发后标记串从正文移除（符号隐藏，由装饰层重画）。
- `DocumentMarkdownInput.swift:214-219`：行内只认"本次输入刚好补全、以光标结尾、同一行内"的最近一处闭合；空 URL、空内容、未闭合保持字面（用户确认）。
- `DocumentMarkdownInput.swift:283-292`：2026-10-17 改为渲染期重解析（覆盖历史字面），加性、幂等、代码段/分割线不动。
- `NativeTextView.swift:103-104`：粘贴富文本按纯文本参与输入期转换（整串写入口径）；Slash 触发只认纯字符串输入。
- `NativeTextView.swift:122-125`：`、` 常由中文输入法提交，允许组合态下的单字符提交作为触发。

### 10.5 其余 TODO 类

- 全仓 `Features/Tasks/TaskInspector` + `Features/Editor` 内 **没有** 字面 `TODO`/`FIXME`（grep 无命中）；"未/暂"多出现在注释说明"未实现/不补造"，例如动态空态"不补造历史记录"（`TaskActivityPanel.swift:25`）。
- `TaskEmptyInspectorView.swift:3-6`：原实现的三个占位星形"artwork remains pending"，已换统一空态组件；宽度 176 与居中为契约，勿改。
- 测试注释记录的能力缺口：`TaskMoreMenuRoundTwoTests.swift:42`「打印」仍缺席，按"无假按钮"处理（滴答有，属能力缺口）。

---

## 11. 测试锁定清单

共 17 个文件、189 个 `test` 方法（本盘点读到的范围）。下面按"锁什么"归类（括号为用例起始行）。

### 11.1 编辑栏结构与几何

- `TaskInspectorShellContractTests.swift`（5）：
  - 顶栏优先级贴右、分隔线 1×20、日期视口不越界、返回按钮仅窄列、无 reminder、重复按钮条件（`:8`）；
  - 子任务面包屑在标题之前、高 30（`:48`）；
  - 标题与正文同内容原点、间距 16、`documentLeadingPadding + fragmentPadding == 20`、完成框 15pt 墨迹左对齐（`:61`）；
  - 空态插画 176 宽、面板内居中（`:80`）；
  - 日程文案/颜色语法（今天/上周日/overdue/empty）（`:91`）。
- `TaskInspectorHierarchyRenderTests.swift`（5）：
  - 子任务详情里 `+`/标题角标不越出 pane、`+` 可开空块菜单且不改文本（`:8`）；
  - 无子任务时没有子任务区/addChild/面包屑，底栏两端对齐（`:69`）；
  - 子任务区跟随正文自然高度（空/单行/多行）、区顶间距 20、行高 40 + gap 6（`:81`）；
  - 选中子任务：面包屑、无可移动清单、只读（`:108`）；
  - 多子任务行贴紧无 divider（`:123`）。
- `TaskMoreMenuRoundTwoTests.swift`（2）：更多菜单 15 行顺序、移除项不存在（`:5`）；放弃/恢复/删除是普通文本色（`:48`）。
- `TaskFocusSubmenuTests.swift`（5）：子菜单右优先/左翻/夹取（`:8`）；番茄与正计时都真开会话、忙碌不替换（`:20`）；真实 inspector 里 More 宽 208、子菜单 176、Esc 逐层关、点日期关 More（`:45`）；20 轮 More→日期 单击与 Esc 不改日程（`:97`）；点标题一次事件同时关 More 并聚焦标题（`:131`）。

### 11.2 呈现状态 / Esc

- `TaskInspectorPresentationTests.swift`（7）：reminder/recurrence/schedule/deadline 的 Esc 先关浮层再结束编辑再窄列返回；宽列保持；标题草稿同任务保留、换任务重置（`:5-69`）。
- `TaskInspectorActionPanelTests.swift`（3）：动作面板互斥替换、子菜单/面板分层 Esc、完成与外部关闭共用状态（`:5,18,44`）。

### 11.3 切换 / 输入法 / 焦点

- `TaskSwitchingTests.swift`（8）：切任务只重绑不重建编辑器（`:95`）；旧任务 IME 组合先提交、清焦点/撤销/浮层（`:133`）；快速往返提交未上屏文本（`:171`）；删除选中任务先提交（`:199`）；21、50 任务规模下切换延迟（`:219`）；原生标题第一击即切详情（`:253`）。
- `DocumentEditorHitTargetTests.swift`（4）：正文原生命中区、点正文夺焦点、内容尺寸增长与外部滚动、空文档也有可点区（`:8-93`）。
- `NativeTextViewTests.swift`（8）：干净文档切换不 decode、外部存储变化仍 flush、IME 组合只提交旧文档、rebind 清 slash 窗口/观察者、detach 关选区工具条、UndoManager 按文档隔离、find bar Esc 不关 inspector、组合态不发布（`:7-157`）。

### 11.4 Markdown / 格式

- `MarkdownInputTriggerTests.swift`（31）：块级前缀（含整串写入、行中有文字、空中间行、后续输入延续）、分割线（末行/中间行/`***`/`___`/非整行不转/一次撤销）、围栏（开始/空中间行/延续与空行退出/守卫/一次撤销/代码段落保持字面）、行内（闭合才转/双写不抢跑/保留周围文字/引用与代码段/空 URL 与未闭合保持字面/继续输入继承标记/一次撤销/整串插入全部闭合）、渲染期重解析（历史字面/跳过代码段保留工具条标记/多片段/保留光标/粘贴内容同样触发）（`:42-616`）。
- `MarkdownSyntaxTests.swift`（19）：H1–H6、标记范围、`*`/`-` 无序、有序、检查项状态、引用嵌套、围栏、分割线、paragraph 合并与空行折叠、滴答扩展行内（`~` 下划线、`::高亮::`）、标准行内、单波浪线语义、双写内部字面、未闭合/不支持保持字面、markerRanges、链接标记范围（`:16-169`）。
- `DocumentFormatStyleTests.swift`（16）：结构化段落紧凑几何、列表只改选中段、空段格式可撤销重做、空块退出可撤销重做、block/mark 读取口径、混合选区不激活、标题字号字重与行距实测、空行套标题后继续同字号、文末空段级别存活、重绑带回文末级别、已勾选检查项灰+删除线不污染 marks、套标题后输入沿用级别（`:10-314`）。
- `DocumentContentTests.swift`（20）：回车延续标题/退出空标题/空列表；列表不在上一行生效；文末检查项点击；块格式不变成行内；行内组合与切换；选区逐项格式；换行两侧输入样式；移除格式保留链接/附件/选区/撤销；混合选区激活口径；JSON/文本 round-trip；格式持久化与撤销；legacy 附件；附件 round-trip；检查项状态；连续有序编号；链接编辑；附件撤销不泄漏到输入；格式保留嵌入文件引用（`:8-378`）。
- `DocumentDecorationRenderTests.swift`（11）：已勾选展示键清理、勾选早期行不污染文末标题、标题/引用几何不受文末输入样式影响、退出列表后检查框右缘仍可点、双回车退出列表标记不漂、混合列表与连续引用、标题/`+` 沟槽在宿主内容原点之前、活动标题角标、空行 `+`、普通行留空、文末待定列表标记（`:15-380`）。
- `DocumentProfileTests.swift`（15）：紧凑 Slash 12 条且高度 443、任务 host 只路由业务动作、笔记选区建任务、短标题是元数据、引用负载保留链接、工具条 descriptor 保真、标题/时间 picker 契约、每个时间格式与插入文本一致、浅深色渲染、真实工具条顺序与 26×28 几何 + 点击生效、目录 ID 唯一、任务/笔记/通用 profile 共享格式身份、Slash 适配执行结果一致、任务 Slash 顺序与文案、紧凑菜单打后续字符即关闭（`:8-355`）。
- `SlashSessionTests.swift`（25）：检查项/子任务走不同变更通道、业务选择器先消费触发、格式与分割线单次撤销、悬停/键盘/Esc 共用选中、窗口父子与底翻、跟随视口与窗口、空白后触发、`/` 与 `、` 同面板、UTF16 范围搜索与键盘环绕、删 `/` 或移出取消、注入命令只在本 profile、执行消费查询、块格式行范围与光标、空行检查项不污染下一行、有序连接相邻项、行内格式作用于后续输入、分割线保留周围文字、Esc 保留查询、glyph 映射顺序、选区上打字是普通文本、两种触发同样处理、IME 提交 `、` 打开面板、触发需文首/空白、URL 不开、重绑清撤销与 Slash（`:14-473`）。

### 11.5 面板与存储

- `TaskCommentStoreTests.swift`（5）：顺序追加、按任务隔离、trim、删除、flush/reload 持久化（`:6-48`）。

### 11.6 未被测试锁定的部分（明确说明）

- 日期面板内部组件（月历、时间 48 项、提醒/重复/结束子页、农历页）没有在本次读到的测试文件里被逐项锁定（`Schedule*Tests.swift` 存在但不在本次范围，**未确认**其覆盖）。
- 优先级浮层、标签面板、父任务/关联面板的**视觉几何**没有对应断言（父任务/关联仅由 `TaskRelationInteractionTests` 等业务测试覆盖，本次未逐行读，**未确认**）。
- 子任务行的悬停底色、日期列宽、`NSOutlineView` 折叠状态没有测试。

---

## 附：最值得与滴答逐项对比的 5 个薄弱点（供差异表优先展开）

1. **底栏只有 6 个出口（常显 4）**，源码注释却写"滴答 8 出口"：标签/合并还靠数据条件隐藏，缺的 2 个没有任何占位或禁用态。
2. **截止日期与提醒的入口断了**：deadline popover、`ScheduleField.deadline`、`InspectorPopover.reminder` 代码都在，但 shell 无调用点、更多菜单已删「截止日期」——与滴答"日期 + 截止日期 + 提醒"三件套差距最大。
3. **正文没有选区工具条、没有块手柄/折叠、没有图片按钮、没有 ⌘B/I**：任务 profile 显式关掉选区浮条（`selectionToolbarEnabled: false`），格式只能靠底栏工具条、Slash 或 Markdown；滴答的"选中即浮条 + 块拖拽"完全缺席。
4. **标题与正文是两套焦点系统**：Return/Esc 只结束标题编辑，不进入正文，也没有新建任务自动聚焦标题；宽/窄列只靠 `showBack` 一个布尔，没有按宽度收缩的次级控件策略。
5. **子任务区是"能看能改名"的最小实现**：单击/双击都只是打开详情、没有拖拽排序/优先级/删除、折叠不持久、常态 4% 灰底；与滴答的完整子任务行（日期、优先级、更多）不在一个量级。
