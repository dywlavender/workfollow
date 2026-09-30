# TickTick Task Surface Parity

## 基准与范围

从本轮开始，Task surface 的 UI 基准顺序为：用户提供的滴答 macOS 截图与确认行为 → Native 已有能力 → Flutter 业务规则参考。不再将 Flutter UI 尺寸当作最终视觉目标。

当前收到一张 3022×1900 原始任务页截图（本轮用户附件），展示有日期父任务、一个 child 和 Footer。文字方案提及的其余截图本轮未附：没有空详情、日期面板、Quick Add 属性菜单、Slash 的完整实图。因此不能把未提供的图片当作像素验收依据。

排除窄窗口独占模式、breakpoint、Sidebar、Rail、已完成的 Task List 三轮、Focus、Calendar、Matrix、Note Editor；不猜评论业务、More 内容、Tag Picker、Pin/Focus 最终入口。

## Commit 1：Shell / Header / Empty

### TI-001 空详情

- 无 Header、Footer、操作提示文字；无放大 SF Symbol。
- `TaskEmptyInspectorView` 使用低对比 Canvas 星形装饰，居中、不可命中、不进入辅助功能树。
- **状态：实现 / 渲染测试 / 真窗口截图通过；装饰准确复刻待空态参考图。** 当前装饰是明确的占位资产，不宣称是滴答原插画。

### TI-002 Header

- Completion 复用 `TaskCompletionBox`（18pt）；继续调用既有状态动作，放弃态保留叉号辨识。
- Divider → 无底色 Schedule → 条件 Repeat → 右侧固定 Priority。Header 无 Reminder、Focus、Pin。
- 无日期为“设置日期”及 tertiary；今天/未来使用现有全局 accent，过期使用 danger；不单独修改全局 Theme。
- Schedule 示例：`今天, 9月30日`、`上周日, 9月27日, 20:30`；去掉“逾期 N 天”。日历相关前缀按实际 now/calendar 推导：9月30日的9月20日不在上周，不能硬编码方案示例。
- 日期仍打开原 Schedule Panel；Repeat 复用其 recurrence 页面；Reminder 配置留在日期面板内部。面板内部本笔不变。
- 保留已有 58pt Header、52pt Footer 与20pt horizontal padding；这些是上一轮来源尺寸，尚非相同窗口滴答测量值。没有拿缩放后的截图猜新高度。
- **状态：实现 / 状态与窗口渲染测试 / 真窗口交互通过；完整逐像素验收待等尺寸参考与固定数据。**

## 验收证据

- `TaskInspectorShellContractTests`：320/760pt 长日期下 Priority 不被挤出、Divider 尺寸、Reminder 始终缺席、Repeat 条件显示、无选择不创建 Header、空装饰居中、日期标签与三类 tone。已有 breadcrumb 顺序测试继续回归。
- `TaskInspectorPresentationTests`：既有 Escape 顺序回归通过。Reminder 弹层状态能力保留，但不再暴露 Header 入口。
- 最新 App 由 `/tmp/workfollow-native-derived-data/Build/Products/Debug/WorkFollow.app` 构建，退出旧进程后重新启动；截图见本轮工具输出。
- 真窗确认空态无文字；有 reminder/recurrence 的任务 Header 仅显示 Schedule/Repeat；日期点击打开原 panel，Escape 关闭后选择保留；无日期 child 显示“设置日期”。没有修改用户任务内容作截图夹具。

## Commit 2：TI-003～TI-007 / 正文、父子结构与 Footer

- **TI-003 自然正文流：** 保留 `DocumentEditor(contentSized: true)`，不改 Core；子任务区起点为 document.maxY + 20pt，移除旧的双重 top padding。空/单行/多行正文有独立窗口渲染断言，正文变高时 child 随内容下移，不占满剩余 Inspector。
- **TI-004 子任务区：** 独立 `TaskInspectorChildRow`，统一 CompletionBox 16pt、行高42pt、半径8pt、水平内边距12pt。未完成标题用 primary，完成态仍弱化；neutral 灰底与 hover，无蓝色 selected 底。Child 之间不再插普通 Divider，行间与 Add 前间距6pt；无日期不创建尾栏。有日期沿用现有日期入口。不改变新增、inline edit 和子任务状态动作。
- **TI-005 Breadcrumb：** 显示实际父名后跟9pt右 chevron，4pt gap；在 title 上方，点击选择 parent，同一个 Inspector 内导航。
- **TI-006 Footer：** Parent 保留清单 Menu 及既有移动权限；Child 清单改成正常 primary 墨色的只读 Label，不使用 disabled Menu，不允许 child 独立移动清单。List 左边缘20pt，More 右边缘20pt，Formatting/More 仍靠右。
- **TI-007 / TASK-INSPECTOR-GAP-COMMENTS：** 评论/活动能力未确认，继续保留 Gap，无假按钮。
- **自动验收：** 新增 `TaskInspectorHierarchyRenderTests`，NSWindow + NSHostingView 固定880×900，渲染并保存 parent-no-child、parent-with-child（empty/single/multiline）、parent-multiple-children、selected-child；几何断言覆盖 breadcrumb/title、document/child、row/add gap、Footer endpoints。与 Shell/Presentation 定向测试一并通过。渲染 PNG 输出至 `/tmp/workfollow-inspector-hierarchy-renders`，测试不依赖用户数据。
- **真实窗口：** 退出旧进程后启动本笔最新编译 App；点击子行背景打开 child，点 breadcrumb 回 parent；点击子行完成框不会跳转 Inspector，已完成后再恢复到原状态；parent 清单 Menu 可打开并 Escape 关闭；child Footer 显示正常清单 Label、不是 disabled Menu。父/子截图见本次工具输出。
- **状态：IMPLEMENTED / TESTS PASSED / REAL WINDOW CHECKED。** 没有宣称等尺寸逐像素完全一致；未修改 Date Panel、Quick Add、Slash、More 内容、Tag Picker、Editor Core 或窄屏行为。

## 后续提交（未完成）

2. **Commit 3 / DATE-001～003：** 同一 Draft Schedule Panel 的日期/时间段、Calendar、Time、Reminder、Repeat/End、Clear/Confirm；需要日期面板参考图最终锁视觉。
3. **Commit 4 / QA-001～002：** 四枚 priority flags、List/Tags/Attachment/Template、独立输入框设置；需要属性菜单参考图。
4. **Commit 5 / SLASH-TASK-001：** Task DocumentProfile 命令顺序/分组/图标，不把任务分支塞进 Editor Core；需要 Slash 参考图。

这份契约替代 `native-parity-contract.md` 中旧 Inspector Round 1 的 Header Reminder/文字空态要求；历史记录保留，不将旧结论继续当作当前目标。
