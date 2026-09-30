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

## 后续提交（未完成）

1. **Commit 2 / TI-003～007：** 正文自然流、child section、`父名 >` breadcrumb、child Footer list。Comments/Activity 登记 `TASK-INSPECTOR-GAP-COMMENTS`，不做假按钮。
2. **Commit 3 / DATE-001～003：** 同一 Draft Schedule Panel 的日期/时间段、Calendar、Time、Reminder、Repeat/End、Clear/Confirm；需要日期面板参考图最终锁视觉。
3. **Commit 4 / QA-001～002：** 四枚 priority flags、List/Tags/Attachment/Template、独立输入框设置；需要属性菜单参考图。
4. **Commit 5 / SLASH-TASK-001：** Task DocumentProfile 命令顺序/分组/图标，不把任务分支塞进 Editor Core；需要 Slash 参考图。

这份契约替代 `native-parity-contract.md` 中旧 Inspector Round 1 的 Header Reminder/文字空态要求；历史记录保留，不将旧结论继续当作当前目标。
