# 编辑栏优化方案（2026-10-16）

日期：2026-10-16。分支：`experiment/macos-native`。参考：本机滴答 macOS 8.0.80（rea 资源与运行截图）。

依据：本轮"滴答编辑栏 vs 本地实现"参照对比（结论摘要见第 1 节，证据索引见文末）。
衔接：[Native Editor 平台整合方案](native-editor-platform-plan.md)（EP 门禁与分层合同）、[TickTick Task Surface Parity](ticktick-task-surface-parity.md)（TI-001~007、Commit 4/5、GAP-COMMENTS）、[文档块装饰口径](document-editor-decorations-2026-09-28.md)（2026-10-16 输入期修订）。
范围：任务详情编辑栏（Header / 标题 / 正文编辑器 / 子任务 / Footer）。不含列表、日历、看板、快速添加栏。

## 1. 对比结论摘要（本方案的根据）

- **已对齐**：工具条 15 控件命令集/顺序与 444×38、26×28 几何；时间插入 4 格式；标题 picker；完成框 15pt；**Header 62 / Footer 48（2026-10-17 同窗口 AX 实测校准）**；子任务行几何；Markdown 块级/分割线/行内/围栏（10-16 输入期，10-17 升级为**渲染期解析**：历史字面、粘贴中段、编辑揭示的闭合都会渲染）。
- **操作性差距（已收口）**：围栏代码块输入期已实现（ED-OPT-1）；行内解析的"历史字面不重解析"差距已在 2026-10-17 用渲染期重解析补齐（见第 12 节）。
- **需要先补证据**：正文"Markdown 源码编辑"开关（`TTTaskDetailBottomActionView.mdEditButton`，行为未实测）；属性菜单/底部操作条运行态（Commit 4/5 缺参考图）；子任务折叠、进度视图、类型按钮、备注信息、次要日期等组件映射。
- **有意不做**：协作类（指派/评论/合并）；不按 nib 反推滴答内部架构；不照搬 nib 保存几何。
- **文档卫生**：两处表述与现状不符（见 ED-OPT-2）。

## 2. 优化项总表

| ID | 项 | 类型 | 证据状态 | 优先级 | 状态（2026-10-16） |
|---|---|---|---|---|---|
| ED-OPT-1 | 围栏代码块输入期触发与退出 | 功能 | 滴答渲染已固化；输入期按块级同款推断（无输入期探针） | P0 | 已实施（专项 44 项、全量 1375 项 0 失败） |
| ED-OPT-2 | 两处过期文档同步 | 文档 | 代码核对可证 | P0 | 已执行 |
| ED-OPT-3 | 正文源码编辑开关（mdEditButton）补测 | 证据 | 已实测（2026-10-16，AX 脚本） | P1 | **已完成**：`{}`=详情展开/收回、底栏 `A`=格式工具条开关（mdEditButton 映射）、更多菜单无源码编辑——未发现源码双态，无需立项（[执行记录](audits/ticktick-rea-2026-10-16/mdedit-probe-plan.md)） |
| ED-OPT-4 | 属性菜单与底部操作条参考采集（Commit 4/5 输入） | 证据+UI | **采集完成**（属性菜单+触发路径+展开结构 ✓、优先级 ✓、Slash ✓、三态操作条 ✓、多选态 ✓） | P1 | **已完成**（[记录](audits/ticktick-rea-2026-10-16/inspector-evidence-plan.md)）：12 张证据图已入档 |
| ED-OPT-5 | 子任务折叠等组件映射补测 | 证据 | **部分实测**（子任务区结构 ✓；进度视图/备注信息/类型按钮在普通任务详情未出现；次要日期未采） | P2 | **部分完成**（[B 部分记录](audits/ticktick-rea-2026-10-16/inspector-evidence-plan.md)） |
| ED-OPT-6 | Slash 从"对齐项"转"本地能力"备案 | 文档口径 | **已确认滴答存在 Slash（12 项，2026-10-16）** | P2 | **改判并完成**："本地能力备案"不成立——滴答 Slash 已采集；**12 项逐项一致、四节 3 分隔已对齐、图标逐项一致、几何实测基本一致**（[合同](native-task-slash-contract.md)） |

## 3. P0 设计

### 3.1 ED-OPT-1 围栏代码块输入期（已实施）

现状：`MarkdownSyntax` 已支持围栏解析（围栏行、`codeLines`）；本地有 `.code` 段落类型与工具条"代码块"命令；输入期此前未接，`MarkdownInputTriggerTests.testFenceStaysLiteralForNow` 锁定"暂不触发"——已按新口径反转（与块级"守卫用例反转"同一处理先例）。

设计与决议（与块级输入期同一执行路径：删标记 → `applyFormat(lineStart:)` 设值，同一撤销分组）：

- **触发**：光标前**整行**恰为 3 个及以上反引号（允许行首最多 3 个空格）时，最后一个反引号落下即转换——行文本移除、段落设为 `.code`、光标留在该段；整行围栏判定优先于行内 `` `码` `` 判定。带语言标记的围栏在整串写入（AX/粘贴）时保持字面；逐键输入无法预知后续字符，第三个反引号即成块、语言标记文本落在代码段里（触发时机使然，已由测试锁定）。
- **延续**：有内容行回车延续 `.code`（沿用既有"格式行回车延续"机制）；代码段落内不触发行内/块级转换（沿用既有 guard）。
- **退出（已确认）**：空代码行回车退回正文（与标题/列表"空块退出"同款）；不采用"再敲整行反引号退出"。
- **撤销**：删符号 + 设段落类型同属一次撤销（同块级）。
- **实施记录（2026-10-16）**：改动 `MarkdownSyntax.isFenceLine`、`DocumentMarkdownInput.applyTypedMarkdownFence`（含输入入口分派）、`NativeTextView.exitEmptyBlockOnNewline` 的 `isExitable` 加入 `.code`；`MarkdownInputTriggerTests` 增补围栏用例（触发 / 延续与退出 / 守卫 / 撤销，替换原"暂不触发"守卫），`MarkdownSyntaxTests` 增补整行判定规格。专项 44 项、全量 1375 项（5 跳过）0 失败。三个宿主入口（主右栏 / 规划浮层 / 回收站）的手工复验仍按防复发清单执行。

### 3.2 ED-OPT-2 两处文档同步

1. `native-editor-platform-plan.md` 第 136 行"保留'Markdown 符号作为普通文本'的已有产品规则，不引入自动格式转换"已被 2026-10-16 输入期口径修订取代，建议改为指向[文档块装饰口径](document-editor-decorations-2026-09-28.md)的 10-16 节。
2. `document-editor-decorations-2026-09-28.md` 防复发清单的"编辑器被三个宿主复用（含任务编辑弹框）"与现状不符：`DocumentEditor` 当前只有 `TaskInspectorShell` 与 `NotesWorkspaceView` 两个调用点；`TaskInspectorShell` 自身被右栏 / 规划浮层 / 回收站三处复用。建议按实际修订（不改宿主行为）。

## 4. P1：探针与参考采集

### 4.1 ED-OPT-3：mdEditButton 行为探针

