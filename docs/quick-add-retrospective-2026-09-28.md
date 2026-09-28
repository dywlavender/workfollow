# 快速添加输入框改造复盘（2026-09-28）

> 这份文档不是功能介绍，是**给下一个接手的人（人或 agent）看的交底**：
> 哪些结论有实测支撑、哪些只是推理、哪些还没验证、以及这次为什么做偏了。
>
> 配套文档：`quick-add-three-way-comparison-2026-09-28.md`（布局骨架对比）、
> `quick-add-detailed-feature-matrix-2026-09-28.md`（细节功能对照）、
> `quick-add-ticktick-alignment-2026-09-28.md`（改造说明与验收）。

---

## 一、先说结论

这次改造交付了三项能力（Tab/⇧↩︎ 进描述、换行批量添加、`#`/`@` 实时候选），
并把它们接入了全局快速添加面板。**但选题偏了**：

- 三项能力全部落在「**用户输入之后**」才发生；
- 而用户每次打开输入框，**第一秒碰到的是「点进去它长什么样」**，这一层完全没动。

这不是「漏做了一项」，是**需求来源的方法本身有偏差**——详见第四节。

---

## 二、事实清单：哪些有实测支撑，哪些没有

### 有实测支撑（可复现）

| 结论 | 证据 |
| --- | --- |
| 真实 XCTest 可跑，453 用例 0 失败 | `macos-native/scripts/run-tests.sh` |
| 单行 `NSTextField` 的默认插入路径把 `\n` 换成空格 | 探针实测：`insertText("red\ngreen")` → `"red green"` |
| 赋值路径保留换行 | 探针实测：`stringValue = "alpha\nbeta"`、`editor.string = "gamma\ndelta"` 均保留 |
| `⇧↩︎` 映射到 `insertNewlineIgnoringFieldEditor:` | `StandardKeyBinding.dict` 的 `~\r` |
| 六个按键 selector 的路由正确 | `QuickAddCompositionTests.testKeySelectorsRouteToTheMatchingCallback` |
| 粘贴保换行的接管逻辑 | `testMultiLinePasteIsTakenOverAndKeepsNewlines` |

### 只是推理，**没有**实测

- 候选列表在真实窗口里的**视觉位置**；
- 真实按键事件在活窗口里的**端到端路径**（测试是直接调 delegate，不是真按键）；
- 描述行与候选列表之间的**焦点交接**；
- 全局面板动态改高度后**实际观感**（会不会闪、会不会跳）。

### 已知未做

- 识别文本的「保留 / 移除」开关；
- 输入框设置页（默认日期、默认提醒、智能识别开关）；
- 点击正文里已识别的文本即取消识别；
- 剪贴板导入（首行标题、其余行描述）；
- 全局面板的 token chip 不可单独移除（列表条可）。

---

## 三、⚠️ 一个待判定的真实缺陷：点击输入框后不展开

**用户反馈**：点击输入框后，日期与「更多」两个槽位应该立即出现，而不是等输入了文字。

**查证结果**：**两边逻辑一样，且我没改坏它。**

Flutter 版 `desktop/lib/widgets/quick_add.dart:728-733`：

```dart
// The list add row keeps two slots right of the field, matching
// the TickTick reference — but only while selected: an unfocused
// row shows just "+ placeholder".
if (widget.listStyle && expanded) ...[
```
其中 `expanded = focused || customDate || text.text.isNotEmpty || parse.spans.isNotEmpty || _propertiesOpen || _scheduleOpen`

原生版 `TaskListView.quickAddExpanded`：

```swift
quickAddFocused || descriptionFocused || candidate.descriptionVisible || !descriptionDraft.isEmpty
    || !draft.isEmpty || quickAddScheduleOverride != nil
    || showQuickAddSchedule || showQuickAddProperties
```

`git show HEAD` 确认原代码同样以 `quickAddFocused` 开头——**这个语义本次未被改动**。

**所以只有两种可能，且读代码判定不了**：

| 现象 | 结论 |
| --- | --- |
| 点击后光标进入输入框，但槽位没出现 | 渲染 / 状态同步问题 |
| 点击后光标都没进入输入框 | **焦点没落到 `NSTextField`** |

**下一步（必须实测）**：跑起 app 点一下，看光标是否进入。一句话就能砍掉一半范围。
不要再用读代码的方式猜。

### 三之补：真凶找到了，并且已目视验收通过（18:26）

