# 新建任务输入框：细节功能对照表（2026-09-28）

> 四个对照面：**Flutter 版**（`feature/flutter-personal-desktop`）、**原生列表条**（`experiment/macos-native` 的 `TaskListView.quickAddBar`）、**原生全局面板**（同分支 `GlobalQuickAddController`）、**滴答清单**（TickTick macOS 8.0.80）。
>
> 证据：三处源码逐文件阅读 + 本机 `TickTick.app/Contents/Resources/zh-Hans.lproj/Localizable.strings`（3457 条）逐条检索 + AppKit `StandardKeyBinding.dict` 实测。
>
> 本文是 `quick-add-three-way-comparison-2026-09-28.md` 的**细节续篇**：前篇讲布局骨架，本篇逐项过「每个按键、每个字段、每个开关」。

---

## 零、一句话结论

**原生版已经把 Flutter 的输入框完整迁移过来了，并且在此之上多做了三件滴答有、Flutter 没有的事**（Tab 加描述、换行批量添加、`#`/`@` 实时候选），外加一个 Flutter 完全没有的全局快速添加面板。

所以「把 Flutter 的输入框迁移过来」这个动作**不需要做**——它是当前状态的上位集合的反向操作。下表可逐项核对。

---

## 一、按键与焦点（逐按键）

| 按键 | Flutter 版 | 原生列表条 | 原生全局面板 | 滴答清单 |
| --- | --- | --- | --- | --- |
| `↩︎` 提交建任务 | ✅ `onSubmitted → submit()` | ✅ 拦截 `insertNewline:` | ✅ 同左 | ✅ `敲击 Enter 添加任务` |
| `⇧↩︎` 进描述行 | ❌ | ✅ 拦截 `insertNewlineIgnoringFieldEditor:` | ✅ 同左 | ✅ `Shift+↩︎ 可添加描述` |
| `Tab` 进描述行 | ❌ | ✅ 拦截 `insertTab:` | ✅ 同左 | ✅ `敲击 Tab 添加任务描述` |
| `Tab` 提交当前候选 | ❌ | ✅ 候选列表开着时 | ✅ 同左 | ✅（`#` 候选场景） |
| `↑` / `↓` 移动候选高亮 | ❌ | ✅ 循环，未开列表时**放行**给插入点 | ✅ 同左 | ✅ |
| `Esc` 第一下 | ✅ 失焦、保留草稿 | ✅ 分层：候选 → 描述行 → 草稿 | ✅ 分层：候选 → 描述行 → **关面板** | ✅ 退出编辑不销毁草稿 |
| `Esc` 第二下 | ✅ 清空 | ✅ 清空 | —（面板已关） | ✅ |
| 点击整条聚焦 | ✅ `TextFieldTapRegion` | ✅ `.onTapGesture` | —（面板即输入） | ✅ `点击空白区域，可以添加任务。` |
| 粘贴多行 | ❌（默认插入把 `\n` 变空格） | ✅ 拦截 `paste:` 保换行 | ✅ 同左 | ✅ `换行可添加多个任务` |
| 全局热键唤起 | ❌ 仅应用内 `⌘N` | — | ✅ `⌘⇧A`（Carbon 热键 + 非激活 NSPanel） | ✅ 默认 `⌘⇧A`，可自定义 |

**Flutter 侧的硬证据**：`quick_add.dart` 全文只出现一次 `LogicalKeyboardKey`，就是第 672 行的 `escape`；没有 `Tab`、没有方向键、没有任何 `description` 字样。

**原生侧的硬证据**：`QuickAddTokenFlowLayout.swift` 的 `Coordinator.control(_:textView:doCommandBy:)` 是一张显式映射表，六个 selector 各归一个回调，其余一律 `return false` 放行。AppKit 的标准键位表把 `⇧↩︎` 映射到 `insertNewlineIgnoringFieldEditor:`（`StandardKeyBinding.dict` 里的 `~\r`），不是 `insertNewline:`——漏接这一条 `⇧↩︎` 会静默失效。

---

## 二、提交行为（逐路径）

