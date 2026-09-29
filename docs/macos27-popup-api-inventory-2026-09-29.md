# macOS 27 弹框 API 清单

> 日期：2026-09-29
> 问题：macOS 27 的「弹框」有多少种？
> 证据源：`MacOSX27.0.sdk` 的 `SwiftUI.swiftinterface` + `AppKit.framework/Headers`
> 关联：[macos27-component-replacement-2026-09-28.md](macos27-component-replacement-2026-09-28.md)

---

## 〇 结论

「弹框有多少种」没有单一数字，取决于按哪一层数。三层数字如下：

| 口径 | 数量 |
| --- | --- |
| **SwiftUI 呈现修饰符（挂在视图上弹出）** | **11 类**，其中 **10 类 macOS 可用**，1 类不可用 |
| └ 这些修饰符的 public 重载总数 | **92 个**（macOS 可用 90 个） |
| **SwiftUI Scene 级弹窗（整个窗口/菜单栏）** | **4 类 macOS 独占** |
| **形态与语义修饰符**（`presentation*` / `dialog*` / `dismissal*`） | **10 + 4 + 1 = 15 个** |
| **AppKit 侧弹框**（原生 macOS 另一整套） | **8 类** |

即：**按机制族数约 23 类；按 API 面数，光 SwiftUI 视图修饰符就有 92 个重载。**

Apple 自己对「呈现形态」的定义只有 **5 种** —— `PresentationAdaptation` 的全部成员：
`automatic` / `none` / `popover` / `sheet` / `fullScreenCover`。这是最权威的一个数，
但它是「形态」而非「API」，且其中 `fullScreenCover` 在 macOS 上**不可用**。

---

## 一 SwiftUI 视图修饰符（public，挂在 `SwiftUICore.View` 上）

| 修饰符 | public 重载 | macOS 可用 | 不可用 | 已弃用 | macOS 引入版本 |
| --- | ---: | ---: | ---: | ---: | --- |
| `alert` | 31 | 31 | 0 | 2 | 10.15 ×2, 12.0 ×23, 13.0 ×6 |
| `confirmationDialog` | 24 | 24 | 0 | 0 | 12.0 ×18, 13.0 ×6 |
| `fileExporter` | 12 | 12 | 0 | **8** | 11.0 ×4, 14.0 ×6, **27.0 ×2** |
| `dismissalConfirmationDialog` | 8 | 8 | 0 | 0 | 15.0 ×8 |
| `contextMenu` | 4 | 4 | 0 | 1 | 10.15 ×2, 13.0 ×2 |
| `fileImporter` | 3 | 3 | 0 | 0 | 11.0 ×2, 14.0 ×1 |
| `navigationDestination` | 3 | 3 | 0 | 0 | 13.0 ×2, 14.0 ×1 |
| `sheet` | 2 | 2 | 0 | 0 | 10.15 ×2 |
| `popover` | 2 | 2 | 0 | 0 | 10.15 ×2 |
| `inspector` | 1 | 1 | 0 | 0 | 14.0 ×1 |
| **`fullScreenCover`** | 2 | **0** | **2** | 0 | ✗ macOS 不可用 |
| **合计** | **92** | **90** | **2** | **11** | |

三点值得单独记：

1. **`fullScreenCover` 在 macOS 上不可用。** 两个重载都挂在
   `@available(macOS, unavailable) extension SwiftUICore.View` 下。跨平台代码里若用了它，
   在 macOS 上必须换 `.sheet`。
2. **`fileExporter` 12 个重载里有 8 个已弃用**（其中 4 个是 macOS 11.0 引入的老 API），
   弃用信息为 `Conform your document type to WritableDocument or Transferable instead.`。
   同时 macOS **27.0 新增了 2 个重载** —— 说明 Apple 没有放弃这条路径，只是改了文档模型。
3. **`navigationDestination` 是否算「弹框」可议** —— 它属于导航压栈，不是浮层。
   去掉它，视图修饰符是 **10 类**。

### 计数时被排除的东西（避免同名误算）

