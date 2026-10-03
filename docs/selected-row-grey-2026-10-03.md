# 第二 / 第三栏的选中底色：强调蓝 → 中性灰（2026-10-03）

用户报：「笔记和任务 第二栏和第三栏 选中后的的颜色能不能改成和滴答一样的，
都是灰色的，现在蓝色太显眼了」。

三个追问的答复：**焦点环直接去掉**；**导航列文字跟滴答一样改深色**；
**灰的深浅照滴答 `#F2F2F2`**。

## 一、滴答怎么做的（本轮实测，只读）

滴答进程 `pid 1241`，窗口 `@0,33 1512x859`——和我们的窗口**同位同尺寸**，
所以两边的像素可以直接对表。用 `ax2 select` 选中导航「最近7天」与任务「囧」，
`-R 0,33,660,290` 取 2× 截图，逐行取众数色：

| | 底色众数 | 文字 | 描边 | 偏蓝像素 |
| --- | --- | --- | --- | --- |
| 导航列「最近7天」选中行 | `(241,241,241)` | 深墨（最深 5% 均值 `(0,0,0)`） | 无 | **0.0%** |
| 任务列「囧」选中行 | `(241,241,241)` | `(43,43,43)` | 无 | **0.0%** |
| 未选中行（对照） | `(255,255,255)` | `(25,25,25)` | — | 0.6% |

两条附带事实：

- **选中行没有任何描边。** 我之前给列表选中行叠的那圈蓝色焦点环（`focusRing`，
  accent 35%）在滴答里没有对应物。
- **导航列选中项的文字是深色，不是强调色。** 滴答的选中导航项和未选中项一样
  是墨色字，只靠底色区分；我们原来把选中项的文字和图标刷成了 `accent`。
- 底色水平范围：导航 `逻辑 72..263.5`（列 62..274，左右各内缩 ~10），
  任务列 `逻辑 292.5..625`（AX 行框 274..638，左右内缩 ~18 / ~13）。
  两边都是「内缩的圆角块」，不是通栏。

## 二、我们改前是什么（HEAD `6a18904` 的干净构建）

为了拿到真正的「改前」，在 `/tmp/wf-verify2`（detached `6a18904`，无本轮改动）
单独构建了一份，与改后**同一个窗口位置、同一份数据、选中同一条任务**
（`归纳高频问题`），两张截图同为 3024×1720 且选中行的 y 带**逐像素对齐**：

| | 底色众数 | 文字 | 焦点环 `(187,188,243)` | 偏蓝像素 |
| --- | --- | --- | --- | --- |
| 导航列「今天」选中行 | `(239,239,252)` | accent `(91,92,227)`，324px | 43px（圆角毛边） | 93.4% |
| 列表列「归纳高频问题」选中行 | `(239,239,252)` | `(37,37,39)` | **2756px** | 85.1% |

`(239,239,252)` 正是 `WFColors.selection = accent.opacity(0.10)` 落在白底上的值
——用户说的「蓝色太显眼」就是这一块，加上列表行那圈 `(187,188,243)` 的焦点环。

## 三、改法

新增一个语义明确的 token，然后换掉第二、三栏的选中底色：

```swift
// Colors.swift
static let selection     = accent.opacity(0.10)                 // 不动：浮层/菜单/日历格
static let listSelection = themed(rgb(0xF2F2F2), rgb(0x363A42)) // 新：列表选中行
// focusRing 已删除
```

| 文件 | 改动 |
| --- | --- |
| `DesignSystem/Colors.swift` | 删 `focusRing`；新增 `listSelection` |
| `Features/Tasks/TaskList/TaskListView.swift` | `TaskRowView` 去掉 `focused:` 参数与焦点环 overlay；底色 → `listSelection` |
| `Features/Notes/NotesWorkspaceView.swift` | 底色 → `listSelection` |
| `Features/Tasks/TaskTrashView.swift` | 底色 → `listSelection` |
| `Features/Sidebar/SidebarViews.swift`（3 处） | 底色 → `listSelection`；`foregroundStyle` 由 `accent` → `WFColors.text` |
| `Features/Tasks/TaskManagementViews.swift`（2 处） | 底色 → `listSelection` |
| `WorkFollowTests/TaskCompletedRowRenderTests.swift`、`TaskTreeGeometryContractTests.swift` | 去掉构造调用里的 `focused: false` |

### 三个耦合点

1. **`#F2F2F2` 与行分割线 `#F4F4F4` 只差 2 级**，靠「选中行不画分割线」
   才分得开——那条规则是上一轮 `6a18904` 加的，本轮没有回退它。
