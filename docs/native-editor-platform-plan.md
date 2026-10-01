# Native Editor 平台整合方案

日期：2026-10-01。状态：EP-003 LIFECYCLE CONTRACTS ESTABLISHED / PLATFORM NOT FROZEN。

目标：保护当前编辑器优化，将 Slash、格式栏、选区浮条、右键与后续快捷键变成同一能力系统的入口；不是重写编辑器，也不是新增编辑能力。下面的审计表是整合前快照，后续变化以末尾执行记录为准。

## 1. 当前事实与设计判断

| 当前证据（仓库相对路径） | 事实 | 需要收拢的边界 |
|---|---|---|
| `macos-native/WorkFollow/Features/Editor/DocumentFormatCommand.swift` | 各入口已有共享 `NativeTextView.applyFormat`；右键格式菜单也调用它 | 缺稳定能力 ID、统一展示信息和入口声明，不是四套格式引擎 |
| `…/Editor/DocumentProfile.swift`、`SlashMenuGlyph.swift` | Slash 按 block 类型找格式，但生成 `task.format.0..6`，图标另按这些 ID 映射 | 顺序、图标、标题之间仍有隐式约定 |
| `…/Editor/DocumentSelectionToolbar.swift` | 格式栏和选区浮条共享格式命令；按钮集合、图标、tooltip 和短标题各自在 View 组织 | 引入命令元数据和显式 layout，不能靠数组下标或业务字符串判断 |
| `…/Tasks/TaskInspector/TaskInspectorShell.swift`、`…/Notes/NotesWorkspaceView.swift` | 两个宿主现场拼 Profile；任务仅根任务有 child，笔记提供 selection→task | 抽宿主 Profile，不改变现有可用能力及顺序 |
| `…/Editor/DocumentEditor.swift` | Handle 的 `insertNoteReference(_ note: Note)` 接收业务模型 | 通用层仍有 Note 依赖；转换为宿主产生的引用插入值 |
| `…/Editor/NativeTextView.swift`、`SlashCommandPanel.swift` | 独立 UndoManager、IME guard、Slash/选区 NSPanel 已存在；选区浮条资格还依赖 `taskSlash` | 用策略描述 profile 行为；保留当前实现，逐步替换条件 |
| `…/Editor/DocumentEditorCoordinator.swift`、`DocumentTextCodec.swift`、`DocumentBlockDecorations.swift` | 文档身份、组合输入、模型投影、空行格式和装饰已有边界 | 这些是保护资产，不另造 Model/Codec/Engine |
| `…/Infrastructure/Presentation/PopupEscapeRouter.swift`、`AnchoredPropertyPanel.swift` | 已有窗口归属与子层路由设施 | 编辑器复用规则；不复制第二套全局 monitor/OverlayManager |

省略号均指 `macos-native/WorkFollow/Features`，Infrastructure 行除外。旧的 `native-editor-reference.md` 是历史对照：其中 Slash 触发前缀、32pt 行高等描述已不代表当前源码，不能用作新方案验收依据。

判断：主要风险是能力描述、宿主扩展和 presentation 归属分散，不是整个 TextKit 架构失效。文件多、bool 多本身不构成缺陷；互斥状态、重复映射和生命周期无归属才需要改造。

## 2. 目标依赖和职责

```text
Task / Note Host（业务数据、持久化、导航、业务 Undo）
      ↓ 提供 Profile + Host Actions + 引用插入值
Command Catalog + Dispatcher（身份、可用性、状态、执行策略）
      ↑ 入口投影：格式栏 / Slash / 选区 / 右键 / 已存在快捷键
Editor Session + Presentation Policy（文档身份、选区、焦点、浮层协议）
      ↓
既有 NativeTextView / Coordinator（编辑、IME、文档 Undo）
      ↕ DocumentTextCodec（唯一模型投影边界）
NativeDocument / Block / Run / Mark
      → DocumentBlockDecorations（绘制和命中结果，不自行写业务数据）
```

这是职责分层，不要求建立六套目录、六个 service 或六个 ObservableObject。

### 命令定义与执行分离