- **目标**：确认滴答详情底部"md 编辑"按钮的行为——是否切换正文的源码/渲染双态、符号是否可见可编辑、退出源码态后的呈现规则。
- **动作**：在滴答编辑栏打开一条含 `**粗**` 等标记的临时任务 → 点击 md 编辑按钮 → 记录正文呈现（符号是否可见）、尝试编辑 → 返回渲染态 → 记录结果与按钮激活态；全程截图。
- **产出**：`docs/audits/` 下截图 + 观察记录；判定"本地是否需要字面标记编辑出口"（本地当前只能靠行内代码写含符号字面）。执行清单已建：[mdedit-probe-plan.md](audits/ticktick-rea-2026-10-16/mdedit-probe-plan.md)。
- **执行结果（2026-10-16）**：已完成（含一次误触与恢复，过程见清单）。结论：`{}`（工具条最左独立分组，即契约中的 four-corner entry）= 详情**展开/收回**（卡片 ↔ 全窗口，实测可逆）；底栏 `A` = **Markdown（格式）编辑工具条浮动开关**（mdEditButton 的运行态映射）；"…"菜单 16 项无源码编辑；**未发现源码/渲染双态**——不需要"字面标记编辑出口"立项。Slash 存在性（A3）首轮未执行（见清单）。

### 4.2 ED-OPT-4：属性菜单与底部操作条参考（Commit 4/5 输入）

- 属性菜单：四枚 priority flags、List / Tags / Attachment / Template 的排列与文案。
- 底部操作条的运行态可见性：nib 列了 8 个动作（moveToProject / tag / comment / mdEdit / merge / delete / deleteForever / more），运行态何时显示哪些。
- 顺带确认滴答是否存在 Slash——不存在则 ED-OPT-6 生效（本地 Slash 转"本地能力"备案）。
- 执行清单已建：[inspector-evidence-plan.md](audits/ticktick-rea-2026-10-16/inspector-evidence-plan.md)（A 部分）。
- **执行记录（2026-10-16，完成）**：属性菜单**触发路径已确认**（"添加任务"行激活态 → ▾ 按钮 @(578,97)）且**展开结构已补**（优先级行内四枚 flags 横排 / 清单子菜单（当前清单名）/ 标签子菜单 / 任务模板面板 / 输入框设置"简洁|详细"两种模式）；**Slash 已确认存在**（12 项，截图 `ticktick-slash-menu.png`）；详情"…"菜单 16 项已采（截图 `ticktick-detail-more-menu.png`）；详情操作条三态已观察（普通 / 已完成 / 回收站：底栏同结构，"…"菜单随状态微调）。**对齐已落（2026-10-16）**：Slash 四节 3 分隔、优先级菜单彩色旗均已实现（全量 1376 项 0 失败）；**图标逐项一致、菜单几何实测基本一致**（宽 ≈156 vs 160、行高 ≈33 vs 34，亚 5pt 级精调未做）。证据图共 11 张，见清单目录。

## 5. P2 备案

- ED-OPT-5：子任务折叠（`containsCollapsedSubtasks` / `subtaskCellHeight`）、进度视图、类型按钮、备注信息入口、次要日期标签的实测映射；拿到运行证据前不加假按钮（沿用 TI-007 的处理）。执行清单（B 部分）：[inspector-evidence-plan.md](audits/ticktick-rea-2026-10-16/inspector-evidence-plan.md)。
- ED-OPT-6：~~Slash 无滴答证据，转"本地能力"备案~~——已改判（2026-10-16 实测滴答有 Slash：12 项逐项一致、四节 3 分隔 / 图标 / 几何均对齐，见[合同](native-task-slash-contract.md)）；本项关闭，后续 Slash 变更按合同维护。

## 6. 不做清单

1. 协作类能力（指派 / 评论 / 合并）——个人本地版边界，缺省正确。
2. 按 nib / 声明反推滴答状态管理并重构本地分层——证据只到类与出口名。
3. 照搬 nib 保存几何（480×40 等非同窗口测量值）——视觉对齐时必须重新实测。

## 7. 执行顺序与门禁

1. ED-OPT-2 文档同步 + ED-OPT-1 口径确认（第 8 节）→ 测试契约先行（反转守卫用例、增补断言）→ 实现 → 全量回归 → 三宿主真机复验。完成后，Markdown 输入期与滴答渲染期**已确认范围**（块级 / 分割线 / 行内 / 代码块）一致。
2. ED-OPT-3 探针 → 决策"字面标记编辑出口"（已完成：不立项）。
3. Commit 5 已落（2026-10-16）：**Slash 分节线四节对齐 + 图标逐项一致 + 几何实测基本一致**；**优先级菜单彩色旗对齐**（受 SwiftUI Menu 不渲染菜单项图标限制，见第 10 节）；属性菜单/操作条参考采集见 ED-OPT-4。仍按 TI 分笔提交流程。

## 8. 已确认决议（2026-10-16，用户逐条）

1. ED-OPT-1 触发：**整行 3+ 反引号落下即转**。
2. 退出：**空代码行回车退回正文**（不采用"再敲整行反引号退出"）。
3. ED-OPT-2：**执行**两处文档同步。
4. ED-OPT-3：**现在安排**探针，执行清单见总表链接。

## 9. 手工复验清单（三宿主，随 ED-OPT-1 交付）

编辑器（`DocumentEditor`）的 Markdown 行为（**渲染期解析**，2026-10-17 口径）在三个宿主入口各过一遍：主右栏 / 规划浮层 / 回收站。逐条核对；发现问题记录"入口 + 序列 + 现象"。

| # | 输入序列 | 预期 |
|---|---|---|
| 1 | `**粗**` | 符号移除、"粗"变粗体、光标在内容后；接着输入的字仍是粗体 |
| 2 | `~~删~~` | 符号移除、"删"删除线 |
| 3 | `[字](https://x.com)` | 符号移除、"字"成链接 |
| 4 | `[字]()` | 保持字面（空 URL 不转） |
| 5 | `# ` 后接标题 | 成一级标题（回归） |
| 6 | 整行 `---` | 分割线 + 光标落下一行（回归） |
| 7 | 逐键输入三个反引号（整行） | 行文本移除、成代码段；接着输入为等宽字体 |
| 8 | 代码段：有内容行回车 → 空行上回车 | 先延续代码段，再退出回正文 |
| 9 | 任一转场后按 ⌘Z | 一次撤销回到输入前（符号恢复）；**撤销后的字面不会被自动重渲染** |
| 10 | 粘贴 `前 **粗** 后` | 中段也转换（`前 粗 后`），前后文不受影响 |
| 11 | 粘贴一段含多个标记的文本（粗体+行内代码+链接） | 所有闭合片段一次全部渲染 |
| 12 | 代码段内输入/粘贴 `**x**` | 保持字面（代码段不参与解析） |
| 13 | 打开一个正文已含字面标记的任务（或切走再切回） | 历史字面被渲染（加载期重解析），不会弹撤销 |

## 10. 本地实测验证（2026-10-17，WorkFollow.app 真机）

构建方式：`xcodebuild -scheme WorkFollow -configuration Debug build` + `open`，用与滴答探针相同的 AX/CGEvent 方法操作真机（临时任务 `WF Verify 1017`，验证后已删除）。

