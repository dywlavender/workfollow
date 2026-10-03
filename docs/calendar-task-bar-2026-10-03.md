# 日历页任务条：字号 / 条高 / 配色对齐滴答（2026-10-03）

需求（用户原话）：

> 日期页面中的任务字体太大了，任务也太宽了，@Clipboard_Screenshot.png 参考滴答进行修改。
> 另外任务的颜色也要改成和滴答一样的好看。

参照图：`~/.workbuddy-ai/clipboard-images/clipboard-2026-10-03T13-40-29-892Z-b69c1862.png`
（3020×1718，2× 图，Display P3）。

---

## 一、参照图实测

### 1.1 几何（全部在 2× 原图上量的，除以 2 得 pt）

| 量 | 滴答 | 我们（改前） | 我们（改后） |
| --- | --- | --- | --- |
| 列间距 | 414px = 207pt | 414px = 207pt | 同 |
| 行高 | 310px = 155pt | 310px = 155pt | 同 |
| 日期号带 y | 1428..1447 | 1428..1447 | 同 |
| **条高** | **34px = 17pt** | 58px = 29pt | **34px = 17pt** |
| 条间距 | 4px = 2pt | 4px = 2pt | 同 |
| **条宽 / 内缩** | 406px = 203pt，左右各内缩 5px = 2.5pt | 402px = 201pt，内缩 3pt | 同（未动） |
| 圆角 | ≈5px = 2.5pt | 3pt | 3pt（差半个像素，没动） |
| **标题墨迹高** | 21px（`写影评` 3 字宽 67px） | 27px | **20px** |
| **时刻墨迹高** | 16px | — | — |
| **勾选框外框** | 21×21px = 10.5pt | 27px = 13.5pt | **20px = 10pt** |
| 框左内边距 | 11px = 5.5pt | 5pt（`WFSpace.dense`） | 同 |
| 框 → 标题 | 8px = 4pt | 2pt + 框的 3pt 命中区 = 5pt | 同 |

换算：标题 CJK 墨迹 21px = 10.5pt ≈ system 12pt 的字身（0.86 倍）；时刻数字墨迹
16px = 8pt ≈ system 11pt 的 cap 高（0.70 倍）。**12pt / 11pt** 正好是 `WFType`
里本来就为这两个位置准备的角色（`listMeta` / `caption`）。

> 「任务太宽」指的是**条的厚度**，不是横向宽度：改前我们 201pt、滴答 203pt，
> 横向我们反而窄 2pt；纵向 29pt vs 17pt，是 1.7 倍。

### 1.2 配色模型（这一节推翻了我最初的假设）

滴答的日历条不是「一种颜色 + 一个强调色」，而是**同一个清单色画在两个透明度上**，
两档对应的就是**完成 / 未完成**：

| 档 | 透明度 | 标题墨色 | 勾选框 |
| --- | --- | --- | --- |
| 已完成 | ≈**0.12** | 浅灰（墨迹和 ≈460，≈`#969BA1`） | **实心**灰底 + 白勾 |
| 未完成 | ≈**0.36** | 深墨（墨迹和 ≈180~194） | **空心**描边 |

三条独立证据：

1. **同色相两档的离白距离正好 1:3**（三通道一致）：
   蓝 `(233,242,251)`↔`(190,216,243)` = 0.34/0.33/0.33；橙 `(252,245,236)`↔`(247,225,199)`
   = 0.38/0.33/0.34；青 0.30/0.23/0.59（这一对不是同色相）；绿 `(242,247,238)`↔`(215,230,205)`
   = 0.33/0.32/0.34。
2. **全图 59 条交叉表**：实心勾选框的 56 条，标题墨迹全部落在 455..474；空心框的 3 条
   全部落在 180..194。**一一对应，没有例外。**
3. 网格线（242,242,242）与格底（255,255,255）在全部 5 行里逐像素相同 → 不是整片
   被压暗/合成出来的，两档是真实状态。

**结论：我们原来的 `taskBarFillAlpha 0.32` / `taskBarCompletedFillAlpha 0.12` 本来就是
同一套模型**（滴答 0.36/0.12），只是未完成档略淡一档。本轮**没有改透明度**。

### 1.3 我们条的颜色其实和滴答一样

截图都是 Display P3，不能直接拿数值比。用我们自己渲染的实心强调色校准：
源码 `#5B5CEB` = (91,92,235) → 截图实测 **(91,92,227)**（B 少 8，R/G 不变）。

拿这把尺子回算：我们的未完成条实测 (191,208,234) → sRGB ≈ (191,216,242)；
滴答的未完成蓝是 (190,216,243)。**几乎逐通道相同。**

所以「灰蓝」不是色值问题，见第四节。

---

## 二、改了什么

`macos-native/WorkFollow/Features/Planning/PlanningMetrics.swift`：

| 常量 | 改前 | 改后 |
| --- | --- | --- |
| `taskBarHeight` | 29 | **17** |
| `taskBarTitleFont` | `Font.system(size: 16)` | **`WFType.listMeta`（12）** |
| `taskBarClockFont` | `Font.system(size: 14)` | **`WFType.caption`（11）** |
| `taskBarCheckboxSize` | 13.5 | **10** |
| `taskBarFillAlpha` | 0.32 | 0.32（**没动**） |
| `taskBarCompletedFillAlpha` | 0.12 | 0.12（**没动**） |
| `taskBarRadius` | 3 | 3（实测滴答 ≈2.5，差半个像素） |