- `EditorCommandID`：稳定语义 ID，例如 `format.heading1`、`format.bold`、`insert.divider`、`host.createChild`。不得按顺序生成 ID。
- `EditorCommandDescriptor`：ID、标题、入口短标题、icon/glyph、搜索词、分类、placements、执行语义。纯描述，不保存 View、TaskWorkspace 或 NSTextView 的强引用。
- `EditorCommandContext`：编辑器身份、UTF-16 range、当前 block/marks、editable/composing、宿主 capability。用于计算 enabled/active/mixed；不可用要有可解释原因。
- `EditorCommandDispatcher`：根据 ID 和 invocation 调现有引擎或宿主 action。按钮状态和执行前的可用性校验使用同一规则。
- `EditorCommandInvocation`：来源入口、目标范围/段落、Slash trigger range；保留 Slash 的 lineStart 与删除 trigger 后的目标偏移语义。只有 Slash 入口删除 trigger/query。
- 先提供现有 `DocumentFormatCommand / DocumentCommand / DocumentSelectionAction` 的 adapter，分入口迁移；不要求第一笔物理删除三个类型。
- 同一能力可有不同入口显示文案和目标解析规则，但编辑语义只能有一个执行目标。右键系统剪切/复制/拼写等继续由 AppKit 负责，不强行纳入 Catalog。

### Catalog 不等于自动布局

`placements` 决定能在哪出现；`ToolbarLayout / SlashLayout / SelectionLayout` 显式决定顺序、分组和 picker。所有 layout 引用能力 ID，不复制执行闭包。

标题 picker 是入口容器，正文/H1/H2/H3 才是命令；时间 picker 同理。按钮 help、无障碍名称、active state 来自同一 descriptor；字体、间距仍属于组件 Metrics。不能为了自动生成 UI 抹掉现有分组和顺序。

### Profile 和宿主边界

- `TaskDocumentProfile`：根/子任务 capability、业务入口、触发与查询策略、选区工具条策略；只在 Tasks 模块组装。
- `NoteDocumentProfile`：笔记选择文本创建任务及关联行为；只在 Notes 模块组装。
- Core 仅调用窄 `EditorHostActions`，如 createChild/openTags/openRelation/createTaskFromSelection；宿主负责业务校验和结果，不把 workspace 暴露给 Core。
- 插入笔记引用：宿主将 Note 转成标题/URL 或文档片段，再交给通用插入命令。Core 不接收 Note/Task 对象。
- 选区浮条不再判断 `note.createTask` 来缩短标题，也不根据 `taskSlash` 猜资格；Profile 声明 selection policy，descriptor 提供短文案。
- 引擎层仍可知道 paragraph/checklist/link 等文档类型；禁止直接依赖 Task/Note Store 和业务导航。

## 3. 状态所有权：不是一个大总控对象

| Owner | 拥有内容 | 不能拥有 |
|---|---|---|
| Editor session（Coordinator/NativeTextView） | document identity、选区、typing attributes、composition、focus、Undo | 宿主 tags/relation/导航状态 |
| Editor presentation | Slash session、selection suppression、formatting visibility、互斥 child picker | Task/Note 持久字段 |
| Host presentation | tags/relation 等业务 popup 和 Inspector/Note 导航 | NSTextView 原始选区和文档 Undo |
| Window adapter | NSPanel/NSPopover 的创建、定位、监听和销毁 | 执行业务修改或决定 capability |

格式栏可持久打开，Slash/选区浮条是临时层；不能把它们全部压成一个 enum 导致格式栏被误关。只对同级互斥子菜单使用 `activePicker: heading/time/none`；hover flags 是观察状态，可保留。

文档切换、离开页面、宿主销毁：先完成现有 composition flush，再关闭 owned overlay、取消异步回调/监听、清理旧文档 Undo 和选区。异步文件选择/宿主动作需要携带文档身份；只回写仍绑定的文档，不能把旧选区恢复到新任务。

## 4. 行为合同：保留资产，不顺手重新设计

### 焦点、选区与 Undo

- 打开格式栏保留正文焦点与选区；动作执行后按现有行为保持格式栏。
- 弹层输入允许拿焦点（链接输入、文件选择），但取消不修改文档，恢复同一文档的有效选区。选择操作不能因为按钮 first responder 而丢失目标。
- IME 组合期间不得重投影 storage、执行格式、删除 Slash trigger 或被全局 Escape monitor 提前消费。保留已提交中文顿号的触发例外。
- `/` 与 `、` 仅在首位置或前字符为空白时触发；文字后、普通选区替换不触发。Task/Note compact Slash 当前不做 query；整合不新增搜索。
- Slash 选择命令时 trigger 清理+文档格式操作维持一个文档 Undo group；Escape 保留触发文字。
- 文档动作走 editor Undo；子任务等业务动作走 Application Undo。一个组合动作跨两者不能假装天然原子，先保留现有语义并单列验收，不新增全局 Undo 总线。
- 正文 checklist 是 DocumentBlock，不是真实 child task。已有点击、checked 样式、命中和 undo 全部先锁基线，不借整合改变产品表现。

