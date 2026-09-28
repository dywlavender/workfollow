# 新建任务输入框三方对比：Flutter 版 / `experiment/macos-native` / 滴答清单

> 日期：2026-09-28
> 对比对象：`feature/flutter-personal-desktop`（Flutter 桌面版）、`experiment/macos-native`（SwiftUI 原生版）、滴答清单 TickTick macOS 8.0.80
> 证据来源：三处源码逐文件阅读 + 本机 `TickTick.app` 中文语言包（`zh-Hans.lproj/Localizable.strings`，3457 条）逐条检索 + 项目既有 parity 文档

---

## 一、仓库与分支结构

四个本地目录实际是**同一个仓库 `dywlavender/workfollow` 的多工作树**（`workfollow/` 是主工作树，其余为 `git worktree`，所以 `git branch` 里都带 `+` 标记）：

| 目录 | 检出分支 | 内容 |
| --- | --- | --- |
| `workfollow/` | `main` | 主仓库：`backend/`、`frontend/`（Web 端）、`collaboration/`、`deploy/`、`design-preview/` |
| `workfollow-flutter-personal/` | `feature/flutter-personal-desktop` | Flutter 桌面版，代码在 `desktop/lib/` |
| `workfollow-macos-native/` | `experiment/macos-native` | SwiftUI 原生版，代码在 `macos-native/WorkFollow/` |
| `workfollow-mcp-agent/` | `feature/mcp-agent-access` | MCP/Agent 接入 |

远程：`git@github.com:dywlavender/workfollow.git`。`experiment/macos-native` 的分支提交历史里已有一批 TickTick 对齐提交（`feat(native): ticktick parity — …`、`fix(native): restore quick-add bar focus and click-anywhere behavior`、`feat(native): restyle quick-add date entry as the task row date badge`）。

### 模块划分

**Flutter 桌面版**（`desktop/lib/`）
- `app.dart` 应用壳 + 原生菜单栏通道（`workfollow/menu`）
- `screens/` 页面：`today_screen`、`calendar_screen`、`matrix_screen`、`notes_screen`、`trash_screen`
- `widgets/` 组件：`quick_add.dart`、`task_add_surface.dart`、`task_row.dart`、`task_inspector.dart`、`sidebar.dart`…
- `features/tasks/{application,domain,presentation}` 任务领域层
- `state/workspace_controller.dart`（158 KB 单体控制器）
- `theme/` 设计令牌：`workfollow_theme.dart`（84 KB）、`workfollow_color_tokens.dart`、`workfollow_surface_tokens.dart`
- `services/smart_date_parser.dart` 智能识别解析器
- `models/task.dart`

**原生版**（`macos-native/WorkFollow/`）
- `App/`：`WorkFollowApp`、`AppEnvironment`、`AppCommands`、`AppNavigation`
- `Features/<功能>/`：`Tasks/{TaskList,TaskInspector,Templates}`、`QuickAdd`、`Editor`、`Planning`、`Focus`、`Habits`、`Notes`、`Summary`、`Filters`、`Settings`、`Shell`、`Feedback`、`Sidebar`
- `Application/`：`TaskWorkspaceModel`（32 KB）、各 Store 与 Projection
- `Domain/`：`Task`、`Note`、`Habit`、`Focus`、`Filter`、`Summary`、`Templates`、`Document`
- `Infrastructure/`：`Persistence`、`Files`、`Notifications`
- `DesignSystem/`：`Colors`、`Metrics`、`Spacing`、`Typography`
- `WorkFollowTests/`：143 个 Swift 文件中的单元测试

### 新建任务输入框的关键代码路径

| 角色 | Flutter 版 | 原生版 |
| --- | --- | --- |
| 列表内联快速添加条 | `widgets/quick_add.dart` → `QuickAddField(listStyle: true)`（1197 行） | `Features/Tasks/TaskList/TaskListView.swift:192` `quickAddBar(in:)` |
| 智能识别解析器 | `services/smart_date_parser.dart` → `SmartDateParser`（633 行） | `Features/Tasks/TaskList/QuickAddParser.swift`（402 行） |
| 输入框本体 / 高亮 | `_SmartTextEditingController`（Flutter TextField） | `QuickAddTokenFlowLayout.swift` 内 `QuickAddTextField`（`NSViewRepresentable` 包 `NSTextField`）+ `QuickAddTokenFlowLayout`（换行流式布局） |
| 属性面板 | `_QuickAddPropertiesPanel`（popover 宽 245） | `QuickAddPropertiesPopover.swift`（宽 270） |
| 日程/日期面板 | 复用 `showTaskSchedulePanel`（`task_schedule_panel.dart`） | 复用 `TaskDatePopoverV2`（`initialPage: .main/.reminder/.recurrence`） |
| 日历/四象限新建卡 | `widgets/task_add_surface.dart` → `TaskAddSurface`（371 行） | `Features/Planning/TaskQuickComposer.swift`（291 行） |
| 全局快速添加 | 无独立面板（仅菜单栏 ⌘N 请求聚焦 `quickAddFocusPending`） | `Features/QuickAdd/GlobalQuickAddController.swift`（235 行，⌘⇧A 非激活 `NSPanel` 480×88） |
| 菜单栏 | 原生 Runner 菜单栏 | `Features/QuickAdd/StatusItemController.swift`（55 行） |

