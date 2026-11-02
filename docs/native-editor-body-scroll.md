# 主页面正文无法滚动：定位与修复

## 现场证据

用户实测：任务与笔记主页面正文超过一屏后，鼠标滚轮和触控板均不能滚动；浮窗可以。
在独立运行、使用虚构资料的 App 中，用户也复现了笔记正文无法滚动。
被动事件记录显示滚轮已命中 `NativeTextView`，6191 个字符仍在，但正文高度从 4414pt 变为 568pt，外层内容高度从 4513pt 变为与视口相同的 667pt。滚动范围因此消失。

## 原因

`NativeTextView.mouseMoved` 会调用附件悬停检测，旧实现无条件读取 `NSTextView.layoutManager`，即使鼠标只经过普通文字。
这个访问触发 TextKit 1 兼容模式，原有 `textLayoutManager` 随即变为 nil。
`DocumentEditorContent.sizeThatFits` 依赖 TextKit 2 测量全文，随后返回 nil，长正文被压成视口内的高度。

先前只发送滚轮的测试漏掉了鼠标移入正文的路径，不能代表实际使用。补上生产 `mouseMoved` 路径后，旧实现的一项完整窗口用例失败，同时复现排版引擎丢失、正文缩短及双向滚动失败。

## 改动

附件悬停改用字符位置及共享的 `viewRect(forCharacterAt:)` 查询附件矩形，保留附件名称提示，不再触发旧排版引擎。
任务与笔记通过共享编辑器获得修复。没有增加独立滚动实现。
临时的滚轮、尺寸及调用位置记录仅用于隔离诊断副本，没有合入本次生产改动。

## 验证

最终源码的 25 项定向回归全部通过：

- `EditorBodyScrollTests`：4 项，覆盖真实鼠标移入处理后的笔记/任务滚动、普通鼠标与触控板、短长笔记切换、长段落粘贴、切页与缩放，以及附件提示。
- `EditorScrollRoutingTests`：10 项。
- `NotesNativeEditorIntegrationTests`：7 项，包含格式编辑、输入法及笔记切换。
- `FloatingEditorIntegrationTests`：4 项。

2026-11-02，用户在同一隔离 App 中，将鼠标移入长笔记正文后用日常滚轮或触控板复测，确认“已恢复正常滚动”。任务正文通过共享修复及完整窗口回归覆盖，尚未单独获得人工确认。
随后用户授权替换日用版。2026-11-02 已正常退出旧版、备份数据与偏好，并将 Release 0.2.0（6）安装至 `/Applications/WorkFollow.app` 后重新打开。临时滚动探针限定在 Debug 编译中，正式包不包含该探针。

安装后打开原先无法滚动的长笔记，点击正文后复测上下滚动，滚动条值从 0 到约 0.554，再回到 0。数据库的任务及旧笔记 ID 集合与备份一致，保留 73 条任务记录（含 12 条笔记项）及 2 条旧笔记记录。
数据备份位于 `~/Library/Application Support/WorkFollowNativeUpdates/data-backups/before-scroll-fix-20261102-085400`；旧构建 5 保留在 `~/Library/Application Support/WorkFollowNativeUpdates/previous/WorkFollow.app`。