| 项 | 结果 | 证据 |
|---|---|---|
| Slash 菜单（分节） | **通过**：四节 3 分隔、12 项、文案与图标与滴答同构（无 `{}`——合同既定不做） | `native-slash-menu-live.png` |
| 行内输入期（逐键） | **通过**：`**bold**` → 符号移除、"bold" 加粗 | 现场截图 |
| 围栏代码块（粘贴/整串） | **修复后通过**：粘贴 ` ``` ` 成代码段、后续输入等宽、空行回车退出回正文 | `native-fence-exit-live.png` |
| 粘贴普通文本 | 通过：多字符文本落段正确、不误触发转换 | — |
| 格式工具条 | 通过：15 控件命令集/顺序与滴答同构 | `native-format-toolbar-live.png` |
| 优先级菜单 | **通过（2026-10-17 修复）**：顺序/文案一致；改自绘浮层后**四行彩色旗（红/橙/蓝/灰）可见**、无当前值对勾 | `native-priority-panel-live.png` |
| 底栏格式入口 | 通过：`Aa` → 字面 **A**（对齐滴答底栏） | `native-inspector-live-20261017.png` |
| 更多菜单 | 通过：补入「**打开便签**」（滴答第 12 项）；「打印」本地无能力，按"无假按钮"不做 | `native-more-menu-live.png` |
| 子任务行高 | 通过：42 → **40**（滴答 AX 实测 ≈40）；测试改为引用度量常量 | — |
| 持久化 | 通过：重启 app 后正文内容保留 | — |

### 实测发现并修复的缺陷

1. **粘贴不触发输入期 Markdown（已修复）**：`paste(_:)` 的默认实现绕过 `insertText`，整串写入口径（粘贴 ` ``` ` / `**粗**`）完全不生效——单元测试直接调 `insertText` 所以测不到。
   修复：纯文本粘贴改走 `insertText(text, replacementRange:)`（与逐键同路径；富文本按纯文本粘贴）；补测试 `testPastedContentTriggersLikeTyping`（String / NSAttributedString 两路径 + 带语言标记的围栏保持字面）。
2. **优先级菜单项不显示旗子图标（2026-10-17 已修复）**：SwiftUI `Menu` 桥接 NSMenu 不渲染菜单项 Label 图标（`systemImage` 与自定义彩色旗均实测不显示）。已改为与「更多」同款的自绘浮层（`AnchoredPropertyPanel` + 四行彩色旗），真机验证通过（`native-priority-panel-live.png`）。

## 11. 第二轮按滴答对齐（2026-10-17，已实现 + 真机验证）

| 项 | 改动 | 结果 |
|---|---|---|
| 底栏格式入口 | `Image(systemName: "textformat")`（Aa）→ `Text("A")` | 与滴答底栏一致 |
| 优先级菜单 | SwiftUI `Menu` → 自绘 `AnchoredPropertyPanel` 浮层（四行彩色旗、无对勾、Esc/点外关闭、切换任务自动收起） | 修复"菜单项图标不显示" |
| 更多菜单 | 补入「打开便签」（`StickyNoteWindowController`，滴答第 12 项） | 与滴答顺序一致 |
| 子任务行高 | 42 → 40（`TaskInspectorMetrics.childRowMinHeight`），新增行与行间距不变 | 对齐 AX 实测 |

验证：全量 **1377 项（5 跳过）0 失败**；`WorkFollow.app` 真机逐项截图核对（`native-inspector-live-20261017.png` / `native-priority-panel-live.png` / `native-more-menu-live.png`）。

未做（有理由）：

- **「打印」**：本地无打印能力，不放假按钮（能力缺口，如要对齐先做打印实现）。
- **`{}` 展开入口 / 卡片形态**：合同既定"保持不做"。
- **Header / Footer 几何**：**已完成**（2026-10-17 同窗口实测校准为 62/48，见第 13 节）。
- **Markdown 历史字面重解析**：**已完成**（2026-10-17，见第 12 节）。

## 12. 第三轮：Markdown 渲染期解析（2026-10-17，已实现 + 真机验证）

口径：从"输入期触发"升级为"渲染期解析"（对齐滴答）——见[文档块装饰口径](document-editor-decorations-2026-09-28.md) 第一节第 2 条。

实现：

- `NativeTextView.reparseInlineMarkdown(paragraphs:registeringUndo:)`：段落级重解析（**加性、幂等、保光标**）；段内从右到左删标记并按设值语义加 mark，代码段/分割线跳过；先只读扫描，无可转换片段时**不触碰撤销栈**。
- 挂载点：`insertText` 每次编辑后（所在段落）；`DocumentEditorCoordinator.didLoadDocument(reparseInline: true)` 在加载/切换文档后**异步**重解析整篇（不登记撤销，避免在 SwiftUI update 中改模型）。
- 口径变化（取代 10-16 的"整串写入只转最近一处"）：粘贴 `前 **粗** 后` 也转中段；历史字面在加载时渲染。

验证：

- 测试：`MarkdownInputTriggerTests` 新增 4 条（历史字面 / 代码段与工具条 marks / 一段多片段 / 光标保持），原"整串只转最近一处"用例改为"整串全转"；全量 **1381 项（5 跳过）0 失败**。
- 真机：粘贴 `前 **粗** 后` → `前 粗 后`（中段转换）；AX 写入字面后切换任务往返 → 加载期渲染为 `前 粗 后`（`粗` 加粗，`native-render-time-reparse-live.png`）。

保留口径：未闭合字面、`~~删~`/`**粗*` 防抢跑、空 URL `[文字]()`、代码段不参与；撤销方面加载期不登记、编辑期与本次编辑同一分组。

真机边界复验（2026-10-17，WorkFollow.app）：

- 一段多片段（粗体 `**甲**` ＋ 行内代码 ＋ 链接 `[丙](https://x.com)`）→ 一次全部渲染为「甲 与 乙 和 丙」；
- 代码段内粘贴 `**x**` → 保持字面（代码段不参与解析）；
- `**bold**` 转换后 ⌘Z → 正文回到 `**bold**`，1.6s 后仍保持字面（不被自动重渲染，符合"撤销可用"的取舍；见第 12 节说明）。
- 临时任务已删除，界面复原（所有任务 1）。

## 13. 同窗口几何校准（2026-10-17）

滴答 8.0.80 与 `WorkFollow.app` 同时运行、窗口几何相同（`@0,33 1512×859`），AX 读取同一组锚点：

| 锚点 | 滴答 | 本地（前） | 本地（后） |
|---|---|---|---|
| 内容区顶 | 96 | 92 | **96** |
| 标题 y | 106 | 112 | **106** |
| 正文 y | 145 | 145 | **145** |
| 内容区底 | 843 | 839 | **843** |
| Header / Footer | 63 / 49 | 59 / 53 | **63 / 49** |

改动：`TaskInspectorMetrics` 的 `headerHeight 58→62`、`footerHeight 52→48`、`titleTopPadding 20→10`、`titleDocumentGap 10→16`；`TaskInspectorShellContractTests` 的 Header 高度断言改为引用常量。全量 **1381 项（5 跳过）0 失败**；截图对照 `e2-local-detail.png` / `e3-ticktick-detail.png`（临时文件，结论已记入[内容对齐规范](task-inspector-content-alignment.md)）。

已知差异（本次未动）：

- 内容区宽度：本地 895 vs 滴答 880，源自列表列宽（327 vs 358），属列表几何。
- 专注摘要行：本地普通任务常驻显示「设置预计专注 · 实际 0 分钟」，滴答同任务右栏未见该行（疑似仅在有专注记录时出现），映射待确认。

## 14. 组件 AppKit 化（2026-10-17 起，分阶段）

口径：用户要求"组件与滴答一致"。滴答的 nib/私有类不可复用，路径是**用 AppKit 重建同构控件**；约束是每阶段视觉与测试零回归。

做法：SwiftUI 外壳与 `inspectorRenderAnchor` 锚点保留，内部控件换成 AppKit（`NSViewRepresentable`）。这样渲染契约不断，AppKit 控件按显式几何落位。

