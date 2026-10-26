# macOS 滴答正文编辑器与当前笔记 Quill 的差异

日期：2026-10-25。参考对象为本机 `/Applications/TickTick.app`，版本 8.0.80 (492)。项目对象为当前 WorkFollow 源码中的笔记编辑器，内核 Quill 2.0.3。日用 WorkFollow 为 0.2.0 (14)，其 bridge.js、editor.css、slash-menu.js 与本次分析源码相同。

本轮是分析：已撤回上一轮尚未验证的“笔记切回原生编辑器”改动，保留 Quill 和既有滚动修复。本轮没有修改任务编辑器、共享文档模型，也没有安装应用或改写真实任务、笔记。

## 结论

**当前这版 macOS 滴答的任务正文是原生 Markdown 编辑器，不能认定为 Quill Web 编辑器。普通任务和笔记类型共用任务详情体系。**

关键证据：

1. AppestKit 的 Objective-C 元数据明确记录 `APMarkdownTextView` 的父类为 `NSTextView`。同包的 `APMarkdownLayoutManager` 继承 `NSLayoutManager`，`APMarkdownTypesetter` 继承 `NSATSTypesetter`。
2. TickTick 主程序的 `TTTaskDetailMarkdownCell.textView` 类型为 `AppestKit.APMarkdownTextView`。
3. `TTSingleTaskDetailViewController` 同时具有 `editingMarkdownTextView`、`detailMarkdownCellTaskIsNoteKind`、`isNoteKind`、`bottomActionViewDidClickConvertTaskAndNotes:`。这与用户观察到的“笔记是任务的一种类型、在同一任务页编辑”一致。共用正文组件不等于所有类型字段和配置完全相同。
4. REA 从实际框架导出符号并解码出 `markdownTextStorage: NSTextStorage`、`parseMarkdown(...)->NSAttributedString`、`undoTextReplacement(...)` 等原生编辑接口。正文实际 AX 节点也是文本输入区，并暴露 Markdown 标记。
5. 包内静态文件枚举未发现 Quill 分发文件；这条否定搜索仅作辅助，原生类继承和正文持有类型才是主要依据。不能由应用使用了 WebKit 推断正文使用 WebKit。

所以，Quill 是本项目选择的实现路径，不能当成“直接使用滴答的原编辑组件”。继续采用 Quill 仍然可以对齐产品体验，但需要补完数据、命令、选区和宿主交互。

## 当前笔记编辑器的确定问题

| 优先级 | 问题与用户可见影响 | 代码依据 |
|---|---|---|
| P0 | **保存回读有损。** Quill 的 ops 先转成块模型，再编码回 ops。文字颜色、缩进、对齐不保留；任意背景色收敛为固定黄色；普通 image embed 变成“[图片]”。界面当下看起来存在的内容，重新装载后可能降级。 | [NativeDocument.swift](../../../macos-native/WorkFollow/Domain/Document/NativeDocument.swift:28)、[QuillDeltaCodec.swift](../../../macos-native/WorkFollow/Domain/Document/QuillDeltaCodec.swift:146)、[Coordinator](../../../macos-native/WorkFollow/Features/Editor/QuillDocumentEditorView.swift:91) |
| P1 | **命令只有入口，执行链不完整。** 附件、链接、表格、时间、更多发送 requestAction 后没有完整宿主处理；流程图只发通知，未找到订阅方；表格为占位块。图片选择入口能执行，但受到上一项保存问题影响。 | [toolbar.js](../../../macos-native/WorkFollow/Resources/quill-web/toolbar.js:74)、[bridge.js](../../../macos-native/WorkFollow/Resources/quill-web/bridge.js:49)、[宿主处理](../../../macos-native/WorkFollow/Features/Editor/QuillDocumentEditorView.swift:112) |
| P1 | **鼠标选择斜杠命令丢失插入位置。** activate 先调用 close，close 清空 slashIndex，随后回调拿到 null。键盘 Enter 使用另一变量，鼠标和键盘因此不一致。 | [slash-menu.js](../../../macos-native/WorkFollow/Resources/quill-web/slash-menu.js:84)、[bridge.js](../../../macos-native/WorkFollow/Resources/quill-web/bridge.js:134) |
| P1 | **格式工具栏在整篇正文末尾。** Aa 只改变显隐；增长型 WebView 中没有将工具栏保持在视口内，也没有显示后定位。长文在顶部时可能看不到工具栏。 | [DOM 装配](../../../macos-native/WorkFollow/Resources/quill-web/bridge.js:56)、[显隐](../../../macos-native/WorkFollow/Resources/quill-web/bridge.js:277)、[笔记宿主](../../../macos-native/WorkFollow/Features/Notes/NotesWorkspaceView.swift:238) |
| P1 | **选区与宿主接口未接通。** selectionChanged 没有 Swift 接收分支；handle 和 onEditingChanged 只是保留参数。笔记空白处调用原生 handle.focusEnd，不能控制 Quill；笔记原有“选中文字创建任务”等动作没有迁入这条链路。 | [选区事件](../../../macos-native/WorkFollow/Resources/quill-web/bridge.js:247)、[宿主参数](../../../macos-native/WorkFollow/Features/Editor/QuillDocumentEditorView.swift:19)、[空白处点击](../../../macos-native/WorkFollow/Features/Notes/NotesWorkspaceView.swift:269) |
| P2 | **外观尚未形成单一规范。** Quill 与 SwiftUI 各有一套空文档占位；正文为 14px、1.6 行高，外层占位为 15pt；段落、菜单、工具栏由不同宿主负责，尚未逐项核对当前原生参考。 | [editor.css](../../../macos-native/WorkFollow/Resources/quill-web/editor.css:47)、[占位层](../../../macos-native/WorkFollow/Features/Notes/NotesWorkspaceView.swift:245) |

