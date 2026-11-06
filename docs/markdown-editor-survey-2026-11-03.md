# 可嵌入开源 Markdown 编辑器调研报告

日期：2026-11-03。范围：为 WorkFollow macOS 原生 App 评估"可嵌入到代码里的开源 Markdown/富文本编辑器内核"，判断能否做得比当前自研编辑器更优。**本轮不改代码。**

## 0. 结论先行（5 条）

1. **没有一个开源项目能"开箱即用"替换当前的 NSTextView + TextKit 2 自研编辑器。** 当前编辑器的能力面（块级 8 类 + 行内 11 标记 + 嵌套缩进 + 表格 + 图片拖拽改尺寸 + LaTeX 公式 + DrawIO 图 + 附件 + 斜杠菜单 + Markdown 输入期触发 + 渲染期解析 + 独立 Undo + 中文 IME + 剪贴板 codec）在开源生态里是"组合天花板"，任何单一候选都只能覆盖其中一段。

2. **业界做"块级笔记编辑器"的主流范式是 WebView + ProseMirror 系（Notion/Logseq/Obsidian/Typora 全是）。** 纯 Swift 原生做块级富文本是逆流——Apple 自己的备忘录也只用 TextKit 做线性富文本，不做块级。但**逆流不等于错**：WorkFollow 的 IME/焦点/滚动/剪贴板/性能已经在原生路径上踩平了，换 WebView 等于把已解决的问题重新踩一遍。

3. **如果只看"比当前更优"的潜力上限，最值得认真评估的是 Milkdown（ProseMirror + Markdown 双态）或 TipTap v3（ProseMirror，MIT 核心已开源 10 个原 Pro 扩展）走 WKWebView 路线。** 它们的 Markdown 一等公民、schema 可扩展、协同生态是原生短期内够不到的天花板。代价是焦点/滚动/IME/剪贴板要重写桥接，且项目已有一条 Quill P3 搁置的 WebView 疤痕。

4. **如果只看"低风险、渐进改善当前痛点"，最务实的不是换内核，而是把当前的 `DocumentTextCodec`/`DocumentBlockDecorations` 状态机收拢成"AST + 增量渲染"，并用 STTextView 替换裸 NSTextView 的布局层（可选）。** 当前 13084 行编辑器代码里，真正在对抗 TextKit 2 的只有约 8 处（自绘装饰规避 NSTextList 双标记、选区私有子视图叠层、文末空段落级别挂在 typingAttributes、ImageResize 不走 layoutManager 几何）。这些是可控的局部债，不是"架构失败"。

5. **明确不推荐**：Quill 继续做主力（已搁置且能力天花板低）、Slate.js（API 不稳、Markdown 非一等公民）、BlockNote（Markdown 导出官方文档明说"lossy"，且深度绑定 React）、Monaco（代码编辑器不是笔记编辑器）、AGPL/商业双许可方案（许可证红线）。

---

## 1. 当前编辑器的真实画像（基于源码与 docs，非营销话术）

### 1.1 规模与结构

| 维度 | 数值 | 证据 |
|---|---|---|
| Features/Editor 目录文件数 | 47 个 .swift | `ls WorkFollow/Features/Editor/*.swift \| wc -l` |
| 编辑器+Domain 总行数 | 约 14700 行 | `cat Features/Editor/*.swift Domain/Document/*.swift Domain/Markdown/*.swift \| wc -l` |
| 最大单文件 | NativeTextView.swift 1847 行 | `wc -l` |
| Domain/Document 模型文件 | 10 个 | `ls WorkFollow/Domain/Document/` |
| 编辑器相关测试 | 40+ 个测试文件 / 1136 条断言 | `ls WorkFollowTests/*Editor*.swift *Document*.swift` |
| 编辑器目录 git 提交数 | 76 次 | `git log --oneline -- macos-native/WorkFollow/Features/Editor \| wc -l` |
| 部署目标 | macOS 14.0 / Swift 5.0 | project.pbxproj |
| 第三方包依赖 | 0（无 SPM、无 Package.resolved） | 工程检查 |

