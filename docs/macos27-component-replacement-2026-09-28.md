# macOS 27 组件替换分析（2026-09-28）

> 目的：评估「把项目里自己手写的实现换成 macOS 27 / SwiftUI 27 系统组件」的可行范围。
> 结论先行，证据在后。**所有「可替换」判断都附了替换后的验证方式**；
> 凡是我没实测过的，明确标注「待实测」。

## 〇、结论速览

| 类别 | 项数 | 说明 |
| --- | --- | --- |
| **可替换并删代码** | 3 | 真能删掉手写实现 |
| **零改动白拿** | 2 | 只重编译，不改代码 |
| **明确用不上** | 5 | **写在这里是为了防止白干** |
| **需要新建（非替换）** | 2 | 是新功能，不是替换 |
| **要警惕的副作用** | 1 | Liquid Glass 会自动换肤 |

一句话：**这个项目手写的东西，比想象中少；能替换的，比想象中少；而最大的收益来自一处不用改的改动。**

---

## 一、可替换并删代码（3 项）

### 1.1 任务列表拖拽排序 —— 收益最大

**现在怎么写的**

| 位置 | 内容 | 行数 |
| --- | --- | --- |
| `Features/Tasks/TaskList/TaskListView.swift:1071-1094` | `TaskReorderDropModifier`：`dropDestination` + **自画 `Capsule` 插入指示条** | 24 |
| `TaskListView.swift:788` | `draggable` 标记拖动源 | — |
| `Features/Planning/CalendarWorkspaceView.swift:523/623/708/1031/1105` | 日历里自算列/日落点 | — |
| `Features/Planning/MatrixWorkspaceView.swift:269/459` | 四象限自算落点 | — |

**新组件**

```swift
ForEach(tasks) { task in
    TaskRow(task)
}
.reorderable()

// 容器侧
.reorderContainer(for: Task.self) { difference in
    model.apply(difference: difference)
}
```

配套还有：
- `.reorderable(collectionID:)` + `.reorderContainer(for:in:isEnabled:move:)` —— **多集合（分节）版本**
- `.dragContainer(for:in:_:)` —— 拖到容器**外**时提供传输表示
- `.dropDestination(for:isEnabled:action:)` + `session.reorderDestination(for:in:)` —— 接收外部拖入
- `ReorderDifference` —— 系统算好的位置变更描述

**为什么值得换**：官方文档明说，在此之前「支持拖放重排需要**自定义命中测试和插入位置计算**」。项目里那 24 行正是干这个的 —— 系统接管后，插入位置、占位空间、指示条全不用自己画。

**风险（本项唯一的高风险点）**：任务列表是**父子层级**结构（`TaskWorkspaceModel` 里 parent/child 带折叠）。新 API 的多集合版本是按「分节/相册」模型设计的，**父子树能不能直接映射成「多个集合」，我没实测，标为待实测**。建议先用日历或四象限（扁平结构）试点，再碰主列表。

**验证方式**：`CalendarWorkspaceView` 换成 `reorderable` 后，真实拖动一次，确认落点与插入指示位置一致；再跑 471 项测试确认 `TaskWorkspaceModel` 的排序断言没破。

---

### 1.2 回收站确认浮层

**现在怎么写的**

`Features/Tasks/TaskTrashView.swift:191-245` —— `TaskTrashConfirmationOverlay`，**自绘 ZStack 遮罩 + 卡片**，55 行。

**新组件**：系统 `.confirmationDialog` / `.alert`，且 macOS 27 新增了 **item 绑定模式**（和 sheet 一样，设值即弹）。

**为什么值得换**：项目**已经在用**系统的 `.alert`（3 处：`HabitsWorkspaceView:641`、`FocusWorkspaceView:247`、`SettingsDataView:326/332`）和 `.confirmationDialog`（4 处）。说明团队接受这个方向，回收站这处是**历史遗留**，风格还不统一。

**风险**：低。需确认自绘浮层有没有系统做不到的行为（例如特定的按钮排布）。待实测。

**验证方式**：删除一条任务 → 确认框出现 → 取消 → 任务还在；确认 → 任务进回收站。再跑 `TrashIsolationTests`。

---

### 1.3 编辑器选区工具条 / 提示条的定位

**现在怎么写的**

