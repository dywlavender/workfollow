# 文档块装饰与编辑行为改造复盘（2026-09-28）

## 背景

本轮把任务/笔记共用的文档编辑器（`Features/Editor/`）从"纯文本 + 少量样式"
改造为滴答同款的**块装饰编辑器**：列表标记、标题级别角标、空行"+"、引用竖线、
回车延续格式、空块回车退出、文末空段的级别管理，并按产品要求移除 Markdown
符号触发。涉及文件：

- `DocumentBlockDecorations.swift` — 行首装饰绘制（视图层自绘）
- `DocumentTextCodec.swift` — 段落属性（缩进/字体/级别）与编解码
- `NativeTextView.swift` — 回车/退出/文末级别同步
- `DocumentEditorCoordinator.swift` — commit 与模型同步
- `DocumentFormatCommand.swift` — 格式应用（含文末空段分支）
- `Features/Tasks/TaskInspector/TaskInspectorShell.swift` — 任务详情面板宿主
  （空白点按聚焦、内容撑满视口）
- 测试：`DocumentDecorationRenderTests`（新增，离屏渲染验收）、
  `DocumentContentTests`、`DocumentFormatStyleTests`、`SlashSessionTests`

本文记录**实测结论、踩坑与验收方法**，指导后续同类改造。

## 一、最终确定的产品口径（用户逐条确认过）

1. 段落格式通过"/"菜单与格式工具条修改；**Markdown 块级前缀的输入期触发**是
   2026-10-16 的口径修订（对齐滴答 8.0.80，用户确认）：`# `～`###### `、
   `* `/`- `/`+ `、`1. `、`- [ ] `/`- [x] `、`> ` 在标记完成（空格落下）时
   立即成块、标记串从正文移除（标记由装饰层重画）。分割线（整行
   `---` / `***` / `___`）在整行敲完时换成分割线附件、光标跳下一行。围栏
   代码块（整行 3+ 个反引号，允许行首最多 3 个空格）在整行敲完时立即成块——
   行文本移除、段落转为代码、空代码行回车退回正文（同日第二轮修订，用户确认；
   带语言标记的围栏保持字面，另行对齐）。规格与逐条断言见
   `MarkdownSyntax`/`MarkdownSyntaxTests`，输入契约见 `MarkdownInputTriggerTests`；
   原"`# ` 等一律是普通文本"的守卫用例已按新口径反转。
2. **行内标记改为「渲染期解析」**（2026-10-17 口径修订，对齐滴答的渲染期解析，
   取代 2026-10-16 的"输入期触发"）：`**粗**`、`*斜*`、`~~删除线~~`、`~下划线~`、
   `::高亮::`、`` `码` ``、`[文字](url)` 在**闭合**后即转换——开闭符号从正文移除，
   内容按**设值**语义应用行内标记（只加不减，不走工具条"全有才取消"的切换）。
   解析覆盖三处：
   - **文档加载/切换**：历史字面一次性渲染（`didLoadDocument` 后异步重解析，不登记撤销）；
   - **每次编辑后的所在段落**：粘贴中段、编辑揭示的闭合都转；一段里**所有**已闭合
     片段都转换，不再只认"以光标结尾的最近一处"（`前 **粗** 后` 中段也转）；
   - **本次输入**：闭合字符落下即转，光标落内容末尾、与本次输入同一撤销分组、
     继续输入的字符继承该行内标记（同块级"接着输入的字落在新块里"）。
   仍保持的口径：`~~删~`、`**粗*` 这类双写标记中间态保持字面（防抢跑守卫）；
   链接以 `)` 闭合触发，空 URL 的 `[文字]()` 保持字面（有意口径）；引用段落照常，
   代码段落不参与；未闭合、空内容标记（如 `::::`/`~~~~`）、IME 组合期不转换。
   输入契约见 `MarkdownInputTriggerTests`（含 `reparse` 用例与"整串写入全转"用例）。
3. 行首标记分两类：
   - **常驻**：列表标记（• / 1. / 复选框）、引用竖线——所有可见行都画；
   - **活动行**：标题角标（H1/H2/H3）与空行"+"——只在光标所在行显示，失焦隐藏。
4. 角标/加号画在**文字左侧的空白区**（所有段落统一 20pt 行首缩进让出的沟槽），
   标题与正文左对齐；**不能**用"标题多缩进"或"textContainerInset 外挂"实现
   （前者被用户否定，后者有技术墙，见下）。
5. 回车语义：有内容的格式行回车 → **新行延续格式**；空格式行回车 → **退回正文**
   （滴答/Quill 同款，否则用户被困在格式里）。
6. 文末空段上应用列表：符号**立即显示**且**常驻**，不能落到上一行，
   也不能在光标离开后消失。

## 二、TextKit 2 关键实测结论（每条都踩过）

