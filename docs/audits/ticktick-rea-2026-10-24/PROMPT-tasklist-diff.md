# 可直接粘贴的提示词：任务栏差异分析

> 用途：在 DSH / Claude Code / Codex 里对 rea 说这段话。
> 前置：`rea setup --client <你的客户端>` 已完成，且会话里能看到 `mcp__rea__*` 工具。
> 已有产出：`docs/audits/ticktick-rea-2026-10-24/task-list-gap-analysis.md`（282 行，6 个缺口 + 3 个行为差异）。
> 本提示词默认你要的是**增量复核 + 补证据**，不是从零重做；如需重做，把「增量」那句删掉。

---

## 提示词正文（从这里开始复制）

用 rea 对 `/Applications/TickTick.app`（8.0.80，sha256 `752e2c05…`）做任务栏差异分析，输出写到 `docs/audits/ticktick-rea-2026-10-25/tasklist-diff.md`。

### 1. 先把「任务栏」这个词钉死

我指的是**主窗口中间那一列任务列表**：顶栏（标题/共享/筛选/AI）+ 快速添加条 + 分组头 + 任务行 + 空态。

**不含**左侧导航栏、右侧详情栏、看板、时间轴、日历——那些另有审计，串进来会稀释结论。

如果你对范围有疑问，先问，不要自己扩大。

### 2. 滴答侧：用 nib 拿结构，不要拿二进制硬解

目标 nib 只有 8 个，全部在 `Contents/Resources/` 下：

```
TTTaskListViewController.nib     143 objects / 40 connections
TTTaskListStandardCell.nib       117 objects / 31 connections
TTTaskListDetailedCell.nib       156 objects / 39 connections
TTTaskListSectionCell.nib         69 objects / 14 connections
TTTaskListInputView.nib          133 objects / 38 connections
TTTaskListInputMenuViewController.nib  34 / 4
TTTaskListCountdownCell.nib       28 / 6
TTTaskListHabitCell.nib           49 / 14
```

**关键坑（我已实测）**：直接 `open_binary /Applications/TickTick.app` 再
`decode_interface_builder`，`max_documents` 上限是 **64**，而 TickTick 有 **442 个 nib**；
前 64 个会被 Sparkle、日历、倒计时那些挤满，8 个任务栏 nib 里只挤进去 4 个，其余报
`omitted because max documents`。直接调大 `max_documents` 会撞 schema 上限（≤64）。

**绕法（已验证有效）**：在 workspace 里拼一个只含目标 nib 的迷你 bundle，再 open 它。

```bash
mkdir -p .probe/TaskListProbe.app/Contents/{MacOS,Resources}
cp /Applications/TickTick.app/Contents/MacOS/TickTick .probe/TaskListProbe.app/Contents/MacOS/
cp /Applications/TickTick.app/Contents/Resources/TTTaskList*.nib .probe/TaskListProbe.app/Contents/Resources/
cp /Applications/TickTick.app/Contents/Info.plist .probe/TaskListProbe.app/Contents/
```

然后 `open_binary .probe/TaskListProbe.app` → `decode_interface_builder`（detail=summary），
一次就能拿到全部 8 个 nib：**947 nodes / 517 edges**（outlet 157、action 27、
target_action 81、objc_selector 26）。分析完记得 `rm -rf .probe` 并 `close_binary`。

要提取的东西（每个 nib 都要）：

- **outlet 清单**：名字 + 类名 + `NSFrame` 几何（`{{x,y},{w,h}}`）——几何是判断
  「留白/命中区/密度」的硬证据，比截图可靠
- **target-action 连接**：`selector → 目标对象`，这是「滴答有哪些动作入口」的唯一来源
- **资源名**：`NSResourceName`（如 `add` / `more` / `arrow_down` / `section_icon_pinned`），
  说明图标语义
- **控件类**：`TTThemeButton` / `TTHoverableImageView` / `TTLabel` 这类自定义类名，
  能反推交互（hoverable = 悬停才出现）

