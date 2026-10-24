# 编辑器内核切换：P3 焦点攻坚战报（2026-10-24）

状态：P0/P1/P2 完成并验收；P3 数据链闭环已验证，**键盘焦点问题未解**，已收尾为稳定底稿。

## 已验证的事实（复现路径）

1. **内核与组件全通**（P0/P2）：Quill 2.0.3 离线加载、工具条 20 钮、斜杠菜单 14 项、
   markdown 触发、CJK 渲染——spike 窗口（WKWebView 直挂 contentView）里全部可用。
2. **数据链全通**（P3，决定性证据）：`WorkFollowNativePreview/workspace.sqlite` 直查
   `note_documents` 表，笔记 `6B24FD77` 的 document 为新形态
   `{"ops":[{"insert":"PROBE"},…],"plainText":"PROBE"}`——
   JS 注入（探针）→ deltaChanged → onDocumentChange → SQLite 持久化，全程无断点。
3. **旧形态兼容**：同库另一篇笔记仍是 `{blocks}` 旧形态，按 P1 设计兼容读、
   下次保存自动转新形态。

## 未解问题（唯一）：键盘事件到不了 WebContent

- 症状：真实键入在编辑器 UI 上无任何反应（无光标、无 text-change）；
  同一编辑器里 JS 注入（探针）可写可存。
- 另一个对照组失效的线索：P2 时 spike 窗口**曾经可以键盘输入**（英文+中文实测过），
  P3 改用新版模块化 bridge（index.html + workfollowEditor API）后未再复测通过——
  **bridge 版本差异是当前最大嫌疑**，未排除。

### 已试无效的修法（全部保留在代码里，标注了实测注释）

1. `acceptsFirstResponder`/`becomeFirstResponder` 转发（QuillDocumentEditorView）
2. 约束式布局（autoresizing 不可靠）
3. `hitTest` 透传到 webView
4. 本地 mouseDown monitor + `makeFirstResponder(webView)`
5. 本地 keyDown monitor + `webView.keyDown(with:)` 转发
6. keyDown 文本经 JS 直注（`injectKeyEvent/backspace/arrow` 通道，bridge 已备好）——
   **monitor 未命中**：无条件诊断版也零命中，且 `makeNSView` 有执行（marker 文件验证）。
   嫌疑：System Events 合成 keystroke 的事件分发路径与 addLocalMonitorForEvents 的
   交集问题（真实键盘未测试过——机器无外接键盘场景验证）。
7. bridge 侧 mousedown → `quill.focus()`（缓存版本号多次递增排除旧缓存）

### 建议的下一步（按性价比排序）

1. **真人键盘实测**：所有"键入无效"结论都基于 System Events 合成按键。
   真实键盘的事件分发路径不同，`injectKeyEvent` 通道可能直接就能工作。
   打开 Debug 菜单 → 笔记页 → 点编辑器 → 直接打字。这是 5 分钟就能做的决定性实验。
2. 对照 bridge 差异：用 git 历史恢复 P2 时的单文件 bridge（spike 键盘可用的版本），
   diff 两版的关键差异（contenteditable 初始化路径/事件绑定顺序）。
3. 若 1、2 都不通：放弃 SwiftUI 嵌入，改用 NSHostingController-free 的 AppKit
   直挂（NotesWorkspaceView 的编辑区改为 NSViewRepresentable 容器直接
   addSubview，像 spike 一样）。

## 当前代码状态

- `QuillDocumentEditorView.swift`：正式宿主（数据链通、rev 防回环、布局/焦点修法全保留）
- `quill-web/`：bridge 含 `injectKeyEvent/backspace/arrow` JS 直注通道（待 Swift 侧触发）
- Debug 菜单：Quill spike 窗口 + "注入文本"探针（验收工具，保留）
- runtimeVersion = "8"（改 bridge 必须 bump，否则 Caches 不失效——已踩过两次）
- 测试：QuillBridgeSpikeTests / QuillDeltaCodecTests / NoteFeatureTests 25/25 绿

提交：7114294（P0）→ bdf13d8（P1）→ 463ca44（P2）→ e3c97bf → 本文件随收尾提交。
