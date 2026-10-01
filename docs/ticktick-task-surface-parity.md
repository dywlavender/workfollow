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

## DATE Round 1：原子提交与主面板定向校正

- **原子保存：** Workspace `saveTiming` 直接透传 `reminderOffsets`。保存/清除不再借用 `bulkSelection/applyBulk`；schedule、reminder、repeat、offsets 同一事务写入，单次业务 undo 恢复全部字段。保留原 bulk selection、不产生 bulk feedback。
- **DATE-001～004：** 主入口仅今天/明天/下周/周末四枚快捷图标；Tonight Domain 保留。定时 offset 0 显示“准时”，全天仍“当天”；计数结束显示“重复 N 次后结束”。已配置的重复结束值使用 accent。主面板260pt、属性行30pt，图标列及 trailing chevron 同轴；重复关闭不创建结束行。
- **测试：** `TaskScheduleAtomicCommitTests`、`TaskSchedulePanelRenderTests`、既有 `SchedulePopoverContractTests` / `TaskDateDraftModelTests` 定向通过。NSWindow + NSHostingView 渲染 empty、20:30/准时、monthly22/count2 和全天场景，输出 `/tmp/workfollow-schedule-panel-renders`；子面板开关不改变主面板尺寸，丢弃 Draft 不写任务。
- **真实窗口：** 重编译并退出旧进程后验收四个快捷入口、快捷日期修改后 Escape 丢弃、确定后 Header 更新。另发现月历 gesture 日期格未响应真实点击，将日期格包装为 plain Button 并给出日期辅助功能名称；选择日期与关闭子面板使用同一个回调，不改变月份/农历/假日/重复推演算法。重新点击26日、确定后 Header 更新为9月26日09:00；验收任务日期已恢复。
- **验收边界：** 结构与保存合同通过，不宣称等尺寸逐像素完全一致。提醒/重复二级浮层保持原实现，未判为 TickTick parity verified。
- **TASK-SCHEDULE-GAP-WORKSPACE-UNDO-SHORTCUT：** 单次工作区业务 undo 已由测试验证，但真实窗口 ⌘Z / Edit Undo 未接工作区撤销，快捷键撤销不判通过；留待独立输入路由修复，不混入本轮。

## DATE Round 2：提醒 / 重复原位展开

- **结构：** 展开内容属于同一个日期面板；保留当前属性与之前的属性，隐藏其后属性和主 Clear/Confirm。提醒有自身取消/确定，重复预设直接选入日期草稿并收起；工作日/节假日二级页原位返回。宽度260pt固定，高度随内容自然变化，替代 Round 1 的“开子面板尺寸不变”合同。
- **提醒草稿：** `ScheduleReminderDraft` 独立保存当前多选；取消不写日期草稿，内层确定只写日期草稿，主确定才原子提交任务。全天预设09:00，定时预设沿用安排时间。修复自定义提前数量输入后未纳入确认结果的问题。
- **自动验收：** `ScheduleExpandedSectionTests` 覆盖截断行、双层确认、取消/重新打开、定时20:30预设、34pt选项行、单份 Footer；与原子提交、主面板渲染、Draft 和 Popover 合同测试一并通过。渲染图片输出 `/tmp/workfollow-schedule-expanded-renders`。
- **真实窗口：** 使用本笔 `/tmp/workfollow-native-derived-data/Build/Products/Debug/WorkFollow.app`，退出旧进程后启动。已检查提醒展开、选择后取消、重开无选择、内层确定后主行更新而任务仍无日期；重复展开及工作日返回通过。没有点击主确定，用户任务未被修改。
- **DATE-GAP-ESCAPE-REAL-WINDOW：** 原 SwiftUI exit command 被 NSPopover 的取消抢先处理，增加 AppKit 事件路由。NSWindow + 真实 NSPopover 键盘事件测试证明首个 Escape 收起、第二个关闭、任务不变；但电脑控制工具的 Escape 在最新 App 中仍关闭整个面板。尚不能确认是否输入工具激活窗口导致瞬态关闭，**此实机路径未验收通过，不标记 Round 2 全面通过**。
- **DATE-GAP-LUNAR-RECURRENCE / DATE-GAP-EBBINGHAUS：** 尚无对应完整 Domain 支持，记录差异，不增加不能工作的菜单项。
- **边界：** 不改月份、农历、假日、重复 occurrence 算法；不宣称逐像素一致。