2. **焦点环去掉后 `listFocused` 还在、还在被赋值**，只是不再跨进 `TaskRowView`。
   没有连带删除，避免把键盘导航的状态机一起拆掉。
3. **深色主题未实测**（没有在深色下跑过界面），取 `menuSelected` 同族的 `0x363A42`。

### 刻意没动的三处

- 最左 62pt 图标栏的选中图标仍是 `WFColors.accent`——那是主题的强调色身份，
  和「列表选中行」不是一回事。
- 拖拽悬停时的 `dragTargeted` accent 描边——那是拖拽状态提示，不是选中。
- 浮层 / 右键菜单 / 命令面板 / 日历格 / 习惯打卡仍用 `selection`；
  检查器里「关联任务」那张卡片也用 `selection`（它是强调色卡片，不是列表行）。

## 四、验收

改后构建（工作树，非 HEAD 归档）启动后，同一个窗口、同一条任务：

| 项 | 改前 | 改后 | 滴答 |
| --- | --- | --- | --- |
| 导航列选中底色 | `(239,239,252)` | **`(242,242,242)`** | `(241,241,241)` |
| 导航列选中文字 | `(91,92,227)` 强调色 | **`(37,37,37)` 深墨** | 深墨 |
| 列表列选中底色 | `(239,239,252)` | **`(242,242,242)`** | `(241,241,241)` |
| 列表列焦点环 `(187,188,243)` | 2756px | **0px** | 无 |
| 两栏选中行「偏蓝像素」占比 | 93.4% / 85.1% | **0.0% / 0.0%** | 0.0% |
| 未选中行（白底 / `(39,39,39)` 字 / `(235,76,70)` 日期） | — | **与改前逐像素一致** | — |

最后一行是这次对照的**控制组**：两张截图里未选中的那一条任务行在改前改后
完全一致（底色 60015 个 `(255,255,255)`、文字 940 个 `(39,39,39)`、
日期 897 个 `(235,76,70)`，三项数目都相同），说明变化只落在选中行上，
不是整体渲染漂移。

`(242,242,242)` = `#F2F2F2`，与滴答的 `(241,241,241)` 差 1 级。

### 构建与测试

在独立工作树 `/tmp/wf-verify2`（detached `6a18904`）里放进**恰好待提交的那 8 个文件**
（`git status --porcelain` 只列出这 8 个），构建 **`BUILD SUCCEEDED` / 0 error**；
再跑项目自带的 `scripts/run-tests.sh`：

| | 本轮（`6a18904` + 改动） | 上一轮基线（裸 `HEAD`） |
| --- | --- | --- |
| 报告出的用例 | 648（643 passed / 5 failed） | 648（同样 5 failed） |
| 失败用例 | `ArrowlessTaskPopupContractTests`、`FocusRenderTests`、`NativeResourceLinkTests`、`SchedulePopoverContractTests` ×2 | **同 5 个** |
| 崩溃点 | `TaskActivityIntegrationTests.testActivityPanelClosesMoreAndUsesArrowlessChildWithEscape` | **同一点** |

**零测试增量**——5 个失败与那次崩溃都是既有的（`xcrun xctest` 是单进程，
一个用例抛 `NSException` 会带走整轮，所以 649 个 started 里只有 648 个有结果）。

证据：`screenshots/selected-row-grey-2026-10-03/`

| 文件 | 内容 |
| --- | --- |
| `reference-vs-ours.png` | 三栏对照：滴答参照 / 我们改前 / 我们改后 ×（导航行、列表行） |
| `before-after-rows.png` | 我们自己的改前改后，行级放大 + 实测色值 |
| `before-after-window.png` | 整窗对照 |
| `before-window.png` / `after-window.png` | 两张原始 2× 整窗截图（3024×1720，同位） |
| `ticktick-reference.png` | 滴答原始截图 |

## 五、两条记录在案的旁注

1. **截图前先确认「哪一份构建在跑」。** 上一轮我手边只有一份「改前」截图，
   是 `10-03 00:31` 的构建——它的导航行高是 32pt，现在是 35pt，两图对不齐。
   凡是拿旧截图当基准，先核一遍**行高/行距这类会变的几何量**，别只核颜色。
2. **`ax2 clickat` 不是有效子命令。** 正确写法是 `ax2 click <pid> <x> <y>`
   （源码里 `clickat` 落到 `default: exit(2)`，只打印 usage 到 stderr，
   容易被 `2>&1 | head` 吃掉）。我第一次点空了，截出来「列表没有选中行」，
   差点当成「改动没生效」。
