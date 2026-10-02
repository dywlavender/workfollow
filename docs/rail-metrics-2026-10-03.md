# 图标栏对齐滴答：栏宽 52→62pt、图标 23→21pt、图标改全实心（2026-10-03）

> 本文是**修订版**，三轮叠加，不另开文档。
> 第一轮只改栏宽与图标（52→62、18→23）；
> 第二轮用户指出「我们的比滴答的大」，复量后发现**基准取错**，据此回调（23→21）；
> 第三轮用户指出「图标不一样，为什么选中后的颜色图案和滴答一样」，
> 复量滴答的选中态后发现**那块蓝就是图标本体**，于是把图标换成实心、
> 并删掉我们自己的选中底色块。

## 一句话

按滴答清单的实测值把图标栏对齐：栏宽 52→**62pt**、图标字号 18→**21pt**
（中间曾在 23 停留，见下）、**8 个图标全部换成实心（`.fill`）符号**、
**选中态改为图标自己变蓝、不再有独立底色块**，项间距 **48pt**。

## ⚠️ 读数基准：栏里第 1 个不是图标，是用户头像

这是第一轮最大的错误来源，也是用户第二轮直接指出来的：

```
AXWindow        @0,33 1512x859
AXButton        @14,74 34x34      ← 头像按钮（在滚动区**之外**，位于栏顶）
AXImage         @38,70 14x14      ← 皇冠角标
AXScrollArea    @0,123 62x601     ← 图标栏本体，从 y=123 才开始
  AXRow @0,123 62x48 → AXImage @15,131 32x32   ← 这才是第 1 个**图标**（任务）
  AXRow @0,171 62x48 → AXImage @15,179 32x32   ← 第 2 个
  ...
```

按截图墨迹量（2× 图，连通域）：

| 元素 | 墨迹 | 说明 |
| --- | --- | --- |
| **头像**（栏顶第 1 个） | **65×72px = 32.5×36pt** | 填充照片，天然比图标大 |
| **任务**（图标栏第 1 个 = 全栏第 2 个元素） | **42×42px = 21×21pt** | ← **这才是图标基准** |
| 日历 / 四宫格 / 专注 / 倒数 / 习惯 / 搜索 | 42~44px = 21~22pt | 与任务一致 |

**两条禁令**：
1. 别拿**头像**当图标基准（它 32.5×36pt，比图标大一截）；
2. 别拿 `AXImage 32x32` 当基准（那是滴答图标的**容器框**，不是画出来的大小）。

## 第一轮（栏宽 + 图标初调）

| | 改前 | 改后 | 依据 |
| --- | --- | --- | --- |
| `width` | 52 | **62** | AX `AXScrollArea 62x601` + 用户截图 61+1pt 分隔条 |
| `iconSize` | 18 | **23** | 18 × 21/16.5 ≈ 23（用我们自己的墨迹比例换算） |
| `hitSize` | 34 | **38** | 与 `selectedSize` 保持 4pt 差 |
| `selectedSize` | 30 | **34** | 图标 23 时留白 (34−23)/2 = 5.5pt |
| `selectedRadius` | 9 | **10** | 9 × 34/30 ≈ 10 |
| `itemGap` | 12 | **10** | 38 + 10 = **48**，对齐滴答行距 |

## 第二轮：用户指出「我们的比滴答的大」

用户原话：

> 「看起来果比滴答的大，不要和滴答第一个图标比，因为第一个是用户头像，要和第二个比」

**用同一把尺子复量（两边都是 2×，栏宽定标一致）**：

| 元素 | 滴答 | 我们（iconSize 23） | 差 |
| --- | --- | --- | --- |
| 任务（滴答第 2 / 我们的第 1） | 42×42px | 笔画 **51×46px** | **+21%** |
| 笔记 | — | 46×39px | — |
| 日历 | 42×42px | 45×42px | +7% |
| 四宫格 | 42×42px | 42×42px | 0 |
| 专注 | 44×44px | 46×46px | +5% |
| 习惯 | 42×44px | **52×52px** | **+24%** |
| 摘要 / 搜索 | 44×44px | 41×41px | −7% |
| 中位数 | **42** | **45.5** | **+8%** |
| **选中态整体** | **42px**（图标自身填色，无独立底色层） | **底色 68×68px** + 笔画 | **+62%** |

