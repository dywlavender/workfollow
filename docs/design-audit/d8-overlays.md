# D8 Menu / Popover / Picker / Toolbar 收口

## 本轮结论

D8 把浮层的入口收成一套可读的 Overlay contract。业务组件只声明用途和锚点，定位、翻转、视口安全区、Esc 和焦点恢复由共享基础设施处理。

| 规则 | 统一事实源 |
| --- | --- |
| 菜单 / Picker / Toolbar / Dialog 层级 | `DesktopOverlayLayer` |
| 打开时焦点策略 | `PopoverFocusPolicy` + `DesktopOverlayPolicy` |
| 外部点击与焦点恢复 | `DesktopOverlayPolicy` |
| 锚点、翻转、clamp | `calculatePopoverGeometry` / `showAnchoredPopover` |
| 持久工具栏和 caret 菜单 | `PersistentAnchoredPopoverController` |
| 非锚定全局浮层 | `showDesktopDialog` |

## 已迁移入口

- Task / Note 的 `/` 菜单都通过 `PersistentAnchoredPopoverController`，组件不再自己创建或定位 `OverlayEntry`。Caret 位置由 `anchorRectResolver` 提供，窗口变化和滚动只触发统一 controller 重算。
- `/` 菜单使用 `DesktopOverlayPolicy.menu` 的 `none` focus policy，编辑器保留 selection；鼠标点击、↑↓、Enter、Esc 和外部点击分别由菜单状态或编辑器快捷键处理。
- Task / Note 的 `A` 工具栏都使用 `DesktopOverlayPolicy.toolbar`，保持打开，格式操作不会自动关闭；Task 切换、Note 切换、Inspector 关闭和 dispose 会清理 controller。
- `showDesktopMenu`、Task Context、More、Sidebar 清单/标签、Habits 菜单统一走同一条 anchored menu route；Picker 通过 `DesktopOverlayPolicy.picker` 进入相同的定位和焦点管线。
- Command Palette 和 Settings Panel 统一通过 `showDesktopDialog` 创建全局 route，保留原有过渡参数，不再由组件自行调用 `showGeneralDialog`。

## 关闭与层级规则

1. 子 Picker / 子菜单先消费 Esc。
2. 当前菜单或 Picker 关闭并恢复打开前的 focus。
3. 持久 Toolbar 由编辑器的 Escape 层级关闭，关闭后恢复编辑器 focus。
4. 切换任务或笔记、页面卸载和 dispose 清理所有 persistent controller。
5. Menu < Picker < Dialog；Toast 由反馈宿主维护在 route 之上，浮层不通过 z-index 解决遮挡。

## 保留的特殊值

- Slash 的自绘 H1/H2/H3、列表和引用 glyph 仍属于专用绘制白名单。
- Command Palette / Settings 的现有 transition 和 barrier 是 D9 前的 motion 例外，本轮只把 route 入口收口。
- `showDialog` 在 Settings 内部只用于导入预览、恢复确认等真正的二级 Dialog，不属于 anchored menu/picker。

## 验证

```text
flutter test test/desktop_overlay_contract_test.dart
flutter test test/desktop_popover_test.dart
flutter test test/task_slash_session_test.dart
flutter test test/task_document_editor_test.dart
flutter test test/task_editor_popovers_test.dart
flutter test test/workspace_behavior_test.dart
```

上述回归覆盖定位翻转和 clamp、外部点击、Esc、键盘菜单、编辑器 Slash、工具栏 selection 保留、日期/清单/标签/重复 Picker 以及 Command Palette。