> 已废弃/未接线：原生 `QuickAddSchedulePopover.swift` 全项目无调用点（列表快速添加已改用 `TaskDatePopoverV2`）；Flutter `QuickAddField(listStyle: false)` 的卡片变体在桌面端也无实例化（日历/四象限走 `TaskAddSurface`）。

---

## 二、布局结构

### 2.1 未聚焦（收起态）

| 维度 | Flutter 版 | 原生版 | 滴答清单 |
| --- | --- | --- | --- |
| 位置 | 页头下方、任务列表上方 | 同左 | 页头下方、任务列表上方 |
| 容器高度 | `minHeight: 42`（`TaskListMetrics.quickAddHeight`） | `minHeight: 36` | 约一行输入框高 |
| 圆角 | `10`（`quickAddRadius`） | `8`（`WFMetrics.corner`） | 圆角浅灰条 |
| 底色 | `tokens.canvas`（浅灰） | `WFColors.canvas` | 浅灰（源码注释记录：曾用 `controlBackgroundColor` 在浅色下不可见，已改 canvas） |
| 描边 | 收起时无 | 收起时无 | 收起时无 |
| 左图标 | `WorkFollowIcons.add`，`textTertiary` | `plus`（SF Symbol），`WFColors.secondaryText` | `+` |
| 占位文字 | `添加任务至“<当前清单>”` | `添加任务至“<当前清单>”`（`TaskListViewDefaults.quickAddTargetName`：无选中清单时回退收集箱） | `添加任务至"<清单>"`（`Add task to "%@"`）、`添加任务至"@"，回车即可创建` |
| 右侧 | `⌘N` 提示文字（`textTertiary`） | `⌘N` 提示文字（`WFType.caption`） | 快捷键提示（`输入↩︎添加`、`Use shortcut key %@ to open this input box`） |
| 水平内边距 | 条内 `14`（`relaxedGap`）；条外 `TaskListMetrics.horizontalPadding` | 条内 `12`（`WFSpace.md`）；条外 `20`（`WFSpace.xl`） | — |

### 2.2 聚焦/展开态

两者共用同一套「展开」判据：`聚焦 || 有文字 || 有识别 token || 面板打开`（原生 `quickAddExpanded`，Flutter `expanded`）。

展开后右侧出现**两个固定槽位**（两者一致，也与滴答一致）：

| 槽位 | Flutter 版 | 原生版 |
| --- | --- | --- |
| 日期入口 | `PropertyButton`（`quick-add-schedule`），日历图标 + 日期文案；收集箱上下文退化为**纯图标**（不注入默认「今天」） | 按钮，`calendar` 图标 10pt + 日期文案；`inbox` 目标下不显示日期文案 |
| 更多属性 | `AppIconButton`（`quick-add-properties`，`expandMore` 图标） | `ellipsis` 按钮 |

展开后**行内新增两行**（这是本工程自研的形态，滴答是把面板浮在输入框下方）：

1. **识别 chip 行**：Flutter 用 `Wrap` + Material `InputChip`（带 `close` 删除图标）；原生用自写 `QuickAddTokenFlowLayout`（`Layout` 协议，逐行折行）+ `Capsule` 背景。chips 缩进：Flutter `nestedContentIndent = 29`，原生 `24`。
2. **摘要行**：`→ 9月27日 09:00 · 每天 · #工作 · @个人 · 高优先级`，两者格式一致，同样缩进。

展开态描边差异明显：
- Flutter：`quickAddBorder(listStyle: true, expanded: true)` = **强调色 45% alpha**
- 原生：`RoundedRectangle.stroke(WFColors.border)` = **中性分隔线色**

