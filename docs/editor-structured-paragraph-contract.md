# 正文列表与引用布局

参考用户 2026-10-02 提供的 WorkFollow / 滴答截图。此次只调整格式段落呈现，不改变输入、保存和撤销语义。

## 统一规则

- 普通正文、标题的内容基准不变；`+ / H1` 仍在内容前方的 decoration lane。
- 列表文字相对普通正文缩进 16pt，圆点、序号、检查框继续由装饰层绘制，不使用 NSTextList，避免双重标记；标记与段落文字**左缘对齐**（2026-10-16 实测修订）。
- 列表和引用段后距统一 2pt；普通正文段后距 10pt（2026-10-28 按 ima 实测段距 5+5 对齐：Enter 换段与自动折行刻意拉开）；自动折行和软换行仍在同一段内，只走行盒。标题段后距 8pt，维持 35 / 32 / 30 的标题节距。行盒按滴答实测：标题 1.6× 字号、列表与引用 18、正文 21（`DocumentTextCodec` 用 lineSpacing 补字体自然行高之差，不写死系统默认行高）。
- 引用文字缩进 16pt；竖线在普通正文基准右侧 4pt，宽 2pt，使用现有语义边框色。
- 相邻引用段落绘制连续竖线，非引用段落中断连接。绘制不合并文档块。
- 指标集中于 DocumentEditorGeometry，不能通过调整整个 Inspector 留白修补单种格式。

以上是 2026-10-02 依据截图关系选取的逻辑尺寸；其中标记位置、标题字阶（18 / 16 / 14、粗体）、行盒与正文换段节距已在 2026-10-16 / 2026-10-28 按滴答与 ima 截图逐像素实测修订，证据与回归测试见[文档块装饰复盘](document-editor-decorations-2026-09-28.md) 的「标记对齐」。没有证据支持改动引用字体或 Enter 行为，因此保留。

## 验收

DocumentFormatStyleTests 验证缩进、段后距、行盒与段间距（`testParagraphLineBoxesAndPitchesMatchMeasuredTickTickSpacing`）、普通正文与标题起点不变；DocumentListMarkerAlignmentTests 离屏渲染锁定标记与文字左缘的相对列位置；DocumentContentTests 覆盖格式保存与输入；DocumentDecorationRenderTests 在真实 TextKit 窗口渲染混合列表、连续引用和普通正文，并验证引用间隙竖线像素。

渲染证据：`/tmp/render_mixed_list_quote.png`。这是测试窗口截图，不等于主 App 完整点击流程验收。
