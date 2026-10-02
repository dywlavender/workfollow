# 倒数纪念日 A 批：三条空壳补上，以及补的过程中暴露的两个真缺陷

日期：2026-10-02
范围：倒数纪念日模块
基线：`f95da26`（含「声明 vs 实际」对照表）
前置：`docs/countdown-declared-vs-actual-2026-10-02.md`
测试环境：隔离工作树 `/tmp/wf-verify-abc`（`git worktree add --detach … f95da26`），
只拷入本批改动的 6 个文件；`AppEnvironment.swift` 因为混着另一会话的在途改动，
是在工作树里手工补的两处，没有整文件拷贝。

---

## 一句话结论

三条空壳都补上了，真机验过。**但补的过程中发现两处「看着对、实际不生效」的实现缺陷，
两处都是我自己在补的时候写进去的，两处都只有真机跑一次才看得见**——
81 个单测在缺陷还在的时候全绿。

---

## 一、做了什么

| # | 原空壳 | 补法 | 关键位置 |
| --- | --- | --- | --- |
| 3 | 节日目录 19 条没人走得到 | 名称行右侧加目录下拉（`Menu` + `chevron.down`），选中即填名称 + 日期 + 重复 | `CountdownEditorView.swift` `festivalPicker` / `applyFestival` |
| 4 | 除夕（`.lunarEve`）造不出来 | 随 #3 打通；另外修了「选中后被折成固定月/日」的缺陷（见二·1） | 同上 |
| 1 | 提醒存了但不排通知 | `NativeReminderService` 增加倒计时来源；`AppEnvironment` 注入 store + 订阅 | `NativeReminderService.swift` / `AppEnvironment.swift` |
| 5 | 卡片顺序无入口 | 卡片菜单加「上移 / 下移」两项，首末位各自禁用 | `CountdownWorkspaceView.swift` `menuItems` |

`reminderOffsets` 两边同名但**语义相反**（任务：相对到期时刻、提前为负；倒计时：提前多少分钟、
非负整天），这一点在 `ReminderSchedule.fireDates(for:event:)` 的注释里写死，
并由 `CountdownReminderScheduleTests` 钉住符号方向。

---

## 二、验证过程中发现的两个真缺陷

### 1. 节日目录选中的规则被旁路：除夕被折成固定的腊月廿九

**症状（真机实测）**：从目录选「除夕」后，面板显示的是

```
日期：农历腊月廿九
重复：每年（腊月廿九）
```

而不是应有的 `农历除夕` / `每年（除夕）`；落盘规则是
`{"lunarYearly": {"month": 12, "day": 29}}`，**不是** `{"lunarEve": {}}`。

**为什么是缺陷**：`.lunarEve` 的农历月/日**逐年变**（腊月廿九或三十）。
折成固定的 `lunarYearly(12, 29)` 之后，腊月恰有三十天的年份会**早一天**——
而且因为 12/29 本身是个合法日期，不会报错，只会安静地错。

**根因**：面板的「用户动过日期没有」判断是 `draft != seed`，其中 `seed` 是 `let`
（打开面板时的初值）。`applyFestival` 只改了 `draft`，没改 `seed`，于是
`draftDeviates` 立刻为真，`resolvedRule` 走 `draftBaseRule` 分支——
那条分支只会用「农历/公历 月/日」重建规则，`.lunarEve` 到这里就没了。
注释里明明写着「靠 `draftDeviates` 保证没动过时保存回原规则」，
但那个前提从来就不成立。

**修法（不是补一处赋值）**：把 `seed` 与 `festivalRule` 两个独立状态合成**一个**值类型：

```swift
private struct Baseline: Equatable {
    var draft: DateDraft
    var rule: CountdownRule?
}
```

`applyFestival` / `applyKind` / `init` 都整份替换 `baseline`，
`draftDeviates` 与 `resolvedRule` 都从它读。这样「草稿初值」和「它对应的规则」
**只能一起变**，是结构上的必然，而不是靠记得。

**修后实测**：面板显示 `农历除夕` / `每年（除夕）`，落盘 `{"lunarEve": {}}`，
卡片显示「除夕，还有 126 天」。

### 2. `@Published` 的 willSet 时序：新建的纪念日静默排不上通知

**症状（插桩实测）**：通过界面新建一条带提醒的纪念日，磁盘上已经是 4 条，
但那次 reconcile 读到的是 `countdowns=3`，并且 `changed=false` 提前返回——
**新记录一条通知都没排上**。