| 名字 | 被排除的 | 原因 |
| --- | --- | --- |
| `popover` | 4 个 `internal` 重载 | 非 public，不可调用 |
| `popover` | 2 个挂在 `SwiftUI.TabContent` 上 | macOS 15.0+，作用于标签页 |
| `contextMenu` | 1 个挂在 `SwiftUI.TabContent` 上 | 同上 |
| `fullScreenCover` | `PresentationAdaptation.fullScreenCover` | 是个**枚举值**，不是弹出 API |
| `presentationMode` | — | 是 `EnvironmentValues` 上的**属性**，不是视图修饰符，且已弃用 |

---

## 二 形态与语义修饰符

### `presentation*` —— 控制浮层外观/尺寸/交互（13 个声明 / 10 个名字）

| 修饰符 | 重载 | macOS |
| --- | ---: | --- |
| `presentationDetents` | 2 | 13.0+ |
| `presentationDragIndicator` | 1 | 13.0+ |
| `presentationBackground` | 2 | 13.3+ |
| `presentationBackgroundInteraction` | 1 | 13.3+ |
| `presentationCompactAdaptation` | 2 | 13.3+ |
| `presentationContentInteraction` | 1 | 13.3+ |
| `presentationCornerRadius` | 1 | 13.3+ |
| `presentationPlacement` | 1 | 随族 |
| `presentationSizing` | 1 | 15.0+ |
| `presentationPreventsAppTermination` | 1 | 15.4+ |

### `dialog*` —— 对话框语义（8 个声明 / 4 个名字）

| 修饰符 | 重载 | macOS |
| --- | ---: | --- |
| `dialogSeverity` | 1 | 13.0+ |
| `dialogIcon` | 1 | 13.0+ |
| `dialogSuppressionToggle` | 5 | 14.0+ |
| `dialogPreventsAppTermination` | 1 | 15.4+ |

`DialogSeverity` 只有 3 个值：`automatic` / `standard` / `critical`。

### `dismissal*`

| 修饰符 | 重载 | macOS |
| --- | ---: | --- |
| `dismissalConfirmationDialog` | 8 | 15.0+（iOS 27.0） |

作用：**关闭前确认**（「有未保存改动，确定关闭？」）。tvOS / watchOS / visionOS 不可用。

---

## 三 Scene 级弹窗

| 类型 | macOS | 平台独占性 |
| --- | --- | --- |
| `AlertScene` | 15.0 | **macOS 独占**（iOS/tvOS/watchOS/visionOS 均不可用） |
| `MenuBarExtra` | 13.0 | **macOS 独占** |
| `UtilityWindow` | 15.0 | **macOS 独占** |
| `Settings` | 11.0 | **macOS 独占** |
| `Window` | 13.0 | iOS/tvOS/watchOS 不可用 |
| `WindowGroup` | 11.0 | 全平台 |
| `DocumentGroup` | 11.0 | tvOS/watchOS 不可用 |
| `ImmersiveSpace` | ✗ | macOS 不可用 |

`AlertScene` 是「macOS 独占」这件事容易反直觉 —— 它是把 `alert` 提升到 Scene 层，
却只有 macOS 有。

---

## 四 AppKit 侧（原生 macOS 另一整套）

| 类别 | 说明 |
| --- | --- |
| `NSAlert` | 模态警告框；`runModal` 或 `beginSheetModalForWindow:` 挂成工作表 |
| `NSPanel` | 浮动面板（`NSSavePanel` / `NSOpenPanel` 的基类） |
| `NSSavePanel` / `NSOpenPanel` | 文件选择/保存对话框 |
| `NSPopover` | 锚定浮层 |
| `NSMenu` / `NSMenuItem` | 上下文菜单 / 菜单栏菜单 |
| `NSWindow` sheet API | `beginSheet:completionHandler:` / `beginCriticalSheet:` / `endSheet:`（10.9+） |
| `NSColorPanel` / `NSFontPanel` | 系统共享面板 |
| `NSDrawer` | 抽屉（已弃用） |

---

## 五 对本项目的意义

先看现状（在 `macos-native/WorkFollow` 下按字面量统计）：

| 机制 | 使用次数 |
| --- | ---: |
| `.popover(` | 20 |
| `.sheet(` | 5 |
| `.confirmationDialog(` | 4 |
| `.alert(` | 3 |
| `NSMenu` | 13 |
| `NSPanel` | 12 |
| `NSAlert` | 7 |
| `NSPopover` | 5 |
| `NSSavePanel` / `NSOpenPanel` | 2 / 2 |
| `.contextMenu(` / `.inspector(` / `.fileImporter(` / `MenuBarExtra` / `AlertScene` | 0 |

