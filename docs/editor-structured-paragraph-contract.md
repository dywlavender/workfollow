# 正文列表与引用布局

参考用户 2026-10-02 提供的 WorkFollow / 滴答截图。此次只调整格式段落呈现，不改变输入、保存和撤销语义。

## 统一规则

- 普通正文、标题的内容基准不变；`+ / H1` 仍在内容前方的 decoration lane。
- 列表文字相对普通正文缩进 16pt，圆点、序号、检查框继续由装饰层绘制，不使用 NSTextList，避免双重标记。
- 列表和引用段后距统一 2pt；普通正文维持 8pt，行距维持原值。
- 引用文字缩进 16pt；竖线在普通正文基准右侧 4pt，宽 2pt，使用现有语义边框色。
- 相邻引用段落绘制连续竖线，非引用段落中断连接。绘制不合并文档块。
- 指标集中于 DocumentEditorGeometry，不能通过调整整个 Inspector 留白修补单种格式。

这些是依据截图关系选取的逻辑尺寸，不宣称对滴答进行了逐像素测量。没有证据支持改动引用字体或 Enter 行为，因此本轮保留。

## 验收

DocumentFormatStyleTests 验证缩进、段后距、普通正文与标题起点不变；DocumentContentTests 覆盖格式保存与输入；DocumentDecorationRenderTests 在真实 TextKit 窗口渲染混合列表、连续引用和普通正文，并验证引用间隙竖线像素。

渲染证据：`/tmp/render_mixed_list_quote.png`。这是测试窗口截图，不等于主 App 完整点击流程验收。
