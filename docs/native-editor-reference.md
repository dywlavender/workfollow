# Native task editor：Flutter 原版对照

审计日期：2026-09-26，已按当前 Native 源码复核。范围仅含任务 Inspector 的标题/正文编辑区、底部格式入口、`/` 命令面板与相关 Escape 行为。本文件是源码和现有记录的对照；Native 真窗口行为只按控制文档标明为“主控报告”，不冒充本子任务独立验收。

证据标记：**源码事实**表示能从当前代码直接确认；**测试事实**表示 Flutter 测试明确断言；**截图事实**只说明已存图片呈现的静态外观；**推断/建议**是按 Flutter 当前行为作为迁移基准得出的待实施项。

## 结论

Native 已有可编辑标题、正文、横向格式条和 `/` 命令面板。当前源码已补上 Flutter 工具条中的 H3、分割线、时间入口和行内代码；标题占位文案也已区分父/子任务。源码层命令覆盖明显接近，但交互仍未完全相同：

1. Flutter 的“插入当前时间”会弹出日期、日期时间、时间三种格式；Native 当前直接插入固定的 `yyyy-MM-dd HH:mm`。工具条都为 444×38 左右，但 Flutter 居中锚定在触发按钮上方，Native overlay 靠 Footer 右侧。
2. Flutter `/` 面板是小尺寸、分组、无搜索输入的固定命令集合；Native 当前提供搜索过滤，命令集合和触发条件也不同。

因此目前应记为 **FORMAT BAR = IMPLEMENTED / SOURCE COMMANDS MOSTLY MATCH, INTERACTION PARTIAL；SLASH = NOT PARITY VERIFIED；EDITOR GATE = NOT PASSED**。Native 新增的 H3/分割线/时间/行内代码尚无逐项真窗口操作证据；格式条的选区、Escape 和宽窄窗口仍应按控制记录逐项验收。

## 1. 编辑区与底部格式入口

| 项目 | Flutter 当前行为 | Native 当前代码 | 对齐判断 |
|---|---|---|---|
| 编辑区组成 | Inspector 正文区纵向放置标题输入和任务文档；正文使用共享 `DocumentEditor`，Footer 独立固定在滚动正文之外。见 `desktop/lib/widgets/task_inspector.dart:534-615`、`desktop/lib/features/editor/presentation/document_editor.dart:608-719`。 | Native 顶栏固定 56pt；标题、内容高度自适应的 `DocumentEditor` 和子任务位于外层 `ScrollView`；Footer 固定 48pt。见 `TaskInspectorShell.swift:45-58,138-142,332-345`、`DocumentEditor.swift:38-77`。 | 结构方向相近。主控记录称 35 段长正文可滚到子任务且 Footer 保持固定；布局边界仍需真窗截图核验。 |
| 标题 | 独立 `TextField`，`onChanged` 直接调用 `setTitle`；父任务占位文案“任务标题”，子任务“准备做什么？”。见 `desktop/lib/widgets/task_inspector.dart:559-574`、`desktop/lib/features/editor/presentation/document_title_editor.dart:37-54`。 | 独立 SwiftUI 多行 `TextField`，draft 改动调用 `workspace.setTitle`；父/子占位文案分别为“任务标题”/“准备做什么？”。见 `TaskInspectorShell.swift:489-503`。 | **占位文案已对齐**；输入焦点、IME 和多行标题行为仍需 Native 真窗口验收。 |
| Footer 布局 | 左侧清单入口；右侧格式按钮、更多按钮，中间状态槽。见 `desktop/lib/widgets/task_inspector.dart:467-531`、`desktop/lib/features/editor/presentation/document_editor_footer.dart:28-56`。 | 左侧清单 `Menu`；右侧格式按钮和更多 `Menu`。见 `TaskInspectorShell.swift:75-115`、`:352-377`。 | Footer 槽位与入口形态已基本对齐；格式条几何和命令仍有差异。 |
| 格式入口 | 点击 `document-format-toggle` 调用 `toggleToolbar`，弹出可切回正文继续编辑、执行格式命令后仍保持打开的持久横向工具条。宽 444、高 38，锚在触发按钮上方并水平居中。见 `desktop/lib/widgets/task_inspector.dart:513-518`、`desktop/lib/features/editor/presentation/document_editor.dart:291-334`、`desktop/lib/theme/workfollow_theme.dart:217-218`。 | Footer 按钮切换 `showFormattingToolbar`；横条以 overlay 呈现，最多宽 444、高 38，代码对齐到 Footer 右下。任务切换时关闭，Escape 先关闭横条。见 `TaskInspectorShell.swift:138-142,196-230,292-310`。 | **入口与持久显示方向已对齐，位置及时间入口语义仍不同。** 主控记录称真窗口已验证选中文字→打开工具条→粗体后工具条保持，Escape 收起且 Inspector 保留；记录在 `docs/native-migration-control.md:17-18`。Flutter 静态基准见 [`task-editor-format.png`](screenshots/task-editor-format.png)，不是 Native 截图。 |