| 位置 | 内容 |
| --- | --- |
| `Features/Editor/DocumentSelectionToolbar.swift:189-243` | 用 `frame.midX` **手算** tooltip 水平位置 |
| `Features/Editor/DocumentToolbarTooltip.swift:37-55` | 自己收集 frames 做定位 |
| `Features/Editor/SlashCommandPanel.swift:63-105` | 自建 `NSPanel` 并自己定位 |

**新组件**：`.popover(item:attachmentAnchor:)` 让系统负责锚定与避让。

**风险**：**中**。这套定位是照着 Flutter 版逐像素对齐过的（`DocumentSelectionToolbar` 有明确的 parity 注释）。系统 popover 的形态、边距、动画都可能不同，**换完可能要重新对齐**。收益（删几十行）与代价（重新对齐）需要权衡。

**验证方式**：选中一段文字 → 工具条出现在选区正上方且不越界；把窗口拖到屏幕右边缘再试一次。截图对比改造前后。

---

## 二、零改动白拿（2 项）

### 2.1 `@State` 宏化 → 类惰性初始化 ⭐ 本次最大即时收益

**项目现状**：**218 处 `@State`**。

**变化**：`@State` 从属性包装器改为**宏**，存在 `@State` 里的 class 变成**惰性初始化**（每个视图生命周期只初始化一次）。

**关键**：苹果通过编译器**向下兼容到了 macOS 14**。也就是说 ——
- **不用改代码**
- **不用改部署目标**
- 只要把编译环境切到 Xcode 27，**老系统上也照样拿到**内存与启动速度收益

这是整个升级里**唯一零风险、零工作量、立即见效**的一项。官方建议直接用 Instruments 对比升级前后的内存峰值和冷启动时间。

**验证方式**：升级前后各跑一次 Instruments 的 Allocations，记录峰值；冷启动计时各 5 次取中位数。

---

### 2.2 `ContentBuilder`（`ViewBuilder` 更名）→ 构建提速

**项目现状**：37 处 `ViewBuilder`，其中**显式书写的只有 3 处**：
- `Features/Editor/DocumentSelectionToolbar.swift:319`
- `Features/Planning/PlanningOverlayLayer.swift:50`
- `Features/Planning/PlanningOverlayLayer.swift:87`

**变化**：`ViewBuilder` 公开为 `ContentBuilder`，Xcode 27 构建时间显著缩短。不改代码。

**验证方式**：记录升级前后 `xcodebuild` 的 wall-clock 时间。

---

## 三、明确用不上（5 项）—— 写在这里是为了防止白干

### 3.1 工具栏新 API —— 前提不存在

`visibilityPriority` / `ToolbarOverflowMenu` / `topBarPinnedTrailing` / `toolbarMinimizeBehavior`

**为什么用不上**：**项目几乎不用系统 `.toolbar`。** 全仓只有 **1 处**：
`Features/Settings/SettingsDataView.swift:409-410` 的一个 `.cancellationAction` ToolbarItem。

顶部栏、工具条、属性条**全是自己用 `HStack` 搭的**：
- `RootShellView.swift:11/114` —— 断点式显隐
- `DocumentSelectionToolbar` / `DocumentToolbarTooltip` —— 自建工具条
- `TaskListView.swift:169`、`TaskInspectorShell.swift:165`、`HabitsWorkspaceView.swift:137` —— 手写「更多」菜单

**结论**：想用这套 API，前提是**先把自建顶栏迁到系统 toolbar**。那是**架构重构**，不是组件替换。要不要做是独立决策，不能算进「替换」的账。

> 官方给的收益是「以前为了适配窗口尺寸写了一堆 `if horizontalSizeClass == .compact` 分支，现在可以删掉」。项目确实有类似的断点逻辑（`RootShellView`），所以**如果**决定迁，收益是真的。但这是「换架构」，先别混进本轮。

---

### 3.2 `swipeActionsContainer` —— 没有手写轻扫可替换

**为什么用不上**：项目**没有手写左滑**。全仓只有 3 处 `DragGesture`，全是**分隔条拖宽**：
- `Features/Shell/RootShellView.swift:103`
- `Features/Tasks/TaskTrashView.swift:28`
- `Features/Notes/NotesWorkspaceView.swift:53`

任务属性里的「提醒」行是 `.onTapGesture { toggleSheet(sheet) }`（`TaskDatePopoverV2.swift:180`）—— **点击打开子面板，不是轻扫**。