**结论先行**：缺陷不在「展开判据」，而在 `updateNSView` 里一个**反向收回焦点**的分支。
点击其实一直是生效的 —— 只是展开在同一轮 runloop 里被自己撤销了。

#### 怎么定位的

读代码到此为止，改用**插桩 + 从终端启动 app 抓 stderr**。日志（去掉该分支之前）：

```
[QADBG] updateNSView focused=false owns=false
[QADBG] field.mouseDown                                   ← 点击确实到了输入框
[QADBG] updateNSView focused=false owns=true              ← 输入框拿到了焦点
[QADBG] quickAddExpanded=true fieldFocused=true quickAddFocused=false   ← 展开了
[QADBG] didEndEditing                                     ← 焦点被收走
[QADBG] updateNSView focused=false owns=false
[QADBG] quickAddExpanded=false fieldFocused=false quickAddFocused=false ← 又折回去
```

一行日志就把范围从「不知道哪边是真的」压到了唯一一处。

#### 根因（两层）

1. **`@FocusState quickAddFocused` 是个死信号。** `NSViewRepresentable` 没有
   `.focused()` 绑定，SwiftUI 不为它维护焦点状态；delegate 里写回
   `wrappedValue = true` 不生效（日志里 `quickAddFocused=false` 贯穿始终）。
   所以「聚焦即展开」这条判据从来就没成立过，唯一还撑着展开的是 `!draft.isEmpty`
   —— 于是表现成「**打字才展开**」，正是用户看到的现象。
2. **`updateNSView` 里 `else if fieldOwnsFocus { window.makeFirstResponder(nil) }`
   在每一次点击后都命中。** 它假设 `focused` 可信（SwiftUI 说没聚焦就把 AppKit 的焦点收回），
   但既然 `focused` 永远是 false，这个分支就变成了「**用户一点进来就把焦点踢出去**」，
   随即触发 `didEndEditing` → `onFieldFocusChange(false)` → 折叠。

该分支**在 `HEAD` 里就存在**（不是本次引入）；本次只是把它的实现改成延后一个 runloop，
所以它照样命中。

#### 改了什么

| 文件 | 改动 |
| --- | --- |
| `QuickAddTokenFlowLayout.swift` | 新增 `QuickAddFocusReportingField`（`mouseDown` 先上报再交给 `super`）；造框逻辑抽成静态工厂 `QuickAddTextField.makeField(...)`，钩子在工厂里接好；**删掉 `else if fieldOwnsFocus` 里收回焦点的动作**，改为什么都不做并写明原因 |
| `TaskListView.swift` | 新增 `@State fieldFocused`；`quickAddExpanded` / `activeMarkerQuery` 改为「两个聚焦方向取或」；装饰描边加 `.allowsHitTesting(false)` |
| `GlobalQuickAddController.swift` | 同样接上反向聚焦 |

焦点释放交回 AppKit：点到别处自然 `didEndEditing`，反向状态由 `onFieldFocusChange` 回报。

#### 验收证据（全部实测）

`AXUIElementCopyAttributeValue` 读焦点归属 + `screencapture` 截图：

| 动作 | 焦点元素 | 输入框宽度 |
| --- | --- | --- |
| 初始（未点） | `AXScrollArea` | 328（折叠，只有 `⌘N`） |
| **点一下输入框** | **`AXTextField`** | **283（展开，露出 `📅 今天` 与 `⋯`）** |
| 输入 `x` | `AXTextField`，value=`"x"` | 283 —— 按键确实落进输入框了 |
| 点任务行 | `AXScrollArea` | 328（折叠） |
| 再点输入框 | `AXTextField`，value=`"x"` | 283（重新展开，草稿还在） |

截图对比：折叠态是 `+ 添加任务至"收集箱"` + `⌘N`；展开态是
`+ 添加任务至"收集箱"` + **`📅 今天`** + **`⋯`**。

#### 顺带查明的工具事实（不是缺陷）

- 应用的 owner 名是 **"WorkFollow Native"**（不是 "WorkFollow"），窗口 `layer=0`。
- 辅助功能 API 的命中测试在本应用里**不完全可靠**：点任务行时
  `AXUIElementCopyElementAtPosition` 返回 `AXGroup`，但实际点击能选中任务。
  所以命中测试只能作参考，判定必须靠「点完看状态变没变」。
- `AXUIElementSetAttributeValue(app, kAXFrontmostAttribute, true)` 能让应用前置，
  但**不会**让窗口成为 key window；配套 `kAXMainAttribute` + `kAXFocusedAttribute` 才稳。