### 2.3 日历/四象限的新建卡（第二套输入界面）

`TaskAddSurface` ↔ `TaskQuickComposer` 已逐项对齐，都是三行卡：

```
[日期胶囊 …………………… 优先级旗标]
───────────────────────────
[标题输入区（高 126 / 4 行槽位）]
───────────────────────────
[清单胶囊 …………………… 「更多」]
```

- 无「确定/取消」按钮，**回车即创建**
- 「更多」只含提醒、重复两项，且都跳到同一个日程面板的对应页（`.reminder` / `.recurrence`）
- 原生版注释明确说明：这张小卡与任务列表的快速输入行是两件事，早期把两者合成一个表单是错的

---

## 三、交互行为

| 行为 | Flutter 版 | 原生版 | 滴答清单 |
| --- | --- | --- | --- |
| 回车提交 | `onSubmitted → submit()` | `control(_:textView:doCommandBy:)` 捕获 `insertNewline` → `addTask` | 回车保存（`输入↩︎添加`） |
| Esc 两段式 | 第一次失焦（保留草稿）、第二次清空 | 完全一致（`quickAddEscapePrimed`） | 第一下退出编辑、不销毁草稿 |
| 点击整条聚焦 | 输入框自身 tap region + `TextFieldTapRegion` 包住右侧槽位 | `.onTapGesture { quickAddFocused = true }` | `点击空白区域，可以添加任务。` |
| 识别项删除 | 删除 chip → **掩码重解析**：把被删片段替换为等长空格后重新 parse，保证「明天 下午3点」删掉日期后时间 token 语义独立 | 删除 chip → `dismissedQuickAddTokens` 记录 token id，`QuickAddParser` 按 id + 区间重叠过滤；被删片段**退化为普通标题文字** | `已识别到文本中的日期，点击即可取消识别。`（直接点正文里的识别文本） |
| 属性面板锚定 | `showDesktopPopover`，`bottomEnd`，宽 245 | `.popover(arrowEdge: .bottom)`，宽 270 | 输入框下方浮出 |
| 日程面板 | `showTaskSchedulePanel(focusPolicy: preserveEditor)`，关闭后**回焦到输入框** | `TaskDatePopoverV2`，关闭后 `quickAddFocused = true` 回焦 | 日期/提醒/重复同面板 |
| 属性面板联动 | 点清单/标签行**不关闭父面板**，子 popover 锚定到该行（`preferredSide: right`） | 点清单/标签行弹 `.popover(arrowEdge: .trailing)` 子面板 | — |
| 聚焦请求 | `workspace_controller.quickAddFocusPending` + `consumeQuickAddFocus()` | `AppEnvironment.quickAddRequest` 计数触发 | 全局热键 |
| 全局热键 | **无**（仅应用内 ⌘N 聚焦） | ⌘⇧A，Carbon `RegisterEventHotKey` + `.nonactivatingPanel`，`UserDefaults` 持久化开关与键位 | 默认 ⌘⇧A（`快捷键 → 快速添加任务`），可在任意界面唤起 |
| Tab 加描述 | 未实现 | 未实现 | **支持**：`敲击 Enter 添加任务；敲击 Tab 添加任务描述` |
| 换行批量添加 | 未实现 | 未实现 | **支持**：`换行可添加多个任务`、`快速添加多个今日任务`、`批量添加任务` |
| 向下添加任务 | 未实现 | 未实现 | **支持**：`add_task_below` = `向下添加任务` |

> 结论：核心交互（回车提交、两段式 Esc、点击整条聚焦、回焦、chip 删除语义）Flutter 与原生已高度一致；原生**多出**全局快速添加；两者**共同缺失** Tab 加描述、换行批量、向下添加。

---

## 四、支持的功能字段

### 4.1 智能识别词表（`SmartDateParser` ↔ `QuickAddParser`）

两侧的 token 种类枚举完全相同：`date / time / recurrence / tag / list / priority`。

