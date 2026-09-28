# 快速添加：剩余不一致审计（2026-09-28）

本文只回答一个问题：**除了已经修掉的「点击不展开」，还有哪些不一致？**

结论分两档，别混着读：

- **已实测**（跑起来观测过，附证据）
- **仅代码层**（读了代码得出，**没有**跑起来验证；标了原因）

---

## 〇、本轮修订（21:45）：§六 的三条已按方案改完并实测

> 审计出结论之后，按 §六 的建议顺序做了改造。**下面各节的结论有过期的地方，
> 已就地用「✅ 已修」/「⏳ 仍未验」标注**，别只看原文。

改动落在 3 个文件：`QuickAddTokenFlowLayout.swift`、`TaskListView.swift`、
`GlobalQuickAddController.swift`（+ 两个测试文件）。

| 项 | 状态 | 证据 |
| --- | --- | --- |
| §一 根因：聚焦意图改用 `@State` | ✅ 已修 | 见下方「实测证据」 |
| §二.1 Esc 两级语义 | ✅ 已修，与 Flutter 逐行一致 | 三下 Esc 的行为全对 |
| §三 面板落点（清单/标签） | ✅ 已修（**单测验证**，非目视） | `GlobalQuickAddTests` 3 条新用例 |
| §三 面板 chip 可点掉 | ✅ 已修（**单测验证**） | 同上 |
| §三 面板默认日期 | ⏳ 有意不齐（取舍，见 §三 脚注） | — |
| §五.1 面板自动聚焦 | ⏳ 仍未验（热键无法合成触发） | — |
| §五.2 列表条 Esc 重复消费 | ✅ 已定案：**不会**，且那层是死代码，已删 | 插桩计数 `field=1 view=0` |
| §五.3 退格键 | ⏳ 仍未查清（工具 vs 应用） | — |

### 补：用户报的另一个缺陷（不属本审计的分类，但记一笔）

**`⋯`（更多）按钮点了没反应** —— 不是逻辑问题，是**命中区域塌缩**：
`Image(systemName: "ellipsis")` 后面漏了 `.frame(...)` + `.contentShape(Rectangle())`，
`.plain` 按钮的命中区于是收缩到省略号的着墨范围，AX 报出来是 `12x2`（**2 点高**）。
实测只有 y=137–138 有反应，y=134 / 140 都无效。补上 `34x34 + contentShape` 后
有反应的区间变成 y=119–151（33 点）。详细定位过程、全仓同类扫描（43 处命中，
但脚本只能当线索）见 `quick-add-retrospective-2026-09-28.md` §八。

教训：**「点了没反应」要先分开「动作没执行」和「动作执行了但没点中」**，
扫一遍坐标量出命中区域的形状，比读代码快得多。

### 实测证据（列表条，pid 实测，AX 读数 + 截图）

| 动作 | 焦点元素 | 输入框宽度 |
| --- | --- | --- |
| 初始 | `AXScrollArea` | 328（收起） |
| **点输入框** | **`AXTextField`** | **283（展开）** |
| 打字 `abcde` | `AXTextField` value=`abcde` | 283 |
| **点条内空白处**（非输入框） | **`AXTextField`** | **283（展开）** ← 修复前无效 |
| 输入框聚焦时按 ↓ | 仍是 `AXTextField` | 283 ← 修复前会抢走列表选择 |
| 焦点不在输入框时按 ↓ | `AXScrollArea`，列表选中项移动 | 328 |

Esc 三级语义（逐条对齐 Flutter `quick_add.dart:379-394`）：

| 起始状态 | 按一下 Esc | 实测结果 | Flutter 期望 |
| --- | --- | --- | --- |
| 聚焦、草稿 `abcde` | 第 1 下 | 焦点 → `AXWindow`，**草稿保留**，仍展开（283） | 保留草稿 + `unfocus()` ✅ |
| 重新点回、聚焦、草稿 `abcde` | 第 2 下 | **草稿清空**，焦点保留（Flutter 的清空分支也不 unfocus） | `_resetDraft` ✅ |
| 聚焦、草稿为空 | 第 3 下 | 焦点 → `AXWindow`，宽度 → 328（收起） | `_escapePrimed = true` + unfocus ✅ |

