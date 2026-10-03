# 选中行的分割线：底边蓝色描边被盖掉（2026-10-03）

用户报：「任务的下面一半怎么不是一样的蓝色」，附一张选中行的 2× 截图
（`screenshots/selected-row-divider-2026-10-03/before-user-screenshot.png`，
676×140，即逻辑 338×70，选中行本体 50pt）。

## 一、现象与实测

在用户那张截图上逐行取中位色，选中行（逻辑 y 475→525）的纵向剖面是：

| 逻辑 y | 内容 | 中位色 |
| --- | --- | --- |
| 474.0–474.5 | 上一行的分割线 | `(244,244,244)` |
| **475.0–475.5** | 选中框**上**描边 | `(187,188,243)` 连续 610px |
| 476–523.5 | 选中底色 | `(239,239,252)` |
| **524.0–524.5** | 选中框**下**描边 | 只有 **70** 个像素是描边色 |

也就是说：**上、左、右三边和两个圆角都有蓝色描边，唯独底边中间那段没有**
——底边只剩左右两个圆角是蓝的，中间被 1pt 的 `#F4F4F4` 盖住。放大 3× 看
（`before-after.png` 上半），左角之后蓝色描边就断了。

「下面一半不是同一个蓝」说的就是这个：蓝色的块看着像被削掉了一条边。

## 二、成因

上一版 `274932a0` 把分割线从 `LazyVStack` 的**兄弟视图**挪进了行内的
`.overlay(alignment: .bottom)`。好处是行距不再每行多出 1pt（pitch 从
51/56 回到 50/55）；代价是 **`.overlay` 画在 `.background` 之上**：

```swift
.frame(minHeight: WFMetrics.rowHeight)
.background(selected ? WFColors.selection : …, in: RoundedRectangle(…))  // 底色
.overlay { if focused { RoundedRectangle(…).strokeBorder(WFColors.focusRing) } } // 焦点环
// ← 274932a0 新增：再叠一层分割线，于是它压在焦点环的底边之上
```

兄弟视图版本永远压不到行自己身上，所以这个现象是**上一版引入的新缺陷**。
另外笔记列原本有 `if visibleNote?.id != note.id { Divider() }`——即
「选中行不画线」这条规则本来就在，是我这轮统一两栏时把它删掉了。

## 三、滴答怎么做的（实测）

选中滴答「今天」列表里的 `codex` 行（`ax2 select`，只读），2× 截图取像素：

- 选中行灰底 `(242,242,242)`，**整行满宽、满高**，上下都**没有分割线**；
- 未选中行的分割线在 `ly = 273.0 / 334.0 / 395.0 / 456.0 / 618.0`，
  1pt `(244,244,244)`，左内缩 53pt、右端到 617.5（让开常驻滚动条）；
  **唯独紧贴选中行的 517.0 和 578.0 两条不见了**。

结论：滴答在选中行上不画分割线。我们照这条做。

## 四、改法

选中行不画这条线，两栏都改：

- `TaskListView.swift`：把 `selected:` 的内联表达式提成 `let isSelected`，
  分割线的 overlay 加 `if !isSelected`。
- `NotesWorkspaceView.swift`：恢复 `if visibleNote?.id != note.id`。

未选中行的分割线位置、颜色、左右内缩**不变**（任务列 302..571.5、
笔记列 282..578，色 `#F4F4F4`），行距仍 **50 / 55**。

## 五、验收（工作树构建，非 HEAD 归档）

`HEAD + 本次改动` 在独立工作树 `/tmp/wf-verify-sel` 构建通过，启动后：

| 项 | 实测 |
| --- | --- |
| 选中行蓝底高度 | ly 475.0 → 524.5 = **50.0pt** |
| 底边描边 | **616px 连续**（改前 70px，只有两个圆角） |
| 选中行处的灰线 | **0 条**（改前 1 条压在底边上） |
| 其余分割线 | ly 264 / 314 / 369 / 419 / 474，x 302..571.5，`(244,244,244)` |
| 行距 | 50 / 55（未变） |
| 笔记列 | 选中行 ly 214..268.5 无灰线；未选中行 282..578 的线照旧 |

证据：`screenshots/selected-row-divider-2026-10-03/`
（`before-after.png`、`after-task-row-selected.png`、`after-note-row-selected.png`）。

## 六、两个记录在案但**不是**本次范围的观察

1. **点开一条笔记会把它的 `updatedAt` 顶到当前时间。** 我为了截图点了
   `notes[1]`，它的 `updatedAt` 从 `812719905.99`（19:31:45）变成
   `812720482.18`（19:41:22），正文一字未改。这会让「按最近编辑排序」
   把刚点过的笔记顶到最前。既有行为，已把该值还原（`workspace.json`
   sha256 回到 `8cf5d481…`）。
2. **直接调 `xcodebuild` 必须显式给
   `OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'`**，
   只设 `WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1` 环境变量没用（那个变量只有
   `scripts/run-tests.sh` 认）。漏了它，`swift-plugin-server` 起不来，
   报 `external macro implementation type 'SwiftUIMacros.StateMacro'`，
   再级联出 1300+ 条「找不到 `$xxx`」，看着像代码炸了其实一行没改错。
   同一条结论 2026-10-02 已经写进 `docs/countdown-audit-2026-10-02.md`，
   这次又踩了一遍。
