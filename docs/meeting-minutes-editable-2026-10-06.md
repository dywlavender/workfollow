# 会议纪要页：纪要改为可直接编辑（2026-10-06）

## 请求

> 会议纪要改成可编辑的就好了，不用单独做一个更新纪要的按钮

上一轮刚把「对话记录 / 滚动纪要」从 segmented tab 改成同页左右并排
（见 `meeting-split-2026-10-06.md`）。这一轮改的是右栏本身：**从只读投影变成可编辑**，
底栏的「更新纪要」按钮删掉。

## 改了什么

| 位置 | 改前 | 改后 |
| --- | --- | --- |
| 右栏正文 | `MeetingMinutesView` 只读投影（渲染 Markdown） | `TextEditor`，直接写 |
| 底栏 | 「更新纪要」+「复制纪要」 | 「复制纪要」；手动接管后多一条「交回自动更新」 |
| 右栏表头 | 恒为「更新于 hh:mm」 | 手动接管后改显「已手动编辑」 |
| 左栏表头 | 恒为「N 段 · M 段未进纪要」 | 手动接管后只报「N 段」 |
| 左栏分界线 | 恒画「以下 M 段尚未进入纪要」 | 手动接管后撤掉 |

新增的落盘字段：`MeetingRecord.minutesEditedByUser`。

## 关键设计：为什么必须有「手动」这个标记

纪要原来是 Pi 每 25 秒重写一次的。**如果只把视图换成可编辑、别的都不动，
用户敲进去的字会在下一次心跳里被整段冲掉。** 所以「可编辑」这个要求本身
就要求引入一个接管标记：

- 第一笔输入 → `minutesEditedByUser = true`；
- `pumpMinutes` 里一条守卫（`!meeting.minutesIsManual`）拦住 Pi——
  守卫放在**这一处**而不是各调用点，心跳 / 停止录音 / 转写完成 / 手动触发
  四条路径就都覆盖到了；
- 请求在飞行途中用户动手编辑的，回写前**再查一次**标记，那一份结果作废，
  否则等于把刚敲的字盖回去。

### ⚠️ 这个字段必须是可选类型

```swift
var minutesEditedByUser: Bool?      // ✅
var minutesEditedByUser = false     // ❌ 会让所有存量文件解码失败
```

Swift 合成的 `Codable` **不会**用属性默认值去填缺键——实测：

```
DecodingError.keyNotFound: Key 'flag' not found in keyed decoding container.
```

存量 `meetings.json` 里没有这个键，声明成非可选 `Bool = false` 的话，
用户打开 app 就是一条会议都没有（解码整体失败）。与 `CountdownEvent.displayUnit`
同一个套路。留了回归用例 `testLegacyRecordWithoutManualFlagStillDecodes`。

### 留了一条退路

手动接管是**单向**的：不给人退路的话，误敲一个字就永远失去自动更新。
所以底栏在接管状态下才露出「交回自动更新」——与工具栏「补转写」同一个口径，
只在真能做点什么的时候出现。

交回时**不清空**用户写的内容：它会作为「已有纪要」成为下一次更新的基底
（`MeetingMinutesPrompt.make(minutes:lines:)` 就是这么用的），所以手动补充的事实不丢。

## 取舍：Markdown 渲染没有了

原来 `MeetingMinutesView` 会把 `## 标题` 渲染成标题、`- 项` 渲染成 `• 项`。
`TextEditor` 显示的是 Markdown **源码**，那些符号会直接露出来。

这是「可编辑」换来的：一个可编辑控件只能显示源码。要两样都有就得加一个
「预览 / 编辑」切换——那是额外的控件，这次没加（你说的「就好了」）。
**要的话说一声，`MeetingMinutesView` 那 40 行我可以加回来做成切换。**

## 验收

构建 `BUILD SUCCEEDED`（只有三条既有无关警告：`WorkFollowApp.swift:41`、
`FocusNotifier.swift:37`、`TaskBatchPanelView.swift:187`）。

隔离实例 `/tmp/wf-edit/`，数据在 `/tmp/wf-edit/data`，34 段转写的夹具
（**故意不含 `minutesEditedByUser` 键**，顺便验证存量文件仍能解码）。

### 真机 AX 读数（不是看代码）

| 时刻 | 左栏表头 | 右栏表头 | 分界线 | 底栏按钮 |
| --- | --- | --- | --- | --- |
| 编辑前 | `30 段 · 3 段未进纪要` | `更新于 18:12` | `以下 3 段尚未进入纪要` | 复制纪要 |
| 敲入一个字后 | `30 段` | `已手动编辑` | 消失 | 复制纪要 · Pi 已停止自动更新 · 交回自动更新 |
| 点「交回自动更新」后 | `30 段 · 3 段未进纪要` | `更新于 18:12` | 回来了 | 复制纪要 |

右栏正文的角色是 **`AXTextArea`**（`851,203 421x603`）——即真的是可编辑控件，
不是一个套了边框的只读文本。输入用合成键盘事件（`keyboardSetUnicodeString`），
25 个字符含中文，耗时 0.687s（含工具内的 240ms 固定等待），**没有输入迟滞**。

### 落盘确认

编辑后读 `/tmp/wf-edit/data/modules/meetings.json`：

```
minutesEditedByUser = True
包含【我手写补充】: True
```

点「交回自动更新」后再读：

```
minutesEditedByUser = <键不存在>     ← nil 不落盘
我写的内容还在 = True                ← 交回不清空
```

### 窄窗口

900pt 宽（详情栏 < `MeetingMetrics.splitMinimum 640`）下自动上下堆叠，
纪要编辑区 `412,203 480x224` 在上、对话记录 `404,506 496x308` 在下，
两栏的底栏按钮都在。

### 截图

`docs/screenshots/meeting-minutes-editable-2026-10-06/`

- `01-minutes-is-now-an-editor.png`
- `02-after-manual-edit.png`
- `03-narrow-stacked-still-works.png`

## 顺带修的一个缺陷

「交回自动更新」最初写成 `if !blockedMinutes.contains(id) { 排队 }`——
但 Pi 失败过一次之后这一条是被 `blockedMinutes` 封住的，光清接管标记它也不会再跑，
**按钮会变成点了没反应**。改成显式 `blockedMinutes.remove(id)`（与
`updateMinutesNow()` 同口径）。这是验收时看到隔离环境里 Pi 失败报错才发现的。

## 没做的事

- **没做 Markdown 预览切换**（见上面的取舍）。
- **没做编辑的撤销 / 历史**。要回滚只能靠 `backups/` 里的日备份。
- 上一轮候选图里的另外两处（列表行补摘要、详情首屏压成一行元信息）**仍未改**。
- 窄窗口回退形态仍是上一轮我替你定的，**仍待你确认**。

## 数据安全

隔离实例的 `WorkFollowAcceptanceStorageRoot` 在**构建之后**用 `PlistBuddy`
指向 `/tmp/wf-edit/data`，bundle id 也改了。
已确认用户真实数据未被写入：`~/Library/Application Support/WorkFollowNativePreview/modules/`
下没有 `meetings.json`。

⚠️ 老坑复现：`WorkFollow-Info.plist` 里该键的值是构建变量
`$(WF_ACCEPTANCE_STORAGE_ROOT)`，**每次重建都会清空**，所以 `PlistBuddy Set`
必须放在构建之后。
