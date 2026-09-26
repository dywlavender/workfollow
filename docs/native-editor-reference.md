# Native task editor：Flutter 原版对照

审计日期：2026-09-26，已按当前 Native 源码复核。范围仅含任务 Inspector 的标题/正文编辑区、底部格式入口、`/` 命令面板与相关 Escape 行为。本文件是源码和现有记录的对照；Native 真窗口行为只按控制文档标明为“主控报告”，不冒充本子任务独立验收。

证据标记：**源码事实**表示能从当前代码直接确认；**测试事实**表示 Flutter 测试明确断言；**截图事实**只说明已存图片呈现的静态外观；**推断/建议**是按 Flutter 当前行为作为迁移基准得出的待实施项。

## 结论

Native 已有可编辑标题、正文、横向格式条和 `/` 命令面板。当前源码中的日期/日期时间/仅时间入口与 Flutter 语义一致；任务 Slash 命令也已收敛为 Flutter 对应顺序，任务模式不提供查询过滤。格式条从 Footer trailing 改为在 Footer 水平居中；最新构建真窗截图确认其位于 Inspector 水平中部，打开后正文继续持有焦点，立即按 Escape 可收起工具条并保持正文焦点。

因此目前应记为 **FORMAT BAR = CENTERED LAYOUT + FOCUS/Escape LIVE VERIFIED；TASK SLASH = COMMANDS AND QUERY CONTRACT SOURCE-ALIGNED / GEOMETRY PARTIAL；EDITOR GATE = NOT PASSED**。附件实际导入、输入法组词和紧凑窗口等缺口不能被测试通过数替代。

## 1. 编辑区与底部格式入口

| 项目 | Flutter 当前行为 | Native 当前代码 | 对齐判断 |
|---|---|---|---|
| 编辑区组成 | Inspector 正文区纵向放置标题输入和任务文档；正文使用共享 `DocumentEditor`，Footer 独立固定在滚动正文之外。见 `desktop/lib/widgets/task_inspector.dart:534-615`、`desktop/lib/features/editor/presentation/document_editor.dart:608-719`。 | Native 顶栏固定 56pt；标题、内容高度自适应的 `DocumentEditor` 和子任务位于外层 `ScrollView`；Footer 固定 48pt。见 `TaskInspectorShell.swift:45-58,138-142,332-345`、`DocumentEditor.swift:38-77`。 | 结构方向相近。主控记录称 35 段长正文可滚到子任务且 Footer 保持固定；布局边界仍需真窗截图核验。 |
| 标题 | 独立 `TextField`，`onChanged` 直接调用 `setTitle`；父任务占位文案“任务标题”，子任务“准备做什么？”。见 `desktop/lib/widgets/task_inspector.dart:559-574`、`desktop/lib/features/editor/presentation/document_title_editor.dart:37-54`。 | 独立 SwiftUI 多行 `TextField`，draft 改动调用 `workspace.setTitle`；父/子占位文案分别为“任务标题”/“准备做什么？”。见 `TaskInspectorShell.swift:489-503`。 | **占位文案已对齐**；输入焦点、IME 和多行标题行为仍需 Native 真窗口验收。 |
| Footer 布局 | 左侧清单入口；右侧格式按钮、更多按钮，中间状态槽。见 `desktop/lib/widgets/task_inspector.dart:467-531`、`desktop/lib/features/editor/presentation/document_editor_footer.dart:28-56`。 | 左侧清单 `Menu`；右侧格式按钮和更多 `Menu`。见 `TaskInspectorShell.swift:75-115`、`:352-377`。 | Footer 槽位与入口形态已基本对齐；格式条本身另按编辑区水平居中。 |
| 格式入口 | 点击 `document-format-toggle` 调用 `toggleToolbar`，弹出可切回正文继续编辑、执行格式命令后仍保持打开的持久横向工具条。宽 444、高 38，按编辑区水平中心定位在触发按钮上方。见 `desktop/lib/widgets/task_inspector.dart:513-518`、`desktop/lib/features/editor/presentation/document_editor.dart:291-334,336-351`、`desktop/lib/theme/workfollow_theme.dart:217-218`。 | Footer 按钮切换 `showFormattingToolbar`；横条最多宽 444、高 38，以 Footer 水平居中呈现。打开时显式把 first responder 交回正文；任务切换时关闭，Escape 先关闭横条。见 `TaskInspectorShell.swift:138-142,196-230,292-310`、`DocumentEditor.swift` 的 `focusEditor()`。 | **居中定位、开栏后正文焦点、立即 Escape 收栏均已在最新构建真窗验证。** 横条在格式操作后保持、任务选择保留的既有验收记录见 `docs/native-migration-control.md`。Flutter 静态基准见 [`task-editor-format.png`](screenshots/task-editor-format.png)，不是 Native 截图。 |