| 字段 | 识别写法（两者一致） |
| --- | --- |
| 日期 | 今天/今日/明天/明日/后天/大后天/今晚/今早/明早/明晨/明晚；本周X/下周X/下下周X（周/星期/礼拜）；`X月X日`、`X月X号`、`X/X` |
| 相对时间 | `N天后`、`N小时后`、`N分钟后`、`半小时后`（及「…之后/以后」变体） |
| 时间 | `X点`、`X时`、`X:XX`、`X点半`；配合 早上/上午/中午/下午/晚上；支持中文数字（一…十） |
| 组合式 | `明早9点`、`明天 下午3点` —— 优先级高于单独的日期/时间匹配 |
| 重复 | `每天`/`每日`、`每周X`、`每月X号`（原生额外携带 `RecurrenceRule(weekday:)` / `(monthDay:)`） |
| 标签 | `#标签` |
| 清单 | `@清单` —— **仅命中已有清单名才识别**；未知名保留在标题里（Flutter 在 title 投影阶段判断，原生在 `parse` 阶段就置 `retainsInTitle`） |
| 优先级 | `!!!` 高、`!!` 中、`!` 低（需独立成词） |

共同规则：**带时间的识别会同时生成提醒**（`reminderAt = dueAt`）；识别片段在输入框内**原地高亮**（Flutter `_SmartTextEditingController` 绘制 span，原生 `QuickAddTextField.syncTextAndStyling` 给 `NSAttributedString` 上色 + 14% 底色）。

### 4.2 字段承载能力对比

| 字段 | Flutter 版 | 原生版 | 滴答清单 |
| --- | --- | --- | --- |
| 标题 | ✅ | ✅ | ✅ |
| 日期（含区间） | ✅（日程面板可设 `dueAt`/`dueEndAt`） | ✅（`QuickAddScheduleDraft.dueEndAt`） | ✅ |
| 时间（全天/具体时刻） | ✅ | ✅ | ✅ |
| 提醒 | ✅ | ✅ | ✅（含「更多提醒」） |
| 重复 | ✅（日/周/月，`RecurrenceRule`） | ✅ | ✅（含自定义重复、农历重复） |
| 标签 | ✅ | ✅ | ✅（输入 `#` 可**快速选择**已有标签） |
| 清单 | ✅ | ✅ | ✅ |
| 优先级 | ✅ | ✅ | ✅ |
| 任务描述 | ❌（需 Tab） | ❌（需 Tab） | ✅（Tab 进入） |
| 附件 / 子任务 / 时长 | ❌ | ❌ | 部分（描述内联、附件在详情页） |
| 默认日期 / 默认提醒注入 | ✅（非收集箱上下文注入 `creationDate`；收集箱不注入） | ✅（`currentQuickAddSchedule(for: scope)`） | ✅（`task_default_tips`、`settings_default_reminder_day`） |

---

## 五、视觉样式

### 5.1 识别 token 配色（两侧 token 名与色值一一对应）

| token | Flutter 令牌 | 原生令牌 | 实际色 |
| --- | --- | --- | --- |
| 日期 | `quickAddDate` | `WFColors.accent` | 强调色（浅色 `#5B5CEB` 系） |
| 时间 | `quickAddTime` | `WFColors.accentHover` | 强调色 hover（`#4B4CD9`/`#98A1FF`） |
| 重复 | `quickAddRecurrence` | `WFColors.secondaryText` | 次要墨色 |
| 标签 | `quickAddTag` | `WFColors.success` | 绿（`#237A57`/`#5BCE91`） |
| 清单 | `quickAddList` | `WFColors.warning` | 橙（`#A15C08`/`#F2B84B`） |
| 优先级 | `quickAddPriority` | `WFColors.danger` | 红（`#FF4D4F`/`#FF6868`） |

chip 底色：两者都是**同色 9% alpha**（Flutter `withValues(alpha: .09)`，原生 `color.opacity(0.09)`）。

### 5.2 差异清单

| 项 | Flutter 版 | 原生版 |
| --- | --- | --- |
| chip 形状 | Material `InputChip`（圆角矩形） | `Capsule`（全圆角） |
| chip 内边距 | Material 默认 + `visualDensity: compact` | `horizontal 6 / vertical 3` |
| 删除图标 | `WorkFollowIcons.close`，`metadataIcon` 尺寸 | `xmark.circle.fill`，9pt |
| 输入字号 | `WorkFollowMacTypography.control`（13pt regular） | `NSFont.systemFont(ofSize: 13, weight: .regular)` |
| chip 字号 | 13pt medium | `WFType.control`（13pt medium） |
| 摘要字号/色 | `supporting`(12) medium，**`textTertiary`** | `WFType.metaMedium`(12 medium)，**`secondaryText`** |
| 展开描边 | 强调色 45% | 中性 `WFColors.border`（50% 分隔线色） |
| 日期徽标着色 | `_scheduleActive` 布尔 + 日期文案 | `quickAddBadgeColor` 按 `dateBadgeStyle` 归类：过期红 / 今天强调色 / 未来灰（**与任务行日期徽标同一套规则**） |
| 列表条左侧图标色 | `textTertiary`（刻意弱化） | `WFColors.secondaryText` |

