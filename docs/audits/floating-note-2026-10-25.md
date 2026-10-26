# 悬浮笔记（置顶浮窗内编辑）：可行性分析与实现方案

日期：2026-10-25
原调查范围：分析与设计。文中 AppKit 调查结论附 SDK 头文件行号或探针实测日志；
所有"没测到"的地方明确标注为未验证，不写成结论。

## 后续公共化实施

- 笔记和任务便签现在共用 `FloatingEditorWindowController`、`FloatingEditorPanel` 和 `FloatingEditorView`。窗口定位、主题、层级、关闭提交及正文格式工具条由公共层负责。
- `FloatingNoteWindowController` 与 `StickyNoteWindowController` 只保留各自的创建、数据绑定、删除跟随和主页导航。任务便签移除了纯文本转换及独立的 0.5 秒延迟写入队列。
- 浮窗按文档 ID 绑定。打开期间主页正文改为预览，关闭后恢复编辑；中文组合输入在关闭前提交，修改继续通过现有任务／笔记存储与撤销链保存。
- 按用户最终要求，笔记和任务入口统一为编辑栏顶部的独立「打开便签」按钮，共用同一控件；更多菜单移除重复入口。同一内容再次打开只前置已有窗口，任务原独立详情入口也接入公共浮窗。
- 22 项相关原生控件与完整页面测试通过，覆盖富文本、多级列表、撤销、中文关闭保存、落盘重读、主页编辑权交接、多个浮窗与更多菜单。
- 顶部入口调整后，9 项相关定向测试通过：笔记顶部点击、任务顶部点击及中文输入交接、宽／紧凑布局、窗口复用、选中任务切换与重复菜单移除。
- 日用版已更新为 0.2.0（21），保留（20）作为回退。安装后通过实际界面分别点击任务、笔记顶部「打开便签」，确认打开对应悬浮窗，关闭后恢复主页编辑；本轮安装候选包及测试产物已清理。

后文保留原调查过程，其中旧窗口类名及行号属于当时版本；跨应用鼠标和全屏交互的历史未验证项不因本轮自动化测试而改记为已验证。

伴生证据目录：`docs/audits/floating-note-2026-10-25/`（探针原始输出）

---

## 1. 需求拆解

用户原话拆成六条可判定的行为：

| # | 需求 | 判定方式 |
|---|---|---|
| R1 | 笔记编辑框悬浮在桌面最上层 | 盖住其他 App 窗口（含全屏 PDF） |
| R2 | 鼠标移开笔记，焦点移开；滚轮直接操作下面的 PDF | 光标在 PDF 上滚 → PDF 滚动，笔记内容不动（"焦点移开"按"点击别处"实现，见 §6.3） |
| R3 | 笔记可拖到桌面任意位置，位置要记住 | 标题栏拖动；重启后回到原位置 |
| R4 | 一边看 PDF 一边记录 | R1+R2+键盘输入同时成立 |
| R5 | 点笔记能输入；移开鼠标滚 PDF 后，继续键盘输入，光标还在笔记里 | 滚 PDF 不改变键盘去向；光标/选区保留 |
| R6 | 在笔记外点击 → 无法再输入到笔记 | 点 PDF 后敲键盘，字符进 PDF 而不是笔记 |

**关键结论：R1–R6 在机制层面都能成立，不需要任何全局键盘钩子。** 因为 macOS 的两条原生规则正好就是用户想要的行为：

- 滚轮按**指针位置**派发，不按"焦点窗口"派发（`NSEvent.h:474`，见 §2.3）；
- 键盘按**key window** 派发，而"点窗口外"天然让本 App 失活、笔记 resign key（见 §2.2）。

也就是说 R2/R5/R6 不是要"实现"的功能，而是要**不破坏**的功能：只要笔记不抢 key、不吞滚轮，平台免费给出这些语义。

**但 R2 的"鼠标移开 → 焦点移开"必须按"点击别处"来读，不能按"光标离开矩形"来读**——macOS 键盘焦点不跟随光标。两种读法的取舍见 §6.3，建议采用"点击别处才移焦"。