结论：**两样都偏大**——图标本体约 +8%，选中底色 +62%（后者是栏里最显眼的，
且正好落在第 1 个图标上）。用户选择「图标 + 选中底色一起缩」。

### 第二轮改了什么

| 常量 | 23 那版 | **现在** | 依据 |
| --- | --- | --- | --- |
| `iconSize` | 23 | **21** | 墨迹落到 37~47px、中位 **41~42**，对上滴答的 42 |
| `selectedSize` | 34 | **26** | 52px，比滴答的 42px 大 24%；再小就贴住图标了 |
| `selectedRadius` | 10 | **8** | 10 × 26/34 ≈ 8 |

> ⚠️ 上面这两行是**第二轮当时**的值。第三轮已把 `selectedSize` / `selectedRadius`
> 与选中底色块**整个删掉**（见下），`iconSize` 的 21 保留至今。
> 第一轮表里的 `selectedSize 30→34`、`selectedRadius 9→10` 同样是历史值。

**`hitSize` 故意不动（仍 38）**：它是**不可见的点按区**，
`38 + itemGap 10 = pitch 48`，与滴答行距一致。把它改小只会牺牲可点性，
还会连带改 pitch。

## 第三轮：图标改全实心，删掉选中底色块

用户原话：

> 「看起来很怪，图标不一样，为什么选择后的颜色图案是和滴答的一样呢，要不直接把图标也改成和滴答的一样」

### 先复量滴答的「选中态」到底是什么

上一轮把滴答的选中态记成「42px，即图标自身填色」，但**没验证过它背后有没有底色块**。
这次直接量：在滴答的 2× 截图里按颜色（`rgb(80,112,240)`）取包围盒——

```
选中蓝块 bbox: x 42..81 (w=40)  y 208..247 (h=40)  px=1380
→ 40×40px = 20pt，与旁边灰图标墨迹（42~44px）同量级
```

**结论：滴答的选中态就是图标本体变蓝，背后没有任何底色块。** 那个「蓝色圆角方块」
就是它的**任务图标**（实心圆角方块 + 挖空的白勾）。

这就解释了用户说的「怪」：我们抄了滴答**图标的形状**当选中底，
却配着自己的**描边**图标 —— 蓝块于是读起来像一张贴上去的色块。

### 改法：两头对齐到同一套语言

1. 8 个图标全部换实心（`.fill`）符号；
2. 删掉选中底色块（`selectedSize` / `selectedRadius` / `.railSelectedBackground`），
   选中态＝图标自己变 `WFColors.accent`。

| 目的地 | 改前（描边） | 改后（实心） | 隐喻 |
| --- | --- | --- | --- |
| 任务 | `checklist` | `checkmark.square.fill` | 不变（且与滴答同形） |
| 笔记 | `text.alignleft` | `text.document.fill` | 线条 → 文档页 |
| 日历 | `calendar` | `calendar.circle.fill` | 方形 → **圆形** |
| 四象限 | `square.grid.2x2` | `square.grid.2x2.fill` | 不变 |
| 倒数纪念日 | `hourglass` | `hourglass.bottomhalf.filled` | 不变（做成半实心） |
| 专注 | `timer` | `timer.circle.fill` | 不变（外面加实心圆） |
| 习惯 | `checkmark.seal` | `star.square.fill` | 印章 → 星（滴答的习惯就是这个形） |
| 摘要 | `square.and.pencil` | `list.bullet.clipboard.fill` | 笔纸 → 剪贴板 |

底部「搜索 / 设置」**保持描边**——滴答自己的搜索也是描边放大镜。

### 为什么必须换这 6 个：SF Symbols 的实心覆盖是部分的

拿系统自己的符号清单查的（`/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist`，
8526 个符号），不是凭记忆：