### Escape：一个合同，不硬塞一条无条件总排序

1. 系统 modal/IME 拥有当前输入时先退让；共享窗口路由和 text responder 必须遵守相同前置条件。
2. 可交互的最深 child picker 先关闭，只消费一次；tooltip 不消费 Escape。
3. 正文 responder 的既有链保持：Slash → Selection toolbar → 系统 find bar → Host callback。
4. Host callback 保持当前差异：Task footer 子层 → formatting toolbar → 浮动详情/活动任务弹层 → 结束编辑 → 窄屏返回；宽屏保留 Inspector。Note formatting toolbar → 结束编辑，后续导航由 Note Host 决定。
5. 不用本次整合重新排序 tags/relation 与格式栏；若要改变产品顺序，需单独 interaction contract + 实机验证。

接入已有 PopupEscapeRegistry/Router，而不是同时维护新的 window monitor。整合时证明同窗一次事件只走一个出口、其他窗口和隐藏 owner 不消费；不能仅因 unit tests 通过就声称真人键盘链通过。

### 浮层规范：统一政策，多套适配器

| 类型 | 锚点/宿主 | 生命周期与约束 |
|---|---|---|
| Slash | caret / 所属编辑窗口的非激活 Panel | 保留输入焦点；跟随滚动/窗口；下方优先，空间不足 flip/clamp；列表内部滚动 |
| Selection toolbar | selection / 非激活 Panel | 保留有效 range；取消后同一选区不立即重开；更新/滚动需要重算 anchor |
| Formatting toolbar | Host Footer/control anchor | 持久层；child picker 不影响父框、正文高度和按钮位置 |
| Heading/Time child | 工具栏按钮 bounds | 一个 child；保留 hover bridge；开关前后 icon/text/control frame 不变 |
| Tooltip | 控件 bounds | 仅展示；不进入 Escape 栈、不抢焦点；child 打开时抑制 |
| Tags/Relation | Host 控件/显式 parent window | 复用 popup 政策；业务 draft/commit 在 Host |
| Link/Attachment | 当前原生 modal/open panel | 保留原生输入与确认语义；本轮不改成普通无焦点 overlay |

先抽纯 placement 算法和 owner/dismiss policy；Panel、SwiftUI overlay、系统 modal 保持独立 adapter，不强求一个万能 OverlayManager。可复用现有 Planning placement 规则，但不能让 Editor 长期依赖 Planning 业务模块；共享纯算法迁到 Infrastructure 后保留规划模块 wrapper。

绝对坐标统一转换为明确的 screen/window/editor coordinate space。测试锁 anchor/control frame，不只是 Metrics 常量。浮层不能进入父 fittingSize；边缘受限时内部滚动或翻转，不凭空放大页面。永久内容行的增加与临时浮层展开分开处理。

## 5. 渐进实施与门禁

| 阶段 | 仅做范围 | 验收后才进入下一阶段 |
|---|---|---|
| EP-000 基线清单 | 记录现有能力、入口、策略和测试；固定当前 Task/Note 实机样本 | 所有资产有证据状态；未知项明确保留，不标全通过 |
| EP-001 命令描述 | 稳定 ID/descriptor/layout + adapter；一次迁移一个入口 | 相同命令目标/active state/help；旧新输出、顺序、截图不变 |
| EP-002 Host/Profile | Task/Note profile factory、host actions、引用 payload | 根/子任务资格不变；Core 无 Task/Note 类型依赖；选择创建任务不丢关联 |
| EP-003 Session/交互 | 清理状态归属；统一 Escape 前置条件、文档身份与取消原因 | composition/selection/undo/文档切换不退化；不改视觉 |
| EP-004 Overlay adapter | Slash、选区、toolbar child 逐个迁移定位/生命周期 | 真实窗口 frame、滚动跟随、边缘避让、focus 与 Esc；一类通过再迁下一类 |
| EP-005 能力矩阵 | 补跨入口、Codec fixture、真实窗口测试 | 源码/自动/实机证据分别登记；缺一项不能标全部冻结 |

每笔只处理 1～3 个合同；EP-001/EP-004 可拆多笔，不承诺四个大提交能安全完成全部整合。Profile 提取可与测试 fixture 补充并行（互斥写集）；命令接口确定后再让入口迁移并行，不让多人同时改 NativeTextView。