### 格式工具条命令集合

- **Flutter 横向工具条（源码事实，`desktop/lib/features/editor/document_editor_toolbar.dart:137-225`）：** 标题选择、粗体、高亮、检查项、无序/有序列表、斜体、下划线、删除线、分割线、插入当前时间、链接、行内代码、引用、附件。标题选择另有正文/H1/H2/H3 picker（`:73-104`）。时间按钮会打开三选项弹层：日期、日期+时间、仅时间（`:106-136`）。
- **Native 当前横向工具条（源码事实，`macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift:196-230`）：** 标题菜单（正文/H1/H2/H3）、粗体、高亮、检查项、无序/有序列表、斜体、下划线、删除线、分割线、时间、链接、行内代码、引用、附件；相较此前审计已补齐 H3、分割线、时间入口和行内代码。
- **仍存差异/验收项：** 时间菜单已提供“日期 / 日期时间 / 仅时间”三项，不再是固定格式；源代码也已按 Footer 水平居中呈现工具条。当前最新构建只实测了格式条定位、正文焦点和 Escape；H3、分割线、时间三种选择、行内代码和附件需要在当前构建中逐项复验，不能仅按源码入口记行为通过。
- **主控真窗记录：** 最新记录见 `docs/native-migration-control.md`，包含格式条水平居中、开栏后正文保持 first responder、立即 Escape 收起；较早真窗还显示过完整 Slash 命令集并验证键入查询字符后关闭。截图留在本对话工具结果中，没有导出到仓库的 Native PNG。窄窗口和全部工具项不因此自动验收。
- **状态保持测试事实：** `desktop/test/task_formatting_toolbar_persistent_test.dart:11-58` 断言 Flutter 工具条在回到正文及执行格式操作后继续显示，点击触发按钮可关闭；`:60-93` 断言 Escape 关闭工具条但保留任务选择；`:134-163` 断言窗口变窄后仍被约束在视口内。Native 主控当前记录只确认了粗体及 Escape；最新增补命令、窄窗边界与锚点尚待逐项验收。

## 2. `/` 命令面板

### 触发、搜索与键盘

| 行为 | Flutter 当前行为 | Native 当前代码 | 对齐判断 |
|---|---|---|---|
| 触发 | 只在本次编辑确实插入一个 `/` 时打开；在普通文字后也可触发（测试覆盖 `abc/`）。见 `desktop/lib/features/editor/slash_command_session.dart:21-59`、`desktop/test/task_slash_session_test.dart:85-107`。 | 任务模式在插入 `/` 时不要求前缀为空或空白；非任务 profile 才检查此前缀。见 `NativeTextView.swift:17-28`。 | **任务模式源码条件一致**；其他 profile 不在本次 Task Inspector 关卡内。 |
| 输入查询 | Flutter 会在 caret 离开 slash 后立刻结束 session，注释明确写了当前没有 query/filter mode；菜单内没有搜索字段。见 `document_editor.dart:162-179`、`:469-489`、`DocumentSlashMenu` 的构建 `document_slash_menu.dart:347-389`。 | 任务模式将 `allowsQuery` 设为 `false`，`/` 后继续输入字符会结束 session；一般 profile 仍保留 query 搜索。见 `SlashCommandPanel.swift:14-22`、`DocumentProfile.swift:18-30`。 | **任务模式源码条件一致**；通用 Slash 的搜索行为不属于本次任务 profile 契约。 |
| 键盘/焦点 | 菜单不接管焦点；编辑器路由 ↑/↓ 和 Enter 给当前命令，Escape 先关闭 slash。见 `document_slash_menu.dart:254-299`、`document_editor.dart:629-687`。 | 非激活 `NSPanel` 作候选窗；`NSTextView.doCommand` 处理 ↑/↓、Enter、Escape。见 `NativeTextView.swift:45-55`、`SlashCommandPanel.swift:23-45`。 | 已有真窗操作报告验证键盘 ↑/Enter 可调用标签选择；但当前构建尚未重跑这条完整链。 |
| Escape 后文字 | Flutter 关闭菜单，不自动删掉插入的 `/`；选择命令时再移除该 slash。见 `document_editor.dart:85-89`、`:503-508`、`:567-597`。 | Escape 关闭候选窗并保留 slash/query；执行命令时移除 session 的整个 `/query`。见 `NativeTextView.swift:50-52`、`SlashCommandPanel.swift:54-67`。 | Escape 的“关闭但保留输入”一致；由于 Native 支持 query，执行命令时删除范围更长。 |