| 查过的 | 结果 |
| --- | --- |
| `calendar` 的实心 | 121 个含 calendar，**fill 只有 5 个，全是 `.circle.fill`** |
| `tablecells.fill` | 存在，但读起来是「表格/窗口」，**不是日历** |
| `hourglass` 的实心 | 8 个里只有 `hourglass.circle.fill`；另有 `hourglass.bottomhalf.filled` / `.tophalf.filled`（半实心） |
| `timer` 的实心 | 只有 `timer.circle.fill` |
| `text.alignleft` / `checklist` | **没有 fill 变体** |
| `checkmark.seal.fill` | **存在**（⚠️ 上一轮我记成「没有」，是错的，本轮已纠正） |
| `note.text` | **不存在**（上一轮的提案图里用了它，那一格其实是空的） |

所以**日历只能选圆形**，这是方案 A 唯一一处可见的妥协。备选方案（都已渲染对比、
用户选了 A）：
- **B**：只删底色块、符号一个不换 —— 改动最小，但整体仍是描边风格；
- **C**：自绘「21pt 实心圆角块 + 12.5pt 白色原图标」—— 隐喻一个不换、风格统一，
  但小尺寸下内部细节偏挤，且不是 SF 原生画法。

对照图：`09-icon-style-options.png`（滴答真实像素 | 现状 | A | B | C，每行第 1 格是选中态）。

### 代码与测试的连带改动

| 文件 | 改了什么 |
| --- | --- |
| `SidebarViews.swift` | 8 个符号名；删掉 `railButton` 里的 `RoundedRectangle` 底色块与 `.focusRenderAnchor(.railSelectedBackground)` |
| `Metrics.swift` | 删 `selectedSize` / `selectedRadius`；注释补第三轮 |
| `FocusRenderContract.swift` | 删 `case railSelectedBackground` |
| `FocusRenderTests.swift` | 删 `selectedBackground` 的 `XCTUnwrap` + 2 条断言 + 锚点集合里的那一项 |

⚠️ 上一轮文档说「这两轮改常量都不需要改测试」——**第三轮不成立**：
删掉底色块后 `frames[.railSelectedBackground]` 永远为 nil，
`XCTUnwrap` 会直接抛错，所以那个锚点与断言必须一起删。

⚠️ `MainWindowChromeContractTests` 用**源码文本**断言 `IconRailView` 里必须含
`.padding(.top, max(RailMetrics.topPadding, mainWindowRailInset))`、
`.padding(.bottom, RailMetrics.topPadding)`、`.frame(width: RailMetrics.width)`
三行字符串——改这个视图时这三行**一个字都不能动**。

## 连带效应（改常量前把所有使用点列了一遍）

| 使用点 | 语义 | 是否要动 |
| --- | --- | --- |
| `WFMetrics.railWidth` | 就是栏宽 | 自动跟随 |
| `WFMetrics.navigationBreakpoint` | `railWidth + nav(196) + splitMinimum(621) + 2` | **871 → 881**（导航栏在 881pt 才出现） |
| `MainWindowChromeGeometry.trafficLightFrames` | 按栏宽给红绿灯居中 | 自动跟随，**不用改** |
| `SidebarViews.swift` 的 7 处 | 栏宽 / 图标字号 / 命中框 / 选中底色 | 自动跟随（选中底色已删） |
| `FocusRenderTests.swift` | 断言 `selectedHitArea == hitSize`（从常量推导，自动跟随）；`selectedBackground == selectedSize` 已随底色块一起删掉 | 见第三轮 |

红绿灯：`gap = max(0, min(6, (railWidth − 6 − total) / 2))`，`total` ≈ 42。
改前 `min(6, (52−6−42)/2) = 2`；改后 `min(6, (62−6−42)/2) = 6`（上限生效）。
实测三个按钮 `x 7..36 / 47..76 / 87..116` 在 62pt 栏内居中，与滴答的
`x 13..42 / 49..78 / 85..114` 相比间距大 2pt、边距小 1.5pt——**没为这 2pt 再改公式**。

## 实测

**同一扇 1200×820 窗口**（AX 读数 + 截图连通域）：

栏宽 104px → **124px** = 62pt ✓；pitch 46 → **48pt** ✓；
左边距 `x=12` = `(62−38)/2` ✓ 仍居中；右侧导航栏整体右移 10pt ✓。

