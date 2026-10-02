# 倒数纪念日：「声明」vs「实际」对照表

日期：2026-10-02
范围：倒数纪念日模块（`Domain/Countdown`、`Application/CountdownStore.swift`、
`Features/Countdown/*`）
基线：`fa54688`（含本日 D1–D4 修复）
前置：`docs/countdown-audit-2026-10-02.md`（交互面走查）

---

## 为什么要做这一轮

上一轮走查走的是**交互面**——页头菜单、悬停条、卡片菜单、各种 sheet、归档流程、
深色模式。那些都是「点一下会怎样」。

但一个功能有**两张清单**：

1. **交互面**：界面上有哪些能点的地方
2. **已声明的行为**：代码说「选了这个会发生什么」

上一轮只走了第 1 张。第 2 张被系统性漏掉了——而它恰恰是上一个项目教训里
点名的盲区：**「有文案的功能会被找到，没有文案的交互状态会被过滤掉」**，
同一句话换个方向也成立：**「界面上有的选项会被找到，选了之后的行为会被放过」。**

本轮按「**声明 → 消费方**」逐条查。

---

## 一句话结论

**11 条声明里，4 条是「存了但没有任何行为」的空壳，1 条部分实现。**
其中 3 条是用户能直接看见、能操作、而且会以为它生效的。

---

## 对照表

| # | 声明 | 在哪声明 | 档位 | 判据 |
| --- | --- | --- | --- | --- |
| 1 | 提醒（`reminderOffsets`） | 编辑器「提醒」行 | **没实现** | 无任何路径通向通知中心 |
| 2 | 显示（`smartListDisplay`） | 编辑器「显示」行 | **没实现** | `countdownStore` 全仓只有 2 处引用，无消费方 |
| 3 | 节日目录（`CountdownFestival`，19 条） | `CountdownEvent.swift:853` | **没实现** | 全仓只出现 1 次——定义本身 |
| 4 | 除夕规则（`.lunarEve`） | `CountdownEvent.swift:294` | **没实现** | 无构造路径，唯一制造者是 #3 |
| 5 | 调整卡片顺序（`sortOrder` + `move`） | `CountdownStore.swift:161` | **没实现** | `move` 无调用方；无拖拽 |
| 6 | 备注（`note`） | 卡片菜单 + 编辑器行 | **半实现** | 能写能读回，但界面上完全不可见 |
| 7 | 重复（`rule` 的 9 种） | 编辑器「重复」行 | 真实现 | 投影按规则解析下一次，有测试 |
| 8 | 显示单位（天/月/周） | 点卡片轮换 | 真实现 | 实测过，落盘 |
| 9 | 岁数（`showsAge`） | 生日编辑器开关 | 真实现 | 经 `ageText(asOf:)` 被卡片消费 |
| 10 | 置顶（`pinned`） | 悬停条 | 真实现 | 实测过 |
| 11 | 归档 / 恢复（`archivedAt`） | 卡片菜单 + 已归档 | 真实现 | 实测过 |

---

## 逐条详情

### 1. 提醒：存了，但从不排通知 —— 没实现

- **声明**：编辑器有「提醒」行，默认值就是 `当天, 提前 3 天`，
  点开是完整的选项列表（当天 / 提前 1 天 / 提前 3 天 / 提前 1 周 / 自定义）。
- **消费方**：`NativeReminderService` 的两个入口签名收的都是 **`[Task]`**：

  ```swift
  // Infrastructure/Notifications/NativeReminderService.swift:62
  func enable(for tasks: [Task])
  // Infrastructure/Notifications/NativeReminderService.swift:72
  func reconcile(_ tasks: [Task], force: Bool = false)
  ```

  唯一调用点喂的是任务：

  ```swift
  // App/AppEnvironment.swift:114
  if let self, !self.loadFailed { self.reminders.reconcile(self.taskWorkspace.allTasks) }
  ```

- **结论**：`UNUserNotificationCenter` 全仓只被 `NativeReminderService` 与
  `FocusNotifier` 引用，**没有任何一条路径从 `CountdownEvent` 通向通知中心**。
  `CountdownEvent.reminderOffsets` 被写入、被归一化、被落盘，仅此而已。
- **性质**：静态可证（无调用路径），未做真机验证——验证需要等到触发时刻
  （全天锚点是 9:00），且「没有通知弹出」本身难以与「权限没给」区分。
- **严重度**：**高**。这是默认就带值的选项，用户建完一条记录就以为设好了提醒。

### 2. 显示（智能清单）：存了，但零消费方 —— 没实现

- **声明**：编辑器「显示」行，五档：当天显示 / 提前 3 天 / 提前 7 天 / 一直显示 /
  不在智能清单中显示。
- **判据一（静态）**：`showsInSmartList`、`smartListDisplay`、
  `effectiveSmartListDisplay` 三个符号**只出现在 3 个文件**——
  `CountdownEvent.swift`（定义）、`CountdownStore.swift`（持久化）、
  `CountdownEditorView.swift`（编辑器 UI）。**没有任何读取方。**