**结论**：`swipeActionsContainer` 对项目是**净新增能力**（任何 `ScrollView` 都能挂轻扫），不是替换。想用就是新功能开发。

---

### 3.3 `AsyncImage` HTTP 缓存 —— 没有远程图片

**为什么用不上**：全仓 **0 处** `AsyncImage` / `URLSession` / `NSCache`。项目不加载任何远程图片。

---

### 3.4 Document API —— 架构不匹配

`WritableDocument` / `ReadableDocument` / `DocumentCreationSource` / `NewDocumentButton(source:)`

**为什么用不上**：项目 **0 处 `DocumentGroup`**，也 **0 处 `FileDocument` / `FileWrapper`**。

持久化是手写的：`Infrastructure/Persistence/JSONFileStore.swift`(66 行) + `JSONEncoder` + `Data.write`（另有 `NativePreviewRepository`、`MigrationSnapshot`、`SettingsDataView` 里的若干处）。

新的 URL 直访是为**文档型 App**（`FileDocument`）设计的 —— 让几百 MB 的文件不必整个读进内存。本项目不走那条路。

**结论**：用不上。除非要把整个持久化改成文档型 App —— 那是另一个量级的改造，且与「用新组件」无关。

---

### 3.5 流式布局 —— SwiftUI 至今没有内置

**为什么用不上**：我专门查了，**SwiftUI 到今天仍没有内置 flow layout**，`Layout` 协议依然是唯一途径。

`Features/Tasks/TaskList/QuickAddTokenFlowLayout.swift:307-357`（51 行，全项目**唯一**的 `Layout` 实现）—— **保留，不要动。** 这不是技术债，是必需品。

---

## 四、需要新建（非替换）2 项

| 能力 | 能做什么 | 与现有工作的关系 |
| --- | --- | --- |
| **Foundation Models / Core AI** | 设备端 LLM，多模态提示词，可接 Claude / Gemini 等云模型；Vision 的 OCR 与条码识别可直接被模型调用 | 项目另有 MCP/Agent 工作树（`feature/mcp-agent-access`）。若要做「自然语言建任务」，这是官方路径 |
| **App Intents View Annotations** | 把视图映射到实体，让 Siri 能用自然语言引用并操控屏幕内容 | 纯新功能。项目已有 `AppCommands`，但那是菜单命令，不是 Siri 集成 |

---

## 五、要警惕的副作用：Liquid Glass 会自动换肤

官方说明：**用 Xcode 27 重新编译，就会自动换上 Liquid Glass 新皮肤**，包括 iPad 上非活跃窗口变暗。

**对这个项目这可能是负担而不是收益**：项目的视觉是照着滴答**手调对齐**的 —— `WFColors` / `WFMetrics` / `WFType` 全是自定值，`docs/` 里有多份 parity 对齐文档，编辑器部分甚至逐像素对过（`DocumentBlockDecorations` 的圆角 4.05、边宽 1.053 这种精度）。

自动换肤会让这些手工对齐**整体偏移**。

**建议**：升级 Xcode 27 后**第一件事就是目视对比**主要界面，确认 Liquid Glass 带来的偏移范围。如果需要保持现状，要研究如何opt out 或适配 —— **这一项我没查到确切的 opt-out 方式，标为待查**。

---

## 六、分阶段实施建议

### 阶段 0：只升工具链（不动任何代码）
- 装 Xcode 27
- 部署目标**保持 14.0**
- 跑通 471 项测试
- **目视检查 Liquid Glass 造成的视觉偏移**（这是本阶段最大的不确定性）
- 目的：把「工具链升级」和「代码改造」两个风险源分开

### 阶段 1：白拿收益（不动代码）
- 用 Instruments 对比 `@State` 惰性初始化的内存与冷启动收益
- 记录 `ContentBuilder` 带来的构建时间变化

### 阶段 2：低风险替换
- 回收站确认浮层 → `.confirmationDialog`（55 行 → 几行）

### 阶段 3：中风险替换
- 日历 / 四象限的拖拽 → `reorderable()` / `reorderContainer(for:)`
- 编辑器工具条定位 → `.popover(attachmentAnchor:)`

### 阶段 4：高风险替换（需先验证）
- **任务主列表**的拖拽重排 —— 先确认父子层级能否映射到多集合模型

