# 滴答与 WorkFollow 任务编辑器对比

后续改造与验收见 [编辑器统一实施与验收](implementation-and-acceptance.md)。下文保留改造前的调查基线。

日期：2026-10-25。参考本机 macOS 滴答 8.0.80 (492)，比较对象为当前源码中的 `TaskInspectorShell → DocumentEditor → NativeTextView`。不包含独立笔记页的 Quill，不把列表、看板和日历列为本轮差异。

本轮只读分析项目代码，新增本报告和观察记录。交互复现用临时源码副本、隔离存储和完整任务详情宿主；未修改项目的任务编辑器、共享文档模型或真实任务数据，也没有安装应用。

## 1. 核心判断

**任务编辑器的技术基础已经接近滴答：两者都基于原生 NSTextView。差异主要在结构化内容流转、任务类型入口和宿主状态管理；Markdown 的用户可见行为应以实际输入验证为准。**

参考侧复用本轮已核实版本的 REA Mach-O、Swift 符号解码和原始类元数据：正文为 `APMarkdownTextView: NSTextView`，框架含 `APMarkdownLayoutManager: NSLayoutManager`、`APMarkdownTypesetter: NSATSTypesetter`，普通任务正文的实际 AX 值保留 Markdown 标记。详情控制器包含任务/笔记类型判断与转换入口。

项目侧也已有 `TaskKind.text/note/checklist`，可以留在任务页面内切换。**不能说项目没有任务内笔记类型。** 当前问题是这条路径与“转换成独立笔记”的路径并存，后者进入另一模型和 Quill 编辑器。

## 2. 已有实现，不应再列为缺失

| 范围 | 当前实现 |
|---|---|
| 原生正文 | NSTextView 输入、中文组合输入提交处理、正文自己的撤销历史、任务切换前提交 |
| 格式 | H1–H6、粗体、斜体、下划线、删除线、高亮、列表、检查项、引用、行内代码、代码段、分割线 |
| 工具栏与菜单 | 底栏 A 入口、固定在底栏上方的格式工具条、标题/时间面板、更多溢出菜单、Slash 与块菜单 |
| 任务专属动作 | 添加子任务、标签、关联任务/笔记、`#` 标签补全、`~` 清单补全 |
| 链接及附件 | 链接编辑/移除/悬停、附件插入、文件拖入、粘贴文件、附件列表、图片预览和流程图 |
| 子任务 | 嵌套、行内改名、回车续加、同级拖动排序、折叠持久化和隐藏数统计 |
| 评论等宿主功能 | 评论、回复、编辑、删除、持久化；模板、副本、便签、动态和独立详情窗口入口 |

这些是实际代码执行链和定向验证支持的能力，不代表所有位置、字号和交互均已完成视觉验收。上一轮 Quill 的“按钮只发消息”“工具栏在文末”“普通 image embed 保存丢失”等结论不能套到这里。

原生受支持模型的隔离序列化探针验证：段落、标题、列表、检查项、引用、代码、分割线、普通行内标记、原生图片附件引用和流程图均能正常保存回读。

## 3. 确定的差异与问题

### A. Markdown 输入机制：已根据用户实测纠正假设

**依据：参考侧 AX/元数据、项目源码，以及用户直接在滴答中的输入验证。**

AX 中出现 `# **文字**` 等标记，只能说明底层暴露的文本，不能证明屏幕上让用户编辑源码。用户随后实测：输入 `#` 出现候选框，输入空格后转换为 H1，`# ` 在界面消失，继续输入即为一级标题，与格式菜单选择 H1 一致。

因此撤回“必须改成保留原始标记的源码编辑模式”这一推断。现有原生富文本内核方向符合已确认的用户行为；本轮改造保留该内核，分别验收候选框、空格触发、标题样式、光标与撤销。复制输出和块结构问题仍需独立修复。

位置：[DocumentMarkdownInput.swift](../../../macos-native/WorkFollow/Features/Editor/DocumentMarkdownInput.swift:200)、[重解析](../../../macos-native/WorkFollow/Features/Editor/DocumentEditorCoordinator.swift:126)、[复制](../../../macos-native/WorkFollow/Features/Editor/NativeTextView.swift:804)。

### B. 跨正文复制粘贴会丢标题、列表等块结构

**依据：生产代码的隔离 RTF 往返复现。优先级 P1。**

源内容为两项有序列表，首项带粗体。经过原生 RTF 编解码与当前 `richText(baseKind: .paragraph)` 后，两个块都变成普通段落，粗体保留；复制的纯文本只有项目文字，没有编号。

列表编号主要由装饰层绘制，未写入字符；粘贴转换又把来源块统一为目标段落类型。因此复制任务计划到另一条任务或摘要时，文字能过去，结构却会退化。这是已复现的本项目问题；本轮没有读取滴答的系统剪贴板内容，不声称已测得其所有导出格式。

位置：[粘贴归一化](../../../macos-native/WorkFollow/Features/Editor/DocumentTextCodec.swift:198)、[粘贴入口](../../../macos-native/WorkFollow/Features/Editor/NativeTextView.swift:826)。

### C. 评论草稿跨任务复用，并能发到错误任务