### 三条可执行结论

1. **`TaskTrashConfirmationOverlay` 应当换成 `.confirmationDialog`。**
   它在 `Features/Tasks/TaskTrashView.swift:191-245`，**55 行手写浮层**：
   自绘遮罩 + 圆角卡片 + 红色圆形关闭钮 + 两个按钮 + 手写 Esc 处理。
   对应系统 API 是 `.confirmationDialog` + `dialogSeverity(.critical)` + `dialogIcon`。
   项目里**已经在 4 处用过 `.confirmationDialog`**（`SettingsDataView.swift:326`、
   `:332`、`HabitsWorkspaceView.swift:641`、`FocusWorkspaceView.swift:247`），
   所以换过去是和既有风格一致的，不是引入新范式。

2. **`dismissalConfirmationDialog`（macOS 15.0+）正好对应编辑器的未保存改动确认。**
   项目编辑器有草稿/撤销状态，关闭时的确认目前需要自己接。这是系统现成能力。

3. **别用 `fullScreenCover`。** macOS 上不可用，需要全屏呈现只能用 `.sheet`。

### 一个前置约束

上面 macOS **15.0+** 的 API（`AlertScene`、`UtilityWindow`、`presentationSizing`、
`dismissalConfirmationDialog`、`presentationPreventsAppTermination`、
`dialogPreventsAppTermination`）在**当前部署目标 14.0** 下必须包 `if #available(macOS 15.0, *)`。
而本项目目前 **`#available` / `@available` 的使用次数为 0** —— 也就是说，
要用这些 API，要么引入可用性分支，要么把部署目标提到 15.0 以上。
这是选型时要一起决定的事，不能只看 API 好不好用。

---

## 六 测量方法（以及我在这上面栽的四个跟头）

证据源：`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
（1,984,747 字节 / 34,179 行 / 4,217 个成员声明）。`SDKSettings.plist` 的
`MaximumDeploymentTarget = 27.0.99`。

**`@available` 注解写在声明行之前**，所以必须从声明行**向上连续**收集注解行。
这一点我错了四次，每次都得出过假结论，记在这里免得重犯：

| # | 错误做法 | 后果 |
| --- | --- | --- |
| 1 | 用固定窗口向上扫 N 行 | 窗口跨进相邻声明的注解 → 误判 |
| 2 | 只向上扫，不继承**外层** `extension` 的注解 | `fullScreenCover` 被误判成「macOS 可用」 |
| 3 | 只按名字匹配，不看**所属类型** | `PresentationAdaptation.fullScreenCover`（枚举值）被当成弹出 API |
| 4 | 版本正则写成 `macOS\s+([\d.]+)` | `@available(macOS, introduced: 11.0, deprecated: ...)` 平台名与版本间有逗号 → 同时漏掉版本和弃用标记，`fileExporter` 的 8 个弃用重载全部漏报 |

**通用教训：按名字匹配 ≠ 按语义匹配。** 注解在**前一行**还是**外层作用域**、
成员属于**哪个类型**、是 **public 还是 internal**，任何一项没查都会让数字偏大或偏小。
上面表里的每个数字都经过了「按 owner 过滤 + 作用域注解继承 + public/internal 分离」三步。

---

## 七 边界与未验证项

- **数字口径**：`public` 指 `swiftinterface` 里带 `public` 修饰符的声明。
  `@export(implementation)` 的重载按其字面 public 计入。若把 `internal` 实现重载也算上，
  `popover` 会从 2 涨到 6。
- **未查**：`UIKit` 侧的 macOS 对应物（Mac Catalyst）、`SwiftUI` 之外的
  `AppKit` 头文件级重载计数（本表 AppKit 部分只列了类，未逐方法计数）。
- **未实测**：本表是**接口层清单**，不是「哪些能在本项目跑起来」的验证。
  每个替换项落地前仍需真机验证（见项目通用规则：接口存在 ≠ 行为符合预期）。
- **`dismissalConfirmationDialog` 在 iOS 是 27.0、macOS 是 15.0** —— 这个跨平台版本差
  本身值得注意，说明它在 macOS 上先落地。