截图墨迹（2×，同一把尺子）：

| 图标 | 改前(52/18) | 23 那版 | **现在(21/26)** | 滴答 |
| --- | --- | --- | --- | --- |
| 任务选中底色 | 60×60 | 68×68 | **52×52** | 42（图标自身） |
| 任务笔画 | — | 51×46 | **46×42** | 42×42 |
| 笔记 | 36×31 | 46×39 | **42×36** | — |
| 日历 | 35×33 | 45×42 | **41×38** | 42×42 |
| 四宫格 | 33×33 | 42×42 | **38×38** | 42×42 |
| 倒数 | — | 27×42 | **24×38** | 42×45 |
| 专注 | — | 46×46 | **42×42** | 44×44 |
| 习惯 | — | 52×52 | **48×48** | 42×44 |
| 摘要 | — | 41×41 | **37×37** | 44×44 |
| 中位数 | — | 45.5 | **41** | 42 |

**任务笔画的高度 42px 与滴答的 42px 完全一致**；宽度仍 46 vs 42（+10%），
因为我们的 `checklist` 是「勾 + 两条横线」的宽字形，滴答是方块里的勾——**字形差异，换字号补不平**。

### 第三轮实测（换成实心之后，同一扇 1200×820 窗口）

用同一把尺子（2× 截图、连通域、裁 `x 4..122px`）：

| 位置 | 图标 | 墨迹 px | 墨迹 pt |
| --- | --- | --- | --- |
| 1 | 任务 `checkmark.square.fill`（选中，蓝） | **38×38** | 19×19 |
| 2 | 笔记 `text.document.fill` | 35×44 | 17.5×22 |
| 3 | 日历 `calendar.circle.fill` | **42×42** | 21×21 |
| 4 | 四象限 `square.grid.2x2.fill` | 38×38 | 19×19 |
| 5 | 倒数 `hourglass.bottomhalf.filled` | 24×38 | 12×19 |
| 6 | 专注 `timer.circle.fill` | **42×42** | 21×21 |
| 7 | 习惯 `star.square.fill` | 38×38 | 19×19 |
| 8 | 摘要 `list.bullet.clipboard.fill` | 35×50 | 17.5×25 |
| 底部 | 搜索 `magnifyingglass`（仍描边） | 40×41 | 20×20.5 |

pitch 实测 92~98px（= 48pt，逐行差异来自各字形上缘不同）✓。
AX 读 `AXButton desc="任务" @12,64 38x38` … `摘要 @12,400 38x38`，
命中框仍是 38、步长仍是 48，**无障碍标签一个没丢** ✓。

**与滴答的对比要说清楚**：能一对一比的是**任务**（同形同位）——
我们 38px、滴答 40px，**−5%，视觉上一致**。
其余的不能直接比：滴答那 6 个是它自己的字形（方块/花瓣/环/水滴），
我们换的实心 SF 符号里，`.square.fill` 系墨迹 38px、`.circle.fill` 系 42px，
滴答的同类是 40~44px —— 圆形的 42 已经对齐，方形的 38 偏小约 10%，
但**形状本来就不同，这 4px 不是同一件事**。

⚠️ 顺带纠正上一轮文档里的一句：原来写「同样是 21pt 墨迹，滴答实心、我们描边，
看起来会轻一些，故意没追」——**这一轮追了**，改成了实心。

截图：
- `12-icon-style-before-after.png`（改前描边+蓝底块 | 改后全实心，同尺度）
- `10-rail-solid-vs-ticktick.png`（我们新图标栏 | 滴答图标栏，同尺度并排）
- `11-rail-solid-2x.png`（改后 1200×820 窗口原图 2×）
- `09-icon-style-options.png`（四方案对照，选中态在第一格）
- `07-fix-compare-ticktick-before-after.png`（第二轮三联：滴答 | 改前 | 改后）
- `08-rail-after-21pt-26pt.png`（第二轮改后 2× 原图）
- `04-ticktick-2nd-icon-reference.png`（首图标 3× 放大：滴答头像+任务 vs 我们任务）
- `05-rail-side-by-side.png` / `06-ticktick-rail-fresh-2x.png`
- `01`~`03`：第一轮的对照