#### 仍未解决（明确列出，别当成已完成）

- **`@FocusState quickAddFocused` 依然是死信号**，所以依赖它的路径仍然无效：
  - `handleQuickAddEscape()` 开头 `guard quickAddFocused` 恒为 false → **Esc 完全无反应**
    （两级 Esc：先收候选、再离开输入框，都不生效）。
  - `.onTapGesture { quickAddFocused = true }` 与 `environment.quickAddRequest`
    的程序化聚焦同样是空操作。
  - 正确做法是把「聚焦意图」换成可靠的 `@State`（控件上报的 `fieldFocused` 已经可靠），
    再让 `updateNSView` 按这个意图决定是否 `makeFirstResponder`。**本次没做。**
- 在已聚焦的输入框里按退格（keycode 51）没生效，未查清是测试工具还是应用的问题。

---

## 四、为什么选题偏了（本次最值得记的一条）

### 根因：需求来源是个筛子

本次需求清单是从滴答的 `Localizable.strings`（3457 条中文）里**检索**出来的。
检索这件事本身有过滤效应：

| 能力 | 滴答有没有对应文案 | 结果 |
| --- | --- | --- |
| Tab 加描述 | `敲击 Tab 添加任务描述` | ✅ 被找到 |
| 换行批量添加 | `换行可添加多个任务` | ✅ 被找到 |
| `#` 选标签 | `输入"#"可快速选择标签` | ✅ 被找到 |
| **点击即展开日期 / 更多** | **无任何文案** | ❌ **第一步就被过滤掉** |

**交互状态是没有文案的。** 用文案当需求来源，注定只能找到「有标签的功能」，
永远找不到「没标签的状态」——而后者往往是用户最先碰到的。

### 另外三条叠加原因

1. **对照的是源码文本，不是界面。** 界面状态在源码里表现为一个布尔或，
   读文本看不出它是「点击时」还是「输入时」变 true——那是**状态转移**，文本表达不了。
2. **按「能不能证明」挑任务。** 三项改造都能写单测（易证明），
   点击即展开只能靠看（难证明）。**把「可证明」当成了「重要」。**
3. **顺序反了。** 体验路径是「点进去 → 看到什么 → 输字 → 变了什么 → 回车」，
   我做的三件事全在「输字之后」，等于优化了第二三步。

### 还有一条更早的教训（同一根源）

上一轮复盘已经确认「**验证**要实测」，但没把这条推广到「**选题**也要实测」。
**同一个偏差只修了半截**——所以这次测试全绿，问题却依然存在。

---

## 五、下次接手时的正确顺序

1. **先列「体验路径 / 状态转移」**，不要先列功能清单。
   路径 = 点进去 → 看到什么 → 输字 → 变了什么 → 回车 → 发生什么。
2. **优先做「用户第一秒就碰到」的**，而不是「容易做 / 容易证明」的。
3. **验收看屏幕。** 界面类改动的最终判据是截图/录屏，不是测试报告。
   测试通过只说明「做的对不对」，不说明「该不该做」。
4. **需求来源至少两路**：参照物文案 + 用户实际卡点。
   只有文案一路，就必然漏掉所有无文案的交互状态。
5. **参照物给的是功能清单，不是行为规格。** 行为细节要么真机观察，
   要么自己取舍并**明确标注为「取舍」**，不能含糊成「已对齐」。

---

## 六、怎么在这个环境跑测试

```bash
cd macos-native
./scripts/run-tests.sh                                   # 全部
./scripts/run-tests.sh QuickAddCompositionTests           # 单个类
./scripts/run-tests.sh QuickAddCompositionTests GlobalQuickAddTests
```

`xcodebuild test` 在本机会停在 `The test runner hung before establishing connection`
（runner 编排的 IPC 问题，不是测试包的问题）。脚本绕过它，直接 `xcrun xctest`
加载构建产物里的 `.xctest` 包。原理与坑见用户级 skill `xcode-test-without-xcodebuild`。

**若构建在 "Build Preparation" 阶段秒退**，报：

```
Couldn't create workspace arena folder '.../DerivedData/WorkFollow-<hash>':
Unable to write to info file '.../DerivedData/WorkFollow-<hash>/info.plist'.
```

这不是代码问题，是当前环境不允许改 `~/Library` 下的 DerivedData。把构建产物指到可写目录：

