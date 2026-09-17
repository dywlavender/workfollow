# WorkFollow Desktop Design System

这是 D11 之后的桌面端设计系统索引。组件只组合语义 Token 和模块 Metrics；原始值只出现在 Token 层、内容渲染层或 `exceptions.md` 明确记录的例外中。

## 事实源

| 领域 | 事实源 |
| --- | --- |
| 字体、字重、行高、字距、字体族 | [`workfollow_theme.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_theme.dart) |
| 图标语义 | [`workfollow_icons.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_icons.dart) |
| 语义颜色和 Light/Dark | `WorkFollowTheme`、`WorkFollowColorTokens` |
| 间距和几何 | `WorkFollowSpacing`、`WorkFollowMetrics`、模块 Metrics |
| Surface / radius / shadow | [`workfollow_surface_tokens.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_surface_tokens.dart) |
| 状态 | `WorkFollowInteractionStyles` |
| Overlay | `DesktopOverlayPolicy`、`DesktopOverlayPolicy.toolbar()` |
| Motion | [`workfollow_motion.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_motion.dart) |
| 对比度 | [`workfollow_theme_parity.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_theme_parity.dart) |

## 开发预览

`WorkFollowDesignSystemGallery` 是开发用组件目录，不是产品入口。它覆盖 Typography、Colors、Icons、Controls、TaskRow、Menus、Pickers、Toolbar、Dialog 和 Completion Toast。用 Light、Dark 两个 `ThemeData` 挂载即可检查同一套 Token 的双主题结果。

## 自动约束

```bash
cd desktop
flutter test test/design_system_lock_test.dart
flutter test test/design_system_gallery_test.dart
```

`design_system_lock_test.dart` 会拒绝业务 Widget 直接使用 Material 图标、原始十六进制颜色、状态色、Web 字体、`textTheme`、数字字号/字距/字重、数字行高、数字圆角、孤立阴影、动画时长和曲线。内容渲染的 Quill 水平线等例外，以及并行任务的明确边界见 [`exceptions.md`](exceptions.md)。

## 领域说明

- [Typography](typography.md)
- [Icons](icons.md)
- [Colors](colors.md)
- [Spacing](spacing.md)
- [Geometry](geometry.md)
- [Surfaces](surfaces.md)
- [States](states.md)
- [Overlays](overlays.md)
- [Motion](motion.md)
- [Exceptions](exceptions.md)
