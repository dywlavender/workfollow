# D7 交互状态迁移记录

> 状态：已完成。施工边界是 default、hover、pressed、selected、focused、disabled、destructive；字体、图标、间距、尺寸、圆角、阴影和动画保持原有契约。

## 唯一事实源

`desktop/lib/theme/workfollow_interaction_states.dart` 提供：

- `WorkFollowInteractionState`：七种状态语义。
- `WorkFollowInteractionStyles.resolve`：统一优先级：disabled → pressed → selected → focused → hover → destructive → default。
- `fill`：任务行和菜单等自绘 surface 的状态填充。
- `customFill`：保留导航 rail、用户清单色等组件专属颜色，同时复用同一状态优先级。
- `overlay`：Material `InkWell`、Button、Checkbox、Picker 的 hover/pressed/focus overlay。
- `focusBorder` / `focusColor`：焦点独立于 selected，不再依靠选中背景冒充键盘焦点。

## 状态矩阵

| 状态 | 背景 | 边框/焦点 | 文字与图标 |
| --- | --- | --- | --- |
| Default | 组件默认 surface | 无额外边框 | 正常语义色 |
| Hover | neutral hover 或 menu selected | 不改变 | 不改变 |
| Pressed | 更深的 neutral selected | 不改变 | 不改变 |
| Selected | neutral selected；内容控件可保留已有 active surface | 不依赖粗边框 | 不改变语义层级 |
| Focused | 不强制替换 selected fill | 独立 focus ring / 低透明度 focus overlay | 不改变 |
| Disabled | 默认 surface 或无填充 | 无额外边框 | `textDisabled` |
| Destructive | 默认仍为中性 | hover/pressed 才显示弱 danger tint | danger 文字与图标 |

Focus 只在需要时增加 ring；菜单的键盘当前项仍可以使用 neutral selected 作为可见提示，同时保留 Focus 语义。

## 已迁移区域

| 区域 | 状态收口 |
| --- | --- |
| 通用图标按钮 | `AppIconButton` 使用共享 overlay；disabled 与 active 不再各自维护 hover/pressed 规则 |
| Desktop Menu / PropertyButton | 键盘 focus、鼠标 hover、当前选项和 destructive 文案共用状态解析 |
| Slash / More / Context Menu | 点击入口改用 InkWell overlay；删除默认中性，hover/pressed 才加强 danger |
| Editor Toolbar / Picker | 工具按钮、标题选择、日期/时间选择复用 focus 与 pressed 状态 |
| List / Tag / Date Picker | 选中行、hover、CheckboxListTile 的状态由共享语义层提供 |
| Command Palette / Settings | 键盘当前项和鼠标 hover 分开处理，设置页选中态改用中性菜单状态 |
| Sidebar / Navigation / List / Tag | 保留 rail、清单自定义颜色，但 pressed/focused 与 selected/hover 的优先级统一 |
| Schedule Panel | 日期 Tab、快捷日期、日期格和属性入口复用相同 overlay |

## 并行工作区边界

以下文件在本轮开始前已经由另一项任务修改，D7 没有覆盖其状态实现：

- `widgets/task_row.dart`
- `widgets/task_document_styles.dart`
- `screens/today_screen.dart`
- `widgets/quick_add.dart`
- `widgets/task_list/*`
- `widgets/matrix/*`
- `features/feedback/*`
- `widgets/task_schedule_options.dart`

这些文件保留在 D7 manifest 的 `deferred` 记录中，后续接入 `WorkFollowInteractionStyles` 时只迁移状态，不重写并行任务的业务逻辑。

## 验证

```text
flutter test test/interaction_state_contract_test.dart
flutter test test/task_menu_visual_test.dart test/task_context_menu_panel_test.dart
flutter test test/task_editor_popovers_test.dart
flutter test
git diff --check
```