1. **段落绝不挂 `NSTextList`**。macOS 14+ 的 TextKit 2 会自绘 `textLists`
   的灰色标记并挤占行首空间，与自绘强调色标记叠成"双点 / 1.1"。
   标记全部由视图层画（滴答 `AppestKit` 同款：NSTextView 自绘 60 处、
   `NSTextList` 0 处）。
2. **NSTextView 把绘制裁剪到文本容器区域**。靠 `textContainerInset.width`
   挖出来的左侧留白里画装饰（x < inset.width）**一律不可见**——
   `super.draw` 渲染的文字正常、装饰的填充/文字全部消失，且无任何报错。
   行首沟槽必须用**段落 headIndent** 在容器内实现。
3. **文末空段没有字符**。TextKit 把段落样式挂在字符上，文末空段（最后一个
   `\n` 之后）没有任何字符：主循环按段落遍历看不见它、属性读不到它。
   它的级别只存在于 `typingAttributes` 与一个显式状态
   （`pendingTrailingBlock` / `displayedTrailingBlock`）里，
   解码靠 `decode(_:preserving:trailing:)` 的 trailing 参数。
4. **`NSString.paragraphRange` 对文末零长区间**返回零长 range：
   一切"取光标所在段"的代码都要显式处理 `location == length`，
   否则会落到 `length-1`（上一行）——"格式跑到上面一行"的根源之一。
5. **`firstRect(forCharacterRange:)` 对零长区间**（行首/行尾/文末插入点）
   基本可用（返回插入点矩形），但 `viewRect` 的边界检查要放宽到
   `location <= storage.length`。
6. **离屏捕获分两层**：本轮（09-28）实测装饰用 `cacheDisplay` 抓不到——装饰
   绘制有 `window != nil` 前置，视图没挂进窗口时整段跳过。10-16 起精化为：
   视图挂进真实 `NSWindow` + `orderFrontRegardless` + `ensureLayout` 之后，
   视图级 `bitmapImageRepForCachingDisplay` + `cacheDisplay` 能同时抓到自绘
   装饰与文字墨迹（`DocumentListMarkerAlignmentTests` 用它对列位置做逐像素
   度量）；要看整体合成像素仍用窗口捕获 `CGWindowListCreateImage`。
   `drawViewHierarchy` 是 iOS API，macOS 没有。

## 三、状态分三层，同步时机是生死线

| 层 | 载体 | 谁写 | 用途 |
| --- | --- | --- | --- |
| 输入意图 | `typingAttributes` | NSTextView 选区变化重算；applyFormat/退出显式写 | 接下来输入的样式 |
| 视图待定 | `pendingTrailingBlock` | `syncPendingTrailingBlock()`（didChangeText **先于 super**、选区变化） | commit 解码文末空段 |
| 模型权威 | `displayedTrailingBlock` + `document.blocks.last` | 协调器每次模型同步刷新；applyFormat/退出/seed 直写 | 装饰常驻绘制、切走切回不丢 |

经验：

- `syncPendingTrailingBlock()` 必须在 `super.didChangeText()` **之前**调用，
  否则 delegate 的 commit 拿到的是旧级别（回车延续格式就靠这一步）。
- commit 的 trailing 参数要**模型兜底**：
  `trailing: pendingTrailingBlock ?? Self.trailingBlockKind(of: document)`。
  光标离开文末空段后 pending 会被清空，若无兜底，任何其他位置的编辑都会把
  文末列表重置成正文。
- 文档切换用 `seedTrailingParagraphKind` 把模型级别带回输入属性；
  协调器每次 `update()` 都要刷新 `displayedTrailingBlock`。

## 四、踩坑 → 修法对照表

