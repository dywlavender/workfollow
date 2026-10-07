# 会议纪要页：转写与纪要改为同页左右并排（2026-10-06）

## 请求

> 采用左右布局的吧，然后对话记录支持滑动

即采用候选图里的 **方案 A**：详情栏内部再分两栏，**左「对话记录」右「滚动纪要」**，
两栏各自滚动、各自底部操作行，删掉原来的「对话记录 / 滚动纪要」segmented tab。

## 为什么删 tab 是对的

纪要与转写是**摘要 ↔ 依据**的关系——`MeetingStore.pumpMinutes()` 就是拿
「新增且未被总结的行」去更新纪要的。核对一条结论来自哪几句话，必须**对着看**，
而 tab 强制二选一，每次都要来回切。

数据层本来就支持这个改法：`MeetingRecord.summarizedLineIDs` / `summarizedLineCount`
让「哪些转写行还没进纪要」是可识别的（`transcript.filter { !done.contains($0.id) }`）。
分栏之后这条信息才有地方显示；分 tab 时它永远看不见。

## 改了什么

| 位置 | 改前 | 改后 |
| --- | --- | --- |
| 详情栏内容区 | 一个 `ScrollView` 包住整页 | `GeometryReader` 内两栏，各自 `ScrollView` |
| 内容切换 | `Picker(.segmented)` + `detailTab` 状态 | 删除。两样同时在场 |
| 转写行 | 「说话人 + 时刻」一行、正文一行 | 时间 / 说话人 / 正文 **三列**，一行一条 |
| 底部操作行 | 一条，随 tab 换内容 | 两栏各一条：左「记录者 + 手动补充对话 + 添加记录」、右「更新纪要 + 复制纪要」 |
| 进度显示 | 无 | 左栏表头「27 段 · 3 段未进纪要」 |
| 未进纪要的行 | 不可见 | 转写里画一条「以下 N 段尚未进入纪要」的分界线 |

新增 `Features/Meetings/MeetingMetrics.swift`（照 `WFCalendarMetrics` 的做法，
这一页专属的尺寸放 feature 目录，不往全局 `WFMetrics` 里塞）。

### 门槛与常量

- `MeetingMetrics.splitMinimum = 640`：详情栏 ≥ 640pt 才左右并排。
  两侧各约 320pt，扣掉内边距 24、时间列 34、说话人列 46、两个列间距 16，
  正文还剩约 200pt。默认窗口 1280 时详情栏是 `1280 − 62 − 340 − 1 = 877`，默认即并排。
- `minFraction / maxFraction = 0.28 / 0.72`：拖分割线时两侧的最小占比。
  存**比例**而不是绝对值，窗口缩放时两栏一起变。
- 分割线沿用列表列那条的做法：1pt 的线 + `WFSpace.sm` 宽的无形命中区 +
  `NSCursor.resizeLeftRight / resizeUpDown` + `DragGesture`。

### 窄窗口的回退（这是我替你定的，请确认）

详情栏窄于 640pt 时**自动改成上下堆叠**（纪要在上 45%、转写在下 55%，同样可拖）。
理由：两种形态都同时看得见两样东西，任何宽度下都不丢信息；退回 tab 就等于又把它藏起来。
如果你更想要别的（比如窄了就只留一栏、靠按钮切），告诉我改。

## 验收

构建 `BUILD SUCCEEDED`（只有两条既有无关警告：`FocusNotifier.swift:37`、
`WorkFollowApp.swift:41`）。

### 滚动独立性（真机合成滚轮事件，不是看代码）

窗口 1280×820，隔离数据（34 行转写、25 行纪要，两侧都溢出）：

| 操作 | 「对话记录」变化像素 | 「滚动纪要」变化像素 |
| --- | --- | --- |
| 在对话记录栏内滚动 | **240 604** | **0** |
| 再在滚动纪要栏内滚动 | **0** | **220 485** |

两栏各自滚动、互不影响。方法：`screencapture -l<winid>` 前后两张图，按两栏的
AX frame 裁切后逐像素比。**第一轮这个实验是无效的**——当时纪要只有 5 行、根本没溢出，
两栏都是 0；把纪要加长到 25 行才验出真结果。

### AX 结构

| 窗口宽度 | AXScrollArea | 位置与尺寸 |
| --- | --- | --- |
| 1280 | #2 对话记录 | `520,215 438x619` |
| 1280 | #3 滚动纪要 | `959,215 437x619` |
| 900 | #2 滚动纪要（上） | `520,215 496x240` |
| 900 | #3 对话记录（下） | `520,526 496x308` |

窄窗口下两块**都在**（240 + 308 = 548，加各自表头 30 / 底栏 38 正好填满），
不是藏起一块。

### 截图

`docs/screenshots/meeting-split-2026-10-06/`

- `01-wide-transcript-left-minutes-right.png`
- `02-transcript-scrolled-minutes-untouched.png`（能看到「以下 3 段尚未进入纪要」那条线）
- `03-minutes-scrolled-transcript-untouched.png`
- `04-narrow-stacked-fallback.png`

## 与示例图的一处**故意不一致**

示例图里把「尚未进入纪要」的转写行**调淡**了。实现时**没有调淡**，只画分界线。

原因：未进纪要的是**最新**的几段，不是最不重要的几段。调淡会读成「过期 / 已禁用」，
方向正好反了。示例图那版是我画错了，实现按修正后的做。

## 没做的事

- **没加自动滚到底**。录音中转写持续增长时是否要自动跟到最新一条，会和用户手动上翻
  打架，属于行为取舍，等你定。
- **没做点选联动**（点纪要里一条 → 左栏滚到对应位置）。示例图的「待确认」里列了它。
- 上一轮候选图里的另外两处（列表行补摘要、详情首屏压成一行元信息）**仍未改**。

## 数据安全

验收用隔离实例：`/tmp/wf-split/`，`WorkFollowAcceptanceStorageRoot` 在**构建之后**
用 `PlistBuddy` 指向 `/tmp/wf-split/data`，并改了 bundle id。
已确认用户真实数据未被写入：`~/Library/Application Support/WorkFollowNativePreview/modules/`
下没有 `meetings.json`（改前改后各查一次）。

⚠️ 老坑复现：`WorkFollow-Info.plist` 里该键的值是构建变量 `$(WF_ACCEPTANCE_STORAGE_ROOT)`，
**每次重建都会清空**，所以 `PlistBuddy Set` 必须放在构建之后。