- **判据二（静态，更直接）**：`countdownStore` 全仓只有 2 处引用——
  `AppEnvironment`（创建与落盘）和

  ```swift
  // Features/Shell/RootShellView.swift:45
  CountdownWorkspaceView(store: environment.countdownStore)
  ```

  即**倒计时页自己**。智能清单（`TaskListProjection`）读的是 `Task`，与倒计时无关。
- **判据三（真机实测）**：建一条记录，日期=**今天**，显示=`在智能清单中当天显示`，
  落盘确认 `"smartListDisplay": "sameDay"`；切到「今天」智能清单
  （页面标题 `AXStaticText value="今天"`），**该记录不在其中**。

  ```
  倒计时页：AXButton desc="审计临时3，还有 0 天"     ← 存在
  今天清单：grep "审计临时3" → 0 处匹配              ← 不存在
  ```

- **严重度**：**高**。同上——默认值就是「当天显示」，用户会以为它进了今天。

### 3. 节日目录：19 条建好了，没人走得到 —— 没实现

- **声明**：`CountdownEvent.swift:853` 定义 `CountdownFestival`，
  19 个节日（春节 / 元宵 / 龙抬头 / 端午 / 七夕 / 中元 / 中秋 / 重阳 / 腊八 /
  除夕 / 元旦 / 情人节 / 妇女节 / 植树节 / 劳动节 / 儿童节 / 教师节 / 国庆 / 圣诞），
  每条都带**正确的**农历或公历规则（`lunarYearly` / `lunarEve` / `solarYearly`）。
- **判据**：`grep -rn "CountdownFestival"` 全仓**只有 1 处命中——第 853 行的定义本身**。
  `all` 与 `name(for:)` 两个入口都没有调用方。
- **真机确认**：「节日」类型的新建面板与「倒数日」**结构完全相同**——
  空名称框 + 日期行 + 提醒 + 重复（每年）+ 类型 + 显示，**没有节日选择器**：

  ```
  AXTextField value=""                          ← 要手输「春节」
  AXButton desc="日期：选择日期"                  ← 要手选日期
  AXButton desc="重复：每年"
  AXButton desc="类型：节日"
  ```

- **严重度**：中。功能上用户仍能建节日（手输），但**一张建好的、规则正确的目录表
  完全闲置**；对照滴答清单，节日类型是有目录可选的。

### 4. 除夕（`.lunarEve`）：一个造不出来的规则 —— 没实现

- **声明**：`CountdownRule` 有 `.lunarEve` 分支（`:294`），注释写着
  「除夕的农历月/日是逐年变的（腊月廿九或三十）」。
- **判据**：`combinedRule`（`CountdownEditorView.swift:925`）**只能在 base 已经是
  `.lunarEve` 时保留它**（`case .lunarYearly, .lunarEve, .lunarOnce:` 走保留分支），
  而 base 来自 `draftBaseRule`（`:895`）或 `original?.rule`。
  `draftBaseRule` 只会产出 `solarYearly` / `lunarYearly` / `lunarOnce` / `once`——
  **永远造不出 `.lunarEve`**。`original?.rule` 只在记录已存在时非空，
  而唯一的制造者就是死掉的 #3。
- **最值得注意的地方**：**代码里有 5 处在为「除夕存在」做辩护**——
  `:41`、`:65`、`:882`、`:913`、`:922` 的注释都在解释「除夕这类规则没法从月/日重建，
  只能原样留着」。作者以为这条路径是通的。**注释描述了一个不存在的世界。**
- **严重度**：中。本身不误事（用户建不出除夕），但它是 #3 的下游，
  而且这 5 处注释会继续误导下一个读代码的人。

### 5. 调整卡片顺序：API 建好了，无入口 —— 没实现

- **声明**：

  ```swift
  // Application/CountdownStore.swift:160
  /// 在主列表内移动到 `index`（越界自动收敛），并按新顺序重排 sortOrder。
  func move(_ id: UUID, to index: Int)
  ```

  排序确实按 `sortOrder` 走（`:222`），`add` 也确实在追加（`:68`）。
- **判据**：`grep -rn "\.move("` 命中的全是别处的 `CGPath.move`；
  `Features/Countdown/` 下**没有** `onMove` / `onDrag` / `draggable` / `dropDestination`。
  上一轮走查已确认卡片菜单是 5 项（编辑 / 样式 / 备注 / 归档 / 删除），**没有排序项**。
- **结论**：`sortOrder` 只会被 `add` 写成「最大值 +1」，
  所以**顺序恒等于创建顺序**（置顶的排前面）。用户无法调整。
- **严重度**：低—中。不误事，但「按 sortOrder 排序」+「move 能重排」
  这套机制是白建的；对照滴答清单，卡片是可拖拽排序的。

### 6. 备注：能写能读回，但界面上看不见 —— 半实现

- **声明**：卡片菜单有「备注」，编辑器里也有一行备注（两处入口写同一个字段）。
- **实现的部分**：写入、落盘、重开读回都对（上一轮走查实测过：
  取消不写盘 / 保存写盘 / 中文输入正常 / 重开 `AXTextField value="测试备注"`）。