代价只有一个，且必须提前和用户对齐：**R5 的"继续键盘输入"要求 WorkFollow 处于激活态**，于是点笔记时 macOS 会把菜单栏换成 WorkFollow 的菜单栏（PDF 阅读器菜单栏消失），并且会把 WorkFollow 的窗口组提前。这正是本方案唯一需要小心处理的副作用（§2.2、§6.1）。

⚠️ 一处必须说清的保留：上面是"机制推导 + 各条独立实测"的结论，**不是端到端实测**。本机拿不到辅助功能/输入监控权限，合成鼠标键盘投递不进去，所以"点笔记 → 打字 → 滚 PDF → 继续打字"这条完整链路没有被自动验证过。端到端验收见 §8，未验证项见 §9。

---

## 2. 平台机制与实测证据

### 2.1 悬浮层级（R1）

`level = .floating`（CGWindowLevel 3）足够盖住所有普通窗口（level 0），包括全屏的 PDF 阅读器。
探针 5 的窗口层级转储显示本 App 的 L3 面板排在 ChatGPT / Safari 的 L0 窗口之上。

配套两个必须项：

- `hidesOnDeactivate = false`（`NSWindow.h:416`）。默认值会让面板在 App 失活时消失——而"点 PDF 就失活"正是本功能的核心操作，不设这个开关功能直接不存在。
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`，否则用户把 PDF 全屏后笔记被关在原来那个 Space 里，R4 断掉。

现仓库 `FloatingNoteWindowController.swift:228-230` 已正确设置这三项。

### 2.2 焦点模型（R5 / R6）——本文档最重要的一节

三条实测事实：

1. **窗口显示可以不激活 App。** 探针 5：`orderFrontRegardless()` / `order(.above, relativeTo: 0)` 后 `NSApp.isActive == false`，面板仍可见、仍在 L3。
2. **窗口"变 key"必然激活 App。** 探针 7：`orderFrontRegardless` → `active=false`；单独 `makeKey()` → `active=true key=FLOAT`；`makeKeyAndOrderFront` → 同样 `active=true`。结论：激活是"成为 key window"带出来的，不是 orderFront 带出来的。
3. **App 的"可被提前窗口组"就是 main + key 两个。** 探针 13 / 17 在笔记被点成 key 之后读到 `raiseSet = [NSApp.mainWindow, NSApp.keyWindow]`：`canBecomeMain = false` 时是 `["MAIN","NOTE"]`，`canBecomeMain = true` 时是 `["NOTE","NOTE"]`（四组 styleMask 组合结论一致，见 `probe-result17-*.txt`、`probe-result13-*.txt`）。
   **注意**：这里实测到的是"main/key 身份归属"，不是"窗口真的被抬起来了"——跨 App 的前后序没测成（§6.1 末段）。

由此得到两条纪律：

- **打开/展示悬浮窗时不要激活 App**，用 `orderFrontRegardless()`。否则用户按 Cmd+Opt+N 新建笔记，PDF 就被抢了焦点。
- **用户点击笔记时才激活**（这是用户明确要的语义，不是"抢焦点"）。但激活会把 App 的 main window 一起提前——如果 main window 是那个占大半屏的 WorkFollow 主页，PDF 就被它盖住了。见 §6.1。

关于 `.nonactivatingPanel`：`NSWindow.h:51` 说明它只是"不让面板激活所属 App"。它是**不需要键盘**的浮层（如现有 StickyNote）该用的；本功能要打字，所以不能靠它，只能接受激活。反过来说，一旦选了激活，也就顺便绕开了 `.nonactivatingPanel` 在旧系统上破坏输入法的已知问题（Qt QTBUG-121434，macOS 13 复现、14+ 部分复现）——我们不用这个 styleMask，就不踩这个坑。

还有一条限制写在 `NSApplication.h:222-236`："You shouldn't assume the app will be active immediately after sending this message. The framework also does not guarantee that the app will be activated at all." 也就是说程序化激活不保证成功（macOS 14 起是协作式激活）。脚本化探针 16 里就出现了"定时器里调 makeKeyAndOrderFront 但 App 没被激活"的情况——**这正好说明为什么最终验收必须在真机上用真鼠标点**（§8）。

### 2.3 滚轮路由（R2 / R5）

`NSEvent.h:474` 原文：

> All the gesture events are sent to the view under the cursor when the NSEventPhaseBegan occurred.

`NSEvent.h:354` 补充：惯性滚动"latches these scroll wheel events to the view that is under the cursor when the flick occurs"。

机制后果：

- 光标在 PDF 上滚 → 事件进 PDF 那个进程，WorkFollow 收不到，**键盘焦点不受影响**（滚动不改变 key window）。这正是 R5 想要的：滚 PDF 的同时键盘还能继续打字。
- 光标在笔记上滚 → 事件进笔记自己的 SwiftUI `ScrollView`，滚动笔记内容。R2 的"滚轮直接操作下面那个页面"仅指光标在 PDF 上时，两者不冲突。
- **因此不需要任何全局滚轮监听/转发。** 唯一要保证的是笔记自己别把滚轮吞掉又不用：`DocumentEditor` 的 `contentSized: true` 路径把 `textView.usesHostScrollView = true`，滚轮归外层 `ScrollView` 所有，链路是通的。

顺带一个已有实现的风险点：`CalendarSwipeGesture.swift:59` 判断 `window === NSApp.mainWindow`。§6.1 若采用"让笔记当 main window"的方案，日历横滑手势会在笔记持有 main 身份期间失效，必须一起改（改成按 `identifier == "WorkFollowNativeMain"` 认窗口）。

### 2.4 拖动（R3）

两条路线，建议都用：

- 标题栏区域：自绘 header 里的 `DragView`（`FloatingNoteView.swift:183,186`）`acceptsFirstMouse → true` + `window?.performDrag(with: event)`。`NSWindow.h:659-661` 说明这个方法把拖动交给 Window Server，"allows the window to participate in space switching, and other system features"，并且"a mouseUp may not get sent"（所以别在 mouseUp 里做收尾逻辑）。
- 整窗背景：`isMovableByWindowBackground = true`（`:226`）。风险是正文也可能被当拖动区；实际上 `NSTextView` / `NSScrollView` 的 `mouseDownCanMoveWindow` 返回 false，正文天然安全，所以这条可以留着当"空白处也能拖"的兜底。

位置持久化：`frameAutosaveName = "WorkFollowFloatingNote"` + 关闭时 `saveFrame`（`:96,164-165`）。多笔记时按 26pt 级联偏移避让，并 `clamp` 到当前屏幕 `visibleFrame` 内（屏幕从 5120×2880 变成笔记本屏时不会跑到屏幕外）。

### 2.5 首次点击要能落下光标（R5 的前置）

App 处于非激活态时，第一次按下鼠标的 view 必须返回 `acceptsFirstMouse == true`，否则这一下只用来激活 App，光标不落（用户感知就是"点了没反应，要点两下"）。

`NSView.h:225` 是默认实现。探针 18 实测默认值（`probe-defaults.txt`）：

```
NSTextView.acceptsFirstMouse        = false
NSScrollView.acceptsFirstMouse      = false
NSHostingView.acceptsFirstMouse     = false
NSTextView.needsPanelToBecomeKey    = true
NSHostingView.needsPanelToBecomeKey = false
NSTextView.mouseDownCanMoveWindow   = false
NSScrollView.mouseDownCanMoveWindow = false
```

仓库里只有 `FloatingNoteView` 的 `DragView` 覆盖成 true（`:183`），`NativeTextView` 与 `NSHostingView` 都没有覆盖。所以按上述默认值推断，非激活态第一次点击正文会被用来激活 App、光标不落（用户感知"点了没反应，要点两下"）——这是要在编辑器视图上补的一处。

**注意边界**：这条是"默认值 ⇒ 行为"的推断。探针 14 想用合成点击直接验证，但本机无辅助功能权限，`NSApp.postEvent` 投递的点击没有进入视图链（plain 与 firstmouse 两组结果完全一致，`selectedRange` 都没变），**该点本身未实测**，列入 §9 第 1 项。

另外 `NSTextView.mouseDownCanMoveWindow == false` 这一条反过来证明 §2.4 的"整窗背景可拖"不会误伤正文。

### 2.6 标题栏与自绘 header

探针 15 实测：`.titled` 面板标题栏高 32pt。

- 带 `.fullSizeContentView` 时，`hitTest` 在距顶 4–40pt 的横向位置都命中**我们自己的** `NSButton`，即自绘 header 可点。
- 不带时，距顶 4–29pt 全部命中 `NSThemeFrame`，即顶部一整条属于系统标题栏，自绘按钮点不到。

现仓库 `:221` 已带 `.fullSizeContentView`，配置正确，无需改动。

### 2.7 其它已就绪的支撑

以下各项在当前工作区里**已实现并已验证**：

- 正文宿主同源：悬浮窗与笔记页共用 `DocumentEditor` + `NoteDocumentProfile`（`FloatingNoteView.swift:85`），不存在第二套编辑器语义。
- 不会双写：笔记页在浮窗打开时隐藏自己的编辑器与格式工具条（`NotesWorkspaceView.swift:311,321`）。
- 浮层弹窗层级跟随宿主：`NativeTextView.swift:777,784` 的按需面板用 `EditorPopupWindowLevel.apply(to:owner:)`（`EditorPopupPresentation.swift:143-149`，仅对 floating 及更高的宿主 +1），浮窗为 floating 时弹层 = level+1。
- 落盘：`NoteStore.edit` → `persistenceChanges` → `PersistenceCoordinator` 去抖原子写；关闭浮窗时先 `flushPendingComposition()` 再 `saveFrame`，空白新笔记会被 `discardEmptyNote` 回收。
- 位置恢复与多笔记避让：`frameAutosaveName` + 26pt 级联（`:177-178`）+ `clamp` 到屏幕可视区（`:194`）。

已跑通的自动化验证：

```
$ WORKFOLLOW_DERIVED_DATA=/tmp/wf-dd WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 ./scripts/run-tests.sh FloatingNoteTests
Test Suite 'FloatingNoteTests' passed
  Executed 3 tests, with 0 failures (0 unexpected) in 0.187 seconds