### 格式工具条命令集合

- **Flutter 横向工具条（源码事实，`desktop/lib/features/editor/document_editor_toolbar.dart:137-225`）：** 标题选择、粗体、高亮、检查项、无序/有序列表、斜体、下划线、删除线、分割线、插入当前时间、链接、行内代码、引用、附件。标题选择另有正文/H1/H2/H3 picker（`:73-104`）。时间按钮会打开三选项弹层：日期、日期+时间、仅时间（`:106-136`）。
- **Native 当前横向工具条（源码事实，`macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift:196-230`）：** 标题菜单（正文/H1/H2/H3）、粗体、高亮、检查项、无序/有序列表、斜体、下划线、删除线、分割线、时间、链接、行内代码、引用、附件；相较此前审计已补齐 H3、分割线、时间入口和行内代码。
- **仍存差异：** Native 的时间按钮直接插入固定 `yyyy-MM-dd HH:mm`，Flutter 允许在日期/日期时间/时间三种格式中选择；Native 工具条靠 Footer trailing overlay，Flutter 以触发按钮为锚点并水平居中。Native 虽有全部对应图标/入口，H3、分割线、时间、行内代码和附件尚无逐项 Native 真窗口证据，不能仅按源码入口记行为通过。
- **主控真窗记录（非本子任务独立操作）：** `docs/native-migration-control.md:17-18` 记录了选区粗体、横条在格式操作后保持、Escape 收起且任务选择保留，以及构建/测试返回成功；没有导出到仓库的 Native PNG。窄窗口和全部工具项不因此自动验收。
- **状态保持测试事实：** `desktop/test/task_formatting_toolbar_persistent_test.dart:11-58` 断言 Flutter 工具条在回到正文及执行格式操作后继续显示，点击触发按钮可关闭；`:60-93` 断言 Escape 关闭工具条但保留任务选择；`:134-163` 断言窗口变窄后仍被约束在视口内。Native 主控当前记录只确认了粗体及 Escape；最新增补命令、窄窗边界与锚点尚待逐项验收。

## 2. `/` 命令面板

### 触发、搜索与键盘

| 行为 | Flutter 当前行为 | Native 当前代码 | 对齐判断 |
|---|---|---|---|
| 触发 | 只在本次编辑确实插入一个 `/` 时打开；在普通文字后也可触发（测试覆盖 `abc/`）。见 `desktop/lib/features/editor/slash_command_session.dart:21-59`、`desktop/test/task_slash_session_test.dart:85-107`。 | 只在插入 `/` 且此前为空或以空白结尾时开启；紧跟普通字符的 `/` 被当作普通路径/URL 字符。见 `NativeTextView.swift:17-28`。 | **条件不一致。** Flutter 用“是否刚插入”识别命令，不把前导空白当触发条件。 |
| 输入查询 | Flutter 会在 caret 离开 slash 后立刻结束 session，注释明确写了当前没有 query/filter mode；菜单内没有搜索字段。见 `document_editor.dart:162-179`、`:469-489`、`DocumentSlashMenu` 的构建 `document_slash_menu.dart:347-389`。 | 可在 `/` 后继续输入 query；`SlashSession.update/results` 更新并按命令标题/keywords 过滤。见 `DocumentProfile.swift:33-64`、`SlashCommandPanel.swift:14-22`、`:71-103`。 | **产品交互不一致。** Native 额外实现了 Flutter 当前没有的搜索式 slash 输入。 |
| 键盘/焦点 | 菜单不接管焦点；编辑器路由 ↑/↓ 和 Enter 给当前命令，Escape 先关闭 slash。见 `document_slash_menu.dart:254-299`、`document_editor.dart:629-687`。 | 非激活 `NSPanel` 作候选窗；`NSTextView.doCommand` 处理 ↑/↓、Enter、Escape。见 `NativeTextView.swift:45-55`、`SlashCommandPanel.swift:23-45`。 | 目标都是保留正文焦点并支持键盘，但 Native 实际 responder/鼠标行为尚未真窗口核验。 |
| Escape 后文字 | Flutter 关闭菜单，不自动删掉插入的 `/`；选择命令时再移除该 slash。见 `document_editor.dart:85-89`、`:503-508`、`:567-597`。 | Escape 关闭候选窗并保留 slash/query；执行命令时移除 session 的整个 `/query`。见 `NativeTextView.swift:50-52`、`SlashCommandPanel.swift:54-67`。 | Escape 的“关闭但保留输入”一致；由于 Native 支持 query，执行命令时删除范围更长。 |