```bash
WORKFOLLOW_DERIVED_DATA=/tmp/wf-dd ./scripts/run-tests.sh
```

（脚本已支持该环境变量；构建产物用完记得删，一次约 265M。）

---

## 七、第二轮：审计 → 按方案改造 → 实测（21:45 补记）

第三轮做的是审计（见 `quick-add-inconsistency-audit-2026-09-28.md`），
第四轮按审计 §六 的顺序把三条改完并实测。**这一轮的教训主要不在代码上，在「怎么确认」。**

### 7.1 改了什么

| 文件 | 改动 |
| --- | --- |
| `QuickAddTokenFlowLayout.swift` | `focused` 从 `FocusState<Bool>.Binding` 换成普通 `Binding<Bool>`；`updateNSView` 反向分支从「故意什么都不做」改成「延后一个 runloop、重读实时值后再交还焦点」；抽出 `shouldRelinquishFocus(intent:fieldOwnsFocus:)` 让判据可测 |
| `TaskListView.swift` | `quickAddFocused` 从 `@FocusState` 换成 `@State`；删掉并存的 `fieldFocused`（两个真值合一）；删掉视图层那层不可达的 `.onExitCommand` |
| `GlobalQuickAddController.swift` | 同样把 `inputFocused` 换成 `@State`、删掉 `fieldFocused`；面板落点补上「当前清单 / 当前标签」；识别 chip 从纯 `Text` 改成可点掉的 `Button` |

### 7.2 这轮最有价值的一条：**「死信号」不会自己暴露**

第一轮修「点击不展开」时，我是**加了一路新状态**（`fieldFocused`）把症状盖住的，
**没有**去问「为什么原来的 `quickAddFocused` 不生效」。于是：

- 症状消失了 ✅
- 但同一个根因还留在原地，继续毒害另外 15 个调用点 ❌

**症状消失不等于根因消失。** 当时如果能多问一句「这个 `@FocusState` 为什么读出来是 false」，
后面 15 个点一次就一起修掉了。

而且这 15 个点的症状**看起来互不相关**：Esc 没反应、关掉日期浮层焦点不回来、
列表上下键抢键、点空白处不展开……从症状出发根本归不到一起，
**只有从「这一类状态可靠不可靠」出发才能一次收齐。**

判定方法（值得记住）：`@FocusState` 声明处对照 `.focused($变量)` 是否存在。
`NSViewRepresentable` 上挂不了 `.focused()`，没有绑定就是死信号——写不生效、读永远 false。
**但 `@FocusState.Binding` 传给普通 `View` 是好的**（`TaskInspectorShell.titleFocused` 就是这样），
别误伤。

### 7.3 三条「别猜，去数」的实例

审计里留了三个「代码判不了」的问题，这轮全部用**插桩**定案，没有一个是靠读代码或推理结论的：

1. **Esc 是否被两个入口各消费一次？** → 让 app 自己写文件计数，
   一次按键读到 `field=1 view=0`。**不会**，而且视图层那层根本不可达（死代码，已删）。
   三种焦点状态都测了：输入框聚焦 → 字段层接走；描述行聚焦 → 描述框自己接走；
   都没聚焦 → 谁都不触发。
2. **`@FocusState` 到底是不是恒假？** → 上一轮插桩日志已经证实（`focused=false` 贯穿始终）。
3. **`sed -i ''` 为什么会把构建搞挂？** → 报的是 `invalid redeclaration of 'QuickAddCompositionTests'`，
   看起来像重名类。实际是 `sed` 在源码目录里留了 `.!3192!QuickAddCompositionTests.swift`，
   而工程用 `PBXFileSystemSynchronizedRootGroup`，**目录里所有文件都会被编译**。
   去 `ls -la` 看一眼就看见了——**报错文字里的类名把我引向了完全错误的方向**。

### 7.4 一条工具事实：macOS GUI 上抓不到 stderr

「插桩 + 从终端启动 app 抓 stderr」这条路在 macOS 上**有前提**：

- 用 `nohup ... & disown` 启动的 app，**命令一结束就跟着死**（窗口只存在了 4 秒）。
- 用 `launchctl submit -o/-e` 想同时拿到存活 + stderr，**在这台机器上静默失败**。
- 用 `open` 启动能存活，但 **stderr 拿不到**（不进统一日志）。

所以真正可靠的做法是：**让 app 自己把探针写到文件**（本轮就是写 `/tmp/wf-esc.log`）。
下一轮直接用这个姿势，别再在 stderr 上浪费时间。

