# 列表列宽：任务列与笔记列统一为 340pt（2026-10-02）

## 一句话

中栏列表列原来两处各写各的——任务列表 **440**、笔记列表 **330**（按窗口宽度硬编码）——
现在统一成**一个值 340**，取自滴答清单任务面板的实测默认宽度。

## 现状与目标（全部实测，不是估算）

| | 改前 | 改后 | 目标 |
| --- | --- | --- | --- |
| 任务列表列 | **440** | **340** | 340 |
| 笔记列表列 | **330** | **340** | 340 |
| 分隔条落点 x | 任务 690 / 笔记 580 | 两页都 **590** | 590 |

## 340 是怎么来的：两个独立来源互证

**① 读滴答自己的 AX 树**（`/Applications/TickTick.app` v8.0.80，pid 1241）：

```
AXScrollArea @274,137 338x751     ← 任务面板
  AXOutline  @273,136 340x753     ← 含左右边框，340
AXScrollArea @612,97  900x699     ← 任务详情区
```

同一棵树里各栏宽度加起来正好是窗口宽度，说明这条读法没漏栏：

```
62(图标栏) + 212(导航栏) + 338(任务列) + 900(详情) = 1512 = 滴答窗口宽
```

**② 用户给的截图**（`clipboard-2026-10-02T15-30-08-058Z-14b95fb6.png`，730×560）：
对若干行做横向颜色剖面，面板边框（`#F4F4F4`）落在 `x=34..713` → **680px**。
680 ÷ 340 = **2.0**，与 AX 读数吻合，同时证明了这是一张 2× 截图。

两个来源都是 340，所以 `listPreferred` 取 340。

## 改了什么（3 个文件）

**`macos-native/WorkFollow/DesignSystem/Metrics.swift`**

```swift
static let listMinimum:   CGFloat = 300   // 原 380
static let listPreferred: CGFloat = 340   // 原 440
static let listMaximum:   CGFloat = 470   // 不变
```

**`macos-native/WorkFollow/Features/Notes/NotesWorkspaceView.swift`**

```swift
// 改前：按窗口宽度硬编码，和任务列没有任何关系
let paneWidth = trash ? min(max(tasks.taskListPaneWidth, WFMetrics.listMinimum), maximum)
    : (geometry.size.width >= 1100 ? 330.0 : 300.0)

// 改后：与任务列共用同一个值
let paneWidth = min(max(tasks.taskListPaneWidth, WFMetrics.listMinimum), maximum)
```

同时把非垃圾桶分支那条静态 `Divider()` 换成与任务页**同一条可拖分隔条**。
原因：共用一个宽度之后，如果在笔记页改不了它，那"一致"就只有一半——
在笔记页够不着，得切回任务页才能调。

**`macos-native/WorkFollowTests/TaskWorkspaceModelTests.swift`**（见下面「测试」一节）

## 一个必须一起改的连带项：`listMinimum`

`RootShellView` / `NotesWorkspaceView` 都用

```swift
min(max(workspace.taskListPaneWidth, WFMetrics.listMinimum), maximum)
```

夹住宽度。**如果最小值还留在 380，340 会被顶回 380，改默认值等于白改。**
所以 `listMinimum` 必须跟着下调。取 **300** 不是新拍的数——笔记页在窄窗口下原本就用 300，
是个已经跑过的宽度。

连带效应（自动跟着算，没有单独改）：

| | 改前 | 改后 |
| --- | --- | --- |
| `splitMinimum` = min + inspectorMinimum(320) + divider(1) | 701 | **621** |
| `navigationBreakpoint` = rail(52) + nav(196) + splitMinimum + 2 | 951 | **871** |

即导航栏在 871pt 宽就会显示（原来 951pt）。默认窗口 1280pt，两条都远在门槛之上。

### 第三个连带效应：笔记页的双栏门槛没跟着走（**2026-10-03 已修**）

上面那张表漏了一条。`splitMinimum` 不只用在自己身上——它同时是**任务页/任务垃圾桶的双栏判据**，
而笔记页（非垃圾桶）用的是**另一个硬编码的数**：

| 页面 | 双栏判据 | 改前 | 改后 |
| --- | --- | --- | --- |
| 任务页（`RootShellView:127`） | `C ≥ splitMinimum` | 701 | **621** |
| 任务垃圾桶（`TaskTrashView:12`） | `C ≥ splitMinimum` | 701 | **621** |
| 笔记页 · 垃圾桶（`NotesWorkspaceView:34`） | `C ≥ splitMinimum` | 701 | **621** |
| 笔记页 · 非垃圾桶（同上，**硬编码**） | `C ≥ 760` | 760 | 760 |