**一次按键 = 一层**：插桩计数证实一次 Esc 只触发一次 `handleQuickAddEscape`
（`field=1 view=0`）。

截图已随文档存档（`docs/assets/`）：

- `assets/quick-add-collapsed.png` / `assets/quick-add-expanded.png` —— 收起 / 展开对照
- `assets/quick-add-tap-blank-bar.png` —— 点条内空白处也展开（修复前无效）
- `assets/quick-add-list-arrow-negative-control.png` —— 负对照：焦点不在输入框时 ↓ 才移动列表选择

### 顺带查明的两条工具事实（写下来，省得下次重踩）

1. **`sed -i ''` 会留下 `.!<pid>!<name>` 临时文件**，沙箱拦掉清理时它就留在源码目录里。
   工程用 `PBXFileSystemSynchronizedRootGroup`，**目录里所有文件都会被编译**，
   于是报 `invalid redeclaration of '<TestClass>'`——看起来像重名类，其实是垃圾文件。
   症状：`WorkFollowTests/.!3192!XxxTests.swift`。
2. **用 `open` 之外的方式启动的 app 会随 shell 一起死**（`nohup`+`disown` 也不行），
   而 `open` 启动的进程 stderr **拿不到**。所以「插桩 + 抓 stderr」这条路在
   macOS GUI 上要靠**让 app 自己写文件**，不能指望 stderr。本轮就是这么定案的。

---

## 一、一类系统性缺陷：`@FocusState` 死信号

这是最值得先修的一条，因为它**一次影响两个入口、约 15 个调用点**，而且症状散落在
「Esc 没反应」「新建后焦点丢了」「快捷键没反应」这些看起来互不相关的现象里。

### 机制

`QuickAddTextField` 是 `NSViewRepresentable`。它把 `focused: FocusState<Bool>.Binding`
当参数收进来，在 `updateNSView` 里读 `focused.wrappedValue` 决定要不要
`makeFirstResponder`。但**它没有 `.focused()` 修饰符** —— `NSViewRepresentable` 用不了。
SwiftUI 因此不为它维护焦点状态：

- 往里写 `wrappedValue = true` **不生效**（delegate 里写了也没用）
- 读出来**永远是 false**

已实测：插桩后日志里 `quickAddFocused=false` 贯穿始终，即使输入框明明拿到了焦点。

### 受影响清单

**列表条** `TaskListView.swift`：

| 位置 | 代码 | 实际后果 |
| --- | --- | --- |
| :67 | `.onChange(of: environment.quickAddRequest) { quickAddFocused = true }` | 外部「请求聚焦快速添加」**无效** |
| :73 | 关闭日期浮层后 `quickAddFocused = true` | 关掉日期浮层后**焦点不回来** |
| :84 | 关闭属性浮层后 `quickAddFocused = true` | 同上 |
| :94 | `.onAppear` 里的 `quickAddFocused = true` | 启动时若带 quickAddRequest，**不聚焦** |
| :220 | `focused: $quickAddFocused` | `updateNSView` 的正向聚焦分支**永不执行** → 程序化聚焦全废 |
| :370 | `.onTapGesture { quickAddFocused = true }` | 点空白处展开**无效**（只能点中输入框） |
| :438 | `commitCandidate` 里 `quickAddFocused = true` | 提交候选后**不恢复焦点** |
| :449 | `closeDescriptionRow` 里 `DispatchQueue.main.async { quickAddFocused = true }` | 从描述行返回后**焦点丢失**（既不在标题也不在列表） |
| :463 | `quickAddExpanded` 以 `quickAddFocused \|\|` 开头 | 该项**恒为假**，靠 `fieldFocused` 兜住 |
| :558 | `handleQuickAddEscape` 开头 `guard quickAddFocused` | **Esc 整个失效**（已实测，见 §三.1） |
| :566 | `quickAddFocused = false` | 无效 |
| :699/704/709/714 | 列表按键 `guard !quickAddFocused` | **恒为真**，这些守卫等于没写 |
| :843 | 提交成功后 `quickAddFocused = true` | 连续录入靠「Enter 不夺焦」侥幸成立，不是这段代码的功劳 |

**全局面板** `GlobalQuickAddController.swift`：