### 阶段 5：独立决策，不算替换
- 自建顶栏是否迁到系统 toolbar（才能吃到溢出菜单与可见性优先级）
- 是否接 Foundation Models

---

## 七、待实测 / 未验证清单（诚实标注）

| 项 | 为什么没验证 |
| --- | --- |
| 父子层级任务列表能否用 `reorderContainer(for:in:)` | 需要 macOS 27 SDK 才能编译验证；**本机没有** |
| Liquid Glass 的视觉偏移范围 | 同上 |
| Liquid Glass 能否 opt out | 未查到官方说明 |
| 自绘确认浮层有无系统做不到的行为 | 需先读完 `TaskTrashConfirmationOverlay` 全部行为再判断 |
| `@State` 宏化的破坏性改动（`variable 'self.title' used before initialization`）在 218 处里命中几处 | 需在 Xcode 27 上编译才知道 |
| 编辑器工具条换成系统 popover 后的重新对齐成本 | 需实际改造后目视对比 |

## 八、附：本机环境实测记录

```
本机系统      macOS 27.0（26A428），Apple M1 Pro / arm64
Xcode         26.6（17F113）
可用 SDK      仅 MacOSX26.5.sdk / MacOSX26.sdk
SDK 上限      MaximumDeploymentTarget = 26.5.99
可用性宏      最高 __MAC_26_5；__MAC_27_0 出现 0 次
```

**结论：本机目前无法验证本文中任何依赖 macOS 27 SDK 的项。** 所有「新组件」的替换代码都写不出来 ——
不是运行会崩，是编译不过。上表第 1、2、5 项都必须等 Xcode 27 到位后才能推进。

## 九、更正：本文推翻的两条此前说法

在本次分析前的口头结论里，我说过两条不准确的话，在此更正：

1. **「项目有 30 处 toolbar，正文工具条一直在跟可见性较劲」** —— 错。
   30 是**文本匹配数**（含 `DocumentSelectionToolbar`、`showFormatToolbar` 等自建名字）。
   项目真正用系统 `.toolbar` 的只有 **1 处**（Settings）。这条误导了「工具栏新 API 可以直接用」的判断。

2. **「『提醒』行那个手写轻扫可以用 `swipeActionsContainer` 替掉」** —— 错。
   「提醒」行是 `.onTapGesture` 打开子面板，**不是轻扫**。项目里没有手写轻扫。

两条都属于**拿文本匹配数当结构结论**。教训：统计出现次数只能当线索，**要打开代码看它到底在干什么**。

---

# 阶段 0 实测结果（2026-09-29 上午，Xcode 27 已装）

## 环境

```
Xcode        27.0（27A266a）
SDK          MacOSX27.0.sdk，MaximumDeploymentTarget = 27.0.99
可用性宏      __MAC_27_0 现已存在（此前 0 次）
本机          macOS 27.0（26A428），Apple M1 Pro
```

## 一、构建：通过，0 错误

**部署目标保持 14.0 未动**（正是阶段 0 的目的）。产物核对：

```
LC_BUILD_VERSION  minos 14.0   sdk 27.0
LSMinimumSystemVersion  14.0
```

警告只有 1 条，且与本项目无关：`Metadata extraction skipped, no AppIntents.framework dependency found`。

**没有出现**：`PreviewProvider` 弃用告警（全仓无 PreviewProvider）、`ld_classic`/`ld64` 报错（全仓无相关标志）、SE-0508 相关错误。

## 二、`@State` 宏化：218 处，0 处破坏

这是阶段 0 最关心的一项。**结论：一处都没坏。**

Apple 自己审计 4 个真实 App（215 个文件 / 267 处 `@State`）时命中 0 处；本项目 **218 处也是 0 处**。
原因也清楚：两种破坏形态都要求「View 结构体里同时有手写 `init` **和** 带声明初始值的 `@State`」，
本项目没有这种写法。

> 注意触发条件：`@State` 用宏还是属性包装器**由编译器决定，与部署目标无关**。
> 所以「把部署目标留在 14.0」并不能躲开这次变更 —— 只是本次恰好没踩到。

## 三、测试：472 项，1 项失败（**与 Xcode 27 无关**）

失败用例：`MigrationSnapshotTests.testParseV3MapsTasksNotesListsAndAttachments`