（`C` = 内容区宽度 = 窗口宽 − 53（导航栏隐藏）或 − 250（导航栏显示）。
`TaskWorkspaceView` 与 `NotesWorkspaceView` 是 `RootShellView` 里同一个 `HStack` 的兄弟节点，
**读到的是同一个 `C`**，所以这两个常数可以直接比。）

于是 `C ∈ [621, 760)` 这一段里两个页面**不同步**。这一段的实际表现（按 `NotesWorkspaceView:42–46`
的两个条件读出来的，不是猜的）：

- **任务页**：`wide = true` → 列表(340) + 分隔条 + 检查器
- **笔记页**：`wide = false`、`detailOnly = false`（切页时被 `.onChange(of: navigation.destination)` 复位）、
  `visibleNote != nil` → 第一个条件 `wide || !detailOnly || visibleNote == nil` 成立 →
  **列表铺满整页、检查器不渲染**（第二个条件 `wide || (detailOnly && visibleNote != nil)` 为假）

也就是：同一扇窗口，从任务页切到笔记页，**详情栏整个消失、列表从 340 撑到满宽**。
这正是用户报的「忽宽忽窄」的最极端形态。

折算成窗口宽度，这一段有两个可达区间（`minimumWindow` 是 360，两个区间都够得着）：

| 导航栏 | `C` 与窗口宽的关系 | 分叉区间 |
| --- | --- | --- |
| 隐藏（窗口 < 871） | `C = 窗口 − 53` | **窗口 674–812pt** |
| 显示（窗口 ≥ 871） | `C = 窗口 − 250` | **窗口 871–1009pt** |

改前这段只有 59pt 宽（`C ∈ [701,760)`），改后 **139pt**——**是我这次下调 `splitMinimum` 顺带拉大的**。
（`760` 本身是 `89334846`（2026-09-28）留下的，不是这次引入的；我引入的是**分叉变宽**。）

**修法是一行**：把 `NotesWorkspaceView` 的 `(trash ? WFMetrics.splitMinimum : 760)`
换成 `WFMetrics.splitMinimum`——垃圾桶分支本来就是 `splitMinimum`，合并后四个页面同一条判据。
因为它改变的是「笔记页在 621–759 时是否折叠成单栏」，属于行为取舍，**2026-10-03 单独确认后**才动。

### 修完的实测（2026-10-03）

窗口固定为 **950×820**，则内容区 `C = 950 − 52(图标栏) − 1 − 196(导航栏) − 1 = 700`，
落在 `[621, 760)` 正中。改前/改后各起一个实例，用 ⌘1/⌘5 切页，读 AX 的列框：

| | 任务页 | 笔记页 |
| --- | --- | --- |
| **改前** | 列表 `@250,130 340x723` + 检查器 `@591,92 359x708` | **单块 `@260,127 680x710`** |
| **改后** | 列表 `@250,130 340x723` + 右栏 | 列表 `@260,127 320x710` + 编辑区 `@591,78 359x730` |

改前笔记页那一块 680pt 从 x=260 铺到 x=940，就是整个内容区（700 − 左右各 10 内边距），
**编辑区根本没有渲染**——和上面按 `NotesWorkspaceView:42–46` 两个条件推出来的一致。
改后列表停在 x=591，与任务页的分隔条位置**逐点相同**。

（顺带对上了一条旧读数：笔记列表的 `AXScrollArea` 左右各缩进 10pt，所以列宽 340 报出来是
`320`、起点从 250 变 260；任务列表没有这个内边距，报的就是 `340`。**两个数不一样不代表列宽不一样。**）

截图：`docs/screenshots/list-column-width-2026-10-02/03-notes-breakpoint-before-after.png`
（三联：改前笔记页 / 改后笔记页 / 改后任务页，同为 950pt 窗口；红色虚线是分隔条应在的
`x=591pt`。改前那张的列表横跨红线，另两张正好停在红线上。）

**两个操作上的坑，下次别再踩：**

1. **窗口尺寸会被 autosave 弹回去。** `WorkFollowApp.swift:105` 的
   `viewDidMoveToWindow` 会调 `setFrameUsingName`，切页重建视图时就把旧尺寸恢复了。
   `resize → 切页` 的顺序会白做，必须**先切页、再 resize、立刻读**。
2. **resize 会写进用户共用的 UserDefaults。** 三个构建的 bundle id 都是
   `com.workfollow.native.preview`，`NSWindow Frame main-AppWindow-1` 被我从
   `0 90 1512 859` 改成了 `0 129 950 820`，**测完已用 `defaults write` 还原**。
   下次做这类测量要么先存原值，要么别用用户正在用的那个 bundle id。

## 验收

### 验的是什么构建（这点要说清楚）