已替换（2026-10-17）：

| 组件 | 滴答对应 | 实现 | 验证 |
|---|---|---|---|
| 标题 cell | `TTTaskDetailTitleCell`（NSTextField 系） | `Features/Tasks/TaskInspector/AppKit/AppKitTaskTitleField.swift`：`NSTextField` 多行、19pt Medium、Return/Esc 结束编辑、高度随换行 | AX `@655,106 837×23`（原 657，差 2pt）；文字像素左缘 656；真机输入写回与恢复通过 |
| 完成框 | `TTTaskDetailTopView.checkButton` | `AppKit/AppKitCompletionBox.swift`：`NSView` 绘制圆角方框、15pt、描边比例与勾色沿用原推导 | 锚点断言仍 15×15、minX=20；Header 截图形态一致 |
| 返回按钮 | 顶栏 `chevron.left`（窄列推入模式） | `AppKit/AppKitHeaderControls.swift` 的 `AppKitIconButton` | 窄列（窗口 < 621）显示 `@82,47 24×34`；点击 `onBack` 回列表，AX 列表行出现 |
| 日期 chip | `TTTaskDetailTopView` 日期入口（NSButton 系） | `AppKit/AppKitHeaderControls.swift` 的 `AppKitScheduleChip`（imageLeading + 13pt Medium `attributedTitle`） | AX `@696,47 111×34`（title+desc 均="今天, 10月17日"）；点击弹「日期属性」；像素左缘 x≈697 |
| 重复按钮 | `TTTaskDetailTopView` 重复入口（条件显示） | `AppKitIconButton`（symbol=repeat，tint=accent，`scheduleTrigger(.recurrence)`） | 设「每天」后 `@815,47 24×34` 出现；点击弹 recurrence 面板；DB `recurrence=daily` |
| 优先级按钮 | `TTTaskDetailTopView` 优先级入口 | `AppKitIconButton`（flag/flag.fill，tint 随优先级） | `@1458,47 34×34`；点击弹「优先级」四项菜单；选「高」后 DB `priority=3`、旗标像素 x≈1469-1475 红色 |

已知坑（写入实现注释）：`NSViewRepresentable` 会被外层命中区 frame 撑大，锚点必须先包一层显式尺寸的 `.frame`，否则 `.completionInk` 测到 24×34。

真机验证注意：CGEvent 点击在应用非 frontmost 时会被系统当作「激活点击」消耗、不触发 `NSButton.action`；AXPress 走动作通道不受影响。验证脚本需先 `NSRunningApplication.activate` 目标应用再点击。

### 14.1 底栏 8 出口（2026-10-17，先补能力再上底栏）

能力补齐（用户 2026-10-17 决策）：
- **评论**：`TaskComment`（Domain）+ `TaskCommentStore`（SQLite `task-comments`，复用 `SQLiteRecordStore`）+ `TaskCommentPanel`（列表 + 输入框）。底栏 💬 出口 → `.comments` 面板。
- **合并**：`TaskActions.mergeChildrenIntoDocument`（子任务标题按行并入正文后软删，单事务一步撤销）。用 `store.commit` 直接落快照，绕过 `commitText` 对 deferred 正文的 materialize 检查——空正文任务在 `task_documents` 无记录时 `materialized()` 失败会静默返回。
- **永久删除**：复用既有 `permanentlyDelete`（垃圾桶视图 `TaskTrashView`，不在 `TaskInspectorShell` 底栏）。

底栏出口（运行态可见性矩阵，普通态 = 清单/A/评论/更多）：

| 出口 | 滴答 outlet | 显示条件 | 实现 | 真机验证 |
|---|---|---|---|---|
| 清单 | projectButton | 始终 | 既有 Menu（父）/ 只读 Label（子） | `@655,860` 收集箱 Menu |
| 标签 | tagButton | 有标签 | `AppKitIconButton(tag)` → `.tags` | `@1350,851`，点击弹标签面板 |
| 合并 | mergeButton | 有子任务 | `AppKitIconButton(arrow.triangle.merge)` → mergeChildrenIntoDocument | `@1350,851`，点击后正文追加子任务标题、子任务软删 |
| A | mdEditButton | 始终 | `AppKitTextButton("A")` 切换格式工具条 | `@1388,854` |
| 评论 | commentButton | 始终 | `AppKitIconButton(bubble.left)` → `.comments` | `@1420,851`，面板弹出、输入、`task-comments.sqlite` 持久化 |
| 更多 | moreButton | 始终 | 既有更多菜单（删除入口在菜单内） | `@1458,851` |
| 删除 | deleteButton | 更多菜单内 | 既有 | — |
| 永久删除 | deleteForeverButton | 垃圾桶态 | `TaskTrashView` 既有 | — |

新增测试：`TaskCommentStoreTests`（5 项）、`TaskBulkSelectionTests` 合并子任务到正文（3 项）。

### 14.2 子任务区 NSOutlineView（2026-10-17，放开嵌套 + 完整树形）

用户决策：**放开嵌套 + 完整树形**（多级子任务，NSOutlineView 折叠/层级/行内改名）。

数据层放开嵌套：
- `TaskActionError` 移除 `childCannotHaveChildren` / `taskHasChildren`，新增 `circularReference`。
- `TaskParentPolicy.rejection` 移除单层限制，只保留循环检测（沿父链向上查祖先，`isDescendant`）。
- `TaskActions.createChild` 移除 `parent.parentID == nil` 检查。

UI 放开嵌套：`TaskInspectorShell` 更多菜单/子任务区/添加行、`TaskDocumentProfile` Slash「子任务」命令、`TaskContextMenuPopover` 右键「添加子任务」均不再按 `parentID == nil` 隐藏（清单移动限制保留——那是"子任务跟随父清单"语义，非嵌套）。

渲染替换：`AppKit/AppKitSubtaskOutlineView.swift`（`NSOutlineView` + 自定义 `SubtaskRowView` cell）：
- 树形数据源（`Task` 作 item，`childrenByParent` 递归构建子树，默认全展开）。
- cell = 完成框（`CompletionBoxView`，19pt 对齐滴答）+ 标题（`NSTextField`，双击/自动进入行内改名）+ 日期（只读 label）。
- 完成框点击、标题点击打开、双击打开详情、行内改名提交走回调。
- 删除 `TaskInspectorChildRow.swift`（SwiftUI 单层行，已无引用）。

渲染契约调整：`.childRow(UUID)` 锚点移除（NSOutlineView 行几何不再经 SwiftUI 锚点暴露），`TaskInspectorHierarchyRenderTests` 改用 `.childSection` 整体高度 + `.addChild` 关系断言；`childCompletionSize` 16→19。

行为变化更新的测试：`TaskDomainTests`（孙任务可建）、`TaskParentActionTests`（嵌套允许 + 循环检测）、`DocumentProfileTests` / `SlashSessionTests`（子任务 profile 含「子任务」命令，Slash 菜单父/子均 12 行）、`TaskMoreMenuRoundTwoTests`（移除单层条件源码断言）、`TaskParentPickerTests`（子任务是合法父候选）。

全量回归：**1389 项（5 跳过）0 失败**（2026-10-17，子任务区阶段后）。

