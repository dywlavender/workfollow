# 快速添加条按滴答清单对齐（2026-09-28）

## 背景

`docs/quick-add-three-way-comparison-2026-09-28.md` 把 Flutter 版、本分支与滴答清单
TickTick 8.0.80 在「新建任务输入框」上的差异列了一张共同缺口表。本次按其中的
**P0 + P1** 三项改造列表快速添加条，并清理一处死代码。

依据仍是本机 `TickTick.app` 的中文语言包（`zh-Hans.lproj/Localizable.strings`）：

| 滴答原文 | 落地能力 |
| --- | --- |
| `敲击 Enter 添加任务；敲击 Tab 添加任务描述`、`Shift+↩︎ 可添加描述` | Tab / ⇧↩︎ 进入任务描述行 |
| `换行可添加多个任务`、`批量添加任务` | 一次提交按行创建多个任务 |
| `在添加任务时输入“#”可快速选择标签`、`Tag Recognition` = 标签识别 | `#` / `@` 实时候选列表 |

本次同时把这三项**接入全局快速添加面板**（滴答的对应说明是
`不用打开 App 即可快速输入，添加任务及描述到指定清单。` 与
`不用打开App即可快速输入，添加多个任务到指定清单，每一行输入都是独立的任务。`）。

## 一、Tab / ⇧↩︎ 进入任务描述

- 快速添加条在标题行下方多出一行描述输入（图标 `text.alignleft`，占位「添加描述」），
  位置紧贴标题，Tab 的落点就是「下一行」。
- 两个快捷键分工不同：`Tab` 在候选列表开着时**提交候选**，否则进描述行；
  `⇧↩︎` 按字面意思**总是**进描述行（候选列表让位收起，已输入的文字原样留着）。
  这与滴答同一屏里给的两条提示一致。
- AppKit 把 `⇧↩︎` 映射到 `insertNewlineIgnoringFieldEditor:`（`StandardKeyBinding.dict`
  里的 `~\r`），不是 `insertNewline:`——所以两者要分别接。
- 描述**不参与**智能识别——它是正文，不是标题的一部分。
- 描述随任务一起落库：`TaskActions.createDraft` / `TaskWorkspaceModel.createDraft`
  新增 `document: NativeDocument = .empty` 参数，在**同一个事务**里调用
  `setDocument`，与既有的 `setTags` / `setReminder` / `setRecurrence` 一致。
  空描述跳过写入，避免留下一个空段落。
- Esc 从描述行返回标题行（描述有内容时行不隐藏，与标题的两段式 Esc 同一取向）。
- 批量创建时**不带**描述：每一行各自成任务，共享同一段描述没有意义。

## 二、换行批量添加

- 提交时先按 `QuickAddComposition.batchLines(in:)` 拆行：归一化 CRLF/CR、去空白行、
  保留顺序。
- 单行时沿用整条草稿的解析结果——只有它带着 chip 删除（`dismissedQuickAddTokens`）的
  忽略状态；多行时每一行独立解析，行与行之间不互相污染。
- 日期 / 优先级 / 清单 / 标签的手动覆盖、以及「今天」视图的默认日期，对批量里的
  每一行同样生效。
- 只有当**一个任务都没建成功**时才保留草稿（沿用原「创建被拒时不清空」的约定）。

## 三、`#` / `@` 实时候选

- 输入末尾出现 `#片段` 或 `@片段` 时，条下方浮出候选列表：`#` 查已有标签、
  `@` 查已有清单，空片段先列出全部。
- 键盘：`↑`/`↓` 移动高亮、`Tab` 提交当前候选、`Esc` 收起；鼠标可点选、可悬停高亮。
- 提交候选会补全名字并补一个空格，末尾不再是标记片段，候选列表随即自行收起。

### 三个关键取舍

1. **只认输入末尾的片段。** 输入框是单行控件，用户几乎总是在行尾继续输入，而行尾判定
   不需要跟踪 `NSTextField` 的插入点——那是 AppKit 里最容易失同步的状态。代价是把光标
   移回句子中间编辑 `#标签` 时不会弹候选，需要重新输入该片段。
2. **用 `overlay` 而不是 `.popover`。** 候选列表要在用户继续打字时一直存在，而
   `.popover` 会生成真正的 `NSPopover` 抢走 first responder，键盘输入随即落到面板上、
   输入框中止。overlay 只借用绘制层，焦点始终留在 `NSTextField`。外层因此加了
   `zIndex(1)`，否则会被后面的任务列表盖住。
3. **回车永远提交任务，Tab 才提交候选。** 若让回车提交候选，用户输入 `买牛奶 #工作`
   后按回车会陷入「候选已精确命中 → 提交候选 → 文本没变 → 候选仍在」的死循环，永远
   建不出任务。另外当片段已经**精确等于**某个候选名时，候选列表会自行收起——没有可
   收敛的空间，此时应当把 Tab 与回车都还给用户。

## 四、清理