- **缺的部分**：**卡片不渲染备注，也没有任何指示器。**
  `CountdownCardView` 的渲染字段只有：图标、名称、岁数、大数字、距离文案
  （`CountdownWorkspaceView.swift:256-300`）；无障碍标签是
  `小美，1 岁，还有 348 天`（`:334`）——**都不含 `note`**。
- **后果**：**你无法从卡片上看出哪条记录有备注**，只能逐条打开备注面板去翻。
- **严重度**：中。数据不丢，但写进去的信息等于沉底了。
- **待定**：卡片该显示备注正文、还是只显示一个「有备注」的小图标——
  这需要参照图（见文末）。

### 7–11. 真实现的那几条（对照用）

留着这一段是为了说明**这不是「整个模块都是壳子」**——
同一个编辑器里，下面这些是真生效的，所以上面那几条才更容易被当成也是真的。

| 声明 | 证据 |
| --- | --- |
| 重复（9 种规则） | `projection(asOf:)` 按规则解析下一次落点；农历 / 每周 / 每年 / 间隔都有测试 |
| 显示单位 | 点卡片 → `onCycleUnit` → `store.cycleDisplayUnit` → `effectiveDisplayUnit.next`（天→月→周→天），实测过 |
| 岁数 | `CountdownEvent.swift:736` `guard kind == .birthday, showsAge else { return nil }`，卡片经 `ageText(asOf:)` 消费 |
| 置顶 | `store.togglePin` → 排序优先级，实测过 |
| 归档 / 恢复 | 写 `archivedAt` 时间戳（不是布尔），实测过 |

---

## 方法上的收获（下一轮能省时间）

### 1. 「数引用文件」这个启发式会误报，必须追派生访问器

我最初按「符号出现在几个文件里」粗筛，`showsAge` 只出现在 3 个文件
（域 / Store / 编辑器），卡片文件不在其中 → **判成死的**。

实际是活的：卡片读的不是 `showsAge`，而是派生的 `ageText(asOf:)`。

**修正后的判据**：不数符号，数**访问路径**。
一个属性若只被「定义 + 持久化 + 编辑器」引用，还要再看它有没有
**派生访问器**被别处消费。反之，派生访问器被消费了，底层属性就是活的。

### 2. 「读路径」和「构造路径」要分开查

`grep "\.lunarEve"` 在编辑器里命中 3 处，看起来是活的。
但那 3 处分别在：一个 `switch` 的**格式化分支**（`:612`）、
一个**保留已有值**的分支（`:932`）、以及注释里。

**能读 ≠ 能造。** 判一个枚举分支是否可达，要看**构造点**，
而不是看它出现在几个 `switch` 里。这个坑直接决定了 #4 的判定。

### 3. 注释可以描述一个不存在的世界

#4 里 5 处注释都在认真解释「除夕这类规则怎么保留」，
读起来像是一条走通的路径。**注释证明的是作者的意图，不是代码的行为。**
判行为只有两个来源：**调用图**（静态）和**实跑**（运行时）。

---

## 待你拍板

### A. 这 4 条空壳，是「补上」还是「拿掉」？

项目自己在 `Features/Tasks/TaskList/TaskBatchPanelView.swift:7` 写了原则：

> 提醒（reminderOffsets）动作层虽支持，但批量场景没有可信的授权 UI，
> **宁缺毋假不暴露**。

按这条原则，编辑器里那两个选项应该**先隐藏**，等行为接上再放出来。
但也可以反过来——它们确实是产品该有的功能，值得直接补：

| 选项 | 补上的工作量 | 说明 |
| --- | --- | --- |
| 提醒 | 中 | `NativeReminderService` 要能收 `CountdownEvent`；要定全天锚点时刻 |
| 显示 | 中 | 智能清单要能混排 `Task` 与 `CountdownEvent`，涉及 `TaskListProjection` |
| 节日目录 | 小 | 接一个选择器把 `CountdownFestival.all` 用起来（数据已经是对的） |
| 排序 | 小 | 加拖拽手势调 `store.move`（API 已经写好） |

### B. 卡片要不要显示备注？

需要参照图（滴答清单倒数纪念日页）。目前 `docs/screenshots/ticktick-reference/`
里 7 张参照图全是任务 / 日历 / 四象限 / 摘要 / 专注 / 习惯 / 菜单栏，
**没有倒数纪念日页**——这也是上一轮 Q1 / Q2 挂起的原因，同一个卡点。

---

## 数据与环境

- 真机测试用临时记录 `审计临时3`（日期=今天，显示=当天），**测完已删除**。
- 用户数据与测试前备份逐键比对，`语义一致: True`。
- 测试中途应用被外部终止（**无崩溃报告**，`DiagnosticReports` 里最近的
  WorkFollow 崩溃是 10-01 23:18，不是这次）。数据未受影响。
- 复核构建：`/tmp/wf-dd-verify2`，基线 `fa54688`。
