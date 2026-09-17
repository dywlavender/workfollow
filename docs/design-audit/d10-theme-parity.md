# D10 Light / Dark 主题一致性改造

> 状态：已完成。施工边界是 Light/Dark 的语义颜色、对比度、Surface 层级、反色前景和可读性；字体、图标、间距、尺寸、圆角、阴影、动画和交互语义保持既有契约。

## 本轮结论

Light 和 Dark 继续使用同一组语义角色：

```text
canvas / sidebar / content / inspector / overlay
textPrimary / textSecondary / textTertiary / textDisabled
border / borderStrong / menuSelected / menuDivider
listRowHover / listRowSelected
accent / success / warning / danger
feedbackSurface / feedbackText / feedbackAction
```

主题值可以不同，但组件不再为同一语义各写一套明暗分支。需要在有色表面上显示前景时，统一通过 [`WorkFollowThemeContrast`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_theme_parity.dart) 选择可读的白色或深色前景。

## 已完成的代码收口

| 区域 | 改动 |
| --- | --- |
| 主题 Token | 校准 Light 的文字三级色、品牌色和状态色；提高禁用文字的语义 alpha；增强 Dark 任务行 Hover 的可见层级。 |
| ThemeData | Dark `error` 使用深色前景；Tooltip 在两种主题都使用相同的 Feedback HUD 表面和文字角色；Dialog/Popup 继续读取 `overlay`。 |
| Sidebar | Light/Dark 的 rail、选中、Hover、Pressed、Footer、前景和渐变都由 `WorkFollowColorTokens` 解析，Widget 不再复制颜色常量。 |
| Filled controls | Home、Calendar、Notes、Tag Picker 的有色按钮/日期格/完成框通过共享前景解析器，避免 Dark 下白字落在浅色状态色上。 |
| Feedback HUD | `feedbackSurface`、`feedbackText`、`feedbackAction` 在两种主题保持相同，完成提示不随主题反转。 |

## 主题契约

[`theme_parity_contract_test.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/test/theme_parity_contract_test.dart) 锁定以下规则：

- 主文字对内容和浮层表面至少 7:1；次级文字至少 4.5:1；三级文字至少 3:1；禁用文字至少 2:1。
- Accent、Success、Warning、Danger 在内容和浮层表面保持可读对比度。
- TaskRow 和菜单的 Hover/Selected、Divider、BorderStrong 在两种主题都有可感知的层级差。
- Light 的白色 Content/Overlay 允许共享填充，但 Popover 必须通过统一的边框和材质角色分层。
- 有色表面的前景由同一个对比度解析器决定。
- Tooltip、Dialog、Popup 的 surface 角色与主题 Token 对齐；Dark 错误色的前景可读。
- Feedback HUD 的表面、正文和撤销操作色在 Light/Dark 完全一致。

## 延后边界

并行任务尚未提交的 `task_document_styles.dart`、`task_schedule_options.dart`、`task_schedule_panel.dart`、`task_row.dart`、`today_screen.dart`、`quick_add.dart`、`widgets/task_list/*`、`widgets/matrix/*` 和 `features/feedback/*` 保留原改动。它们的 Checklist、Schedule、TaskRow、Matrix、Feedback 细节列入后续收口，不在本轮覆盖。

## 验证

```text
flutter test test/theme_parity_contract_test.dart
dart analyze（D10 修改文件）
git diff --check
```

组件行为回归继续使用既有 Task、Menu、Editor、Overlay 和 Feedback 测试；全量测试中若出现并行 Quick Add Focus 用例失败，按并行任务边界单独记录，不改变本轮主题契约。