```
MigrationSnapshotTests.swift:116: XCTAssertEqual failed: ("2") is not equal to ("1")
```

**归属判定（三条独立证据）**：

1. 第 116 行是 `XCTAssertEqual(bundle.folders.count, 1)`，而同一测试文件里的 fixture（第 71–76 行）**写了 2 个 folder**。
2. **同一个测试的第 122 行**写着 `XCTAssertEqual(summary.importedFolders, 2)` —— 期待 **2**。
   同一份 bundle，一处期待 1、一处期待 2，**断言自相矛盾**。
3. `MigrationSnapshot.swift`（+256/−41）与 `MigrationSnapshotTests.swift`（+91）的修改时间是
   **09-28 23:50 / 23:52**，属于另一会话在途改动，早于本次工具链升级。

这是**改 fixture 时漏改的旧断言**。与 `JSONDecoder`、与编译器无关。

## 四、Liquid Glass：**没有可见变化**

原担心「自动换肤会让手调对齐整体偏移」。实测**不成立**。

**目视对比**（Xcode 27 构建的实例，主窗口 + 设置窗口各截一张）：
侧栏、任务行、配色、窗口标题栏、设置页的分段控件与分组行 —— 全部与升级前一致。

**为什么**：这个 App 几乎全是自绘。系统材质用量：

```
ultraThinMaterial 0   thinMaterial 0   regularMaterial 1   thickMaterial 0
NSVisualEffectView 0  visualEffect 0
```

**没有材质可换肤**，所以 Liquid Glass 无处施展。系统样式控件确实有约 55 处
（`.bordered` 26 / `.borderedProminent` 9 / `.borderlessButton` 15 / `.roundedBorder` 5），
集中在**设置窗口**（11 处）、专注页（8）、习惯页（5）；抽查设置窗口渲染正常。

> 未做像素级差分（两次截图窗口尺寸不同、源码也在夜间被改过，不是受控对比）。
> 结论依据是**目视无差异**，标为「目视确认」而非「像素验证」。

## 五、一个环境陷阱（值得记下来）

首次构建**全部失败**，报几千行：

```
sandbox-exec: sandbox_apply: Operation not permitted
error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found
       for macro 'State()'; ... swift-plugin-server produced malformed response
error: cannot find '_name' in scope
error: cannot assign to property: 'self' is immutable
```

**这不是代码问题，也不是 Xcode 27 的问题。** 根因：

- Xcode 27 起 `@State` 是宏，Swift 编译宏时要在**子沙箱**里跑 `swift-plugin-server`；
- 而**本机 `sandbox-exec` 不可用** —— 连 `sandbox-exec -p '(version 1)(allow default)' /bin/echo ok`
  都报 `sandbox_apply: Operation not permitted`（退出码 71）；
- 插件没跑起来 → 宏不展开 → 连带报出 `_name` / `$name` / `self is immutable` 等**假错误**。

**绕法**：`-Xfrontend -disable-sandbox`（前端选项「Disable using the sandbox when executing subprocesses」）。
加上之后最小用例与整个项目都正常编译。

**已固化进 `scripts/run-tests.sh`**：新增 `WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1` 开关。
本地 Xcode GUI 构建**不需要**它（已验证：用户自己 Xcode 构建的产物 minos 14.0 / sdk 27.0 正常）。

**教训**：`cannot find '_name' in scope` 这类错误如果**成片出现**，先怀疑宏没展开，
而不是逐个去改 218 处 `@State`。判据是**同一条错误是否出现在大量无关文件里**。

## 六、阶段 0 结论与下一步

| 项 | 结果 |
| --- | --- |
| 工具链升级本身 | ✅ 干净，0 错误 0 弃用 |
| `@State` 宏化破坏 | ✅ 0 处 |
| Liquid Glass 视觉偏移 | ✅ 目视无变化 |
| 测试 | ⚠️ 472 项 1 失败，**归属另一会话的在途改动** |
| 部署目标 | **仍为 14.0**（未动，符合阶段 0 设计） |

**下一步（阶段 1/2）**：
1. 先让另一会话修掉 `MigrationSnapshotTests:116` 的断言，让基线回到全绿；
2. 再用 Instruments 量化 `@State` 惰性初始化的收益（阶段 1）；
3. 然后才进入阶段 2 的组件替换（回收站确认浮层 → `.confirmationDialog`）。