| 现象 | 根因 | 修法 |
| --- | --- | --- |
| 蓝点 + 灰点同时出现、"1.1" | 段落挂了 `textLists`，TK2 自绘一份 | 移除 `textLists`，标记全自绘 |
| 标记与文字间距过长 | 同上：TK2 的列表布局挤占行首 | 同上 + 标记自绘、与段落文字**左缘**对齐（2026-10-16 实测修订，见下「标记对齐」；原为右对齐到 `lineRect.minX - 7`） |
| 角标压住标题文字 | 角标画在 x=0，标题也从 0 开始 | 全段落 20pt headIndent，角标画 0..17 |
| 角标/加号整体消失 | 画在 `textContainerInset` 留白里，被容器裁剪 | 沟槽改 headIndent 实现（见二.2） |
| 列表格式跑到上一行 | `min(lineStart, length-1)` 钳制 + 斜杠先删"/"再应用格式，文末空段定位落到上一行 | 文末空段走"无字符段落"分支（typingAttributes + pending） |
| 空列表项符号不显示（光标离开后） | 文末空段对主循环不可见；活动行补画只覆盖光标在行上 | `displayedTrailingBlock` + 常驻 `drawTrailingListMarkerIfPresent` |
| 换行后标题丢失 | `pendingTrailingBlock` 未随回车同步，模型把新行解码成正文 | didChangeText 先同步；commit 加模型兜底 |
| 回车被"/"面板吃掉 | `doCommand` 里斜杠会话优先拦截 insertNewline | 各拦截器职责互斥，顺序：斜杠 → 空块退出 → 分割线（已移除） |
| 点编辑栏空白无反应（首次点开任务时尤其明显） | 编辑器是 `contentSized`（只有内容高），空白落在 SwiftUI 背景上，**没有接手势**；笔记页早有同款处理，任务面板漏了 | 宿主内容撑满视口（`GeometryReader` + `minHeight`），背景挂 `Color.clear.contentShape(Rectangle()).onTapGesture { handle.focusEnd() }` |
| 渲染验收测试突然整片失败（角标/+ 全消失，但像素差分用例正常） | 系统切到**深色模式**：装饰用的动态系统色（`tertiaryLabelColor`）变成近白色，画在测试窗口的白底上不可见；"白底 + 非白像素"的断言全失效 | 测试窗口固定浅色外观 `window.appearance = NSAppearance(named: .aqua)`，颜色可预期；应用侧仍跟随系统外观 |
| 撤销后选区被吸附回编辑末尾（链接撤销无法恢复原选区） | TextKit 撤销机制在**闭包结束之后、`undo()` 返回之前**会再 `setSelectedRange` 一次把插入点吸附回编辑位置，覆盖闭包里的选区恢复；直接改 `setSelectedRange` 或在闭包尾设置都无效（实测四变体全败） | 闭包改用"登记意图"：`requestSelectionAfterUndoRedo(_:)` 记下目标选区，由 `undo()`/`redo()` 返回后统一补写（`NativeTextView.applySelectionAfterUndoRedo`） |

| 对已有文字的行应用标题后字号不变（只留下旧字号的粗体） | TextKit 对带属性替换做**字体特征合并**：字号沿用被替换文本、字重取新串；真实窗口下同样如此，工具条与斜杠两条旧路径一直中招（无用例，直到输入期 Markdown 才暴露） | 替换后按渲染结果**精确回写属性**：`applyFormat` 的 reapply 从"只对 mark 命令"扩大到所有命令（2026-10-16） |

### 标记对齐（2026-10-16 实测修订）

滴答同一段内容截图（1px = 1pt）：正文与标题文字起于 x19，圆点 x19..24、
有序编号 x19..28.5、列表文字 x34、引用竖条 x22..23.5。结论：**标记与段落
文字左缘对齐**，不是右对齐成一列。实现与配套修订：

- 标记几何起点 = `lineRect.minX - DocumentEditorGeometry.listTextIndent
  + listMarkerOpticalOffset`（缩进 16、光学补偿 1：首字形起点比墨迹早约 1pt）。
- 同轮把标题字阶定为 18 / 16 / 14、**粗体**（滴答三级到六级同字号，只靠字重
  与段间距区分），行盒标题 1.6× 字号、列表与引用 18、正文 21
  （`DocumentTextCodec` 用 lineSpacing 补字体自然行高与目标行盒之差）。
- 回归：`DocumentListMarkerAlignmentTests` 离屏渲染五类行，以标题墨迹左缘为
  基准锁相对列位置（圆点 +0..+5.5、编号 +0.5..+9、复选框 +0 起约 13pt 宽、
  列表文字 +15、竖条在 +3 起 2pt 宽）；`DocumentFormatStyleTests` 的
  `testParagraphLineBoxesAndPitchesMatchMeasuredTickTickSpacing` 锁行盒与
  段间距（35 / 32 / 30 / 20，±1pt 容差）。

## 五、验收方法论（本轮最重要的沉淀）

**UI 脚本遥控（CGEvent 点击/键盘）不可靠**，踩过的坑：

- 焦点竞争：宿主 IDE 会在命令间隙抢焦点，回车/键盘输入落到别的应用；
- 输入法污染：拼音 IME 下字母进入**组合串**（带下划线的 marked text），
  属性不含 blockKey，干扰一切基于属性的断言；
- 坐标漂移：窗口 id 每次重启都变、滚动位置不定、缩放换算易错；
- 截图时机撞上光标闪烁灭点，造成"没生效"的假象。

**可靠的做法：离屏渲染验收测试**（`DocumentDecorationRenderTests`）：

1. 真实 `NSWindow` + `orderFrontRegardless` + `makeFirstResponder`——
   满足装饰绘制的全部前置条件（焦点、window、布局）；
   **窗口外观必须钉死**（`appearance = NSAppearance(named: .aqua)`），
   否则系统深色模式会让动态色失真（见踩坑表）。