### 3. 本地侧：对着源码读，别猜

```
macos-native/WorkFollow/Features/Tasks/TaskList/            36 个文件 / 8158 行
  TaskListView.swift                    2114 行  ← 主视图，先读这个
  TaskGroupHeaderActions.swift            95 行  ← 分组头动作
  NativeTaskOutline.swift                       ← NSOutlineView 桥接
  TaskBulkActionBar.swift                       ← 现有多选动作条
  QuickAddBarStyle.swift                        ← 快速添加条
macos-native/WorkFollow/Application/TaskViewPreferences.swift ← 视图偏好
```

### 4. 输出要求

一张主表，每行一个差异：

| # | 缺口 | 滴答证据（nib + 对象/几何/selector） | 本地现状（文件:行号） | 用户影响 | 优先级 | 工作量 |
|---|---|---|---|---|---|---|

- **优先级**：P0 影响日常操作 / P1 对齐后有实感 / P2 长尾细节
- **工作量**：S ≤ 半天 / M 1–2 天 / L 3 天以上
- 每条差异必须**两侧都有证据**。只看到滴答有、本地没找到 → 标「本地未实现（已搜 X/Y 关键词）」，
  不要直接判定「本地没有」
- 证据不足的单列一节「待确认」，写清楚**缺什么证据、补什么命令**，不要编

最后给：
1. **如果只做三件事** —— 挑投入产出比最高的三项，说明为什么是这三项、彼此会不会打架
2. **明确不做的清单** —— 依赖云端/AI 的功能（共享、AI 推荐任务）直接标不做，写原因，避免下一轮反复讨论
3. **与既有审计的增量** —— 对比 `task-list-gap-analysis.md`，只列「新增/推翻/补强」的部分

### 5. 约束（很重要，别越过）

- **当前没有 Hopper / Ghidra / IDA**。所以：
  - ✅ 能做：nib 解码、plist、Mach-O 头、dispatch 元数据、资源名、几何
  - ❌ 不能做：伪代码、xrefs、函数追踪、`decompile`、`search-bytes`
  - 需要「点击后调什么函数」这类结论时，**明确说这条卡在缺引擎**，不要用 nib 的
    selector 存在性去充当「实现存在」的证明（rea 自己的 limitation 就写了：
    *target-action selector 是 IB 观察，不证明二进制里有对应实现*）
- 不修改 `macos-native/` 下的任何源码，本次只出分析
- 分析结束 `close_binary`，删掉 `.probe`

### 6. 验收标准

我会这样检查你的产出：

- 每条 P0/P1 差异都能点开一个 nib 对象或一行源码指过去
- 主表里没有「滴答有 / 本地可能有」这种含糊表述
- 「待确认」一节的每条都给了可执行的下一步命令
- 结论没有超出 nib + 源码能支撑的范围（比如不要断言运行时行为）

---

## 提示词正文结束

---

## 为什么这么改（给你看，不用贴给别人）

原提示词的问题在于三处歧义 + 一处硬坑：

| 问题 | 后果 | 改法 |
|---|---|---|
| 「任务栏」有三种理解 | 分析会漂到侧边栏/详情栏 | 第 1 节先钉死范围，并授权它反问 |
| 没说滴答侧怎么取证据 | 它会去 `open_binary` 整个 app，撞 64 文档上限，只拿到 4/8 个 nib | 第 2 节给出迷你 bundle 绕法（实测有效） |
| 没说本地侧看哪里 | 会去 grep 整个仓库，把 `design-preview/` 也算进来 | 第 3 节给出确切路径和行数 |
| 没声明缺引擎 | 它会尝试 `decompile` 然后报 `missing_analysis_engine`，浪费几轮 | 第 5 节说清能力边界，并提醒 nib selector ≠ 实现存在 |

另外加了两条针对你项目习惯的：**优先级/工作量口径**（跟你其他审计一致）、
**「明确不做」清单**（你 10-24 那份里 2.9 节已证明这个能省掉反复讨论）。