## DATE 交互状态：属性值 / 展开 / Hover / 清除

- `SchedulePanelPresentationState` 只管理展开、悬浮和重复二级页；实际时间、提醒、重复仍属于 `TaskDateDraftModel`。不在 View 中维护假时间。
- `SchedulePropertyPresentation` 推导尾控件：有可清除值 + Hover 优先显示 ×；否则展开显示向下箭头、收起显示向右箭头。`SchedulePropertyRow` 共用此规则，展开与清除为独立 Button；时间保留精确到分钟的行内输入。
- 首次打开未设置时间的行，先设置日期草稿的默认时间再展开；已有时间原样保留。默认纯函数暂按最近半小时（15分取后一个半点），时钟跨午夜时保持选中的安排日。此为当前产品约定，尚非实测确认的 TickTick 舍入规则。
- 点击 × 仅清除对应草稿并收起展开；清除重复同时回到“永不结束”。提醒层的独立多选草稿与主面板原子确认链保持不变。
- `SchedulePanelInteractionTests` 覆盖默认舍入、已有11:43不被覆盖、open/hover/clear/discard链、五种属性尾控件规则、提醒/重复清除和动态行渲染。与 DATE Draft / Atomic / Expanded / Render / Popover 定向测试一并通过。
- 真实窗口确认：最新构建点击“时间”后显示默认09:30，时间列表同值勾选，原任务 Header 仍为“设置日期”；未点击主确定。后续 Mac 锁屏，**真实鼠标 Hover × 和点击 × 尚待验收**；不得以状态/渲染测试代替这项签收。前述 Escape Gap 不因本笔重构自动关闭。

## DATE 容器纠偏：固定外框 / 内部滚动

- 本契约替代 Round 2 的“展开后自然增高”策略。`SchedulePopoverContainer` 保留260pt宽、标准560pt高；打开时按屏幕可用高度确定外框，之后不随 expandedSection 改变。
- 日期 Segment、快捷日期和月历属于固定顶部；属性行、展开编辑器、对应 Footer 属于下方有界 ScrollView。展开内容不再参与系统 Popover 的尺寸计算，不使用硬编码纵向 offset，也不隐藏日历。
- `ScheduleContainerRenderTests` 使用 NSWindow + 真实 NSPopover，逐个切换 main/time/reminder/recurrence，断言窗口 X/Y/宽/高、日历 frame、滚动 viewport frame 不变。提醒内容滚到底部后确认 Footer 完整进入 viewport，日历与窗口仍不动；整个过程任务数据不变。
- `SchedulePopoverContractTests` 的旧自然增高断言改为固定尺寸；Draft、Atomic Commit、Expanded Section、Interaction 和主面板 Render 定向回归通过。
- 最新构建实机截图复核：时间、提醒、重复展开时 Segment / 月历位置保持不变；提醒内部滚到底部可看到取消/确定，取消后恢复属性区。外部点击丢弃测试草稿，原任务仍未设置日期。本轮没有关闭之前记录的真实 Hover / Escape 验收缺口。

## 后续提交（未完成）

弹框横向收敛先遵循 [Native 弹框架构审计与统一契约](native-popup-architecture-audit.md)；其中 POP-001～007 区分事实与风险，规定六类呈现策略及保留既有合同测试的迁移顺序。不得在后续 Task/Notes 重构中丢弃日期固定外框、Draft隔离、Focus锚点和编辑器焦点规则。

2. **DATE Round 2 剩余验收：** 复核真实键盘 Escape 与窗口激活的关系，再关闭上述实机 Gap。
3. **Commit 4 / QA-001～002：** 四枚 priority flags、List/Tags/Attachment/Template、独立输入框设置；需要属性菜单参考图。
4. **Commit 5 / SLASH-TASK-001：** Task DocumentProfile 命令顺序/分组/图标，不把任务分支塞进 Editor Core；需要 Slash 参考图。

这份契约替代 `native-parity-contract.md` 中旧 Inspector Round 1 的 Header Reminder/文字空态要求；历史记录保留，不将旧结论继续当作当前目标。
