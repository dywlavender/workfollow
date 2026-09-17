# Typography

macOS UI 只使用 `WorkFollowMacTypography`、`WorkFollowMacWeight`、`WorkFollowMacTracking` 和 `WorkFollowMacTypeFamily`。`WorkFollowTypography` 是 Web 客户端的对照目录，不能被桌面 Widget 引用。

## 角色

```text
pageTitle / sectionTitle
navigation / navigationMeta
listTitle / listBody / listMeta
detailTitle / body / supporting
control / menu / caption
documentH1 / documentH2 / documentH3
```

正文、Quill 标题、列表、检查项、引用、链接和代码块通过文档样式读取同一套 macOS 字体族。`SFMono-Regular` 仅属于代码内容表面。

显示器读数、Slash 专用 glyph、工具栏文字 glyph 和无障碍隐藏 target 不属于普通层级，见 [Exceptions](exceptions.md)。