`slotStride` 由 `taskBarHeight + taskBarGap` 推出，所以格内小条、跨天色带分道、
格子容量计算一起跟着走——**一格从装 3 条变成装 6 条**，与滴答一致。

`macos-native/WorkFollow/Application/TaskListProjection.swift`：

`WFListPalette.colorIndex(for:explicit:)` 的**自动取色**不再落在 11/12/13 三个
无彩色槽位（暖灰 / 板岩 / 灰）上，落到就折回 `[0, 4, 8]`（红 / 绿 / 靛）。
`argb` 表本身没动——它仍是与 Flutter 共享的 14 色契约表，**显式选色**照旧能选到
那三个无彩色。

理由不是审美：日历的「已完成」档本来就是同一个清单色的淡版（α0.12），
**一条灰的清单条和一个灰掉的任务在屏幕上是同一件事**。参考图里 80 条条全部有彩，
没有一条灰的。

`macos-native/WorkFollowTests/PlanningViewLogicTests.swift`：更新被钉住的下标
（`个人` 12→4、`验收-Native-0925` 13→8），并新增
`testAutoColorNeverLandsOnAchromaticSlots`（400 个名字 + 8 个真实名字，断言自动取色
永不落到 11/12/13，且显式选色仍可选到它们）。

---

## 三、为什么配色只动了这么一点（重要）

改完之后日历仍然**以蓝为主**，这不是配色规则没生效，是**数据分布**：

```
日历可见任务（2026-09-26 … 2026-11-07）共 18 条
  收集箱              14 条   → 同一个蓝
  验收-Native-0925     3 条   → 改后由灰变靛（本轮可见变化）
  学习                 1 条   → 青
```

用户的 35 条任务里 20 条在「收集箱」。**同一个清单的任务永远是同一个颜色**——
这正是滴答的规则：参照图 5 日的三条（`功能评审会议` / `晨间日记` / `浇花`）也全是
同一个蓝，6 日的四条全是同一个橙。滴答那张图之所以五颜六色，是因为它的示例数据
分散在十来个清单里。

所以「要更花」只有两条路，都不在配色规则里：

1. 把任务分到不同清单（用户的数据习惯）；
2. 给清单设颜色——**目前 5 个清单的 `taskListMeta` 里一个 `colorARGB` 都没有**，
   也就是全走哈希。想要"选颜色"这个入口，得先做清单选色 UI。

---

## 四、验收

### 4.1 构建

`xcodebuild -scheme WorkFollow -configuration Debug -derivedDataPath /tmp/wf-cal-dd build`
→ `** BUILD SUCCEEDED **`，0 error。

### 4.2 测试

工作树里有并发会话的 77 个未提交改动（含 10 个改过的测试文件 + 一批新测试），
它的用例集和基线不可比（401 用例，在 `NativeResourceLinkTests` 崩）。
所以用**干净工作树对照**：`git worktree add --detach /tmp/wf-cal-head d80747a1`，
只放我这 3 个文件（`git status --porcelain` 恰好列出这 3 个），再跑同一套脚本。

| 跑的是哪棵树 | 通过 | 失败 | 崩在哪 |
| --- | --- | --- | --- |
| HEAD（干净基线） | 643 | 5 | `TaskActivityIntegrationTests.testActivityPanelClosesMoreAndUsesArrowlessChildWithEscape` |
| HEAD + 本轮的 `PlanningMetrics.swift` | 643 | 5 | 同上 |
| **HEAD + 本轮全部 3 个文件** | **644** | **5** | 同上 |

失败的 5 条是既有失败，两次完全一样：`ArrowlessTaskPopupContractTests`、
`FocusRenderTests`、`NativeResourceLinkTests`、`SchedulePopoverContractTests` ×2。
**+1 是新增的 `testAutoColorNeverLandsOnAchromaticSlots`，零回归。**

### 4.3 像素

改后实测（工作树构建，`/tmp/wf-cal-final.png`）：

- 条高 34px = 17pt，条间距 4px = 2pt，条宽 402px，列间距 414px ✓
- 条内标题墨迹高 **20px**（滴答 21px）✓
- 一格装 6 条（改前 3 条）✓
- 收集箱仍蓝 `(191,208,234)`／`(223,230,243)`；`验收-Native-0925` 由灰变**靛
  `(202,205,235)`**；`学习` 青 `(200,223,230)` ✓

对照图见 `docs/screenshots/calendar-task-bar-2026-10-03/`：
`bars-before-after.png`（滴答两档 / 我们改前 / 我们改后）、
`month-grid-before-after.png`（整月网格改前后）。

---

## 五、旁注

- **`taskBarBorderAlpha 0.34` 没动**：它只被周视图的胶囊用（`CalendarWeekPillButton`），
  月视图的条不描边。填充降到 0.12 后，0.34 的描边正好是填充的 3 倍——与滴答那两档
  的 1:3 同构，所以周视图的观感是自洽的。
- **第一行不是双倍高**：上一版笔记里记的「我们首行 620px = 310pt」是错的。重测：
  我们的横线在 166/476/786/1096/1406/1718，**每一行都是 310px = 155pt**，与滴答一致。
- **并发会话**：`AnchoredPropertyPanel.swift` 在本轮中途处于编译不过的状态
  （`register(window:contains:dismiss:)` 的 actor 隔离报错），是另一个会话在途的改动，
  没有动它；等它自己修好后工作树才编译通过。
- **未做**：给清单设颜色的入口（5 个清单目前全走哈希）；「收集箱」是否该有固定色。