| 路径 | Flutter 版 | 原生列表条 | 原生全局面板 | 滴答清单 |
| --- | --- | --- | --- | --- |
| 单条提交 | ✅ | ✅ | ✅ | ✅ |
| 换行拆多条 | ❌ 整串当一个标题 | ✅ 按行拆，逐行独立解析 | ✅ 同左 | ✅ `批量添加任务` |
| 空行处理 | — | ✅ 丢弃，不建空任务 | ✅ 同左 | — |
| `CRLF` / `CR` 归一化 | — | ✅ 粘贴自其它应用可用 | ✅ 同左 | — |
| 只有 token 无标题的行 | — | ✅ 跳过该行，同批其余照常建 | ✅ 同左 | — |
| 一个都没建成时 | 保留草稿 | ✅ 保留草稿 | ✅ **不关面板**（原实现无条件关闭，本次改为保留，免得用户以为建好了） | — |
| 描述随任务落库 | ❌ 无描述 | ✅ 同事务写入正文 | ✅ 同左 | ✅ |
| 批量时是否带描述 | — | ❌ 不带（每行各自成任务，共享描述无意义） | ❌ 同左 | — |

---

## 三、支持字段（逐字段）

| 字段 | Flutter 版 | 原生列表条 | 原生全局面板 | 滴答清单 |
| --- | --- | --- | --- | --- |
| 标题 | ✅ | ✅ | ✅ | ✅ |
| 日期（含区间 `dueAt`/`dueEndAt`） | ✅ | ✅ | ✅ | ✅ |
| 时间（全天 / 具体时刻） | ✅ | ✅ | ✅ | ✅ |
| 提醒 | ✅ | ✅ | ✅ | ✅（含「更多提醒」） |
| 重复 | ✅ 日/周/月 | ✅ + `RecurrenceRule` | ✅ | ✅（自定义、农历、多历法） |
| 标签 | ✅ `#标签` | ✅ + `#` 实时候选 | ✅ 同左 | ✅ `输入"#"可快速选择标签` |
| 清单 | ✅ `@清单`（需已存在） | ✅ + `@` 实时候选 | ✅ 同左 | ✅ |
| 优先级 | ✅ `!` / `!!` / `!!!` | ✅ | ✅ | ✅ |
| **任务描述** | ❌ | ✅ Tab / ⇧↩︎ 进入 | ✅ 同左 | ✅ |
| 默认日期注入 | ✅ 非收集箱注入 | ✅ `scope == .today` 时 | ✅ 不注入（`defaultDueAt: nil`） | ✅ `默认日期` |
| 附件 / 子任务 / 时长 | ❌ | ❌ | ❌ | 部分（详情页） |
| 识别项「保留 / 移除」开关 | ❌ | ❌ | ❌ | ✅ `保留文本中的日期`、`移除任务标题中的标签` |

---

## 四、智能识别（词表已 1:1 对齐）

两侧 token 种类相同：`date / time / recurrence / tag / list / priority`。

| 写法 | 说明 |
| --- | --- |
| 今天/明天/后天/大后天、今晚/明早/明晚 | 相对日 |
| 本周X / 下周X / 下下周X（周/星期/礼拜） | 相对周 |
| `X月X日`、`X月X号`、`X/X` | 绝对日 |
| `N天后`、`N小时后`、`N分钟后`、`半小时后` | 相对时间 |
| `X点`、`X:XX`、`X点半` + 早上/上午/中午/下午/晚上 | 时刻，支持中文数字 |
| `明早9点`、`明天 下午3点` | 组合式，优先级高于单独日期/时间 |
| `每天`/`每日`、`每周X`、`每月X号` | 重复 |
| `#标签`、`@清单` | `@` 仅命中已有清单才识别 |
| `!!!` / `!!` / `!` | 高 / 中 / 低（需独立成词） |

共同规则：**带时间的识别同时生成提醒**；识别片段在输入框内**原地高亮**。

原生比 Flutter 多的两点：`@` 未命中清单时在 `parse` 阶段就置 `retainsInTitle`（Flutter 在 title 投影阶段才判断）；重复额外携带 `RecurrenceRule(weekday:)` / `(monthDay:)`。

---

## 五、视觉样式

| 项 | Flutter 版 | 原生版（两条一致） | 滴答清单 |
| --- | --- | --- | --- |
| 输入字号 | 13pt regular | 列表条 13pt / 全局面板 **14pt** | — |
| chip 形状 | Material `InputChip`（圆角矩形） | `Capsule`（全圆角） | 圆角胶囊 |
| chip 底色 | 同色 9% alpha | 同色 9%（列表条）/ 12%（面板） | 淡色底 |
| 日期 / 时间 / 重复 / 标签 / 清单 / 优先级配色 | `quickAddDate` / `Time` / `Recurrence` / `Tag` / `List` / `Priority` | `WFColors.accent` / `accentHover` / `secondaryText` / `success` / `warning` / `danger` | 按字段着色 |
| 展开态描边 | 强调色 45% | 中性 `WFColors.border` | — |
| 摘要行 | `→ 9月27日 09:00 · 每天 · #工作 · @高优先级` | 同格式 | — |
| 候选列表形态 | 无 | overlay（列表条）/ 内联撑高（面板） | 输入框下方浮层 |
| 候选行高 / 宽 | — | 28 / 220 | — |
| 批量提示 | 无 | 无（列表条）/ `换行将创建 N 个任务`（面板） | 占位文字自带提示 |