**剩下的字形差异**：滴答用它自带的商业图标字体，形状是它自己的；
我们用 SF Symbols，**能对齐的只有风格（实心）、尺寸与对齐方式，字形本身抄不了**。

## 测试

`macos-native/scripts/run-tests.sh` 全量（`WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1`、
`WORKFOLLOW_DERIVED_DATA=/tmp/wf-rail-test-dd`）：**889 个用例 / 14 处断言失败**。

**按失败「集合」归因，不是按数字**（这个仓库的套件本来就不全绿，且另一会话在并发改动）：

| 失败方法 | 断言数 | 归因 |
| --- | --- | --- |
| `DocumentContentTests.testEachInlineFormatAppliesAndTogglesOffForSelection` | 4 | 另一会话在途（`DocumentFormatCommand.swift` mtime 01:34） |
| `DocumentContentTests.testRemovingInlineFormatPreservesLinkAttachmentSelectionAndUndo` | 1 | 同上 |
| `FocusRenderTests.testFocusWorkspaceGeometryAcrossReferenceRenderMatrix` | 8 | **既有失败**：`FocusTimerRing.swift:115` 发的 `.focusTimerDigits` 不在该用例的期望集合里。与本轮无关 |
| `NativeResourceLinkTests.testTaskAndNoteURLsRoundTripAndBuiltAppDeclaresScheme` | 1 | **跑法产物**：它断言 `Bundle.main.infoDictionary["CFBundleURLTypes"]`，而 `xcrun xctest` 下 `Bundle.main` 是 xctest 自己的包。构建产物里该键是有的（`workfollow`），已核对 |

**本轮改动新增失败数 = 0**。两条佐证：
① 上面三个测试文件都不引用 `RailMetrics` / `railSelected*` / `IconRailView`（grep 为空）；
② `FocusRenderTests` 那 8 处失败是**同一个**原因（实际集合比期望多一个 `.focusTimerDigits`），
`.railSelectedBackground` 在**实际与期望两侧都已不存在**，我的删改是**净额为零**的。

`MainWindowChromeContractTests` 只把**栏宽**写死（62），其余断言从 `RailMetrics.*` 推导，
所以前两轮改常量不需要改测试。**第三轮必须改**——见上面「代码与测试的连带改动」。

## 一个要单独说的事：我改了另一个会话的未跟踪文件

`macos-native/WorkFollowTests/MainWindowChromeContractTests.swift` 在 `git status` 里是
**`??`（未跟踪）**，是**另一个会话刚新建、还没提交**的文件。它里面有一条
`XCTAssertEqual(RailMetrics.width, 52)`，我改栏宽必然撞它，所以把 52 改成了 62。

- **我没有把它提交**（`git add` 会把对方整个新文件署到我的提交里）。
- 因此**我的提交里不含这个文件的修改**；等对方提交时，这个 62 会跟着进去。
- ⚠️ 若对方在提交前整份重写了这个文件，我这一行会丢，那条用例会失败——看到就改回 62。

## 这一轮没做的

- **没动 `topPadding`（16pt）与竖向起点**。滴答的图标行从窗口顶下 90pt 开始（上面有头像），
  我们没有头像，起点本来就不同。
- **底部「搜索 / 设置」保持描边**，没换实心——滴答自己的搜索也是描边放大镜。
  但这样栏里就有两种风格并存（上面实心、下面描边），**是有意的**，不是漏改。
- **没把 `iconSize` 从 21 往上调**。换成实心后方形符号的墨迹从 41px 掉到 38px
  （滴答同类 40~44px，约 −10%），圆形的 42px 已经对齐。
  要不要为那 4px 调到 22（方形会回到 ~40px）**留给你定**，本轮没动。
- **没做自绘图标**。方案 C（实心块 + 挖空白图标，隐喻全不换）已渲染对比过，
  你选了 A。若哪天觉得「圆形日历」别扭，C 是现成的退路。
- **红绿灯间距与滴答差 2pt**（我们 6pt、滴答 3.5pt）。