### 7.5 并行会话的干扰，这轮又遇到一次

全量测试 472 条、1 条失败，失败的是 `DocumentContentTests.testLinkEditingPreservesTextAndOtherMarks`
（`("{2, 0}") is not equal to ("{0, 2}")`）。判定它**不是我造成的**，靠三件事而不是感觉：

1. 该测试文件 mtime `20:55`、它依赖的 `DocumentContentActions.swift` mtime `20:58`，
   **都早于我这一轮第一次编辑（21:13）**。
2. 该测试文件里 `QuickAdd` / `focus` 相关符号**一个都没有**（grep 结果为空）。
3. 单独跑 `DocumentContentTests` 仍然失败 → 与我的改动无耦合。

对比基线也变了（上一轮是 463 条 / 2 条失败在 `DocumentDecorationRenderTests`，
现在是 472 条 / 1 条失败在 `DocumentContentTests`）——**失败集合在变**，
正是另一会话正在改 `Features/Editor/*` 的特征。

### 7.6 本轮仍未解决（如实列出）

| 项 | 状态 | 为什么没解决 |
| --- | --- | --- |
| 全局面板打开时自动聚焦输入框 | **仅代码层** | 面板靠 Carbon `RegisterEventHotKey` 触发，合成键盘事件（含 `.cghidEventTap`）**不能触发 Carbon 热键**；且该功能默认关闭，没有常规入口。要坐实需人工按一次 ⌘⇧A |
| 面板落点对齐（清单/标签） | **单测验证，非目视** | 同上，面板弹不出来，只能测 `GlobalQuickAddComposer` 这条纯逻辑接缝 |
| 退格键（keycode 51）在输入框里不生效 | 未查清 | 分不清是测试工具还是应用 |
| 面板默认日期 | 有意不齐 | 取舍：面板是全局浮层，没有视图上下文可推断「今天」。**标为取舍，不是对齐** |

### 7.7 验收证据清单

截图（已随文档存档在 `docs/assets/`，不是 `/tmp`——`/tmp` 重启就没了）：

- `assets/quick-add-collapsed.png` / `assets/quick-add-expanded.png` —— 最终构建的收起 / 展开对照
- `assets/quick-add-list-arrow-negative-control.png` —— 焦点不在输入框时，↓ 让列表选中项移动（负对照）
- `assets/quick-add-tap-blank-bar.png` —— 点条内空白处也展开（修复前无效）

读数（AX）：焦点元素在 `AXScrollArea` ↔ `AXTextField` 之间正确切换；
输入框宽度 `328`（收起）↔ `283`（展开）。**截图给因果，读数给可信度，两者都要。**

> 留档的教训：证据截图不要只放 `/tmp`。这一轮第一次抓的 `tap-blank-bar` 截图
> 其实是在**点击失败那次**留下的，和「收起」那张字节数完全一样——差点把一张
> 说明不了任何问题的图当成证据交出去。**交付前对一下文件大小 / 肉眼过一遍。**

---

## 八、用户报的缺陷：`⋯`（更多）按钮点了没反应（21:55 补记）

用户原话：「输入框中的更多按钮点击没有反映」。

### 8.1 现象与定位

**按钮的逻辑是好的，坏的是命中区域。** 分开这两件事是这次的关键。

先做对照实验：点旁边的日期按钮 `📅 今天` → 日期浮层正常弹出；
点 `⋯` 的**正中心** → 属性浮层也正常弹出（截图 `assets/quick-add-more-popover.png`）。
所以不是 `showQuickAddProperties` 没生效，也不是 popover 不弹。

再看两个按钮的 AX 框，差别一眼可见：

| 按钮 | AX 框 |
| --- | --- |
| `📅 今天` | `@595,121 41x34` |
| `⋯` | `@645,137 **12x2**` |

**2 点高。** 扫描纵坐标确认（每次先点任务行清干净状态，再用 `AXPopover` 是否出现判定）：

| y | 130 | 133 | **137** | **138** | 140 | 143 | 146 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 结果 | — | — | ✅ | ✅ | — | — | — |

即：用户瞄着看得见的 `⋯` 点下去，只有正好落在那 2 点高的缝里才有反应。
**这就是「点了没反应」。**

### 8.2 成因