```

三个用例：`testCreateCanReturnIDWithoutChangingSelection`、`testDiscardEmptyNoteOnlyRemovesUntouchedNote`、`testEditorPopupLevelFollowsFloatingOwnerOnly`。它们覆盖"创建不改变主页选中项""空白回收只删未动过的笔记""弹层层级跟随宿主",**不覆盖**焦点/滚轮/拖动/输入法（见 §9）。

---

## 3. 目标状态机

```
                openNewFloatingNote / open(noteID)
   [不存在] ────────────────────────────────► [Visible·Unfocused]
      ▲                                        │  orderFrontRegardless()，不激活 App
      │ close / Cmd-W                          │
      │                                        │ 用户点击笔记（真鼠标）
      │                                        ▼
      │                                 [Focused·key]
      │                                   │        ▲
      └───────────────────────────────────┘        │ 再次点击笔记
                                              用户点击 PDF → App 失活
                                              笔记 resign key，hidesOnDeactivate=false 保持可见
                                                       ▼
                                              [Visible·Unfocused]
```

| 状态 | key window | App 激活 | 键盘去向 | 滚轮（光标在 PDF 上） |
|---|---|---|---|---|
| Visible·Unfocused | 别的窗口/别的 App | 否 | PDF | 滚 PDF |
| Focused | 笔记 | 是 | 笔记 | 滚 PDF，**键盘仍在笔记** |

要点：

- 进入 Focused 时**不要**额外 `NSApp.activate`：探针 7 证明 `makeKeyAndOrderFront` 自带激活，仓库现在 `:56,:71,:77` 三处重复调用是冗余的（§5）。
- 离开 Focused（点 PDF）时**什么都不做**：不关窗、不隐藏、不清光标。设计依据是 `NSTextView` 在 resign key 时不 resign first responder、也不清 `selectedRange`，所以再点回来光标在原处。
  **这条没有实测到**：探针 17 里 `NSApp.deactivate()` 在脚本环境下没有真的生效（输出仍为 `active=true`），因此"笔记从 key 变非 key"那一步没被观察到。探针 17 只证明了另一件事：key 窗口从 `MAIN` 切到 `NOTE` 时，笔记编辑器的 `firstResp=NSTextView`、`sel={150,0}` 保持不变。真正的"笔记 resign key"必须真机确认，列入 §9 第 7 项。
- R6 天然成立：App 失活后按键给 PDF；要重新输入必须再点笔记（用户原话就是这个意思）。

---

## 4. 窗口配置（目标形态）

```swift
// NSPanel 子类
styleMask = [.titled, .closable, .resizable, .fullSizeContentView]  // 不加 .nonactivatingPanel：要打字
level = .floating                    // 盖住 L0 普通窗口
hidesOnDeactivate = false            // 点 PDF 时不消失
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // 跟到任何 Space / 全屏之上
becomesKeyOnlyIfNeeded = false       // 点正文就变 key
canBecomeKey = true
canBecomeMain = 见 §6.1              // 当前 false，建议改 true
isReleasedWhenClosed = false         // 由 controller 管生命周期
titleVisibility = .hidden / titlebarAppearsTransparent = true  // 自绘 header
```

展示分两种，必须区分：

```swift
// 只是打开/显示：不打扰用户正在看的 PDF
panel.orderFrontRegardless()