### 5.3 滴答清单的视觉与开关（源码字符串证据）

- 占位与提示：`添加任务至 "%@"`、`添加任务至“%@”，回车即可创建`、`点击输入框即可添加`、`点击空白区域，可以添加任务。`
- 智能识别是**可开关的设置项**：`Smart Recognition` = 智能识别、`Smart Date Parsing` = 智能识别日期、`Date Recognition` = 日期识别、`Tag Recognition` = 标签识别、`输入框设置`、`显示快速添加条`
- 识别文本的**保留/移除**开关：`Keep text in tasks` = 保留文本中的日期；`Remove Tags in Task Name` = 移除任务文本中的标签 / `Keep tags in task name` = 保留任务标题中的标签
- 标签候选：`在添加任务时输入“#”可快速选择标签`
- 快捷键说明：`创建或编辑任务时，可输入这些快捷键快速添加细节，如设置日期、标签、清单等。`
- 默认值填充：`添加任务时，会自动填充的任务属性`
- 全局：`显示添加输入框`、`使用快捷键%@可打开此输入框`、`快速添加任务设置`、`使用此快捷键，你不再需要打开%@主窗口，即可一键添加任务。`

---

## 六、差距结论与建议

**已对齐**：列表内联快速添加条的布局骨架（`+` 图标 / 占位文案 / 右侧日期 + 更多双槽位 / 展开后 chip 行 + 摘要行）、智能识别词表（8 类字段写法 1:1 移植）、回车提交与两段式 Esc、chip 删除的语义、token 配色与 9% 底色、原地高亮、收集箱不注入默认日期、日历/四象限三行新建卡。

**原生版领先**：全局快速添加（⌘⇧A + 非激活 `NSPanel`，与滴答默认热键一致）、菜单栏 StatusItem、属性面板的优先级四色旗标行。

**两侧共同缺口（对齐滴答的下一步）**：

| 优先级 | 缺口 | 依据 |
| --- | --- | --- |
| P0 | Tab 进入任务描述 | `敲击 Enter 添加任务；敲击 Tab 添加任务描述` |
| P1 | 换行批量添加多个任务 | `换行可添加多个任务`、`批量添加任务` |
| P1 | `#` / `@` 输入时的**实时候选下拉**（当前只能「先输入再识别」） | `在添加任务时输入“#”可快速选择标签` |
| P2 | 识别文本的「保留/移除」开关 | `保留文本中的日期`、`移除任务文本中的标签` |
| P2 | 输入框设置页（智能识别开关、默认日期、默认提醒） | `输入框设置`、`显示快速添加条` |
| P2 | 点击正文中已识别文本即取消识别（当前只能删 chip） | `已识别到文本中的日期，点击即可取消识别。` |

**建议顺带清理**：原生 `QuickAddSchedulePopover.swift` 已无调用点；Flutter `QuickAddField(listStyle: false)` 的卡片分支在桌面端已无实例化。二者与现行实现并存会让后续对齐时误判「哪套是当前形态」。

---

## 附：证据文件清单

- Flutter：`desktop/lib/widgets/quick_add.dart`、`desktop/lib/widgets/task_add_surface.dart`、`desktop/lib/services/smart_date_parser.dart`、`desktop/lib/theme/workfollow_theme.dart`、`desktop/lib/theme/workfollow_color_tokens.dart`、`desktop/lib/screens/today_screen.dart:243`
- 原生：`Features/Tasks/TaskList/{TaskListView.swift, QuickAddParser.swift, QuickAddTokenFlowLayout.swift, QuickAddPropertiesPopover.swift, QuickAddSchedulePopover.swift}`、`Features/Planning/TaskQuickComposer.swift`、`Features/QuickAdd/{GlobalQuickAddController.swift, StatusItemController.swift}`、`DesignSystem/{Colors,Metrics,Spacing,Typography}.swift`
- 滴答清单：`/Applications/TickTick.app/Contents/Resources/zh-Hans.lproj/Localizable.strings`（v8.0.80，2026-07 构建，3457 条）
- 项目既有记录：`docs/ticktick-gap-analysis-2026-09-26.md`、`docs/ticktick-parity-execution-plan-2026-09-26.md`、`docs/macos-ticktick-inspired-plan-2026-09-13.md`