### 命令集合

**Flutter 任务面板（源码事实）：** 8 个格式项（H1、H2、H3、无序列表、有序列表、检查项、引用、水平分割线）加“附件”；任务 profile 追加“子任务”（仅父任务）、“标签”、“关联任务/笔记”。父任务共 12 项，子任务不提供“子任务”入口。见 `desktop/lib/features/editor/document_slash_menu.dart:98-173`、`desktop/lib/features/editor/profiles/task_editor_profile.dart:92-138`；测试在 `desktop/test/task_document_editor_test.dart:160-215`、`desktop/test/task_slash_subtask_test.dart:71-128`。

**Native 任务面板（源码事实）：** `DocumentProfile.slashCommands` 把 16 项 `DocumentFormatCommand.commands` 与“编辑链接”“插入附件”及父任务专属“创建子任务”合并。当前父任务 19 项、子任务 18 项。见 `macos-native/WorkFollow/Features/Editor/DocumentProfile.swift:18-30`、`DocumentFormatCommand.swift:19-35`、`TaskInspectorShell.swift:332-342`。

**集合差异：** Native task slash 当前没有 Flutter 的“标签”“关联任务/笔记”和水平分割线；同时暴露正文、代码块、已勾选清单、行内代码、粗体/斜体/下划线/删除线/高亮和编辑链接等 Flutter slash 没有的项。虽然 H3 已加入 Native 格式命令，但命令项、分组顺序仍不等价；两边不要因“都有 slash menu”就视为功能等价。

### 面板尺寸与外观

- Flutter 面板宽 160pt，固定小行高；默认高度由命令数计算，窗口不足时缩短并滚动。锚定策略首选 caret 的 `bottomStart`。见 `desktop/lib/theme/workfollow_theme.dart:217-223`、`document_slash_menu.dart:182-204`、`document_editor.dart:510-548`。
- Native 面板宽最多 300pt，最多显示 8 行、每行 44pt；在 caret 上方有空间时放上方，否则放下方。行尾显示 group，顶部显示搜索/键盘提示。见 `SlashCommandPanel.swift:14-45`、`:71-103`。
- **截图事实：** 仓库现有 `docs/screenshots/` 未找到 slash 面板截图；Flutter slash 的内容、尺寸和键盘行为由上述源码及 widget tests 覆盖。本审计没有捕获 Native 新截图。

## 3. 正文模型、保存与子任务

- Flutter `TaskDocumentEditor` 明确把标题保持为普通输入框，正文作为 Quill Delta；`TaskEditorProfile.persist` 同时保存结构化内容和 plain-text 投影。见 `desktop/lib/widgets/task_document_editor.dart:15-22`、`desktop/lib/features/editor/profiles/task_editor_profile.dart:62-70`。任务正文支持 slash embeds/任务块，profile 还可在正文后挂子任务、附件、来源笔记面板（`:141-163`）。
- Native 使用 `NSTextView`/`NativeDocument`；`DocumentEditorCoordinator.textDidChange` 解码 attributed string 并回调写入，输入法 marked-text 结束后提交；拆卸时 flush composition。见 `macos-native/WorkFollow/Features/Editor/DocumentEditor.swift:19-89`、`DocumentEditorCoordinator.swift:56-89`。
- Native task Shell 的 slash profile 当前仅增加创建子任务；子任务列表直接作为正文之后的 SwiftUI 行呈现。见 `TaskInspectorShell.swift:54-98`、`:260-289`。Flutter 也将真实子任务列表接在文档之后，支持行内改名、勾选和单独打开子任务 Inspector；见 `task_editor_profile.dart:145-163`、`desktop/lib/widgets/task_children_panel.dart:81-121`、`:232-318`。
- **判断边界：** 两边编辑器的文档表示和保存链不同；仅凭 UI 对照不能证明格式往返无损。将 Delta ↔ `NativeDocument` 的格式兼容列为独立数据/Domain 验收，不能把它算作本轮已经确认的视觉差异。