### 命令集合

**Flutter 任务面板（源码事实）：** 8 个格式项（H1、H2、H3、无序列表、有序列表、检查项、引用、水平分割线）加“附件”；任务 profile 追加“子任务”（仅父任务）、“标签”、“关联任务/笔记”。父任务共 12 项，子任务不提供“子任务”入口。见 `desktop/lib/features/editor/document_slash_menu.dart:98-173`、`desktop/lib/features/editor/profiles/task_editor_profile.dart:92-138`；测试在 `desktop/test/task_document_editor_test.dart:160-215`、`desktop/test/task_slash_subtask_test.dart:71-128`。

**Native 任务面板（源码事实）：** `DocumentProfile.slashCommands` 按 Flutter 顺序组合 7 个格式项、水平分割线、附件，再追加 profile 注入的任务动作。父任务为 12 项（含子任务），子任务为 11 项；标签为“检查项”。对应回归见 `macos-native/WorkFollowTests/DocumentProfileTests.swift`。见 `DocumentProfile.swift:18-30`、`DocumentFormatCommand.swift:19-35`、`TaskInspectorShell.swift` 中任务 profile 构建。

**集合差异：** 源码当前没有发现任务 Slash 命令标题、数量或顺序方面的差异；父子任务差异也一致。该结论是源码与回归测试事实，不等于完整的真窗操作验收。此前真窗画面曾显示完整 12 项，键入一个查询字符后菜单关闭；标签、关联、附件、子任务及格式命令仍需在最新构建下逐项实际操作。

### 面板尺寸与外观

- Flutter 任务面板宽 160pt，命令项约 34pt 高，按内容计算默认高度；窗口不足时缩短并滚动，锚在 caret 的 `bottomStart`。见 `desktop/lib/theme/workfollow_theme.dart:217-223`、`document_slash_menu.dart:182-204`、`document_editor.dart:510-548`。
- Native 任务面板宽 160pt、每项 32pt，默认锚在 caret 上方，空间不足时放下方；有限窗口中缩短并滚动。见 `SlashCommandPanel.swift` 与 `NativeTextView.swift:35-39`。
- **可确认的几何差异：** 行高和优先 placement 不同（Flutter 34pt/bottomStart；Native 32pt/above-first）。应在后续编辑器真窗操作里比较遮挡、滚动和边界，不要仅按“窗口内可见”视为完全一致。
- **截图事实：** 仓库现有 `docs/screenshots/` 未找到 slash 面板截图；Flutter slash 的内容、尺寸和键盘行为由上述源码及 widget tests 覆盖。Native Slash 截图保留在本对话工具结果中，没有导出为仓库文件。

## 3. 正文模型、保存与子任务

- Flutter `TaskDocumentEditor` 明确把标题保持为普通输入框，正文作为 Quill Delta；`TaskEditorProfile.persist` 同时保存结构化内容和 plain-text 投影。见 `desktop/lib/widgets/task_document_editor.dart:15-22`、`desktop/lib/features/editor/profiles/task_editor_profile.dart:62-70`。任务正文支持 slash embeds/任务块，profile 还可在正文后挂子任务、附件、来源笔记面板（`:141-163`）。
- Native 使用 `NSTextView`/`NativeDocument`；`DocumentEditorCoordinator.textDidChange` 解码 attributed string 并回调写入，输入法 marked-text 结束后提交；拆卸时 flush composition。见 `macos-native/WorkFollow/Features/Editor/DocumentEditor.swift:19-89`、`DocumentEditorCoordinator.swift:56-89`。
- Native task Shell 的 slash profile 当前仅增加创建子任务；子任务列表直接作为正文之后的 SwiftUI 行呈现。见 `TaskInspectorShell.swift:54-98`、`:260-289`。Flutter 也将真实子任务列表接在文档之后，支持行内改名、勾选和单独打开子任务 Inspector；见 `task_editor_profile.dart:145-163`、`desktop/lib/widgets/task_children_panel.dart:81-121`、`:232-318`。
- **判断边界：** 两边编辑器的文档表示和保存链不同；仅凭 UI 对照不能证明格式往返无损。将 Delta ↔ `NativeDocument` 的格式兼容列为独立数据/Domain 验收，不能把它算作本轮已经确认的视觉差异。

