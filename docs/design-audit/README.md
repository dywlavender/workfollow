# WorkFollow Design System Audit

这是桌面端 Design System 的 D0 盘点入口。D0 只记录现状、规范事实源和迁移顺序，不修改 `desktop/lib` 的视觉或行为。

## 快照

- 扫描日期：2026-09-17
- 扫描范围：`desktop/lib/**/*.dart`
- 文件数：96（包含当前工作区中并行任务新增的 Dart 文件）
- 排除：`build/`、`.dart_tool/` 和测试目录
- 当前分支：`feature/flutter-personal-desktop`

计数是语法命中数，不等同于违规数。比如 `SizedBox` 同时包含 Token 值和仍待归类的字面值；`Colors.transparent`、代码表面和遮罩颜色也可能是有意的特殊值。每个类别文档都区分了“确定迁移项”和“需要上下文判断的候选项”。

## 基线计数

| 维度 | 当前命中 | D0 判断 | 施工轮次 |
| --- | ---: | --- | --- |
| Typography | 280 个 `TextStyle`；3 个数字 `fontSize`；8 个 `Theme.of(...).textTheme`；2 个数字 `letterSpacing` | 3 个明确绕过点，其他需按语义角色复核 | D1 |
| Icons | 9 个 `Icons.*`（不含 `WorkFollowIcons` 定义）；0 个 `CupertinoIcons.*` | 9 个明确候选映射 | D2 |
| Colors | 31 个主题外十六进制色；21 个非透明 `Colors.*`；64 个 alpha 变换 | 主题外颜色优先复核，透明/白色等保留上下文判断 | D3 |
| Spacing | 224 个 `EdgeInsets`；291 个 `SizedBox`；99 个 `Padding`；40 个数字 gap/spacing | 语法命中，尚未区分 Token 和局部布局 | D4 |
| Geometry | 29 个数字圆角；162 个数字宽度；231 个数字高度 | 需要按控件类型归并，不能一次性替换 | D5 |
| Surfaces | 91 个 `BoxDecoration`；7 个 `BoxShadow`；27 个 `Border.*` | 先建立 Surface 角色，再收口实现 | D6 |
| States | `selected:` 60；Hover 相关 78；Focus 相关 71；Disabled 相关 32；Active 相关 16 | 语法命中，需按控件状态矩阵归并 | D7 |
| Overlay | 34 个弹层 API 命中，分布在 18 个文件；菜单/Picker/Toolbar/Popover 各有入口 | 定位基础已共享，视觉和焦点规则仍需统一 | D8 |
| Motion | 18 个主题外数字 `Duration`；10 个主题外 `Curves.*` | 反馈 HUD 与页面转场需要先定义 Motion Role | D9 |
| Light / Dark | 32 个明暗模式判断，分布在 10 个文件 | 检查是否把模式差异写进了组件，而不是 Theme | D10 |

## 规范事实源

| 语义 | 唯一事实源 |
| --- | --- |
| macOS 字体角色、字重、行高、字距、字体族 | [`workfollow_theme.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_theme.dart) 中的 `WorkFollowMacTypography`、`WorkFollowMacWeight`、`WorkFollowMacTracking`、`WorkFollowMacTypeFamily` |
| 图标语义映射 | [`workfollow_icons.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_icons.dart) 中的 `WorkFollowIcons` |
| 主题语义颜色 | [`workfollow_theme.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_theme.dart) 中的 `WorkFollowTheme`；组件专属角色见 [`workfollow_color_tokens.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_color_tokens.dart) |
| 原始颜色基元 | `WorkFollowColors` |
| 通用间距 | `WorkFollowSpacing` |
| 通用尺寸与页面布局 | `WorkFollowMetrics`、`WorkFollowLayout` |
| 任务列表尺寸 | `TaskListMetrics` |
| 圆角 | `WorkFollowRadii` |
| 动画时序与曲线 | `WorkFollowMotion` |
| 任务菜单颜色兼容层 | `TaskMenuStyle`（只转发 `WorkFollowTheme`，不再复制颜色） |

## D0 发现状态

- **确定迁移项**：没有上下文依赖、能直接指向现有 Token 的绕过用法。
- **候选项**：需要先确认它属于哪个语义角色，或可能是组件专属值。
- **允许例外**：透明遮罩、代码等特殊表面、绘制用颜色、显示器读数等有明确理由的值；例外必须在对应轮次文档中留记录。
- **待补 Token**：现有 Token 没有对应语义时，先在该轮 Spec 中补角色，再迁移调用方；不在组件内临时新增颜色或尺寸。

## 文档索引

- [设计债务总表](debt-register.md)
- [白名单](whitelist.md)
- [真实工作量排序](workload.md)
- [Typography](typography.md)
- [Icons](icons.md)
- [Colors](colors.md)
- [D3 Colors migration](d3-colors.md)
- [Spacing](spacing.md)
- [Geometry](geometry.md)
- [Surfaces](surfaces.md)
- [Motion](motion.md)
- [States](states.md)
- [Overlay](overlay.md)
- [Light / Dark](theme-parity.md)

## 施工顺序

```text
D0 盘点（本次）
  ↓
D1 Typography
  ↓
D2 Icons
  ↓
D3 Colors
  ↓
D4 Spacing
  ↓
D5 Geometry
  ↓
D6 Surfaces
  ↓
D7 States
  ↓
D8 Overlay
  ↓
D9 Motion
  ↓
D10 Light/Dark
  ↓
D11 Cleanup / Design Lock
```

每一轮只改一个维度，并在该轮结束后冻结审计结果、运行回归测试和截图核对。