真机验证（2026-10-17，屏幕解锁后补验）：
- 子任务区渲染为 `AXOutline`（NSOutlineView），行高 40；cell = 完成框 19pt + 标题 + 日期。
- 行内改名：添加子任务后自动聚焦（`inlineChildEditorID` → `beginEditing` → `makeFirstResponder`），输入「甲」写回 `title='甲'`；回车触发续加（对齐滴答"回车连续添加子任务"）。
- 嵌套 + 折叠 + 层级：子任务甲详情「添加子任务」→ 孙任务乙（`parentID=甲`）；父任务详情树形渲染（乙在甲下、缩进 16pt 由 NSOutlineView 自动、`AXDisclosureTriangle` 折叠箭头出现，点击后孙任务折叠）。
- 单击打开详情（标题非编辑态 `hitTest` 返回 nil 穿透 + NSOutlineView 单击手势）；完成框点击双向切换（active ↔ completed）；悬停高亮（`draw` 绘制 7% 墨色）。
- 交互坑修复（已写入实现注释）：① `reloadData` 后 cell 懒加载，`view(atColumn:row:makeIfNecessary:false)` 找不到新行 → 用 `makeIfNecessary:true`；② `updateNSView` 反复 `reloadData` 重置编辑态 → 加数据变化检测；③ **子任务区不再用 `NSScrollView` 包裹**，直接返回 `NSOutlineView` 随宿主详情 `ScrollView` 滚动——独立滚动会与宿主滚动冲突导致窗口坐标错乱（`convert` 到窗口 y 为负，点击永久落空）；④ 折叠箭头/层级缩进交给 NSOutlineView 自动（`NSTableCellView` 继承，但**不绑定 `textField`**，否则 NSOutlineView 重新管理标题导致其 AX 消失）。

### 14.3 日期面板 AppKit 化（2026-10-18 至 2026-10-20）

面板宿主已是独立 `PopupPresentingWindow`，本轮把内部可见控件替换为 AppKit（保留 SwiftUI 草稿模型与子卡片宿主）。

已完成（代码 + 真机验证 + 全量测试）：
- **月历网格** `AppKitMonthGridView`（自绘 `MonthGridCanvas`）：标题栏（年月 + 上/下月/回到今天）、星期行、6×7 日期格；选中实心圆、今天描边环、区间高亮、节日小字；点击格选日期、点击箭头翻月。主面板与「重复结束 → 按日期结束」两处都替换。
- **日期 / 时间段分段** `AppKitScheduleSegmented`（自绘灰底 + 白色选中胶囊），点击切换页签。
- **属性行** `AppKitSchedulePropertyRow`（自绘图标 / 标题或值 / 尾控件 / 展开灰底，时间行嵌 `NSHostingView` 输入框）：图标、值、尾控件、`row` / `expandedRow` 五个渲染锚点与点击命中全部保留在 SwiftUI 层（透明按钮 + `.onHover`），画布只做绘制。**关键教训**：`NSViewRepresentable` 的 host frame 在 `NSHostingController` / 子窗口宿主下会滞后一拍，条件插入「重复结束」行时与上一行重叠且点击落空；把交互与锚点交回 SwiftUI 后，真机与测试都稳定（真机 5 行清晰、展开灰底与 `chevron.down` 正确）。
- 颜色坑（已写入注释）：`NSColor(WFColors.text)` 这类动态 `Color` 转 `NSColor` 会固定成某个外观值（亮色下文字变白），自绘统一改用 `NSColor.labelColor` 系 + 手写动态 accent；SwiftUI 版 `LunarMonthGridView` 在所有宿主替换完成后已删除（2026-10-21，无剩余调用方）。
- **快捷行 / Footer** `AppKitScheduleShortcutRow` / `AppKitScheduleFooter`：自绘四个快捷 chip 与「清除 / 确定」，均已接入主面板。
- **非本月日期灰**（2026-10-21）：原来用 `tertiaryLabelColor` 偏暗，改为显式浅灰 `#C0C4CB`（暗色 `#6B7078`），实测截图采样 `#C0C4CA`，与本月 `#262626` 形成清晰两级。

**滴答实测纠偏（2026-10-18，直接操作滴答 8.0.80）**：
- 「日期」页签 = 分段 + 快捷行 + 月历 + **时间 / 提醒 / 重复** + 清除/确定，**没有「截止日期」行**。
- 「时间段」入口在当前账号下显示高级会员说明；说明图展示 **开始日期 + 结束日期 + 全天开关** + 提醒 + 重复。该图只能确认展示结构，不能证明实际编辑规则，也不能据此认定「截止日期」与区间结束是同一数据字段。2026-10-19 再次打开仍为会员说明，实际编辑行为未验。
- 因此本地此前「日期面板里加一行截止日期」「顶栏常驻截止日期入口」都是自造设计，已撤销：面板不再渲染 `.deadlineRow`；顶栏恢复滴答 `secondaryDateLabel` 行为——**只在任务已有 `deadlineAt` 时**显示「截止 …」，未设置时不占位。本地 `dueEndAt` 与 `deadlineAt` 保持独立，当前证据不足以归并，也不推断时间段入口承担独立截止日期编辑。
- 顺带修正：顶栏日程区现在只有 chip 时 `.schedule` 覆盖整块，`设置日期` 的点击改用更精确的 `.scheduleChip` 锚点，避免多一个入口后 midX 落到两个控件之间。

**时间段页签对齐（2026-10-18）**：
- 滴答会员说明图中的「时间段」= 开始日期 + 结束日期 + **全天开关** + 提醒 + 重复，未展示月历与快捷行；当前账号尚不能进入实际编辑页。
- 本地改造：时间段页签不再渲染月历/快捷行，改为 `periodDateSection`（开始 / 结束 / 全天）；属性区换成 `periodPropertyRows`（全天关时才出现时间 / 结束时间，提醒/重复始终保留）；面板高度按「3 行 + 属性行」收紧（比日期页签矮）。
- 开始 / 结束是独立行，点击各自弹 `AppKitMonthGridView` 单日选择；结束日期的选择下限取开始日（早于开始的日期变灰）。草稿层新增 `setPeriodStart` / `setPeriodEnd`（开始挪到结束之后会清空旧结束）。
- 测试：新增 `SchedulePeriodTabTests`（直接设置 / 清空非法区间 / 全天开关）；`SchedulePopoverContractTests` 的旧断言「时间段多一行结束时间」改为「时间段不再背月历、面板变矮」。
- 后续补两处（同日）：① 顶栏日期 chip 之前只取 `dueAt`，时间段任务看不到结束日；改为 `dueEndAt` 与开始不同日时输出「开始 - 结束」（如「今天, 10月18日 - 明天, 10月19日」）。② 时间段「开始/结束」弹出的单日选择缺 `CalendarAnnotationOverlay`，节假日/班休标记只在日期页签月历里；已补同一套叠加层（`showBadges: true`）。
- 「时间」行占位（同日）：全天任务（`hasTime=false`）此前把默认锚点 09:00 当值显示，看着像已设时间却没有清除入口；改为**不挂输入框**、只画占位「时间」（`hasTime` 才挂 `timeRowEditor`，结束时间同理），对齐滴答面板。
- 任务列表行内编辑的底色（同日，`TaskRowTitleField`）：field editor（`NSTextView`）默认白底会在选中行上挖出一块白，改为 `drawsBackground = false` + 清空 `textContainerInset`，编辑时底色与选中行一致。
- 任务列表的标签行（2026-10-19，对齐滴答）：`TaskRowView` 在标题/预览下方补一排**只读胶囊**（最多 `TaskListMetrics.maxVisibleTags` 个，其余折成「+N」），色值取 `workspace.tag(named:)?.colorARGB` → `WFListPalette.swatch`，底 10% 透明 + 同色文字。`NativeTaskOutline` 通过 `heightOfRowByItem` 按标题、预览、标签内容动态计算行高，并保留最小行高。
- 弹层契约与测试环境（同日）：`TaskTagManagementView`（颜色选择）与 `AdvancedFilterRuleEditor`（清单/标签取值）的 `.popover(` 改为 `AnchoredPropertyPanel`，业务弹层统一无箭头；`TaskKindTests` / `TaskNoteInfoTests` / `TaskInspectorProgressBarTests` 的渲染宿主补 `.environmentObject(AppEnvironment())`（`TaskInspectorShell` 声明了该 `@EnvironmentObject`，缺失会在渲染期直接 fatal）。
- 悬停展开（2026-10-20）：顶栏「重复 / 任务类型 / 笔记信息 / 优先级」与底栏「标签 / 更多」从"点击展开"改为"移上去展开、移开延迟收起"。
  - 触发器：`AppKitIconButton` 新增 `onHover`，内部改用 `HoverButton`（`NSTrackingArea`；SwiftUI 的 `.onHover` 套在 representable 上会被 AppKit tracking 抢走）。
  - 时序：`hoverOpenPanel` 120ms 后打开（防鼠标扫过顶栏就弹面板），`hoverClosePanel` 250ms 后关闭（留出从图标走过空隙的时间）；`hoverKeepOpen` 给面板内容包一层 `.onHover`，鼠标进面板就 `cancel` 待执行的关闭。
  - 点击仍可用：图标 tap 走原来的 `toggle()`，等价"钉住"，不会被移开自动关掉。
  - 仍是点击展开（有意保留）：日期面板（260×506 主面板，hover 打开会误触）、日期面板内的属性行（表单型）、快速添加属性、筛选器、批量面板、任务列表的导航/显示设置。

