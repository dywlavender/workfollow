# D6 圆角、边框、阴影与 Surface

> 状态：已完成。D6 只收口材质层级；字体、颜色语义、图标、间距、尺寸、动画和业务行为保持原有契约。

## 事实源

| 材质语义 | 唯一事实源 |
| --- | --- |
| 圆角角色 | `WorkFollowRadii` |
| Surface 角色、边框与组合装饰 | `WorkFollowSurfaceTokens` |
| 阴影等级与 Detail 阴影 | `WorkFollowShadows` |
| 运行时表面颜色 | `WorkFollowTheme` |
| 浮层层级顺序 | `WorkFollowLayers` |

## Surface 角色

| 角色 | 圆角 | 边框 | 阴影 |
| --- | --- | --- | --- |
| `surface` | `WorkFollowRadii.surface` | 无默认边框 | Level 0 |
| `input` | `WorkFollowRadii.control` | `tokens.border` | Level 0 |
| `card` | `WorkFollowRadii.card` | `tokens.border` | Level 1（可选） |
| `popover` / `menu` | `WorkFollowRadii.popover` | `tokens.border` | Level 2 |
| `dialog` | `WorkFollowRadii.popover` | `tokens.border` | Level 3 |
| `toast` / HUD | `WorkFollowRadii.card` | 无默认边框 | Level 4 |

组件可以覆盖内容色或边框色表达内容状态，但不能再创建独立的圆角、blur、offset 组合。

## 已迁移区域

- `AppCard` 使用 `WorkFollowSurfaceTokens.card`，raised card 使用 Level 1。
- 通用 `DesktopPopover` 与持久编辑器 Popover 使用 Level 2；编辑器 Toolbar 与日期/清单/标签/重复 Picker 共享 Popover 装饰。
- Slash Menu 增加统一的 Popover 边界，并使用 Level 2。
- Command Palette 使用 Dialog Surface 与 Level 3。
- Task Editor、Task Schedule、Task Context Menu、Home、Board、Calendar、Notes 的数字圆角改为 `WorkFollowRadii` 或命名的 Marker/Checkbox 角色。

## 明确保留项

- Matrix、Feedback、Schedule Options 和 Today 当前由并行任务维护；其 Surface 组合留在白名单，避免覆盖未提交业务改动。
- Stats、Slash、Editor Glyph 的 `CustomPainter` 圆角是绘制几何，不属于 Widget Surface。
- 1px Divider/Border 仍是边界参数，不提升为 Surface 阴影。

## 验证

```text
flutter test test/task_surface_contract_test.dart
flutter test test/task_geometry_contract_test.dart
flutter test
git diff --check
```