此外，Tab 的 shift 参数没有传回，JS 调用 `quill.indent(...)` 的路径需要核实；颜色面板的外部 mousedown 关闭与按钮 click 切换也可能冲突。这两项列为待运行验证，不与已复现的问题混为一谈。

粗体、斜体、下划线、删除线、基本列表、引用、代码块和部分 Markdown 转换确实调用了 Quill。history 模块已启用，不能笼统说没有撤销。中文输入目前走 WebKit 自然路径，本轮没有作中文输入法与撤销分组的桌面交互验收。

## 本轮复现及证据边界

- 使用当前真实 Swift 文档模型和转换器，在隔离命令行程序中执行 JSON 解码、编码：文字颜色、缩进、对齐均未保留，背景色变为 `#ffe98a`，image embed 丢失，正文成为“彩色正文\n[图片]”。这是数据链实跑结果，不是实际用户笔记测试。
- 使用实际 slash-menu.js 配合最小 DOM 桩点击菜单：输入位置 11，回调位置 null。这是命令脚本复现，不是桌面鼠标验收。
- REA 执行 `inspect_macho`、`inspect_analysis_view`、`demangle_swift`；结合系统工具读取原始 Objective-C 类与属性元数据。没有把符号名当成完整业务调用执行证据。
- REA 的整包 NIB 解码受 64 个文档上限限制，没有覆盖到目标正文类；因此没有用该输出证明正文界面结构。
- 原生截图工具仍只返回失真的缩略图，本轮不声称完成字号、边距、弹层位置的像素验收。
- REA 会话已关闭。精简观察记录见 [observations.json](observations.json)。

## 建议的后续顺序

1. **先保证笔记无损保存。** 明确 Delta 真源与旧块模型的职责，建立“编辑—切换笔记—重新打开”的颜色、图片、列表用例。共享文档模型的变更需另行评估任务兼容性。
2. **补齐真实操作闭环。** 先修斜杠菜单位置，再接通链接、附件、时间、更多、选区与焦点；未完成的入口应给出明确反馈。
3. **重排工具栏和弹层。** 以可见视口和当前选区为锚点，长文中也能操作；统一空文档占位、字号、行距、段落间距与菜单几何。
4. **再评估统一的编辑器边界。** 滴答统一的是任务详情、笔记类型与编辑机制。项目目前有独立 NotesWorkspace 和 TaskInspector；是否整合属于另一项产品和架构决策，不能通过直接替换一个编辑控件完成。

当前不应仅根据“滴答似乎用了 Quill”继续扩大迁移。本轮保持任务编辑器不动，也不直接决定笔记退回原生；先依据上述确定缺口完成路线评估。

任务原生编辑器的后续对比见 [task-editor-comparison.md](task-editor-comparison.md)。补充明确：项目已经有任务内的 note 类型，另有转换到独立 NotesWorkspace 的入口；两者并存才是需要评估的体验差异。