| 位置 | 代码 | 实际后果 |
| --- | --- | --- |
| :253 | `@FocusState private var inputFocused` | 同类死信号 |
| :289 | `.onAppear { DispatchQueue.main.async { inputFocused = true } }` | **打开面板不自动聚焦输入框**（推断，见 §五） |
| :306 | `focused: $inputFocused` | 同上，正向聚焦分支永不执行 |
| :414 / :420 | `inputFocused = true` | 无效 |
| :372 | `candidate.marker(in: text, isFocused: inputFocused \|\| fieldFocused)` | 靠 `fieldFocused` 兜住，**唯一没坏的一处** |

> 这两个入口的 `fieldFocused`（控件 → SwiftUI 的上报）都是可靠的 —— 上一轮修「点击不展开」
> 时补的。所以**候选列表和展开本身能用**，坏掉的是「程序化聚焦」与「依赖焦点真值的判断」。

### 不是同类问题的（别误伤）

`TaskInspectorShell.titleFocused`（:13）看起来一样，但它传给的是 `TaskTitleField`
—— 一个普通 `View`，内部有真正的 `.focused($focused)` 绑定。**它是好的。**
其余 `@FocusState`（`descriptionFocused`、`listFocused`、`searchFocused`、
`focusedTitle`、`CommandPaletteView.focused` 等）都有 `.focused()` 绑定，**都没问题**。

判定方法：`@FocusState` 声明处对照 `.focused($变量)` 是否存在。没有绑定的就是死的。

---

## 二、与 Flutter 参照物的行为差异

### 1. Esc 的两级语义 —— 不一致（已实测）

| | Flutter | 原生 |
| --- | --- | --- |
| 第一下 | `_escapePrimed = true` + `focus.unfocus()` → **条立刻收起** | 什么都不发生 |
| 第二下 | 只有在**重新点回输入框**后才可达 → 清空草稿 | 什么都不发生（焦点没丢，所以还能继续按） |

实测：点开输入框后连按两次 Esc，焦点仍是 `AXTextField`、宽度仍是 283（展开态），
草稿仍在。**原生 Esc 完全没有效果**，既不清空也不收起。

Flutter 的 `expanded` 依赖 `focused`，而 `unfocus()` 会真的把 `focused` 变假 → 收起。
原生这条链路断在死信号上（§一）。

### 2. 展开判据本身 —— 一致

Flutter `quick_add.dart:640-645`：
`expanded = focused || customDate || text.text.isNotEmpty || parse.spans.isNotEmpty || _propertiesOpen || _scheduleOpen`

原生 `TaskListView.swift:462-467` 逐项对得上（`customDate`↔`quickAddScheduleOverride`、
`_propertiesOpen`↔`showQuickAddProperties` 等）。**两边都是「聚焦即展开」，这点没错。**
原生多出的 `description*` 三项对应描述行（Flutter 没有这个概念）。

### 3. 按键 —— 原生是超集，属于有意扩展

Flutter `quick_add.dart:670-673` 只处理**一个** `LogicalKeyboardKey`：`escape`。
原生多了 `onTab`（提交候选/进描述行）、`onShiftReturn`（进描述行）、
`onMoveUp/onMoveDown`（候选选择）。代码注释里有对齐滴答文案的说明，算**有意扩展**，
不是漏抄。唯一要注意的是 **Tab**：Flutter 里 Tab 是焦点遍历，原生里 Tab 变成「进描述行」。

### 4. 提交后 —— 一致

两边都是「成功才清空、失败保留」，并且都意图保持焦点以便连续录入。
原生 `quickAddFocused = true` 是无效写，但 Enter 本身不夺焦，所以**结果上一致**。

---

## 三、原生两个入口之间的差异

列表条（`TaskListView.quickAddBar`）与全局面板（`GlobalQuickAddPanelView`）
共用 `QuickAddComposition` 与同一个 AppKit 桥，但**上层行为差得比想象中多**：