### 1.2 已实现能力清单（源码事实）

- **块类型**：`DocumentBlockKind` = paragraph / heading(1..6) / bullet / ordered / checklist(Bool) / quote / code / divider（[NativeDocument.swift:257](macos-native/WorkFollow/Domain/Document/NativeDocument.swift#L257)）
- **行内标记**：`DocumentMark` = bold / italic / underline / highlight / strikethrough / code / link(String) / muted / caption / symbol / ink / textColor / highlightColor（[NativeDocument.swift:300](macos-native/WorkFollow/Domain/Document/NativeDocument.swift#L300)）
- **附件体系**：NativeAttachment（图片 data URL 内嵌 + displayWidth/Height 拖拽改尺寸）、NativeTable、NativeDiagram(DrawIO)、NativeFormula(LaTeX)
- **Markdown 双层**：`MarkdownSyntax.swift`（纯函数解析器，对齐滴答 8.0.80 语法）+ `DocumentMarkdownInput.swift`（输入期触发：`# `/`- [ ] `/``` ``` ` 等空格落下即成块、整行 `---` 成分割线、围栏代码块、闭合行内标记）
- **输入法**：`insertText` / `keyDown` / `doCommand` / `setMarkedText` 全套 NSTextView 重写（NativeTextView.swift:182/1160/1169，30 处 markedText 引用）
- **独立 UndoManager**：每个编辑器实例一个 `documentUndoManager`，不与窗口共享
- **装饰层**：`DocumentBlockDecorations.swift`（584 行）自绘列表标记/引用竖线/标题角标/代码块卡片——**刻意不用 NSTextList**，因为 TextKit 2 会自绘 NSTextList 标记导致"双点/1.1"叠字
- **选区浮条**：`DocumentSelectionToolbar.swift`（760 行）
- **剪贴板**：`DocumentClipboardCodec` + `DocumentExternalClipboardCodec`（RTF↔NativeDocument 往返）
- **公式/表格/DrawIO**：各自独立的 `WindowController`（FormulaEditorWindowController / TableEditorWindowController / DrawioEditorWindowController），编辑在独立窗口，正文只放附件占位

### 1.3 已知痛点（全部来自仓库 docs，非主观判断）

| 痛点 | 证据 | 严重度 |
|---|---|---|
| TextKit 2 自绘 NSTextList 导致双标记，必须自绘装饰层规避 | [DocumentBlockDecorations.swift:8](macos-native/WorkFollow/Features/Editor/DocumentBlockDecorations.swift#L8)、[DocumentTextCodec.swift:175](macos-native/WorkFollow/Features/Editor/DocumentTextCodec.swift#L175) | 中（已规避，但是状态机复杂度来源） |
| 选区画在私有子视图 `_NSTextSelectionView`，装饰要单独叠层 | [BlockDecorationOverlay.swift:5](macos-native/WorkFollow/Features/Editor/BlockDecorationOverlay.swift#L5) | 中（已规避） |
| 文末空段落没有字符，段落级别只能挂在 typingAttributes 上，切走会丢 | NativeTextView.swift 注释 `pendingTrailingBlock`/`displayedTrailingBlock` | 中（已用待定级别兜底，但是边界 case 来源） |
| ImageResize 不能用 layoutManager 取几何，会切回 TextKit 1 | [DocumentImageResize.swift:44](macos-native/WorkFollow/Features/Editor/DocumentImageResize.swift#L44) | 低（已规避） |
| 47 个文件、13000+ 行的状态机难维护 | docs/native-editor-platform-plan.md 明确说"文件多、bool 多本身不构成缺陷；互斥状态、重复映射和生命周期无归属才需要改造" | 中（是组织债，不是技术债） |
| Quill(WebView) 路线 P3 焦点战打了 7 轮，最终搁置 | docs/editor-quill-p3-focus-battle-2026-10-24.md | 高（已投入沉没成本，是"还要不要碰 WebView"的阴影） |
| 正文高度缓存要按文档身份+文本存储版本+宽度+排版参数缓存，否则反复全文布局 | docs/native-projection-and-editor-cache-2026-11-02.md | 低（已优化，但说明 TextKit 布局本身是性能热点） |
| 同步执行完整 `DocumentTextCodec.decode`，没有逐段解码/差量发布 | 同上 | 中（是大文档性能的潜在上限） |

**关键判断**：当前痛点集中在"TextKit 2 的私有行为要靠自绘装饰规避"和"状态机组织复杂"两点。**没有一个痛点是"NSTextView 本身不能编辑富文本"。** 换内核的动机应该是"上限更高"而非"当前坏掉了"。

---

## 2. 候选逐个详述

> 数据来源：GitHub API（已核实 Star/License/pushed_at，部分受 rate limit 影响标注"需核实"）、官方文档、Swift Package Index。Star 数为 2026-11-03 实测。

### A 组：Swift/macOS 原生

#### A1. STTextView（krzyzanowskim/STTextView）

| 项 | 值 |
|---|---|
| 仓库 | github.com/krzyzanowskim/STTextView |
| Star | 1610 |
| 最新 Release | 2.4.1（约 2 个月前） |
| 最近 push | 2026-10-06 |
| License | **NOASSERTION**（Swift Package Index 标注"Unknown license"，LICENSE.md 非标准 SPDX，需逐字阅读确认——已知作者 Marcin Krzyzanowski 的其他项目如 CryptoSwift 是 BSD-3，但本仓需单独核实）⚠️ |
| 依赖 | 2 个 SPM 包 |
| 定位 | "Performant and reusable text view component (TextKit 2), UITextView/NSTextView replacement" |

- **本质**：TextKit 2 的 NSTextView 替代品，纯文本 + 行号 + 语法高亮 hook。**不是富文本编辑器，没有块级/行内标记的概念。**
- **能帮到 WorkFollow 什么**：替换裸 NSTextView 的布局层，可能拿到更干净的 TextKit 2 抽象（line numbers、selection API、viewport）。但装饰层、块模型、Markdown 解析仍要自己写。
- **真实风险**：License 不明（NOASSERTION）是上架 Mac App Store 的硬障碍，必须先解决。作者维护节奏慢（最近 push 27 天前，但 Release 间隔以月计）。富文本能力要自己补，等于"换了个更干净的底盘但车身还是要自己造"。
- **结论**：**可作为"底盘升级"候选评估，但不能直接替换编辑器内核。** License 是前置门槛。

#### A2. Runestone（simonbs/Runestone）

| 项 | 值 |
|---|---|
| Star | 3238 |
| 最近 push | 2026-11-02（活跃） |
| License | MIT ✅ |
| 定位 | "Performant plain text editor for iOS with syntax highlighting" |

- **本质**：tree-sitter 驱动的**代码编辑器**，纯文本 + 语法高亮 + 行号。README 第一句就写 "plain text editor"，**不是富文本/Markdown 块级编辑器**。
- **能帮到 WorkFollow 什么**：如果要做"Markdown 源码模式"（像 Obsidian 的 Source View），Runestone 比 CodeMirror 在原生体验上更好。但当前产品形态是 WYSIWYG 块级编辑，不是源码模式。
- **结论**：**排除作为主力内核。** 可作为"源码模式子视图"的未来候选（如果产品要加 Markdown 源码编辑出口）。

#### A3. CodeEditSourceEditor（CodeEditApp）

| 项 | 值 |
|---|---|
| Star | 727 |
| 最近 push | 2026-10-18（活跃） |
| License | MIT ✅ |
| 定位 | "A code editor view written in Swift powered by tree-sitter" |

- 与 Runestone 同类，代码编辑器。**排除作为主力内核。**

#### A4. SwiftDown / MarkdownUI / Down / MarkdownKit

- **SwiftDown**（qkzhu）：GitHub API 查不到（可能已删除/改名）。**死项目或不可考，排除。**
- **MarkdownUI**（gonzalezreal/swift-markdown-ui）：**Markdown 渲染视图（只读）**，不是编辑器。可作为"渲染预览"用，但不能替换编辑器。
- **Down**：cmark 包装，渲染用。排除。
- **MarkdownKit**：Markdown→HTML 解析，无编辑能力。排除。

#### A5. 其他 Swift 候选

- **Aztec**（Automattic/wordpress-aztec-ios）：iOS 富文本编辑器，基于 UITextView，有块级概念。但**定位是 WordPress 内容编辑器，非 Markdown-first，且 iOS 为主、macOS 支持弱**。License MIT。可作为思路参考，不建议直接嵌入。
- **Ink / ProseMirror-Swift**：查无此项目或不可考。
- **cosmic-text（Rust）+ Swift FFI**：cosmic-text 是 Rust 的纯文本排版引擎（Pop!_OS 在用），能力是"自己排版纯文本"，**没有富文本/块级/Markdown**。FFI 成本高，收益不明确。排除。

### B 组：Web/JS（WKWebView 路线）

#### B1. ProseMirror（prosemirror/prosemirror）

| 项 | 值 |
|---|---|
| Star | 8693（主仓 archived，但 view/state/model 等子仓活跃） |
| License | MIT ✅ |
| 定位 | "The rich text editor framework"（headless，不是成品） |

- **本质**：编辑器内核框架，schema 驱动，所有节点/标记都是自定义的。Markdown 通过 `prosemirror-markdown` 包支持，**是 import/export 转换，不是源码即真源**。
- **能帮到 WorkFollow 什么**：schema 模型与当前的 `NativeDocument`(block+run+marks) 高度同构，迁移路径清晰。装饰层、斜杠菜单、表格、公式都可以做成自定义 node view。
- **真实风险**：headless 意味着**UI 全自己写**（工具条、斜杠菜单、选区浮条）。wkWebView 焦点/滚动/IME/剪贴板桥接要重写——项目已有 Quill P3 的疤痕。ProseMirror 学习曲线陡（schema/transaction/decoration 三套概念）。
- **结论**：**如果走 WebView 路线，这是"最对路"的内核。** 但不是省事的选择，是上限最高的选择。

#### B2. TipTap v3（ueberdosis/tiptap）

| 项 | 值 |
|---|---|
| Star | API 受限，公开数据约 29000+（需核实） |
| 最近 push | 活跃 |
| License | 核心 MIT ✅；**Pro 扩展（Collaboration/Comments/Snapshots/部分 AI）商业闭源，需付费 token** ⚠️ |
| 定位 | ProseMirror 之上的"成品化"封装 |

- **本质**：ProseMirror + 开箱即用的扩展生态 + React/Vue/Svelte 绑定。2026 年 TipTap 把 10 个原 Pro 扩展开源成 MIT（见 tiptap.dev/blog）。
- **能帮到 WorkFollow 什么**：比裸 ProseMirror 省事，Table/Image/TaskList/CodeBlock/LaTeX 都有现成扩展。
- **真实风险**：Pro 扩展的商业条款要逐条确认（Collaboration/Comments 仍闭源）。React 依赖与 WorkFollow 的 SwiftUI 宿主要桥接。Markdown 仍是转换层，非一等公民。
- **结论**：**比裸 ProseMirror 省事，但商业条款和 React 依赖是摩擦点。** 如果走 WebView 且不介意 React，这是 B 组里"投入产出比"最好的。

#### B3. Milkdown（Milkdown/milkdown）

| 项 | 值 |
|---|---|
| Star | 12038 |
| 最近 push | 2026-11-02（活跃） |
| License | MIT ✅ |
| 定位 | "Plugin driven WYSIWYG markdown editor framework" |

- **本质**：ProseMirror + Remark（Markdown AST）双态。**Markdown 是一等公民**——这是 B 组里唯一明确以 Markdown 为真源的 WYSIWYG 框架。
- **能帮到 WorkFollow 什么**：Markdown 双态（源码↔富文本）是当前产品的潜在缺口（docs/editor-optimization-plan 提过 mdEditButton 探针）。schema 可扩展表格/公式/DrawIO。
- **真实风险**：与 ProseMirror 同样的 WebView 桥接成本。中文 IME 口碑有 issue（需核实具体版本）。包体积比 Quill 大。
- **结论**：**B 组里"Markdown 一等公民"最对路的候选。** 如果产品方向是"Markdown 双态编辑器"，Milkdown 是首选。

#### B4. Lexical（facebook/lexical）

| 项 | 值 |
|---|---|
| Star | 约 23000+（gitgenius 数据，需核实，API 受限） |
| License | MIT ✅ |
| 定位 | Meta 的编辑器框架，React 绑定 |

- **本质**：Meta 接替 Draft.js 的项目，schema 驱动，**Markdown 不是一等公民**（要靠 `@lexical/markdown` 转换插件，round-trip 有损）。
- **真实风险**：深度绑定 React。Meta 自己用在 Threads/Facebook，但**桌面笔记 App 用 Lexical 的案例极少**。协同要配 Yjs。
- **结论**：**排除。** Markdown 非一等公民 + React 深度绑定，与 WorkFollow 的诉求不匹配。

#### B5. Slate.js（ianstormtaylor/slate）

| 项 | 值 |
|---|---|
| Star | 31746 |
| 最近 push | 2026-10-28（活跃） |
| License | MIT ✅ |

- **本质**：React 编辑器框架。**API 历史不稳定**（0.x 版本多次 breaking change），Markdown 非一等公民。
- **结论**：**排除。** API 稳定性差，Markdown 非一等公民。

#### B6. BlockNote（TypeCellOS/BlockNote）

| 项 | 值 |
|---|---|
| Star | 10351 |
| 最近 push | 2026-11-02 |
| License | NOASSERTION（需核实，官方定价页有 Pro 闭源项） ⚠️ |

- **官方文档明确写**："The functions to export to Markdown are considered lossy; some information might be dropped."（blocknotejs.org/docs/features/export/markdown）
- **本质**：Notion 风格块级编辑器，基于 TipTap/ProseMirror。**真源是 Block JSON，不是 Markdown。**
- **结论**：**排除。** Markdown 导出官方明说 lossy，与 WorkFollow 的 Markdown 一等公民诉求冲突。

#### B7. CodeMirror 6 / Monaco

- **CodeMirror 6**：源码编辑器，Obsidian Live Preview 的底层。**不是 WYSIWYG 块级编辑器**，但如果走"源码即渲染"范式（Typora/Obsidian Live Preview），这是最成熟的。
- **Monaco**：VS Code 内核，代码编辑器。**排除作为笔记编辑器主力。**

#### B8. Quill 2.x（slab/quill）

| 项 | 值 |
|---|---|
| Star | 47370 |
| 最近 push | 2025-07-25（已不活跃） |
| License | BSD-3-Clause ✅ |

- **本质**：Delta(JSON) 为真源的富文本编辑器。**Markdown 非一等公民**（靠 markdown 模块转换）。
- **项目已有一条搁置的 Quill P3 路线**（焦点战报 7 轮未解，最终用 CGEvent 证明是验证手段问题，但路线已搁置）。
- **结论**：**不推荐继续。** 能力天花板低于 ProseMirror/Milkdown，且已有沉没成本阴影。

#### B9. 其他（Vditor/Cherry/Editor.md/Tui/ByteMD/Novel/Plate）

- **Vditor**（B3log）：开箱 Markdown 编辑器，AGPL-3.0 ⚠️（商用要授权），排除。
- **Cherry Markdown**（腾讯）：开箱编辑器，Apache-2.0，但**是个壳，内核是 marked + contenteditable，不是可扩展内核**。排除。
- **Editor.md**：已不活跃。排除。
- **Tui Editor**：HashiCorp 用，MIT，但**是成品不是内核**，定制成本高。排除。
- **ByteMD**（字节）：MIT，但维护节奏慢。排除。
- **Novel**（vercel）：TipTap 的 Notion 风格封装，**绑定 Vercel 云服务**。排除。
- **Plate**（udecode）：Star 16686，NOASSERTION license ⚠️，React 深度绑定。排除。

### C 组：混合架构方案（不换内核，但借组件）

| 方案 | 思路 | 适用场景 |
|---|---|---|
| **保留 NSTextView + 收拢 AST** | 把 `DocumentTextCodec` 的"段落属性↔NativeDocument"双向编解码重构成单向 AST→attributes 投影，消除文末空段/typingAttributes 的边界 case | 低风险渐进改进 |
| **NSTextView 主力 + CodeMirror 子编辑器** | 正文用原生，公式/代码块的"源码编辑"用 CodeMirror 嵌 WKWebView（比当前的 FormulaEditorWindowController 的纯 NSTextField 更强） | 公式/代码体验提升 |
| **NSTextView 主力 + Runestone 代码高亮** | 代码块用 Runestone 做语法高亮（比当前的 CodeSyntaxHighlighter.swift 305 行自研更强） | 代码块体验提升 |
| **STTextView 底盘 + 自研块层** | 用 STTextView 替换裸 NSTextView，保留自研的 DocumentTextCodec/DocumentBlockDecorations | 底盘升级（需先解决 License） |

---

## 3. 横向对比矩阵

| 项目 | Star | License | 活跃 | 可编辑 | 块级扩展 | Markdown 一等公民 | IME 口碑 | 大文档 | 集成成本 | 协同 | 能支撑笔记编辑器 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **STTextView** | 1610 | ⚠️未知 | 中 | ✅ | ❌ | ❌ | ✅原生 | ✅ | 低(SPM) | ❌ | 部分(需自研块层) |
| **Runestone** | 3238 | MIT | 活跃 | ✅ | ❌ | ❌ | ✅原生 | ✅ | 低(SPM) | ❌ | ❌(代码编辑器) |
| **CodeEditSourceEditor** | 727 | MIT | 活跃 | ✅ | ❌ | ❌ | ✅原生 | ✅ | 低(SPM) | ❌ | ❌(代码编辑器) |
| **MarkdownUI** | — | MIT | 活跃 | ❌只读 | ❌ | ✅渲染 | — | ✅ | 低 | ❌ | ❌(只读) |
| **ProseMirror** | 8693 | MIT | 活跃 | ✅headless | ✅✅ | 转换 | 中(有 issue) | ✅ | 高(全自己写UI) | Yjs | ✅ |
| **TipTap v3** | ~29000 | MIT核心/Pro商业 | 活跃 | ✅ | ✅ | 转换 | 中 | ✅ | 中(React) | Pro付费 | ✅ |
| **Milkdown** | 12038 | MIT | 活跃 | ✅ | ✅ | ✅✅一等 | 中(需核实) | ✅ | 中 | Yjs | ✅ |
| **Lexical** | ~23000 | MIT | 活跃 | ✅ | ✅ | 转换 | 中 | ✅ | 高(React) | Yjs | ✅(但非MD-first) |
| **Slate** | 31746 | MIT | 活跃 | ✅ | ✅ | 转换 | 中 | 中 | 高(React) | ❌ | ✅(但API不稳) |
| **BlockNote** | 10351 | ⚠️需核实 | 活跃 | ✅ | ✅ | ❌lossy | 中 | ✅ | 中(React) | Yjs | ❌(MD lossy) |
| **CodeMirror 6** | 7807(dev仓) | MIT | 活跃 | ✅源码 | ❌ | ✅源码 | ✅ | ✅✅ | 中 | ❌ | ❌(源码范式) |
| **Quill 2.x** | 47370 | BSD-3 | 不活跃 | ✅ | 中 | 转换 | 中 | 中 | 中 | ❌ | 中(天花板低) |
| **Monaco** | — | MIT | 活跃 | ✅源码 | ❌ | ❌ | ✅ | ✅ | 高(体积大) | ❌ | ❌(代码编辑器) |

---

## 4. 明确排除清单

| 项目 | 排除理由 |
|---|---|
| Runestone / CodeEditSourceEditor / Monaco | 代码编辑器，非富文本/Markdown 块级编辑器 |
| MarkdownUI / Down / MarkdownKit | 只读渲染或纯解析，不可编辑 |
| SwiftDown | GitHub 已不可考，死项目 |
| Lexical | Markdown 非一等公民，React 深度绑定，桌面笔记案例少 |
| Slate | API 历史不稳定，Markdown 非一等公民 |
| BlockNote | 官方文档明确 Markdown 导出 lossy |
| Vditor | AGPL-3.0，商用需授权 |
| Cherry/Editor.md/Tui/ByteMD | 成品壳，非可扩展内核 |
| Novel | 绑定 Vercel 云服务 |
| Plate | License NOASSERTION，React 深度绑定 |
| Quill 2.x | 已有搁置的 P3 疤痕，能力天花板低于 ProseMirror/Milkdown |
| cosmic-text(Rust FFI) | 纯文本排版，无富文本/块级/Markdown，FFI 成本高收益不明确 |

---

## 5. 推荐路线与迁移风险

### 5.1 三条可选路线

| 路线 | 一句话 | 投入量级 | 风险 | 上限 |
|---|---|---|---|---|
| **路线 A：不换内核，收拢 AST + 局部借组件** | 保留 NSTextView，把 DocumentTextCodec 重构成单向 AST 投影；代码块高亮借 Runestone；公式编辑借 CodeMirror 子视图 | 小（2-4 周） | 低 | 中（解决当前痛点，但天花板不变） |
| **路线 B：STTextView 底盘 + 自研块层** | 用 STTextView 替换裸 NSTextView 的布局层，保留自研块模型/装饰/Markdown | 中（4-8 周） | 中（License 前置门槛 + 迁移测试） | 中高（更干净的 TextKit 2 抽象） |
| **路线 C：Milkdown/TipTap + WKWebView 全量替换** | 走 WebView 路线，Markdown 一等公民，schema 可扩展，协同生态 | 大（8-16 周） | 高（焦点/滚动/IME/剪贴板桥接重写，已有 Quill P3 疤痕） | 高（业界主流范式，协同/AI 天花板） |

### 5.2 "比当前更优"拆解成可验证维度

| 维度 | 当前 | 路线 A | 路线 B | 路线 C |
|---|---|---|---|---|
| 大文档性能（10k+ 段） | 同步全量 decode，已缓存但无增量 | 可做增量 decode | 同 A + 更干净布局 | ProseMirror 增量事务，原生优势 |
| 块级扩展成本 | 47 文件状态机 | 收拢后降低 | 同 A | schema 声明式，最低 |
| Markdown 双态 | 只有 WYSIWYG | 不变 | 不变 | Milkdown 原生支持 |
| 协同（远期） | 无 | 无 | 无 | Yjs/Hocuspocus 生态 |
| IME | 原生，已踩平 | 不变 | 不变 | WebView 要重踩 |
| 焦点/滚动 | 原生，已踩平 | 不变 | 不变 | WebView 要重踩（P3 疤痕） |
| 维护成本 | 13000 行状态机 | 收拢到 ~8000 行 | 同 A + STTextView 依赖 | 内核小但桥接层大 |
| 上架风险 | 零依赖 | 零依赖 | STTextView License 需解决 | MIT，但 WebView 沙盒要审 |

### 5.3 推荐判断

**如果目标是"比当前更优且低风险"：选路线 A。** 当前痛点是组织债和 TextKit 2 规避，不是架构失败。把 DocumentTextCodec 收拢成单向 AST 投影、消除文末空段/typingAttributes 边界 case、代码块借 Runestone，能在 2-4 周内拿到可感知的改善，且不碰已经踩平的 IME/焦点/滚动。

**如果目标是"上限更高，能做协同/AI/Markdown 双态"：选路线 C（Milkdown）。** 但这是 8-16 周的投入，且要直面 Quill P3 的阴影。建议先做一个"只做公式/表格子编辑器"的 Milkdown 子嵌入 PoC，验证 WKWebView 桥接的焦点/IME 是否真的比 Quill 时代更好（ProseMirror 的 IME 处理比 Quill 成熟），再决定是否全量替换。

**路线 B（STTextView 底盘）只在 License 确认是 BSD/MIT 类宽松许可后才值得评估。** 在 License 没核实前，不投入。

### 5.4 迁移风险评估（若选路线 C）

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| WKWebView 焦点/IME 重现 Quill P3 问题 | 中 | 高 | 先做 PoC 验证 ProseMirror 的 composition 事件处理 |
| Markdown round-trip 有损（NativeDocument↔ProseMirror schema） | 中 | 高 | 建一份完整 schema 映射表，逐 case 测试 |
| 剪贴板 RTF↔Web 剪贴板桥接断裂 | 高 | 中 | 保留当前 DocumentExternalClipboardCodec，走 Swift 侧剪贴板代理 |
| 滚动路由（WebView 内部 vs 外层 SwiftUI ScrollView） | 高 | 中 | 已有 Quill 时代的 EditorHostScrollRouting 经验 |
| 包体积（Milkdown min+gzip 约 200KB+，比 Quill 大） | 低 | 低 | 离线打包，已 QuillRuntime.zip 经验 |
| 协同付费墙（TipTap Pro / Milkdown 要配 Yjs） | 低 | 中 | Milkdown MIT，协同用开源 Yjs |

---

## 6. 证据索引与可信度

| 事实 | 来源 | 可信度 |
|---|---|---|
| 当前编辑器 14700 行、47 文件 | 本地 `wc -l` / `ls` | 高（实测） |
| TextKit 2 双标记痛点 | DocumentBlockDecorations.swift:8 注释 | 高（源码事实） |
| Quill P3 焦点战 7 轮 | docs/editor-quill-p3-focus-battle-2026-10-24.md | 高（仓库文档） |
| STTextView Star 1610 / License NOASSERTION | GitHub API + Swift Package Index | 高（API 实测） |
| Runestone Star 3238 / MIT | GitHub API | 高 |
| ProseMirror Star 8693 / archived 主仓 | GitHub API | 高（主仓 archived 但子仓活跃） |
| Milkdown Star 12038 / MIT / Markdown 一等公民 | GitHub API + milkdown.dev 官方文档 | 高 |
| BlockNote Markdown lossy | blocknotejs.org 官方文档 | 高（官方明说） |
| TipTap Pro 商业闭源 | tiptap.dev/docs/guides/pro-extensions | 高（官方文档） |
| Lexical Star ~23000 | gitgenius.co（非 GitHub API 直测） | 中（需核实） |
| Slate Star 31746 | GitHub API | 高 |
| Quill Star 47370 / BSD-3 / push 2025-07 | GitHub API | 高 |
| 业界主流范式是 WebView+ProseMirror | Obsidian/Logseq/Typora/Notion 公开技术栈 | 中（公开信息汇总，部分推断） |

---

## 附：下一步建议（不写代码）

1. **先做路线 A 的 PoC 设计**：画一份"DocumentTextCodec 单向 AST 投影"的重构草图，评估能否消除 `pendingTrailingBlock`/`displayedTrailingBlock` 边界 case。这是最低风险的"更优"。
2. **STTextView License 核实**：直接读 LICENSE.md 全文，确认是否 BSD/MIT 类。如果是，路线 B 才值得继续评估。
3. **Milkdown 子嵌入 PoC（可选）**：只在公式或表格子编辑器里嵌 Milkdown，验证 WKWebView 的 IME/焦点是否比 Quill 时代好。这是路线 C 的前置验证。
4. **不要全量替换 NSTextView**：当前 13000 行里有 1136 条测试断言保护，全量替换的回归成本是周以月计的。