`Button { … } label: { Image(systemName: "ellipsis") }` 后面**既没有 `.frame(...)` 也没有 `.contentShape(Rectangle())`**。
纯 `Image` 标签的 `.plain` 按钮，命中区会塌缩到**图形的着墨范围**——省略号是横排的三个点，
着墨范围天生就是又宽又扁（12x2）。

旁边的日期按钮一直是这么写的：

```swift
HStack(spacing: 3) { … }
    .frame(height: WFMetrics.controlHeight)   // ← 34pt
    .contentShape(Rectangle())                // ← 整个矩形可点
```

所以它有 41x34。**同一个 HStack 里两个按钮，一个写了、一个漏了**，漏的那个就成了 2 点高的缝。

`TaskInspectorShell.swift:167` 里有个**一模一样的 `⋯` 按钮**，它是写全的
（`.frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight).contentShape(Rectangle())`），
所以全仓的图标按钮惯例是「34x34 方块 + contentShape」，只有快速添加条这一处漏了。

### 8.3 修复与验收

按仓内惯例补上 `34x34 + contentShape`：

```swift
Image(systemName: "ellipsis")
    .foregroundStyle(WFColors.secondaryText)
    .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
    .contentShape(Rectangle())
```

**同一个扫描表，改前改后对照**（这是本次验收的核心证据）：

| | AX 框 | 有反应的 y 区间 | 点数 |
| --- | --- | --- | --- |
| 改前 | `12x2` | 137–138 | **2** |
| 改后 | `34x34` | 119–151 | **33** |

顺带确认浮层内部的行也都是好的（点 `高优先级` → 浮层关闭；点 `提醒` → 切到日期浮层的提醒页，
出现 `准时 / 提前5分钟 / 提前30分钟 / 提前1小时 / 提前1天 / 自定义`）。

**副作用（要主动说）**：按钮从 12 宽变成 34 宽，输入框是 `maxWidth: .infinity`，
所以**输入框宽度从 283 变成 263**。这是布局的必然结果，不是新问题。

### 8.4 同类缺陷的全仓扫描（结论：只有这一处是真的）

写了个脚本扫「label 里只有 `Image(systemName:)`、且 label 与其修饰链里都没有
`.frame(` / `.contentShape(`」的按钮，命中 43 处。**但这个脚本只能当线索，不能当清单**：

- 已验证是**误报**的例子：`TaskListView.swift:176` 报出来是 `Image(systemName: "ellipsis")`，
  实际那里是个 `Button("选择模板…")` 文本按钮——正则向前找 `label: {` 时串到了后面的块。
- 很多命中项外面套着带 padding 的容器，命中区由父级提供，本身没问题。

抽查了**同族的省略号按钮**（省略号是最坏情况，着墨天生最扁）：

| 位置 | AX 框 | 判定 |
| --- | --- | --- |
| 快速添加条 `⋯` | 改前 `12x2` | ❌ **已修** |
| `TaskInspectorShell` 更多操作 | 34x34（代码里写全了） | ✅ 正常 |
| 笔记视图「笔记操作」菜单 | `20x14` | ✅ 能用（不理想，但 14pt 高可点） |

所以**这次只修这一处**。其余 40 来处没有逐个人工量过，
不按启发式批量改——那等于把「未验证」伪装成「已修」。要清就一个区域一个区域量着清。

### 8.5 这轮最值得记的一条

**「按钮点了没反应」有两种完全不同的成因，必须先把它们分开：**

1. **动作没执行**（`showQuickAddProperties` 没生效、popover 不弹）
2. **动作执行了，但用户根本没点中**（命中区域塌缩）

我一开始的直觉是 1，所以先去读了 `QuickAddPropertiesPopover` 和 `onChange(of: showQuickAddProperties)`
那条链路——**方向错了**。真正把它分开的是一次对照实验：
点正中心有效、点上下 2 点就无效 → 立刻锁定是 2。

**做法值得复用：不要只看「点一下有没有反应」，要扫一遍坐标，把命中区域的形状量出来。**
一个「有效 / 无效」的二分答案说明不了问题，一条 y 扫描曲线能直接指出病灶。

另外一条：**AX 报出来的 frame 就是命中区域的形状**，别因为「AX 命中测试不可靠」就把 frame 也一起不信了。
这两件事不是一回事——命中测试（`AXUIElementCopyElementAtPosition`）不可靠，
但元素的 `frame` 是可靠的，而且**框的尺寸本身就能当缺陷证据**（12x2 vs 41x34 一眼就是问题）。