| 维度 | 列表条 | 全局面板 | 影响 |
| --- | --- | --- | --- |
| 落到哪个清单 | `… ?? parsed.listName ?? workspace.activeList ?? 收集箱`（:818） | `parsed.listName ?? 收集箱`（:37） | 面板建的任务**永远进不了当前清单** |
| 当前标签 | 注入 `workspace.activeTag`（:820） | 无 | 面板建的任务**不继承当前标签** |
| 默认日期 | `.today` 视图下默认今天（:815） | 恒 `defaultDueAt: nil`（:35） | 面板建的任务**默认无日期** |
| 识别 chip | 可点掉（Button，:320-336） | 纯 `Text`，**点不掉**（:337-350） | 面板里识别错了**没法撤销** |
| 摘要行 | 有 `quickAddSummary`（:340-348） | 无 | |
| 批量提示 | 无 | 有「换行将创建 N 个任务」（:264-269） | |
| 属性入口 | 日期浮层 + 属性浮层（:230-291） | **无** | 面板只能靠打字设属性 |
| 候选列表位置 | 浮层 overlay（:364-369） | 内联撑高面板（:270） | 渲染差异 |
| 提交后 | 保持打开、可连续录入 | `close()` 关掉面板（:172-175） | 有意为之 |
| Esc 终态 | 清空但仍打开 | `close()` 且**丢弃草稿**（:424-434） | 面板里误按 Esc 丢内容 |

最后一条值得单独看：**全局面板按 Esc 直接丢弃草稿**，而列表条是保留的。

---

## 四、单向特性

**Flutter 有、原生没有**：`listStyle: false` 的卡片变体（带内联优先级/清单/标签/
提醒/重复按钮 + 「添加任务」按钮，`quick_add.dart:827-918`）。
注意：**它在 Flutter 里是死代码** —— 唯一调用点 `today_screen.dart:244` 传的是
`listStyle: true`。所以不迁移是合理的。

**原生有、Flutter 没有**：换行批量创建、Tab/Shift+Return 描述行及其随任务落库、
`#`/`@` 候选列表与方向键选择、粘贴保换行、全局 ⌘⇧A 面板。
这些是原生侧的扩展，不是漏抄。

**语义一致但实现不同**：识别项的「点掉后不再识别」—— Flutter 用遮罩重解析
（`quick_add.dart:198-264`），原生用 `dismissedRanges` 求交后重解析
（`QuickAddParser.swift:320-326`）。用户可见结果相同。

---

## 五、没能验证的项（如实列出）

1. **全局面板的自动聚焦**。代码上 `inputFocused` 是死信号（§一），
   且 `panel.initialFirstResponder = hosting`（`GlobalQuickAddController.swift:213`）
   把焦点给了宿主视图而不是输入框 —— 按代码推断**打开面板后打字会没反应**。
   **但没实测成功**：该面板靠 Carbon `RegisterEventHotKey` 触发，
   实测合成键盘事件（`CGEvent`，含 `.cghidEventTap`）**不能触发 Carbon 热键**，
   面板弹不出来。而且它是默认关闭的开关项，无法用常规入口进入。
   **要坐实需要人工按一次 ⌘⇧A**（开关在「导航」菜单里）。
2. **列表条 Esc 是否被消费两次**。`TaskListView.swift:99` 有一层
   `.onExitCommand(perform: handleQuickAddEscape)`，字段自身 `onEscape`（:222）
   又是一层。一次按键是否会同时走到两层、从而一次吃掉两级，**代码判不了**，
   需要在这两个入口各插一行日志数调用次数。
3. **退格键**。在已聚焦的输入框里发 keycode 51 没有生效，未查清是测试工具的问题
   还是应用的问题。

---

## 六、建议的修复顺序

1. **把「聚焦意图」从 `@FocusState` 换成可靠的 `@State`。**
   这是根因，一次能解掉 §一 的 15 个点、§二.1 的 Esc、§三 里面板的自动聚焦。
   做法：`quickAddFocused` / `inputFocused` 改成普通 `@State`，
   `updateNSView` 按它决定 `makeFirstResponder(field)`；
   反向仍用已经可靠的 `onFieldFocusChange`。改完 `guard quickAddFocused` 之类的
   守卫会自动恢复意义。
2. **Esc 的两级语义对齐 Flutter**：第一下收起（`makeFirstResponder(nil)` 或把
   意图状态置假），第二下清空。顺手确认 :99 那层是否重复消费。
3. **收敛两个入口的差异**：至少把「当前清单 / 当前标签 / 默认日期」三项对齐，
   以及让面板的 chip 可点掉 —— 这几项直接决定任务落到哪里，属于会丢数据的差异。
4. 退格键问题待查（先确认是工具还是应用）。