---

## 六、两处必须说明的实现取舍

### 1. 候选列表只服务「输入末尾」的片段

不做插入点跟踪。`NSTextField` 的插入点是 AppKit 里最容易失同步的状态，一旦漂移就会出现「候选锚在错误位置」这种难查的问题。代价：把光标移回句子中间编辑 `#标签` 时不弹候选，需重新输入该片段。

### 2. 回车永远提交任务，`Tab` 才提交候选

若让回车提交候选，输入 `买牛奶 #工作` 后按回车会陷入死循环：候选已精确命中 → 提交候选 → 文本没变 → 候选仍在 → 永远建不出任务。

配套规则：片段**精确等于**某个候选名时，候选列表自行收起——没有可收敛的空间，此时把 `Tab` 与回车都还给用户。

### 3. 粘贴必须自己接管（本次实测发现）

单行 `NSTextField` 的默认插入路径会把换行**替换成空格**。实测：

| 路径 | 结果 |
| --- | --- |
| `field.stringValue = "alpha\nbeta"` | `alpha\nbeta`（保留） |
| `editor.string = "gamma\ndelta"` | `gamma\ndelta`（保留） |
| `editor.insertText("red\ngreen")` | `red green`（**换行变空格**） |

所以「换行可添加多个任务」如果走默认粘贴路径是**永远失效**的。现在改为拦截 `paste:`，读剪贴板原文与选区合并后写回绑定（走保留换行的赋值路径）。

---

## 七、缺口总表

### 已闭合（本次）

| 缺口 | 状态 |
| --- | --- |
| Tab / ⇧↩︎ 进入任务描述 | ✅ 列表条 + 全局面板 |
| 换行批量添加多个任务 | ✅ 列表条 + 全局面板 |
| `#` / `@` 实时候选下拉 | ✅ 列表条 + 全局面板 |
| 全局面板接入上述三项 | ✅ |
| 死代码 `QuickAddSchedulePopover.swift` | ✅ 已删（全项目无调用点） |

### 仍存（未做）

| 缺口 | 依据 |
| --- | --- |
| 识别文本的「保留 / 移除」开关 | `保留文本中的日期`、`移除任务标题中的标签` |
| 输入框设置页（智能识别开关、默认日期、默认提醒、默认清单） | `输入框设置`、`显示快速添加条`、`快速添加任务设置` |
| 点击正文里已识别的文本即取消识别 | `已识别到文本中的日期，点击即可取消识别。` |
| 全局面板的 token chip 不可单独移除（列表条可） | — |
| 剪贴板导入：首行标题、其余行描述 | `将剪切板中的文本一键添加到指定清单，剪切板中第一行是任务标题，其他行是任务描述。` |
| 候选列表只在行尾生效 | 见取舍 1 |

---

## 八、验收结果

- **真实 XCTest：453 个用例，0 失败**（`./scripts/run-tests.sh`）。
  其中本次相关：`QuickAddCompositionTests` 26 个、`GlobalQuickAddTests` 9 个。
- 覆盖到：拆行与 `CRLF` 归一化、末尾片段识别的正反例、候选过滤与上限、精确命中判定、补全后能被解析器识别、候选/描述状态机的按键分层、**粘贴保换行**、**六个按键 selector 的路由**、描述与批量落库。
- **未在真机窗口人工确认**：候选列表的实际视觉位置、真实按键事件在活窗口里的端到端路径、描述行与候选列表的焦点交接。这三项需要人工点一遍。

---

## 附：证据文件清单

- Flutter：`desktop/lib/widgets/quick_add.dart`（1197 行）、`desktop/lib/services/smart_date_parser.dart`、`desktop/lib/features/tasks/application/task_workspace_ui_state.dart`
- 原生：`Features/Tasks/TaskList/{TaskListView.swift, QuickAddComposition.swift, QuickAddCandidateList.swift, QuickAddTokenFlowLayout.swift, QuickAddParser.swift}`、`Features/QuickAdd/GlobalQuickAddController.swift`、`Application/TaskActions.swift`
- 滴答清单：`/Applications/TickTick.app/Contents/Resources/zh-Hans.lproj/Localizable.strings`（v8.0.80，3457 条）
- AppKit：`/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict`（`~\r` → `insertNewlineIgnoringFieldEditor:`）
- 验收脚本：`macos-native/scripts/run-tests.sh`
