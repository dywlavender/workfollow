# D11 / D11.1 Design System 最终清扫与集成锁定

> 状态：已完成。D11 建立规则，D11.1 收回并行工作区、完成全库复核，不重新设计页面。

## 扫描快照

- 分支：`feature/flutter-personal-desktop`
- 日期：2026-09-18
- 范围：`desktop/lib/**/*.dart`
- 文件数：103（最终复核，包含当前工作区并行新增文件和 D11 Gallery）

| 维度 | 清扫后的结果 | 分类结论 |
| --- | --- | --- |
| Typography | 业务文件没有数字 `fontSize`、数字 `letterSpacing`、数字 `FontWeight` | A 已迁移到 macOS 角色；计时器和隐藏 target 进入命名例外 |
| Icons | 业务文件没有直接 `Icons.*` / `CupertinoIcons.*` | A 全部归入 `WorkFollowIcons`；自定义 glyph 留在绘制层 |
| Colors | 业务文件没有原始 Hex 或语义 `Colors.red/green/grey` | A 归入 Theme；透明层、遮罩和用户内容色按 C/D 记录 |
| Spacing | 页面留白使用 `WorkFollowSpacing` 或模块语义 alias | B 由页面/模块 Metrics 持有 |
| Geometry | 常用 Divider、checkbox stroke、菜单 Divider 使用命名 Metric | C 仅保留绘制和内容渲染参数 |
| Surfaces | 阴影、圆角和边框由 Surface role 组合 | A 不允许业务 Widget 自行拼材质 |
| States / Overlay / Motion | 已有 D7–D9 契约继续作为回归入口 | 新组件必须接入共享 resolver/policy |
| Light / Dark | 已有 D10 对比度和双主题契约继续作为回归入口 | 颜色值可以随主题不同，语义不能分叉 |

## 本轮代码收口

- `WorkFollowMacDisplay.accessibilityHidden`、`WorkFollowMacTracking.timer` 和 `WorkFollowMacTypography.lineNone` 收纳了技术/显示例外。
- `WorkFollowMotion.tooltipWait`、`WorkFollowMotion.submenuIntent` 收纳等待和子菜单意图时序。
- `TaskMenuMetrics.dividerHeight`、`WorkFollowMetrics.checkboxBorderWidth` 和共享 Divider thickness 消除了重复几何字面值。
- Sidebar 的用户色勾选前景改为 `WorkFollowThemeContrast.foregroundOn`，Light/Dark 与任意用户色都可读。
- D11.1 将 Feedback、Matrix、Task List、Schedule、Today 和 Quick Add 的并行源码与回归测试纳入分支快照。
- D11.1 将拖拽预览、检查项、日期选项和 Matrix 几何迁移到模块 Metrics，将反馈停留时间迁移到 `WorkFollowFeedbackTiming`。
- D11.1 将 Feedback HUD 和 Quick Add 表面接入 `WorkFollowSurfaceTokens`，业务源码不再自定义阴影。

## 自动约束

[`design_system_lock_test.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/test/design_system_lock_test.dart) 扫描所有业务 Dart 源码，拒绝：

```text
直接 Material/Cupertino 图标
原始十六进制色和语义 Colors.*
Web 字体、textTheme 或数字字号/字距/字重
数字行高（内容渲染例外除外）、数字圆角、孤立阴影/elevation
孤立动画时长和 Curves
```

Token 源目录和内容/绘制例外是显式集合；例外见 [`docs/design-system/exceptions.md`](../design-system/exceptions.md)。全部业务源码都接受同一份锁定测试。

## 组件目录与回归

[`WorkFollowDesignSystemGallery`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/design_system_gallery.dart) 提供开发预览，覆盖 Typography、Colors、Icons、Controls、TaskRow、Menus、Pickers、Toolbar、Dialog 和 Completion Toast。[`design_system_gallery_test.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/test/design_system_gallery_test.dart) 在 Light/Dark 下确认所有关键 section 可构建且无 Flutter 异常；现有视觉 Widget 测试继续覆盖菜单、编辑器、TaskRow 和 Feedback。

## D11.1 集成闭环

并行任务新增的源码、测试和日期组件文档已经进入当前分支。锁定测试不再按路径跳过业务文件；全库复核只剩内容渲染、遮罩、绘制和用户数据等 `exceptions.md` 中记录的例外。

## 验证命令

```bash
cd desktop
flutter test test/design_system_lock_test.dart test/design_system_gallery_test.dart
flutter test test/task_typography_contract_test.dart test/task_icon_contract_test.dart test/task_color_contract_test.dart
dart analyze lib/theme/design_system_gallery.dart test/design_system_lock_test.dart
git diff --check
```