推荐第一笔：**稳定 Command ID + Catalog adapter + Slash glyph 映射**，保留现有命令执行和布局。验收用父/子 Task 和 Note 的命令集合、顺序、图标映射及旧格式行为；不同时动 Escape/IME/浮层。

## 6. 能力矩阵与证据规则

矩阵每行记录：能力 ID、Task/Note availability、各 placement、active/mixed、目标范围、Undo owner、codec fixture、自动证据、实机证据。未出现的入口记“产品不提供”，不是待补功能。

保护能力：空文档/文末空 block、标题即时字号、连续有序编号、无重复 TextKit marker、自绘 checklist/quote/gutter/空行 +、toolbar active/tooltip/picker、Slash 双触发/hover/滚动/flip、selection 抑制、链接/附件/图片粘贴、IME、独立 Undo、文档切换、Esc。保留“Markdown 符号作为普通文本”的已有产品规则，不引入自动格式转换。

复用当前 `NativeDocumentTests / DocumentContentTests / NativeTextViewTests / DocumentFormatStyleTests / DocumentDecorationRenderTests / DocumentProfileTests / SlashSessionTests / DocumentEditorStateTests / PopupEscapeRoutingTests`；不为了命名整齐批量移动或删除已有测试。新增的是跨入口 capability cases 和窗口级链路。

本轮核对的测试源码证据（不等于本轮运行通过）：

| Test（均位于 `macos-native/WorkFollowTests/`） | 已有断言 | 不能替代的验收 |
|---|---|---|
| `NativeTextViewTests.testCompositionIsNotPublishedUntilCommitted` | 手动 marked text 提交前不发布 | 真实中文输入法组词、取消、提交 |
| `SlashSessionTests.testSlashAndIdeographicCommaOpenTheSameFormatPaletteForTasksAndNotes` | 双触发符和 Task/Note profile | 真正宿主中的菜单装配、焦点和命令效果 |
| `DocumentProfileTests.testTaskSlashCommandsMatchFlutterOrderAndLabels` | 合成父子 Profile 集合/顺序 | Host eligibility 与正文 checklist 不创建 child 的组合测试 |
| `SlashSessionTests.testDocumentRebindClearsUndoAndSlash` | 重绑清 Undo/Slash | picker/IME 活动期间实际切换文档 |
| `PopupEscapeRoutingTests.testWindowOwnershipDepthAndCleanup` | 窗口归属、深度、清理 | 嵌套 editor/host 浮层的真实连续 Escape 链 |

因此 EP-000 不从零补所有测试，优先补“入口装配 → 相同命令结果”“真实宿主 checklist/child 边界”“嵌套浮层+文档切换”三类组合缺口。对更长的内容/格式测试未逐项审计，不据此宣称能力矩阵完整。

Codec round-trip 按语义比较 blocks/runs/marks/附件 payload/空段，允许明确定义的 normalization；不要求原始 attributed string/新 block identity 逐字节一致。Host 命令不进入 codec round-trip。

冻结标准：上述资产不退化；业务与文档边界成立；稳定 ID 无重复、所有 placement 解析到唯一执行目标；真实 Task/Note 窗口完成常用输入、格式、Slash、选区与 Esc 链，含中文输入。自动通过不能替代新构建实机验收。

**Editor Platform 尚未整体完成或冻结**。不新增 Checklist、Slash 搜索、附件编辑器、评论等功能；不在此阶段同时改变 Task/Note 页面几何或主题。

## 7. 执行记录

### EP-001 第一笔：稳定格式命令身份与 Slash adapter