收尾状态：
- 快捷行与清除/确定按钮已完成 AppKit 绘制；透明 SwiftUI 按钮保留渲染锚点、辅助功能和回车确认。2026-10-19 的 80 项定向验证见 [日期面板收尾记录](ticktick-date-panel-finish-2026-10-19.md)。
- 时间、提醒、重复规则及重复结束的子面板保留 SwiftUI；当前没有为统一技术栈而重写它们的计划。
- 2026-10-20 修正过滤器取值弹层的宿主宽度，使其与 264pt 内容一致；新增原生列表测试，验证添加标签后实际行高增长、一次撤销恢复。弹层、过滤器、详情渲染及标签相关共执行 **58 项，1 项跳过，0 失败**；跳过项为临时 XCTest 宿主不能激活前台的键盘焦点测试。随后用户在已安装日用版中确认标签搜索自动聚焦、直接输入与筛选正常，实机补验通过，详见 [日用版验收记录](native-daily-build-2026-10-20.md)。

历史全量回归：**1479 项（6 跳过）0 失败**（2026-10-18；顺带修正标题扩到六级后 `SlashSessionTests` 的遗留断言 3→6）。此数值不是 2026-10-20 的验证结果。

### 14.6 清掉长期红的测试 + 去掉搜索水合（2026-10-23）

**全量 1728 项（7 跳过）0 失败**。此前长期挂着的 5 条全部修掉：

| 用例 | 根因 | 处理 |
|---|---|---|
| `ScheduleExpandedSectionTests` ×2 | `reminderOptionText` 的选项文案从 `标题 (时刻)` 改成 `标题 · 时刻`，跨天项还带「昨天 / 9月21日」 | 测试不再写死格式，改用 `ScheduleDisplay.reminderOptionText(...)` 以同一口径生成锚点 |
| `SchedulePanelWindowFlowTests` ×2 | 同上（`option("提前1天 (09:00)")` 之类找不到） | 该文件在并行改动里已改用前缀匹配，本轮只清掉多余的 helper |
| `ScheduleContainerRenderTests` ×1 | `prefersAbove` 路径的弹层与锚点行之间保留 4pt，断言却要求精确相切 | 改成区间断言：不盖住行顶、且贴在行顶 5pt 内 |
| `ArrowlessTaskPopupContractTests` ×2 | 菜单重构后 `clearDueDate` 已移出、`startFocus` 抽成私有方法（自己关菜单） | 契约断言同步新写法：检查 `startFocus` 方法体内有 `isPresented = false` |

**搜索水合（性能债）**：`DeferredDocumentTests` 断言 1000 条任务 + 搜索入口不应水合任何正文，实际水合了 2 次。定位到 `CommandPaletteProjection.matchingSnippet` —— 它为命中结果读 `document.plainText`，命中 1 条任务 + 1 条笔记就 resolve 2 篇正文。改为：

- `NativeDocument.deferredSummary`：暴露未水合时的 `DocumentSummary`（head / tail / firstLine），读取不触发加载；
- `matchingSnippet` 优先用摘要头尾找命中词，命中在正文中段时退化成首行（不水合），只有本来就是内存文档才读全文；
- 片段截取抽成 `snippet(in:query:)` 供两条路径共用。

### 14.5 摘要测试用例按最新代码补齐（2026-10-22）

按最终形态（`SummaryFilter` / `SummaryDocumentOptions` / `SummaryContentField` / `TaskTemplate.kind`）重排测试，新增 **14 项**：

| 文件 | 数量 | 覆盖 |
|---|---|---|
| `SummaryFilterTests`（新建） | 4 | 默认值（只带日期）、`contentOptionCount`、**旧 JSON 缺 `tagName`/`shows*` 时的解码兼容**、往返编解码 |
| `SummaryDocumentOptionsTests`（新建） | 4 | `standard` 配方、**旧档案 filter→content 迁移**（`showsDate`→完成/任务时间、`showsList`→清单、`showsTags`→标签）、空 payload 回落、往返 |
| `SummaryReviewBuilderTests` | +3 | 按标签筛选、`itemText` 四档显示内容、`document` 条目受 filter 影响 |
| `SummaryStoreTests` | +3 | `save(document:)` 落富文本并同步纯文本、空文档删除条目、旧 `content` 经 `resolvedDocument` 兜底 |
| `TaskTemplateTests` | +3 | 无 `kind` 的旧档案不算摘要模板、`kind="summary"` 往返、`saveDocumentTemplate` 与任务模板互不污染 |

**顺带修掉一个真 bug**：`SummaryFilter` 用合成 `Codable`，新增字段（`tagName` / `showsDate` / `showsList` / `showsTags`）在旧 JSON 里缺失时直接 `keyNotFound` 崩溃。改为显式 `CodingKeys` + 逐字段 `decodeIfPresent` 回落默认，并补回 memberwise `init`（自定义 init 后不再自动合成，`SummaryDocumentOptions` 里 `SummaryFilter(showsDate:showsList:showsTags:)` 依赖它）。

**同步过期的导航断言**：`NativeSmokeTests` 的 `taskDestinations` 补 `.weekPlan` / `.summary`；`CommandPaletteTests` 补「打开本周计划」（10→11 项）。这两处是 `weekPlan` 与摘要并入任务导航后测试没跟上的滞后，不是新 bug。

**同时把一批滞后断言修绿**（全量 failures 23 → 10，case 10 → 5）：