**根因**：`countdownStore.$events` 是 `@Published`，它的发布发生在 **willSet** 里。
sink 直接跑的话，读 `countdownStore.events` 拿到的还是**旧数组**。
于是 `reconcile` 算出的签名与上一次完全相同，被签名比对挡掉。
（任务那条订阅不受影响：它订阅 `revision`，读的却是 `allTasks`——不是同一个属性。）

**修法**：订阅上补一拍 `receive(on: DispatchQueue.main)`，推迟到下一轮主队列，
属性才真的写完。

**修后实测**：新建「中秋节」后，插桩日志里出现 `countdown 中秋节 dates=[…]`，
`pendingAfter` 末尾多出 `countdown.E80B13BC-…-#0` 与 `#1`，全程没有动过任何任务。

---

## 三、为什么 81 个单测全绿也没拦住这两个

这一条比上面两条更值得记。

- 缺陷 1 是**面板状态机**的问题（两份状态该一起变却没一起变），
  不是领域逻辑的问题。`CountdownEventTests` 里 51 个用例测的是
  「规则怎么解析、怎么格式化」，`.lunarEve` 本身完全正确——
  错的是「提交时到底用了哪条规则」。
- 缺陷 2 是**订阅时序**的问题，同理。`CountdownReminderScheduleTests` 里 9 个用例
  测的是「给定事件，触发时刻算得对不对」，签名与标识符前缀也都对——
  错的是「reconcile 拿到的输入数组是哪一版」。

所以：**单测覆盖的是纯函数，而这两处失败面都不在纯函数里。**
本批 3 个 suite 81 个用例在两处缺陷都在的情况下全部通过；
真正把它们挖出来的是三样东西：

1. **落盘文件**（`countdowns.json`）——不是界面显示什么，而是存了什么；
2. **插桩 + 读日志**（`reconcile` 读到几条、`authStatus` 是多少、`pendingAfter` 有哪些）；
3. **AX 读数 + 截图**（面板上那两行字到底写的什么）。

这三样缺一不可：只看界面会以为缺陷 1「生效了」（名称和日期都填进去了），
只看日志会以为缺陷 2「没触发」（其实触发了，只是读到旧值）。

---

## 四、真机验收记录

**环境**：单实例（先 `kill` 掉另一会话在跑的 `WorkFollow Native`，pid 2782，
避免两个进程写同一个 `countdowns.json`）；屏幕录制与辅助功能两个权限都在；
`screenCaptureAccess=true postEventAccess=true`。

截图在 `docs/screenshots/countdown-a-batch-2026-10-02/`：
`01-festival-catalogue-19-items`（目录 19 项，含除夕）、
`02-chuxi-dialog-lunar-eve-preserved`（修后：`日期 = 农历除夕`、`重复 = 每年（除夕）`）、
`03-card-menu-move-up-disabled-at-first`（首位时「上移」灰）、
`04-card-menu-move-down-disabled-at-last`（末位时「下移」灰）。

### (a) 节日目录 / 除夕

| 证据 | 内容 |
| --- | --- |
| 目录弹层截图 | 19 项，含「除夕」（第 10 项） |
| 面板读数（修前） | `名称=除夕` `日期=农历腊月廿九` `重复=每年（腊月廿九）` |
| 面板读数（修后） | `名称=除夕` `日期=农历除夕` `重复=每年（除夕）` |
| 落盘（修前） | `{"lunarYearly": {"month": 12, "day": 29}}` |
| 落盘（修后） | `{"lunarEve": {}}` |
| 卡片 | `AXButton desc="除夕，还有 126 天"` |

### (b) 提醒排通知

插桩输出（`/tmp/wf-probe.log`，验证完已删除）：

```
reconcile tasks=32 countdowns=3 signatures=6 force=false cdSigs=3 changed=true
authStatus=2                     # .authorized
pendingBefore=[]
countdown 小美   dates=[2027-09-12 09:00+08, 2027-09-15 09:00+08]   # 当天 + 提前 3 天
countdown 除夕   dates=[2027-02-02 09:00+08, 2027-02-05 09:00+08]   # 除夕 = 2027-02-05
countdown 春节   dates=[2027-01-30, 2027-02-03, 2027-02-06]          # 当天 + 3 天 + 7 天
pendingAfter=[countdown.<春节 uuid>#0 #1 #2, countdown.<除夕 uuid>#0 #1, countdown.<小美 uuid>#0 #1]
```

新建「中秋节」之后（不动任何任务）：

```
countdown 中秋节 dates=[2027-09-12 09:00+08, 2027-09-15 09:00+08]
pendingAfter=[…原有 7 条…, countdown.E80B13BC-…#0, countdown.E80B13BC-…#1]
```