// 用户明确点了笔记：给键盘
panel.makeKeyAndOrderFront(nil)      // 不要再跟 NSApp.activate
```

---

## 5. 与现有代码的差距（只列差距，不改）

| 位置 | 现状 | 差距 |
|---|---|---|
| `FloatingNoteWindowController.swift:56,71,77` | `makeKeyAndOrderFront` 后又 `NSApp.activate(ignoringOtherApps: true)` | 冗余；且"打开即激活"会抢走 PDF 焦点。打开路径应改 `orderFrontRegardless` |
| `:245` `canBecomeMain = false` | 激活时会被提前的是大主窗口 | §6.1 |
| `NativeTextView` | 未覆盖 `acceptsFirstMouse` | 非激活态首次点击可能只激活、不落光标（待真机确认） |
| `FloatingNoteView.swift:102-103` | 正文背景 `onTapGesture` → `focusEnd()` | 与"点哪落哪"语义冲突：用户点第 3 行会跳到文末 |
| `CalendarSwipeGesture.swift:59` | 依赖 `NSApp.mainWindow` | 若笔记成为 main 窗口，日历横滑失效 |

---

## 6. 三个需要决策的设计点

### 6.1 激活会不会把 WorkFollow 主页顶到 PDF 前面

机制（探针 13 / 17）：笔记被点成 key 之后，App 的"main + key 窗口组"变成 `[mainWindow, 笔记]`。

- `canBecomeMain = false`（现状）→ 组里是 `[MAIN, NOTE]`：那个 800×520 的主页窗口仍持有 main 身份，激活时会被一起提前，可能把 PDF 盖住。
- `canBecomeMain = true` → 组里是 `[NOTE, NOTE]`：被提前的只剩笔记自己。

所以**建议 `canBecomeMain = true`**，让笔记在持有焦点期间同时充当 main window。代价与配套：

1. 语义上有点"借位"（main window 本该是主页），需要在代码注释里写清"why"。
2. `CalendarSwipeGesture.swift:59` 必须改成按窗口 `identifier` 认主页，否则日历横滑在笔记持焦期间失效。
3. 已有审计确认全仓只有这一处依赖 `NSApp.mainWindow`；`NSApp.keyWindow` 的使用（`AppCommands.swift:136,149` 撤销路由、`SidebarViews.swift:116` 等）在笔记持焦时指向笔记编辑器，属于**正确**行为。

**未验证（本节最重要的一条）**：`raiseSet` 只说明"哪两个窗口持有身份"，不能直接推出"其他 App 的窗口一定没被压住"。两次尝试跨 App 前后序测量都失败：

- 探针 16 用 `NSApp.hide` / `deactivate` 造"用户在看 PDF"的场面，脚本环境下 `active` 仍为 `true`，PDF 桩顺序没变，结果不可用；
- `NSApplication.h:222-236` 明确说程序化激活不保证成功，定时器里调用尤其不可靠。

所以"点笔记之后 PDF 是否仍完整可见"**必须在真机上肉眼确认**（§8 第 8 条 / §9 第 2 项）。在那之前，`canBecomeMain = true` 只能写成"依据 main/key 身份推断的更优选择"，不能写成"已验证解决"。

### 6.2 菜单栏会被换成 WorkFollow 的

想打字就必须激活 App，激活就会换菜单栏——这是 macOS 的硬语义，没有绕过办法（`.nonactivatingPanel` 能不换菜单栏，但不能打字）。产品上要不要接受？常见做法是接受（和 Spotlight/便签类工具一致）。若不接受，就只能退化成"只读悬浮窗"，与 R5 冲突。

建议：接受，但让"打开"不激活、"点击"才激活，把菜单栏切换的时机限制在用户主动点击时。

### 6.3 "鼠标移开，焦点就移开"这句话要按行为拆开读

用户原话 R2 是"如果鼠标移开笔记，焦点就移开，滑动滚轮可以直接操作另外一个页面"。这里"鼠标移开 → 焦点移开"有两种读法，必须选一种，因为它们的实现代价差一个数量级：

**读法 A（推荐）：把"移开"理解成"去操作别的窗口"**
点 PDF → 笔记失去 key → 键盘归 PDF、滚轮在 PDF 上滚。用户想要的三件事（能滚 PDF、键盘不误进笔记、点回来接着写）全部满足，且完全用系统原生语义，零全局监听。

**读法 B（字面）：光标一离开笔记矩形，焦点立刻移开**
macOS 的键盘焦点**不跟随光标**，只跟随点击（这是平台级设计，不是可配置项）。要按字面实现只有一条路：装一个全局 `mouseMoved` 监听，实时算光标是否在笔记 frame 内，出来就 `makeFirstResponder(nil)`、进去就还给编辑器。代价：

1. 全局鼠标移动监听要"输入监控"权限（本机实测 `CGPreflightListenEventAccess: false`，装不上就无法验证，用户端也会弹权限申请）；
2. 每次移出都打断输入法组字——中文打拼音打到一半光标滑出去，候选条会被取消，这在"一边看 PDF 一边记"的高频操作里几乎不可用；
3. 移回来还要猜用户想不想继续编辑，容易变成"光标路过笔记就把键盘抢回来"，反而破坏 R6。

**建议采用读法 A。** 它是用户描述的实际使用流程（"滑动滚轮可以直接操作另外一个页面""如果鼠标在笔记外点击了，那就无法输入到笔记中"——用户自己在后半句说的就是"点击"，不是"移动"）。读法 B 只作为候选记录在此，不建议实现。

---

## 7. 与现有 StickyNote 的边界

仓库已有 `StickyNoteWindowController`（每任务便签）：`.nonactivatingPanel` + `.floating` + 纯 `NSTextView` + 0.5s 去抖回写（`:161-167`），打开时对 `NSApp.activate` 有依赖（`:32-33,44-45`）。

两者定位不同，**不要合并**：

| | StickyNote（现有） | FloatingNote（本功能） |
|---|---|---|
| 承载对象 | 某个任务的便签 | 完整笔记（富文本、格式、清单） |
| 编辑内核 | 裸 NSTextView | `DocumentEditor` + `NoteDocumentProfile` |
| 是否吃键盘 | 不吃（nonactivating） | 吃（要真实打字） |
| 与主页关系 | 无 | 主页隐藏同一篇笔记的编辑器，避免双写 |

共享的只有"floating 层级 + 可拖 + 记位置"这点窗口外壳代码；可以抽一个小的 `FloatingPanelChrome` 帮助方法，但不建议动 StickyNote 的行为。

---

## 8. 验收标准

按用户六条需求逐条给出可执行判定（真机、鼠标操作）：

1. **R1**：打开 Preview 的 PDF，点笔记标题栏 → 笔记完整可见且不被 PDF 遮挡；把 PDF 切全屏 → 笔记仍在最上层。
2. **R2**：光标移到 PDF 上滚 → PDF 滚动、笔记内容纹丝不动；光标移回笔记上滚 → 笔记滚动。
3. **R3**：拖标题栏把笔记移到另一角 → 松手位置正确；退出 App 重开 → 位置复原；新建第二篇 → 级联偏移不重叠。
4. **R4**：PDF 上滚一页的同时在笔记里继续敲字 → 两者互不干扰。
5. **R5**：点笔记第 2 行 → 光标落在第 2 行（不是文末）；光标移到 PDF 滚动 → 键盘输入仍进笔记、落点仍是第 2 行；再点回笔记 → 光标仍在第 2 行。
6. **R6**：点 PDF 后直接敲键盘 → 字符进 PDF 阅读器，笔记不变。
7. **输入法**：切中文输入法，在笔记里打拼音 → 候选条正常出现、上屏正确；光标移到 PDF 滚动后再打 → 输入法状态正常。
8. **副作用**：点笔记后菜单栏变成 WorkFollow；PDF 窗口没有被 WorkFollow 主页盖住（§6.1 关键项）。

## 9. 尚未验证 / 需要真机实验

本机 `AXIsProcessTrusted: false`、`CGPreflightPostEventAccess: false`、`CGPreflightListenEventAccess: false`，合成鼠标/键盘事件投递不进去（探针 6、14 均为空结果），`System Events` 报 `-10004`。因此下列各项**只能在真机上手点验证**：

1. 非激活态第一次点击笔记正文，光标是否落下（`acceptsFirstMouse` 是否必须补）。
2. 点击笔记后，WorkFollow 主页是否被提前到 PDF 之上（决定 §6.1 是否必须采用 `canBecomeMain = true`）。
3. 中文输入法在"笔记 key → 点 PDF → 再点回笔记"一轮之后是否仍正常（候选条位置、上屏）。
4. 全屏 PDF 空间下笔记是否仍在最上层。
5. 拖动手感：`performDrag` 在跨 Space 拖动与"松手后不回调 mouseUp"情况下是否正常。
6. 滚轮惯性：在 PDF 上甩一下、光标随即移进笔记，惯性是否仍作用在 PDF（`NSEvent.h:354` 的 latch 语义）。
7. **笔记真正 resign key 的那一步**：点 PDF 让笔记失去 key 之后，编辑器是否仍保持 first responder 且 `selectedRange` 不变（§2.2 里"光标保留"目前只有 key 从 MAIN 切到 NOTE 的实测支撑，笔记自身 resign key 未观察到）。

结论：**机制层面方案成立（R1–R6 都有平台级依据），但 R4/R5 的最终成立依赖"激活不把主页顶上来"与"resign key 不清光标"两点，都必须真机确认后才可写进验收记录。** 在确认前不要把该功能标注为"已可用"。

### 证据文件清单（`docs/audits/floating-note-2026-10-25/`）

| 文件 | 证明的事 |
|---|---|
| `probe-show-without-activate.txt` | `orderFrontRegardless` / `order(above:)` 显示面板而不激活 App；`makeKeyAndOrderFront` 才激活 |
| `probe-makekey-activates.txt` | 单独 `makeKey()` 也会激活 → 激活由"成为 key"引起 |
| `probe-key-state.txt` | `.nonactivatingPanel` 的 `makeKeyAndOrderFront` 会重新激活 App；非激活态普通 NSPanel 不会变 key |
| `probe-pointer-hit-routing.txt` | `NSWindow.windowNumber(at:belowWindowWithWindowNumber:0)` 能按屏幕点解析最上层窗口（滚轮按指针路由的可验证入口） |
| `probe-result13-*.txt` / `probe-result17-*.txt` | 点击笔记后 main/key 身份归属；四种 styleMask 组合结论一致 |
| `probe-result15.txt` | `.fullSizeContentView` 决定自绘 header 是否可点（32pt 标题栏、命中 `NSButton` vs `NSThemeFrame`） |
| `probe-defaults.txt` | `NSTextView` / `NSScrollView` / `NSHostingView` 的 `acceptsFirstMouse`、`mouseDownCanMoveWindow`、`needsPanelToBecomeKey` 默认值 |
| `probe-result14-*.txt` | 合成点击投递失败的证据（本机无权限，因此该结论不采用） |
| `probe-result16-base.txt` | 跨 App 前后序测量失败的证据（不采用） |

## 10. 落地顺序建议（确认后执行）

1. 补 `acceptsFirstMouse`（`NativeTextView`）+ 去掉"点背景跳文末"的 `focusEnd` 覆盖。
2. 打开路径改 `orderFrontRegardless`，删掉三处冗余 `NSApp.activate`。
3. `canBecomeMain = true`，同时修 `CalendarSwipeGesture` 的窗口判定。
4. 真机跑 §8 八条，把实测数字写进本目录的验收记录。
5. 再考虑扩展（多屏跟随、磁吸、透明度、pin 状态）。