- `DocumentFormatCommand.swift` 增加纯元数据 `EditorCommandDescriptor` 和 `EditorCommandCatalog`。16 个既有格式命令有稳定语义 ID；compact Slash 顺序使用显式 ID 清单，图标从格式语义得到，不依赖数组下标。
- `DocumentProfile` 的 compact/generic Slash 统一经 `slashCommand` adapter 转换；仍调用原 `applyFormat`，保留 Slash 的 lineStart invocation。标题、分组、关键词和查询政策不变。
- `DocumentCommand` 支持入口 glyph override。Task/Note compact 使用语义 glyph，generic 原来是正文图标的格式项仍保持正文图标；不借 ID 迁移改变外观。原 host/插入命令 ID 保留。
- 移除 `task.format.0..6`、`format.9` 等位置身份及其测试依赖。没有修改生产持久文档格式、IME、Undo、popover 或 Escape 实现。
- 62 项定向测试运行通过：DocumentProfile、SlashSession、DocumentContent、DocumentFormatStyle、NativeTextView、DocumentEditorState、DocumentDecorationRender。新增覆盖唯一 ID、逆序描述查找的图标一致性、Profile 身份与图标策略、16 项格式 adapter 和直调结果一致。
- 证据：`/tmp/workfollow-editor-command-tests.log`。构建最新 App 已完成；本笔没有重新进行真人输入法、全部按钮实机截图或完整 popup 链验收，不据此冻结 Editor Platform。
- 仍待迁移：格式栏/选区/右键入口的 descriptor 消费、统一 enabled/active 策略和 Host descriptors；当前 Catalog 仅覆盖格式能力，不声称已实现完整 Registry/Dispatcher。
- 下一笔限定为格式栏与选区的描述消费（不改执行与布局）；通过后再推进 Host/Profile 与交互状态。

### EP-001 第二笔：格式栏与选区工具条共享描述

- Descriptor 增加格式目标、工具条 symbol、入口专属标题和 `isActive`。粗体/列表/引用等格式栏按钮、选区六个行内格式按钮消费同一描述；不再在选区 View 单独 switch 图标、在格式栏反复传标题+symbol+查找条件。
- Selection 顺序和 Heading picker 顺序显式引用稳定 ID；标题菜单文字从相同描述读取。保留格式栏“代码”与选区“行内代码”的入口文案差异，高亮仍绘制 A 标签，通用 Slash 图标策略仍不变。
- 格式栏既有 444×38pt 与 26×28pt 控件、选区 24×26pt 控件，以及按钮分组/顺序均保留。增加不参与 sizing 的控件 frame preference，供实际渲染验收使用。
- 新增真实 NSWindow/NSHostingView 控件几何与顺序测试，并发送实际窗口鼠标事件点击两栏“粗体”：同一选区经过两入口 toggle 后恢复非粗体，range 保持。不是仅测试 Catalog 常量。
- 64 项编辑器回归通过，证据：`/tmp/workfollow-editor-toolbar-tests.log`。本笔未重新做真人输入法或完整 Task/Note 弹层实机截图，不宣称像素/交互全部验收。
- 链接、附件、时间容器、Host 业务动作仍沿用旧通道；未将全部命令迁入 Dispatcher。`note.createTask` 短标题分支及 Task/Note 现场拼 Profile 留到 EP-002，不夹带本轮修改。
- 下一笔：EP-002 提取 Task/Note Profile 与窄 Host Actions，保留能力资格、触发政策、业务关联和执行路径；随后再处理交互状态。

### EP-002 第一笔：宿主 Profile 与业务模型边界

- 新增 Tasks 模块 `TaskDocumentProfile / TaskEditorHostActions`，从 Inspector 迁出 child/tags/relation 的描述装配。View 仍负责页面状态与请求 child 编辑器；Profile 只提供资格、顺序和窄回调，不把 Workspace 注入 Editor。
- 新增 Notes 模块 `NoteDocumentProfile / NoteEditorHostActions`，将 selection→task 的 trim、收集箱创建和 linkedTaskIDs 追加逻辑从页面迁到宿主 action factory，操作路径和业务 Undo 不变。
- `DocumentSelectionAction` 增加可选 toolbarTitle；Core 直接消费元数据，移除 `note.createTask` 的短标题特判。完整标题继续用于 help/右键。Profile 提供显式 selectionToolbarEnabled；nil 为旧调用兼容策略，不在本笔删除 taskSlash/noteSlash 或改变查询行为。
- 通用 `EditorReference(title,target)` 替代 Core `insertNoteReference(Note)`。宿主把 Note 变成相同的“📄 标题 + workfollow URL”值，再走原有富文本插入；真实 Task 的 sourceNote 关系仍由宿主原路径写入。
- 定向源码检查：Editor 文件中没有 Task/Note/TaskWorkspaceModel/NotesWorkspaceModel 的业务类型调用，只有边界说明注释。现有 InspectorEscapeEffect 和业务 glyph 的兼容映射仍在，不声称已形成完全独立编译模块或完整 Dispatcher。
- 82 项回归通过，证据：`/tmp/workfollow-editor-profile-tests.log`。新增覆盖实际 factory 的父12项/子11项、回调路由、NoteHost 创建任务/保留既有关联/空文本不创建、任意宿主短标题、命名/未命名笔记引用文本与链接。
- 本笔无新的真人输入法、Task/Note 完整 popup 链或像素级实机验收；既有格式工具条真实窗口测试仍通过。最新 App 已构建，不据此冻结平台。
- 下一笔：EP-003 先核对编辑器/宿主关闭规则和文档切换状态归属，按现有行为增加组合合同；不直接改写 Escape 顺序或整体替换浮层实现。