- `TaskKanbanReorderTests`：不是丢数据。`TaskWeeklyPlanning.recording` 首次对带 `dueAt` 的任务提交时会补一条周计划基线（`history` 从空到一条），期望值改走同一条规则后再完整相等。
- `ArrowlessTaskPopupContractTests`（2 条）：`AppleSyncStatusButton` 违规用 `.popover(isPresented:arrowEdge:)`，改成 `AnchoredPropertyPanel`（宽 340、`placement: .vertical`、`focusPolicy: .preservePresenter`），内容抽成 `panelContent`。
- `NativeSmokeTests` / `CommandPaletteTests`：`taskDestinations` 补 `.weekPlan` / `.summary`，命令面板补「打开本周计划」（10→11）。
- `TaskSchedulePanelRenderTests`（2 条）：提醒行标签新增时刻后缀（`准时` → `准时 · 20:30`、`当天` → `当天 · 09:00`）。

剩余 5 个用例（均与摘要无关）：

| 用例 | 根因 |
|---|---|
| `ScheduleExpandedSectionTests` ×2、`SchedulePanelWindowFlowTests` ×2 | `ScheduleDisplay.reminderOptionText` 的选项文案从 `标题 (时刻)` 改成 `标题 · 时刻`，测试仍在按括号查找锚点。跨天项（`提前1天`）走 `dateText(.compact)`，需按其真实格式逐个对齐 |
| `DeferredDocumentTests` ×1 | 1000 条预览里仍有 2 处水合了 `document` |

### 14.4 摘要改造成可编辑文档（2026-10-21，P0）

对齐滴答「摘要」：正文是一篇可编辑富文本，自动生成只是起点。按 **A 方案**落地——摘要是任务模块里的同级目的地（侧栏入口 + 主内容区），不新开窗口，复用任务正文的 `DocumentEditor`。

- **数据**：`DailySummary` 增加 `document: NativeDocument?`（旧 `summary.json` 缺字段解码为 nil，不批量迁移）；`resolvedDocument` 兜底把 `content` 转成单段文档；`SummaryStore.save(document:dayKey:)` 落富文本并同步一份纯文本 `content`。
- **生成**：`SummaryReviewBuilder.document(for:)` 把周回顾渲染成 `h1(周范围) + h2(已完成/已放弃/未完成) + bullet 列表`；无内容时给一句占位。
- **视图**：`SummaryWorkspaceView.weeklyPane` 换成 `DocumentEditor`（`DocumentProfile()`，与任务正文同一个组件、同一套格式与撤销）；顶栏不再重复周标题；「复制」改为复制 `plainText`；新增「重新生成」显式覆盖。
- **时序**：首次进入某周生成默认内容但**不落库**，用户动手才保存；换周换 `weeklyEditorID` 强制按新文档重建编辑器。
- **清理**：删除旧渲染 `reviewSection` / `weeklyNoteSection` / `weeklyTitle`（79 行）。
- 手记（journal）本轮未动，仍是 `TextEditor`。

真机：周回顾显示为「10月19日-10月25日（h1）→ 未完成（h2）→ 项目符号」，可直接编辑。`SummaryReviewBuilderTests` + `SummaryStoreTests` 17 项通过。

**P1 筛选（同日）**：
- `SummaryFilter`（`Domain/Summary/SummaryFilter.swift`）：**清单（单选，nil=全部）+ 状态（所有/已完成/未完成）**。
- **日期不放筛选里**：本地左侧已有周列表，再叠一层「本周/上周」会有两套互相覆盖的日期语义；滴答没有左侧列表，所以它的日期筛选由右侧承担。
- `SummaryReviewBuilder.review(for:weekOf:filter:)`：清单过滤参与任务；状态决定生成哪几段（`.completed` 只出已完成段，`.uncompleted` 出已放弃 + 未完成段）。
- UI：正文上方一行 `filterBar`（清单 `Menu` + 状态 `SegmentedPicker`）；筛选只影响下次「重新生成」，不擅自覆盖已保存正文。
- 测试：新增 3 个用例（按状态保留段、按状态丢弃段、按清单排除），`SummaryReviewBuilderTests` 14 项通过。

**P1 分组（同日）**：
- `SummaryGrouping`（`Domain/Summary/SummaryGrouping.swift`）：**按完成状态 / 按清单 / 按优先级 / 按标签**；`SummarySection` 为通用「二级标题 + 条目」。
- `SummaryReviewBuilder.sections(from:grouping:)`：完成状态走原三段；清单按 `listName` 拼音序；优先级按 `rawValue` 降序（高→无）；标签按名称拼音序、一个任务多标签会在每个标签段里各出现一次，无标签归「无标签」段。
- `ReviewItem` 增加 `priority` / `tagNames`（默认值，不影响原三段）；`document(for:grouping:)` 按分组渲染二级标题。
- UI：筛选条追加分组 `Menu`（当前项打勾）；改分组后按「重新生成」生效。
- 测试：新增 3 个用例（按清单分桶、按优先级排序、按标签含「无标签」），`SummaryReviewBuilderTests` 17 项通过。