改前/改后**都从工作区构建**，两者之间**只差上面那 3 个文件**：

```
rsync -a <工作区>/macos-native /tmp/wf-before2/          # 工作区快照（含并发会话的在途改动）
git show HEAD:<3 个文件> > /tmp/wf-before2/<同路径>        # 只把这 3 个退回改动前
diff -rq <工作区>/macos-native /tmp/wf-before2/macos-native   # 确认差异恰好 3 个文件
```

- 改后 = `/tmp/wf-wt-dd`（工作区当前状态）
- 改前 = `/tmp/wf-before2-dd`（工作区 − 这 3 个文件）

⚠️ **为什么不能只拿 `git archive HEAD` 当基线**：这个仓库是**多会话共享工作树**，
工作区当时有 67 个脏文件。只按 HEAD 构建虽然能隔离出自己的改动，但**那不是工作区现在的样子**，
`RootShellView.swift`、`TaskWorkspaceModel.swift` 这些**列宽逻辑的归属文件**当时都在别人的
在途改动里。所以基线要取"工作区减去我的文件"，而不是"HEAD"。

（顺带确认过：对方对 `RootShellView.swift` 的改动只涉及 `ignoresSafeArea` 与右栏批量面板，
**没有碰列宽与拖拽那几行**；对 `TaskWorkspaceModel.swift` 的改动只涉及批量选中/分组/反馈事件，
没有碰 `taskListPaneWidth`。）

### 读数

| 页面 | 改前 | 改后 |
| --- | --- | --- |
| 任务列表列 | **440**（`AXScrollArea @250 440x…`） | **340**（`AXScrollArea @250 340x…`） |
| 笔记列表列 | **330**（`AXScrollArea @260 310x…`） | **340**（`AXScrollArea @260 320x…`） |

> ⚠️ **笔记列的 `AXScrollArea` 宽度不等于列宽。** 笔记列表左右各有 10pt 内边距，
> 所以 `列宽 = scrollArea 宽 + 20`。任务列没有这个内边距，`scrollArea 宽 == 列宽`。
> 我一开始按任务列的口径去读笔记列，算错了坐标，白白追了半小时"为什么分隔条点不中"。
> **更稳的判据是详情区的 x**：`列宽 = 详情区 x − 250 − 1`，两页通用。

### 截图

`docs/screenshots/list-column-width-2026-10-02/`，改前/改后同机同尺寸对照
（灰虚线 = 该状态自己的分隔条，红虚线 = 目标 590pt）：

- `01-tasks-column-before-after.png` — 任务列 440 → 340
- `02-notes-column-before-after.png` — 笔记列 330 → 340

### 跨页一致性（这是"一致"的核心，单独测过）

在任务页把分隔条从 340 拖到 375 后，切到笔记页读到列宽 375（`AXScrollArea @260 355x…`，
详情区 `@626`）。**一页拖动，另一页跟着变**，共用一个值是成立的。

## 测试

`scripts/run-tests.sh` 全量：

| | 用例 | 失败 |
| --- | --- | --- |
| 基线（工作区 − 我的 3 个文件） | 824 | 12 |
| 改动后（工作区） | 824 | 12 |

**失败集合逐条比对后完全相同 → 本次改动引入 0 个新失败。** 那 12 条是既有的
（`AnchoredPropertyPanelTests`、`ArrowlessTaskPopupContractTests`、`FocusRenderTests`、
`NativeResourceLinkTests`、`SchedulePopoverContractTests`）。

**但改动过程中确实撞出一条真失败，已修**：`TaskWorkspaceModelTests` 里写死

```swift
model.setTaskListPaneWidth(360)
XCTAssertEqual(model.taskListPaneWidth, WFMetrics.listMinimum)
```

360 是「窗口最小宽度」那个数，不是列表最小宽度——它当时只是「一个小于 listMinimum(380) 的值」。
`listMinimum` 降到 300 之后，360 落进了合法区间，这条断言就**悄悄变成了在测「没有夹取」**，
于是失败。已改成显式小于：`WFMetrics.listMinimum - 40`。

> 教训：断言里写死一个"刚好落在边界外"的字面值，会在边界移动时**静默改变语义**——
> 它不报错、只是不再测原来那件事。要用 `常量 ± 偏移` 表达意图。

**测试证明不了宽度对不对。** 既有测试引用的是 `WFMetrics.listPreferred / listMinimum / listMaximum`
**符号**（`TaskWorkspaceModelTests.swift:61-69`），所以它们只证明模型里的夹取逻辑自洽。
宽度的真正判据是上面的 AX 读数与截图。

### 2026-10-03 那一轮（笔记页双栏门槛）

