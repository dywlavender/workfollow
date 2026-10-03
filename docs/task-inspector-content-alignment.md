# Inspector 内容对齐规范

依据：用户提供的滴答 / WorkFollow Header、标题和空正文截图。截图用于确定对齐关系，不将图片像素直接当作逻辑尺寸。

## 几何约束

- Header 完成框、标题、正文的可见内容统一以距 Inspector **内容原点** 20pt 为基准。基准起点的定义：SwiftUI 的 padding 从内容原点量；可见分栏线在内容原点外约 1pt，因此"距分栏线"的实测值约为 21pt（2026-10-03 实机测得，见文末验证记录）。
- 完成框可见尺寸 15pt，保留 24pt 宽点击区域；图形在点击区域内左对齐。
- Header 高度保持 58pt，不随日期文案变化。
- 标题顶部留白 20pt，标题到正文容器间距 10pt。
- 正文宿主左留白 15pt（`horizontalPadding − documentFragmentPadding`），加 TextKit 的 5pt fragment padding 后得到 20pt 内容起点。
- `+ / H1` 属于正文前方 decoration lane，不得改变正文起点。不要通过修改共享段落缩进补偿 Inspector 留白。
- 日期时间与重复是任务数据；参考图未显示某项，不构成删除数据或隐藏已有值的依据。

尺寸集中在 `TaskInspectorMetrics`，Shell 和 Header 消费同一组指标，不再分别写留白。

## 验证记录（2026-10-02）

通过 14 项测试：TaskInspectorShellContractTests（5）、TaskInspectorHierarchyRenderTests（4）、DocumentDecorationRenderTests（5）。包含标题位置与正文间距、窄宽 Header、Footer 留白、子任务布局和 decoration 对齐回归。

检查实际组件渲染截图：`/tmp/workfollow-inspector-hierarchy-renders/parent-with-child-empty.png`。确认空描述与标题左边缘一致、完成框左对齐、子任务和 Footer 未被裁切。

边界：该截图为测试窗口中的组件渲染，不是运行中 App 的完整点击流程；正文 caret 起点由 TextKit 几何及 decoration 测试覆盖，本轮没有新增聚焦空正文的运行截图。不宣称与滴答逐像素一致。

## 装饰裁切修复与补验（2026-10-03）

之前仅验证独立编辑器的 40pt 宿主留白，未覆盖实际 Inspector 的 11pt 宿主留白，漏掉了装饰区域向左伸出 20pt 后被父容器裁切的问题。

- Inspector 将可见左边界传给编辑器，`+ / H1/H2/H3` 在该边界内绘制，不移动正文起点。
- 空行 `+` 接入现有 Slash 菜单，使用零长度触发范围；打开与取消不会向正文插入 `/`。
- 新增完整窄栏子任务 Inspector 的聚焦截图与点击回归，检查正文起点（当轮 16pt，现为 20pt）不变、菜单出现且文档不变。
- 36 项 DocumentDecorationRenderTests、TaskInspectorHierarchyRenderTests、SlashSessionTests 通过。
- 已在独立修复版主 App 中打开「归纳高频问题」子任务：聚焦文末空行，确认完整加号；点击打开菜单，切回标题关闭菜单，正文不变；聚焦已有 H1 段落确认角标完整。上述实机截图已在会话中展示。
- H2/H3 本轮通过完整 Inspector 测试窗口截图检查，没有宣称在用户任务中逐项改写并验收。

窄栏渲染证据：`/tmp/render_child_inspector_marker_0.png` 至 `marker_3.png`。

## 角标视觉留白试调（2026-10-03）

用户反馈角标仍贴分栏线。本次将 Inspector 统一内容起点由 16pt 调为 20pt，窄装饰槽中 `+ / H1/H2/H3` 距宿主左边界至少 4pt，保持角标与正文间隙，而不是只将角标挤向正文。