**P2 AI / 打印 / 模板 / 插入（2026-10-21）**：
- **AI 优化** `SummaryPiOptimizer`（`Infrastructure/AI/`）：直接调本机 `/opt/homebrew/bin/pi`，与会议纪要同一条通道——`--print --no-session --no-tools --no-extensions --no-skills --no-prompt-templates --no-context-files --offline`，prompt 拼「长度 / 语言风格 / 职业 / 额外要求 + 原文」，只取 stdout 正文；90s 超时。摘要页「AI 优化」按钮执行，成功覆盖正文并落库，失败在正文上方显示错误。参数模型 `SummaryAIOptions`（brief/normal/detailed × plain/warm/formal + profession + hint）。测试默认跳过真实调用（`SUMMARY_AI_INTEGRATION=1` 才跑）。
- **打印** `TaskPrintService.printDocument(title:body:)`：标题 18 半粗 + 正文 13，复用任务的页边距/分页设置。摘要页「打印」按钮。
- **模板**：`TaskTemplate` 增加 `kind`（nil/"task" = 任务模板，"summary" = 摘要模板，手写 Codable 用 `decodeIfPresent` 兼容旧档案）；`TemplateStore.saveDocumentTemplate`；摘要页「模板」Menu（保存为模板 / 套用已有摘要模板）；任务的 `TaskTemplateGalleryView` 与 `TemplateManagementView` 过滤掉摘要模板，两个仓库互不污染。
- **插入摘要**：任务详情「更多」新增「插入本周摘要」，把当周摘要文档（标题 + 分组段 + 列表）追加到任务正文末尾，非空正文前加一条分割线。注：插入的是**本周摘要**，不是任务自身的属性快照；如果语义要改成后者，只需换 `insertWeeklySummary` 的数据源。
- **三栏布局（同日，对齐滴答）**：`SummaryWorkspaceView.body` 改为「左 周列表 280 / 中 正文 / 右 配置面板 248」（窗口 ≥900 才出右栏，窄屏退回两栏）。右栏分区：模板（+ 菜单：保存为模板 / 套用）→ 筛选（清单、状态）→ 显示设置（分组）→ AI 优化（长度、语言风格、职业、额外要求 + 主按钮），与滴答的面板结构和顺序一致。原先横在正文上方的筛选条已移除。
- **去掉左列（同日，按用户反馈）**：周列表那一栏整块删除，改为「正文 + 右栏」两栏；周/日切换收进正文顶栏——周回顾是「‹ 本周（10月19日-10月25日）▾ ›」（中间下拉列出所有周），手记是「‹ 10月21日 ▾ ›」（下拉列出当天有内容的日期 + 今天）。`leftColumn` / `weekList` / `weekRow` / `dayList` / `dayRow` 与 `narrowShowsList` 全部删除。
- **视觉复刻滴答（同日，按滴答截图）**：右栏每个分组改成**浅灰卡片**（`WFColors.hover` 底 + 圆角 8，行高 38、左右 12），AI 优化按钮改成**铺满的蓝色主按钮**（accent 底白字、高 36、圆角 8），模板「+」改浅灰圆角按钮；正文改成**带边框的卡片**（`RoundedRectangle` 描边 + 圆角 8，工具栏与文档都在框内），卡片下方补「保存为 / 复制」动作条。
- **右栏比例校正（同日，按滴答截图的纵向节奏）**：分组间距 16→24、分组标题到卡片 8→10、右栏内边距 16→20、宽度 248→240；模板区补「暂无模板 / 模板列表」块（空态占 26×2 垂直内边距），使「模板 → 筛选」的间距与滴答（约 85px）一致。
- **结构再对齐（同日，逐项比对滴答截图）**：① 模板区改成「标题一行 + 下面单独一行左对齐的灰色 `+`」（滴答不是标题右侧放加号）；② 正文上方那行「复制 / 重新生成 / 打印」整行移除，动作全部收到**卡片下方的动作条**（保存为 / 复制 / 重新生成 / 打印），正文卡片直接顶到顶栏，与滴答一致。
- **细节补齐（同日）**：① 顶部加「☰ 摘要 + 右侧导出按钮」标题栏（`pageTitleBar`，高 44）；②「内容优化（公测）」后加蓝色 `AI` 小徽标；③ AI 的四个参数行装进灰卡片，蓝色按钮移到卡片下方（与滴答一致）。
- **标题栏收拢（同日）**：「周回顾 / 手记」分段与周期导航并入标题栏一行——`☰ 摘要 … ‹ 本周（10月19日-10月25日）▾ › ⋯ ⤴`，切换视角的「⋯」菜单在右侧；独立的那一行 `reviewHeader` 删除。摘要在窄屏也不再需要额外的分段占位。
- **右栏宽度与下拉全部接通（同日）**：右栏 240→**272**（对齐滴答）；六个下拉都有实际作用——「日期」选周（与标题栏同源）、「清单」「状态」「更多（标签）」改 `SummaryFilter`、**「分组」「显示内容」改动后立即重写自动生成段**（`.onChange(of: grouping / filter)` → `regenerateWeekly()`）。`SummaryFilter` 新增 `tagName` / `showsDate` / `showsList` / `showsTags`，`SummaryReviewBuilder.document(for:grouping:filter:)` 按显示内容拼条目文本；「显示内容」显示已开项数（`N 项`）。模板的「＋」改成纯按钮（点击即保存为模板，不带下拉箭头）。行标签加 `lineLimit(1).fixedSize()`，避免「日期」被挤成两行。
- **动作最终收拢（同日）**：底部动作条只留「保存为 / 复制」（与滴答一致）；「重新生成 / 打印」与「周回顾 / 手记」一起收进标题栏右侧的 `⋯` 菜单。
- **标题栏最简（同日）**：中间的 `‹ 本周 ▾ ›` 周期导航也移除，标题栏只剩「☰ 摘要 + ⋯ + ⤴」。周/日切换全部进 `⋯`：周回顾是「上一周 / 下一周 / 选择周（子菜单）」，手记是「前一天 / 后一天 / 今天」。当前周期从正文的一级标题（`10月19日至10月25日`）读取。
- **☰ 接上真实功能（同日）**：标题栏的 `☰` 从装饰图标改成按钮，调用 `AppEnvironment.toggleSidebar()`（与 ⌘\ 同一条路径），折叠/展开左侧导航列；`SummaryWorkspaceView` 因此注入 `@EnvironmentObject AppEnvironment`（`RootShellView` 已提供）。
- **右栏宽度 / 底色 / 下拉配色对齐（同日，按滴答截图逐项量）**：宽度 272→**370**（窗口门槛 900→1000）；卡片底色从 `WFColors.hover`（4% 黑）换成新增的 `WFColors.panelFill`（亮 `#F7F8FA` / 暗 `#2A2A2C`）；行高 38→36。**下拉值的颜色**：`.menuStyle(.borderlessButton)` 会把 label 染成 accent 蓝，`.foregroundStyle` / `.tint` 都不生效，改用 `.foregroundColor(WFColors.secondaryText)` 才压住；箭头用 `.tint(WFColors.secondaryText)` 一起转灰。AI 的「长度 / 语言风格」原来是 `Picker`（蓝色 stepper），换成 `Menu` + 自绘 label。
- **标题栏图标对齐（同日）**：`☰` 从 `line.3.horizontal` 换成滴答那种带框列表图标 `list.bullet.rectangle`；右侧 `⋯` 与导出的蓝色（Menu 的 accent）一并改成灰色（`foregroundColor` + `tint`）。
- **右上角改成「历史文档」（同日）**：换成 `clock.arrow.circlepath`，点击弹 `AnchoredPropertyPanel`（300 宽），内容是空的「没有历史文档」态（文档 + 铅笔图标）。**注意**：`SummaryStore` 目前每次保存都覆盖同一份 `document`，没有版本历史，所以这里只有空态；要真历史需要给 `DailySummary` 加版本数组。
- 顺带修一个 bug：模板区的「＋」保存时用的是 `weeklyDocument.blocks.first?.plainText` 当模板名——AI 改写后整篇正文就是一块纯文本，导致模板名变成一整段、把右栏撑开。改为用 `currentWeekLabel`（"摘要模板 本周（10月19日-10月25日）"），列表项补 `lineLimit(1)`；已产生的错误模板已从 `modules/templates.json` 清除。
- **二次对齐（同日，照滴答截图补齐）**：正文上方加**常驻格式工具栏**（`DocumentFormatToolbarView` + `DocumentEditorHandle`，与任务正文同一套）；右栏补「日期」（回显当前周范围）、「更多」（无）、「显示内容」（日期、标题）、**下一周期任务开关**（在文档末尾追加下一周的未完成清单）、**内容优化（公测）AI 总开关**（关闭时选项与按钮变灰禁用）。
- **仍与滴答不同的一处**：左列。滴答的左列是**全局导航**（所有 / 今天 / 收集箱 / 摘要 + 清单 / 过滤器 / 标签 / 已完成 / 垃圾桶），本地摘要页的左列是**摘要专属**（周回顾/手记 + 周列表）。因为本地侧栏已有独立导航列（任务模块），摘要不再重复一份；若要完全照搬，需要把摘要的左列换成全局导航，等于和侧栏职责重叠，暂不做。

## 证据索引

- 滴答：`docs/audits/ticktick-rea-2026-10-13/rea-selected-evidence.json`、`docs/design/ticktick-replica-2026-10-14/rea-design-evidence.json`（`TTTaskDetailTopView` / `TitleCell` / `BottomView` / `BottomActionView` / `FocusSummaryCell`）、`docs/audits/ticktick-tasks-2026-10-16/rea-task-declarations.json`、运行截图 `docs/audits/ticktick-tasks-2026-10-16/ticktick-task-detail.png`、[工具条实测](editor-toolbar-ticktick-contract.md)。
- 本地：`Features/Editor/`、`Features/Tasks/TaskInspector/`、`MarkdownSyntaxTests`、`MarkdownInputTriggerTests`、[内容对齐实测](task-inspector-content-alignment.md)。