删除 `Features/Tasks/TaskList/QuickAddSchedulePopover.swift`：该视图全项目无调用点
（列表快速添加已改用 `TaskDatePopoverV2`）。其中仍在使用的 `QuickAddScheduleDraft`
移到同目录的 `QuickAddScheduleDraft.swift`。

> Flutter 侧未实例化的 `QuickAddField(listStyle: false)` 分支本次未动——它属于另一个
> 工作树（`feature/flutter-personal-desktop`），留待两侧同步时一并处理。

## 五、涉及文件

| 文件 | 变化 |
| --- | --- |
| `Features/Tasks/TaskList/QuickAddComposition.swift` | 新增。拆行、末尾片段识别、候选过滤、补全替换（纯逻辑）+ 候选/描述状态机 `QuickAddCandidateState` |
| `Features/Tasks/TaskList/QuickAddCandidateList.swift` | 新增。候选列表面板（列表条用 overlay，全局面板用内联） |
| `Features/Tasks/TaskList/QuickAddScheduleDraft.swift` | 新增。从被删文件移出仍在使用的草稿类型 |
| `Features/Tasks/TaskList/QuickAddTokenFlowLayout.swift` | `QuickAddTextField` 增加 `onTab` / `onShiftReturn` / `onMoveUp` / `onMoveDown` / `fontSize`；新增粘贴保换行 |
| `Features/Tasks/TaskList/TaskListView.swift` | 描述行、候选 overlay、键盘分层、批量提交 |
| `Features/QuickAdd/GlobalQuickAddController.swift` | 全局面板接入 Tab/⇧↩︎ 描述、换行批量、候选列表；面板高度改为按内容实测上报 |
| `Features/Tasks/TaskList/QuickAddSchedulePopover.swift` | 删除（无调用点） |
| `Application/TaskActions.swift`、`Features/Tasks/TaskWorkspaceModel.swift` | `createDraft` 增加 `document` 参数 |
| `WorkFollowTests/QuickAddCompositionTests.swift` | 新增。纯逻辑 + 状态机 + 粘贴保换行 + 按键路由 + 描述落库回归 |
| `WorkFollowTests/GlobalQuickAddTests.swift` | 新增 4 条接入回归（批量逐行解析、跳过无标题行、描述只跟随单条、空描述不写正文） |
| `macos-native/scripts/run-tests.sh` | 新增。在 `xcodebuild test` 挂住的环境里跑真实 XCTest |

## 六、验证

- `xcodebuild build-for-testing`：**TEST BUILD SUCCEEDED**（app 与测试目标均通过编译）。
- **真实 XCTest：453 个用例，0 失败**（快照，2026-09-28 14:20）。跑法见 `macos-native/scripts/run-tests.sh`：
  本机 `xcodebuild test` 会停在 `The test runner hung before establishing connection`，
  一个用例都不执行（不是代码问题——同一份产物里的 app 能正常启动并存活）。绕法是
  直接用 `xcrun xctest` 加载产物里的 `.xctest` 包，并在包内 `Contents/Frameworks`
  放几个符号链接满足 `@rpath`，从而不改动 DerivedData、也不用 `install_name_tool`。
- 本次相关用例：`QuickAddCompositionTests` 26 个、`GlobalQuickAddTests` 9 个，全部通过。
  覆盖拆行与 `CRLF` 归一化、末尾片段识别的正反例、候选过滤与上限、精确命中判定、
  补全后能被解析器识别、候选/描述状态机的按键分层、粘贴保换行、六个按键 selector 的
  路由、描述与批量落库。
- **粘贴保换行是实测出来的，不是推理出来的**：单行 `NSTextField` 的默认插入路径
  `insertText("red\ngreen")` 得到 `"red green"`（换行变空格），而赋值路径
  `field.stringValue = "alpha\nbeta"` 与 `editor.string = "gamma\ndelta"` 都保留换行。
  所以「换行可添加多个任务」必须拦截 `paste:` 自己接管，否则永远只剩一行。
- **`⇧↩︎` 走的是另一个 selector**：AppKit `StandardKeyBinding.dict` 把 `~\r` 映射到
  `insertNewlineIgnoringFieldEditor:`，不是 `insertNewline:`。
- **未在真机窗口人工确认**：候选列表的实际视觉位置、真实按键事件在活窗口里的端到端
  路径、描述行与候选列表的焦点交接。这三项需要人工点一遍。

## 七、与滴答仍存的差距

本次未做，仍留在缺口表里：

- 识别文本的「保留 / 移除」开关（滴答：`保留文本中的日期`、`移除任务标题中的标签`）。
- 输入框设置页（滴答：`输入框设置`、`显示快速添加条`、默认日期与默认提醒）。
- 点击正文里已识别的文本即取消识别（当前只能删 chip）。
- 候选列表只在行尾生效（见上文取舍 1）。
- 全局面板的 token chip 不可单独移除（列表条可删）。
- 剪贴板导入（滴答：`剪贴板中第一行是任务标题，其他行是任务描述`）。

细节对照见 `docs/quick-add-detailed-feature-matrix-2026-09-28.md`。