2. 两种抓法按用途选：**整体合成**用 `CGWindowListCreateImage`——这是用户看到
   的真实像素；**列位置度量**用视图级 `bitmapImageRepForCachingDisplay` +
   `cacheDisplay`（视图已挂进窗口时同样抓得到装饰，见二.6，10-16 修订）。
   `drawViewHierarchy` 在 macOS 不存在。
3. **像素断言**：沟槽区（x<20pt）的非白不透明像素 ⇔ 标记画出来了
   （正文/光标都在 x≥25）。必须按 **alpha 过滤**——捕获图两侧有透明黑边，
   alpha=0 的黑会被误判成墨迹。
4. **基线差分**：位置不确定时（捕获存在翻转/底部锚定），不用固定坐标，
   改为"同位置两次渲染、对比目标区间的新增墨迹"。
5. **PNG 落盘目检**：断言之外把图写到 /tmp，人工看几何位置。
6. 每个修复都固化成回归测试；对照用例（普通行沟槽必须为空）与正向用例同等重要——
   它们互相证明对方不是假阳性。

调试技巧（按效率排序）：
临时日志（/tmp 文件 + 去重）→ 红色调试块可视化几何 → 像素分析脚本
（Swift 读 PNG 统计 bbox / 颜色分布）→ 构建失败先查 extension 存储属性这类
低级错误（`Self.debugLog` 在 extension 里调用要写成实例调用）。

## 六、防复发检查清单

### 宿主一致性（本轮两次踩点的教训，优先级最高）

编辑器（`DocumentEditor`）当前有**两个宿主调用点**：任务详情面板
（`TaskInspectorShell`）与笔记页（`NotesWorkspaceView`）；其中任务详情面板
自身被三处复用：主窗口右栏（含窄屏）、规划浮层、回收站。
（2026-10-16 按代码核对修订；原"三个宿主（含任务编辑弹框）"的表述已不成立——
新建任务表单与小卡使用普通输入框，不挂 `DocumentEditor`。）
视图层改动自动同步，但**宿主各自负责的东西必须逐个过**：

- [ ] 空白区域点击行为：`contentSized` 编辑器只占内容高，空白处默认无响应——
      每个宿主都要"内容撑满视口 + 背景 `contentShape` 点按 → `focusEnd()`"
      （笔记页早有；任务面板本轮才补上）
- [ ] 内容为空时的占位文案、侧边留白、滚动行为三个宿主各自是否一致？
- [ ] 宿主提供的 profile（`slashCommands` / `selectionActions` / `onOpenLink`）
      在功能变化后是否还匹配？（共享的是绘制与行为，不是命令集）
- [ ] 改完在**每个宿主入口**手动点一遍：⌘5 进笔记页、点任务行进详情、
      规划浮层与回收站；都看空白点按、回车延续/退出、"/"菜单

### 编辑器内部

- [ ] 段落样式变更是否碰了 `textLists`？（不要碰）
- [ ] 新装饰画在 x<20pt 或容器外？（会被裁剪，改用 headIndent 沟槽）
- [ ] 是否处理了文末空段（无字符段落）？三条路都要：
      绘制（常驻标记）、解码（trailing 参数）、应用格式（无字符分支）
- [ ] `didChangeText` / 选区变化 / 文档切换 / commit 兜底，四条同步路径都覆盖了吗？
- [ ] 回车语义：有内容延续、空块退出，两者是否都保持？
- [ ] 一切"取光标/段落所在位置"的代码是否显式处理了
      `location == length`（文末）与零长 range？（会静默落到上一行）

### 验证与提交

- [ ] 新行为有没有配离屏渲染回归测试？对照用例（不该画的时候是空的）写了吗？
- [ ] 像素断言是否按 alpha 过滤、是否避开固定坐标（用基线差分）？
- [ ] 提交前：临时日志、调试色块是否全部移除？

## 七、遗留与后续候选

- 文末空段的**检查项点击翻转**已完成（`setTrailingChecklist` + `applyTrailingState`，
  带撤销与光标落位，回归测试 `testTrailingChecklistTogglesFromEmptyLine`）。
- `CGWindowListCreateImage` 捕获图存在垂直翻转/底部锚定的现象未深究（测试用了
  方向无关断言绕开）；列位置几何断言可改用视图级 `cacheDisplay`
  （`DocumentListMarkerAlignmentTests`，10-16），不受该问题影响。
- 渲染测试目前只钉浅色外观；若装饰要覆盖深色模式，需要再加一遍
  `appearance = .darkAqua` 的用例（颜色断言口径要相应调整）。
- 撤销（`replaceEmptyBlock` / `applyTrailingState` 的 undo 注册）覆盖了空块
  退出与文末检查项翻转；其他装饰相关属性变更如需撤销要补同款处理。