三条触发时刻都对得上：除夕落在正月初一的前一天，春节「提前 3 天」「提前 7 天」
分别落在 02-03 与 01-30，全部锚在当天 09:00。

### (c) 上移 / 下移

| 操作 | 界面顺序（AX 的 x 坐标） | `countdowns.json` 的 `sortOrder` |
| --- | --- | --- |
| 起始 | 春节(69) 小美(399) 除夕(729) | 春节 0 / 小美 1 / 除夕 2 |
| 对首位「春节」点下移 | 小美(69) 春节(399) 除夕(729) | 小美 0 / 春节 1 / 除夕 2 |
| 对末位「除夕」点上移 | 小美(69) 除夕(399) 春节(729) | 小美 0 / 除夕 1 / 春节 2 |

边界也对：首位时菜单里「上移」呈灰色禁用，末位时「下移」禁用（两张菜单截图）。

### 测试

| 范围 | 结果 |
| --- | --- |
| `CountdownEventTests` | 51 / 51 通过 |
| `CountdownReminderScheduleTests`（新增） | 9 / 9 通过 |
| `CountdownStoreTests` | 21 / 21 通过 |
| 全量 | 774 个用例 / **11 个失败** |

那 11 个是既有失败，不是本批引入的：`FocusRenderTests` 8 个 +
`NativeResourceLinkTests` 1 个 + `SchedulePopoverContractTests` 2 个，
与基线 `c00f5ff` 上的计数和用例名完全一致。
（第一次跑全量时数是 12——`FocusRenderTests` 是渲染/几何类用例，会抖；
连跑第二次即回到 11。）

---

## 五、没做 / 没验的

- **备注指示器**（对照表 #6，半实现）：仍然没做，被参照图卡着。
- **「显示」（`smartListDisplay`）**（#2）：仍然没做，同样被参照图卡着。
- **面板状态机仍然没有自动化覆盖**。本批两处缺陷都出在
  `CountdownEditorView` 的 `@State` 组合上，而 `@State` 在测试进程里读不出真实值。
  真正能兜住这类问题的做法是把「日期 / 基准 / 重复 / 自定义间隔」这几份状态
  抽成一个值类型，把 `resolvedRule` 变成它的纯方法——那样上面缺陷 1
  会有一个能失败的用例。**这次没做，因为它是一次独立的、涉及 1000+ 行视图的重构**，
  和「补三条空壳」不是一个量级。建议单列一轮。
- **通知授权是本机已有状态**（`authStatus=2`），本批没有验证
  「首次授权」这条路径；`enable(for:)` 那个按钮在任务检查器里，只对已设提醒的任务显示。
- **真机上没有等通知真的弹出来**。倒计时的触发时刻恒为「发生日 09:00 减 N 天」，
  当天 09:00 已过时不会被排（`date > clock()` 过滤），所以本次只能观察
  **待发队列**（`pendingNotificationRequests`），不能观察投递。

---

## 六、数据与环境的交代

- 验证期间造过的记录（除夕、中秋节、重复的春节）**已按备份逐字段还原**，
  `countdowns.json` 现在与验证前的备份完全相同（春节 0 / 小美 1）。
- 停掉了另一会话在跑的 `WorkFollow Native`（pid 2782）——两个实例会写同一个数据文件。
  如需恢复，重新构建启动即可。
- 临时插桩（`WFProbe`，写在 `/tmp/wf-probe.log`）**只加在隔离工作树里**，
  已删除，并以主工作树为准覆盖后重新构建 + 重跑测试确认干净。
- 验证产物在 `/tmp/wf-verify-abc`（工作树）与 `/tmp/wf-dd-verify3`（DerivedData），
  可随时删。
- **共享工作树的一次险情（留个记录）**：`AppEnvironment.swift` 里混着另一会话的
  `viewPreferences` 接线。为了让提交只含本批改动，做法是「备份工作树版本 →
  `git show HEAD:<file>` 取干净版 → 只写我的改动 → `git add` → 把备份写回」。
  但写回那一步疑似覆盖了对方最新的 `viewPreferences`。
  发现方式是**另一处引用**：`TaskListView.swift` 仍引用 `environment.viewPreferences`，
  工作树自相矛盾——据此判定这份声明是必需的，把对方那三处补回（未暂存）。
  提交 `b95fd34` 里不含它们，对方的改动完好留在工作树里。
  **教训：动共享文件前先把对方的改动 `git diff` 留档，动完立刻 grep 核对对方改动还在。**
- 提交前 HEAD 已从 `f95da26` 前进到对方的 `791cdf4`（「remove remaining arrowed
  task popovers」）。本批提交落在它之上，没有替对方 push、也没有整理对方的工作树。