## 4. Escape 层级

- **Flutter 源码事实：** 正文快捷键先按 `slash → selection toolbar → formatting toolbar → Inspector callback` 关闭/转移；任务 Inspector callback 再处理任务弹层、从编辑区退焦到 Inspector，以及窄屏返回。见 `document_editor.dart:659-672`、`task_inspector.dart:126-138`。当前 task profile 的 `selectionActions` 为空（`task_editor_profile.dart:165-166`），所以任务正文实际不会显示选区动作条；通用 Escape 链里的 selection-toolbar 步骤对 task profile 是 no-op。
- **Native 源码事实：** `NativeTextView.cancelOperation` 先让 IME 处理，再关 slash、系统查找栏，之后交给 Inspector；Inspector callback 先关闭格式条，再由 `TaskInspectorPresentationState.handleEscape` 依次关闭活动 popover、结束标题/正文编辑、窄屏返回列表（宽屏保留 Inspector）。见 `NativeTextView.swift:155-176`、`TaskInspectorShell.swift:292-310`、`TaskInspectorPresentationState.swift:34-44`、`TaskInspectorShell.swift:175-178`。打开格式条时会调用 `focusEditor()`，把 first responder 还给正文。
- **最新真窗确认：** 从格式按钮打开工具条后不点正文，直接按一次 Escape，工具条即关闭且 AX focused element 仍为正文 `NSTextView`。这只验证格式条这一层，不代表 slash、Popover、IME、标题退出和窄屏返回的完整 Escape 链都通过。Flutter 对应链由 `desktop/test/task_inspector_layout_test.dart:178-234` 覆盖；格式条单独由 `task_formatting_toolbar_persistent_test.dart:60-93` 覆盖。

## 5. 纠偏建议（交主控实施/验收）

以下是按 Flutter 当前代码为基准的建议，不是已经实施的改动：

1. **P0 — 格式工具条动作复验**：最新构建已验证水平居中、开栏后焦点和立即 Escape；还需核验面板边界、选区保持、紧凑窗口，并逐项操作 H3、分割线、时间三选项、行内代码及附件。
2. **P0 — Slash 动作真窗复验**：命令列表、标题、父子差异与顺序已和 Flutter 源码对齐并有 Native 单元测试；当前构建需实际操作标签、关联任务/笔记、附件、子任务及格式命令。
3. **P1 — Slash 几何**：按可见效果核对 Flutter 160pt/约34pt 行高/优先 caret 下方，与 Native 160pt/32pt/优先上方的差异；修复以真窗截图和受限窗口结果为准。
4. **P1 — Escape/焦点**：已验证格式条关闭这一层；再确认 IME、slash、Popover、标题退出、Inspector/窄屏返回的逐次 Escape 链，与 Flutter 定向测试逐步对照。

## 证据索引

- Flutter 基线截图：[`task-editor-format.png`](screenshots/task-editor-format.png)、[`task-editor-detail.png`](screenshots/task-editor-detail.png)、[`task-editor.png`](screenshots/task-editor.png)。前两张展示正文与 Footer/格式条静态布局；不涵盖 slash 面板。
- Flutter 行为测试：`desktop/test/task_document_editor_test.dart:160-290,383-439`；`desktop/test/task_slash_session_test.dart:18-38,85-128,241-283`；`desktop/test/task_slash_subtask_test.dart:71-128`；`desktop/test/task_formatting_toolbar_persistent_test.dart:11-163`；`desktop/test/task_inspector_layout_test.dart:178-260`。
- Native 主要实现：`macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift`；`macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorPresentationState.swift`；`macos-native/WorkFollow/Features/Editor/NativeTextView.swift`；`SlashCommandPanel.swift`；`DocumentProfile.swift`；`DocumentFormatCommand.swift`。