### EP-003 第一笔：文档生命周期与 Escape 决策合同

- 文档切换和卸载统一调用 `NativeTextView.resetDocumentInteraction`：关闭 Slash/选区子窗口、移除 Slash 观察者、清除待定选区/文末 block/caret reveal、切换文档身份、清除本编辑器 Undo。不清理其他窗口或宿主业务状态。
- Coordinator 负责先把未提交组词发布到旧文档，再重绑新文档；卸载走统一 `detach`，提交后断开 delegate、编辑/选区/Escape 回调与 Profile。新文档的文末段落级别仍由模型重新播种，不把清理等同于丢弃文档数据。
- `DocumentEditorEscapeRoute` 显式保留既有优先级：输入法 → Slash → 选区浮条 → 查找栏 → 宿主。宿主内的格式栏/属性弹层/结束编辑/窄屏返回仍由原宿主合同决定，不在此处改变顺序。
- 共享 Popup Escape monitor 在 firstResponder 正在组词时退让，不抢先关闭注册浮层。DocumentEditor 的工具条 style 刷新移到 Coordinator 重绑之后，避免读取旧文档样式。
- 新增实际 NSWindow 下 Slash 子窗口/观察者清理、选区浮条卸载/回调断开测试；新增旧文档组词提交归属、Escape route、共享 router 组词退让测试。98 项 Editor/Note/Popup/Inspector 定向回归通过，证据：`/tmp/workfollow-editor-interaction-tests.log`；最新 App 已构建。
- marked-text 测试是 AppKit 自动化模拟，不等同于真人中文输入法验收；本笔没有新做完整 Task/Note 连续 Escape 链或像素截图。工具条刷新时序修改没有单独的跨文档 SwiftUI 渲染断言，不扩大自动证据范围。
- 后续仍需收拢宿主交互状态与浮层 placement adapter，并补实际入口的连续 Escape/切换文档验收。只完成生命周期第一笔，不宣称 Editor Platform 已冻结。

### 编辑器几何纠偏：装饰沟槽不占正文宽度

- 用户发现空行切换一级标题时右移。源码原因：渲染段落使用20pt沟槽，但初始空文档沿用NSTextView默认零缩进输入属性；此外宿主没有补偿沟槽宽度，编辑区正文相对placeholder整体右移。
- 合同：H1/H2/H3与空行“+”属于正文前的装饰区，不改变输入内容起点或可用正文宽度。普通段落和标题共用正文基线；列表/引用自己的语义缩进保留。
- `DocumentEditor` 统一前置20pt装饰区，由内部TextKit桥承载，宿主不用分别补padding。TextKit内部继续保留可绘制沟槽（避免裁剪标记），外层前置同宽区域补偿，不把它计入宿主正文宽度。默认输入属性与渲染段落统一；新建视图同步文末空段级别。
- 新增NSWindow + NSHostingView几何测试：宿主40pt边距时正文起点45pt（包含TextKit原有5pt内衬），装饰视图从20pt开始；空行转H1的caret X保持不变。
- 73项编辑器回归通过，证据：`/tmp/workfollow-heading-alignment-tests.log`。最新构建的窗口截图已目检：`/tmp/render_heading_host_alignment.png`；H1位于文字前方且可见。这是隔离编辑器窗口验收，不代称完整Task/Note页面实机验收。

### Task Slash 行为与渲染第一轮

- 生产Task/Note Profile显式提供自己的Slash清单；通用Profile保留兼容fallback，共享adapter只执行格式/分割线/附件。稳定ID、现有顺序、查询策略、业务回调与几何不变。
- 补真实workspace的检查项/child区分、标签/关联调用前触发符消费、格式与分割线单次Undo、hover/键盘/Escape，以及NSPanel四状态截图和滚动/窗口跟随合同。
- 修首次呈现读取尚未完成布局caret的问题，首轮布局后校正一次，绑定文档身份与当前面板。
- 103项定向回归通过。完整证据、关系能力缺口与宿主端到端待验项见 [native-task-slash-contract.md](native-task-slash-contract.md)。Task Slash不提前冻结。