同一套 `scripts/run-tests.sh`，改前/改后各跑一遍，两边都从**冻结快照**构建
（`WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1`，见下）：

| | 用例 | 失败 |
| --- | --- | --- |
| 改前（快照 + 回退那一行） | 879 | 9 |
| 改后（快照） | 879 | 9 |

失败**集合**逐条比对完全相同，仍是同 2 个用例的 9 条断言：
`FocusRenderTests.testFocusWorkspaceGeometryAcrossReferenceRenderMatrix`（8 条——渲染锚点
集合相同、**顺序不同**）与
`NativeResourceLinkTests.testTaskAndNoteURLsRoundTripAndBuiltAppDeclaresScheme`（1 条 `XCTUnwrap`）。
都是既有失败，与列宽无关 → **0 个新失败**。

（用例总数 824→879、失败 12→9，是**另一个会话**同期加/修用例的结果，不是这次带来的。）

**这个断点没有任何测试覆盖。** 测试里出现的 `760` 全是渲染用例的窗口尺寸
（`NativeResourceLinkTests`、`TaskFocusSubmenuTests` 等），与 `NotesWorkspaceView` 的断点无关。
所以这一轮的判据只能是 AX 读数 + 截图——测试在这件事上给不了证据。

> ⚠️ **沙箱里构建会假性失败**：Swift 编译宏时要在子沙箱里跑 `swift-plugin-server`，
> 当前进程树已被沙箱化时子沙箱套不上，报
> `sandbox-exec: sandbox_apply: Operation not permitted`，然后连带报出上千条
> `cannot find '$name' in scope` / `'self' is immutable` 的假错误。实测 4/4 次全败，
> 且**换沙箱外、重跑都不管用**。`scripts/run-tests.sh` 已内置开关
> `WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1`；直接调 `xcodebuild` 时用
> `OTHER_SWIFT_FLAGS='-disable-sandbox'`。判别方法一行：
> `grep -c "sandbox_apply: Operation not permitted" <build.log>`，>0 就是这个原因。

## 一个实测到、但**没修**的问题：拖分隔条的位移只有鼠标的一半

在验证"拖动"时量到的，**与本次改动无关**（任务页那段拖拽代码这次一行没动），
但既然量到了就记下来。改前改后都测过，比值一样：

| 鼠标实际位移 | 分隔条实际位移 | 比值 |
| --- | --- | --- |
| −60pt | −30pt | 0.50 |
| +60pt | +30pt | 0.50 |
| +100pt | +54pt | 0.54 |

在工作区构建上复测：+60 → +30（0.50）、+100 → +50（0.50）。

不是事件合并、也不是工具假象，逐条排除了：

1. **换节奏无效**：合成拖拽每步间隔 30 / 60 / 120ms，比值都是 **0.50**（各测两次）。
2. **插桩读到 app 自己的真值**：在 `RootShellView` 的 `onChanged` 里把
   `value.translation.width` 打到 stderr，24 步每一步都打出来了（没有丢事件），
   末值 **translation=30.0**，而鼠标走了 60pt。
3. **坐标空间没问题**：`probe move 590 500` 后带光标截图，光标落在**像素 (1180,1000)**
   = 逻辑 (590,500)，说明 `CGEvent` 坐标就是逻辑点、光标真的走满了 60pt。
4. **不是合成事件缺 delta**：给 `leftMouseDragged` 显式设置
   `mouseEventDeltaX/Y` 后重测，仍然是 0.50。

**成因未定**，所以这里只记现象、不写机制。要查的话，下一步该拿一个**独立于本 app 的
SwiftUI 拖拽目标**做对照（同一个 2× 屏、同一套合成事件）：如果那边也是 0.50，就是
环境/框架层面的事；如果那边是 1.0，才轮到怀疑本 app 的层级。

## 这一轮没做的

- **三处图标网格合并**（编辑器 44×44 / 样式弹窗 34×30 / 习惯页 28×28）与习惯页
  `symbolButton` 缺 `accessibilityLabel`——与列宽无关，仍是独立一轮。
- **笔记页分隔条的拖动没有单独回归**：它复用的是任务页那段**完全相同**的
  `DragGesture` 构造（同样的 `contentShape` + `minimumDistance: 1` + `dragOrigin` 状态），
  且已实测能改宽度（375 → 335）。但因为上面那条 0.5 的问题，**没有**验证它的
  位移比例是否也偏。
- **列宽不持久化**：`taskListPaneWidth` 是纯内存的 `@Published`，重启回到 340。
  这是既有行为，本次没改。
- ~~笔记页双栏门槛仍与任务页分叉~~ —— **2026-10-03 已修并实测**，见上面「第三个连带效应」。