- 装饰标记位置收敛为单一几何：`DocumentEditorGeometry.decorationMarkerX(visibleMinX:) = max(4, visibleMinX + 4)`。绘制（`DocumentBlockDecorations` 的空行 `+` 与标题角标）、命中测试（`NativeTextView`）与测试断言共用同一处；原先 `+` 的 5pt 下限与角标 2pt 下限不一致的问题一并消除。传入的 `visibleMinX` 是**宿主内可见的装饰槽宽度**（容器坐标），不是分栏线位置。
- 16pt 为历史验收值，不再是当前指标。

## 部署实测与遗留（2026-10-03）

构建产物：`~/Library/Developer/Xcode/DerivedData/WorkFollow-gyhvrychuxgquegocymnoysmiokg/Build/Products/Debug/WorkFollow.app`，2026-10-03 01:04 构建。**注意**：本机同时存在副本 `/private/tmp/WorkFollowDecorationFinal.app`，验收前必须先确认运行进程的可执行路径，否则会量到旧产物（本轮已踩过一次）。

实测方法：窗口几何（CGWindowList）+ 截图 2x 像素扫描换算 pt，起点统一取**可见分栏线**，且**分隔线与目标墨迹必须取自同一张截图**。像素扫描用逐步收紧的阈值（200/170/140）区分"描边核心"与抗锯齿边缘。原生窗口 1200pt 宽；滴答参考 1512pt，距离按 pt 可比，不作同尺寸像素级结论。

| 量测项 | 原生（最新构建） | 滴答（参考图 / 实机） | 判定 |
| --- | --- | --- | --- |
| 完成框左缘 | 21.0pt | 21.0pt | 一致 |
| 完成框墨迹尺寸 | **15.0×15.0pt** | **15.0pt**（30px） | 一致 |
| 标题左缘 | 21.5pt | 20.5pt | +1pt，容差内 |
| 页脚图标左缘 | 22.5pt | **22.0pt** | +0.5pt，一致 |
| Header 高度 | 58pt | 57–57.5pt | 一致 |

**结论：编辑栏内容对齐（基准、完成框、页脚、Header 高度）在实测口径下已达 parity，本轮无需改布局。** 两处此前的"待裁决"经复测撤销：

1. 页脚：此前记"比滴答多 3.5pt（滴答 19pt）"是**跨截图误差**——那次把 A 图的分隔线位置配 B 图的页脚墨迹。在同一张图内量（分隔线 x=1218px、页脚墨迹 x=1258px）得到滴答 22.0pt，与我们的 22.5pt 只差 0.5pt。**不改常量。**
2. 完成框：此前记"墨迹 16pt"是 **ROI 含邻近墨迹**导致的虚高。收紧 ROI 后阈值 200/170/140 三次扫描一致为 15.0×15.0pt。**不改路径。**

本轮实做的优化：

- 装饰标记位置收敛为单一几何 `DocumentEditorGeometry.decorationMarkerX(visibleMinX:) = max(4, visibleMinX + 4)`，绘制 / 命中测试 / 测试断言共用；消除 `+`(5pt) 与角标(2pt) 两个不一致的下限（与"至少 4pt"同口径）。副作用仅一处：笔记编辑器里空行 `+` 由 5pt → 4pt（1pt）。
- 契约测试新增**渲染墨迹断言**（`InspectorRenderAnchor.completionInk`）：断言渲染出来的框 15×15pt 且左缘 = `horizontalPadding`，不再只断言 `completionSize` 常量。
- `horizontalPadding` 与 `decorationVisibleMinX` 调用点补语义注释：前者是"内容原点"距离（可见分栏线在其外约 1pt，实测 ≈21pt）；后者是"宿主内可见的装饰槽宽度"，不是分栏线位置。

**验收纪律（本轮两次测量误差的共同教训）**：① 分隔线与目标墨迹必须同图；② ROI 不得含邻近墨迹，用阈值扫描区分核心与抗锯齿；③ 验收前先确认运行进程的可执行路径（本机曾同时存在 `/private/tmp/WorkFollowDecorationFinal.app` 与 DerivedData 两份同名产物）。