## 4. Escape 层级

- **Flutter 源码事实：** 正文快捷键先按 `slash → selection toolbar → formatting toolbar → Inspector callback` 关闭/转移；任务 Inspector callback 再处理任务弹层、从编辑区退焦到 Inspector，以及窄屏返回。见 `document_editor.dart:659-672`、`task_inspector.dart:126-138`。当前 task profile 的 `selectionActions` 为空（`task_editor_profile.dart:165-166`），所以任务正文实际不会显示选区动作条；通用 Escape 链里的 selection-toolbar 步骤对 task profile 是 no-op。
- **Native 源码事实：** `NativeTextView.cancelOperation` 先让 IME 处理，再关 slash、系统查找栏，之后交给 Inspector；Inspector callback 先关闭新加的格式条，再由 `TaskInspectorPresentationState.handleEscape` 依次关闭活动 popover、结束标题/正文编辑、窄屏返回列表（宽屏保留 Inspector）。见 `NativeTextView.swift:155-176`、`TaskInspectorShell.swift:292-310`、`TaskInspectorPresentationState.swift:34-44`、`TaskInspectorShell.swift:175-178`。
- **需真窗口确认：** Native 菜单/Popover 的 Escape 是否按目标顺序消费按键，以及标题/正文第一次 Escape 后的 responder 位置，不能由 SwiftUI 菜单声明 alone 证明。Flutter 对应链由 `desktop/test/task_inspector_layout_test.dart:178-234` 覆盖；格式条单独由 `task_formatting_toolbar_persistent_test.dart:60-93` 覆盖。

## 5. 纠偏建议（交主控实施/验收）

以下是按 Flutter 当前代码为基准的建议，不是已经实施的改动：

1. **P0 — 格式工具条语义与验收**：保留已实现的横向浮条和对应命令入口；把 Native 时间按钮改为 Flutter 的日期/日期时间/时间三选项，核对浮条锚点与视口边界、选区保持、窗口缩窄和 Escape，并逐项真窗口验收新增的 H3、分割线、行内代码及附件操作。右键格式菜单作为额外入口保留即可。
2. **P0 — slash 任务命令**：收敛 Native 命令清单到 Flutter task profile 的命令和顺序，补齐标签、关联任务/笔记和水平分割线；父子任务差异保持一致。格式具体执行结果另做文档格式往返测试。
3. **P1 — slash session**：以 Flutter 当前契约决定触发及输入行为：刚插入 slash 才开启，不限制其前面必须空格；目前不把 `/query` 搜索作为 parity 功能。若产品要保留 Native 搜索，应明确将其视作 Native 增强，而不是声称与 Flutter 相同。
4. **P1 — slash 面板几何**：对齐 Flutter 160pt 菜单宽度、分组分隔、图标行、caret 附近的 placement 和受限窗口滚动；最后通过 Native 真窗口截图验收。
5. **P1 — Escape/焦点**：在 native 实机确认 IME、slash、格式工具条/系统菜单、Popover、正文焦点、Inspector/窄屏返回的逐次 Escape 链，与 Flutter 定向测试逐步对照。

## 证据索引

- Flutter 基线截图：[`task-editor-format.png`](screenshots/task-editor-format.png)、[`task-editor-detail.png`](screenshots/task-editor-detail.png)、[`task-editor.png`](screenshots/task-editor.png)。前两张展示正文与 Footer/格式条静态布局；不涵盖 slash 面板。
- Flutter 行为测试：`desktop/test/task_document_editor_test.dart:160-290,383-439`；`desktop/test/task_slash_session_test.dart:18-38,85-128,241-283`；`desktop/test/task_slash_subtask_test.dart:71-128`；`desktop/test/task_formatting_toolbar_persistent_test.dart:11-163`；`desktop/test/task_inspector_layout_test.dart:178-260`。
- Native 主要实现：`macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift`；`macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorPresentationState.swift`；`macos-native/WorkFollow/Features/Editor/NativeTextView.swift`；`SlashCommandPanel.swift`；`DocumentProfile.swift`；`DocumentFormatCommand.swift`。