**依据：完整 TaskInspectorShell 的隔离原生交互复现。优先级 P1。**

步骤：在 A 展开评论，输入未发送草稿；切到 B，重新展开评论；B 输入框仍显示 A 的草稿；按回车发送后，A 评论数为 0，B 评论数为 1。

原因是 `TaskCommentSection` 本身持续存在，其 draft、编辑草稿、回复目标都是未按 taskID 隔离的 State。切任务时只把展开状态关闭，没有重建或切换这份状态。

位置：[评论状态](../../../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskCommentSection.swift:12)、[发送](../../../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskCommentSection.swift:228)、[详情调用点](../../../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift:542)。

### D. 子任务折叠后，外层占位反而变高

**依据：完整任务详情布局测量。优先级 P2。**

一个子任务含两个孙任务：折叠后，原生树从 3 行变成 1 行，内部高度从 140 降为 60；但整个子任务区的占位从 166 增为 187。外层高度仍按全部子孙行计数，加上“已折叠”提示后更高，导致空白保留、下方内容被推远。

需要修的是宿主占位与可见行数同步，不能说子任务折叠没有实现。仅检查 NSOutlineView.numberOfRows 会漏掉这个问题。

位置：[高度绑定](../../../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift:721)、[高度计算](../../../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift:743)。

### E. 两条“笔记”入口带来不同结果

**依据：项目源码与参考侧共用详情体系证据。优先级 P1 的体验决策项。**

- 标题处选择“笔记类型”：修改同一任务的 kind，留在 TaskInspector，仍用原生正文及 TaskDocumentProfile。
- 更多菜单“转换为笔记”：创建独立 Note、标记旧任务已转换，跳到 NotesWorkspace，使用 Quill。

用户看到相近名称，却会进入不同的数据模型、页面和编辑体验。这比少一个图标更影响一致性。后续应先明确两条入口的产品语义，再决定保留、改名或收敛；本轮没有合并模型。

位置：[类型菜单](../../../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift:1045)、[类型转换](../../../macos-native/WorkFollow/Application/TaskActions.swift:483)、[独立笔记转换](../../../macos-native/WorkFollow/App/AppEnvironment.swift:505)。

### F. 列表层级与文件插入策略尚有差距

**依据：当前模型和代码；与滴答具体行为仍需逐项配对。**

- 列表只有平面 bullet/ordered/checklist 类型，缺少层级和起始编号字段；固定缩进不等于结构化多级列表，也没有专用 Tab/Shift+Tab 处理。
- Finder 文件粘贴只把 URL 传给宿主，追加到任务附件列表；工具栏插附件则落在正文光标处。两种入口的落点不同。
- 文件粘贴登记任务业务历史，正文聚焦时菜单撤销走正文 UndoManager，两条历史的衔接存在风险。本轮未把代码推断写成实际按键验收结论。

位置：[块类型](../../../macos-native/WorkFollow/Domain/Document/NativeDocument.swift:130)、[文件粘贴](../../../macos-native/WorkFollow/Features/Editor/NativeTextView.swift:817)、[宿主回调](../../../macos-native/WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift:996)、[撤销路由](../../../macos-native/WorkFollow/App/AppCommands.swift:139)。

## 4. 暂不认定的差异

- 项目普通任务主动关闭选中文字浮条。滴答虽然有相关方法，但本轮只读选择没有取得浮条出现证据，不能据此判为缺失。
- 清单类型切到文本/笔记再切回时，已勾选状态不能完整恢复；这是源码可确定的往返限制，但还需对照滴答的转换策略，不能直接认定原版一定保留。
- 正文图片按固定上限缩放，是否在窄详情中裁切需要单独布局验收。
- 评论多媒体、独立窗口的绑定方式等宿主能力仍需单独对照，暂不影响本轮普通正文结论。
- 本轮截图仍是失真缩略图，没有给出新的字号、边距、弹层位置像素差值。
- 对原版 Tab 函数补充反编译时，REA 先拒绝通用 Mach-O；提取 arm64 副本后限时分析仍未完成，因此保留原版具体缩进规则为未知，没有据此扩展行为结论。

## 5. 建议顺序与验证记录

建议保留现有任务原生编辑器，在此基础上依次处理：

1. 评论草稿、回复和编辑状态按任务隔离，保证切任务不串内容。
2. 复制粘贴保留块结构，明确 Markdown 源与富文本两种输出策略。
3. 明确两条笔记入口的语义，以及 Markdown 编辑机制的对齐目标。
4. 修复子任务折叠的外层占位，再验证多级列表和文件粘贴的落点、撤销。
5. 最后补字体、行距、工具条和弹层的同窗口视觉验收。

17 项已有相关用例通过，覆盖输入前缀、分割线撤销、检查项、文件粘贴宿主回调、链接及编辑提交。另有 2 项调查用例暴露了评论草稿和折叠占位问题；这些失败是问题复现，不能称为修复后回归通过。调查用例只存在临时源码副本，未加入项目测试目录。

精简观察结果见 [task-editor-observations.json](task-editor-observations.json)。对照笔记 Quill 的报告见 [README.md](README.md)。
