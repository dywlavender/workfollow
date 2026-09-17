# D9 Motion / 动画体系迁移记录

> 状态：已完成。施工边界是动画时长、曲线、进出场、状态过渡和 reduced motion；颜色、图标、间距、尺寸、圆角、阴影、布局和业务动作保持原有契约。

## 唯一事实源

`desktop/lib/theme/workfollow_motion.dart` 提供两层 API：

- `WorkFollowMotionRole`：按交互意图命名的角色，包括 hover、selection、control press、popover、panel、collapse、task completion、feedback 和 drag reorder。
- `WorkFollowMotionTokens`：复用已有 `WorkFollowMotion.instant/fast/normal/standard`，并补充 200ms 的完成/反馈 spring envelope、进场/退场曲线和共享 `SpringDescription`。
- `WorkFollowMotionPolicy`：根据 `MediaQueryData.disableAnimations` 解析时长和曲线。Reduced motion 保留 80ms 的线性 fade/slide，并禁用 spring。

## 角色矩阵

| 角色 | 正常节奏 | Reduced Motion |
| --- | ---: | ---: |
| hoverTransition | 80ms | 80ms linear |
| selectionTransition | 160ms | 80ms linear |
| controlPress | 80ms | 80ms linear |
| popoverEnter | 160ms | 80ms linear |
| popoverExit | 160ms | 80ms linear |
| panelTransition | 240ms | 80ms linear |
| collapseExpand | 240ms | 80ms linear |
| taskComplete / feedbackToastEnter | 200ms bounded spring envelope | 80ms linear |
| feedbackToastExit | 200ms | 80ms linear |
| dragReorder | 160ms | 80ms linear |

## 已迁移区域

| 区域 | 迁移内容 |
| --- | --- |
| Anchored Popover / Desktop Dialog | 统一 fade + 轻微 scale/slide；菜单、Picker 使用 popover 角色，顶层面板使用 panel 角色；反向过渡使用 popover exit 曲线。 |
| Command Palette / Settings | 移除页面内 180ms 和独立 ease 曲线，改用 panel role；保留原有 blur、surface 和布局。 |
| Persistent A Toolbar / Slash | Controller 仍拥有 Overlay 生命周期和定位；surface 使用轻量进出场，关闭时先完成短退场再移除 entry，不抢编辑器 selection。 |
| Shell Sidebar / Page Switch | Sidebar 收起和页面切换使用 panel role；切换方向的进/退曲线统一。 |
| Home Task Checkbox | 状态转换使用 selection role，未触及 Checkbox 几何和颜色。 |
| Completion Feedback HUD | 入口 200ms 上升、轻微过冲和 settle，退出 200ms 下移淡出；动画关闭或系统 reduced motion 时走短 fade 路径。原有 hold time 仍由 FeedbackController 管理。 |

## 明确保留的非动画时序

- `features/feedback/feedback_event.dart` 的 2600/4000/5000ms 是内容停留时间，不是进退场动画。
- `task_context_menu_panel.dart` 的 220ms 是子菜单 hover intent 延迟，不是动画时长。
- `app_icon_button.dart` 的 Tooltip wait duration 是提示出现延迟，不属于组件过渡。
- 日期计算、Focus Timer、拖拽启动 delay 和数据刷新 interval 属于业务时序，不迁移到 Motion Role。

## 并行工作区边界

以下文件在 D9 开始前已有另一项任务的未提交改动，本轮保留其业务和视觉实现，不重写：

- `screens/today_screen.dart`
- `widgets/task_row.dart`
- `widgets/task_document_styles.dart`
- `widgets/quick_add.dart`
- `widgets/task_list/*`
- `widgets/matrix/*`
- `widgets/task_schedule_options.dart`

这些组件已使用现有命名 Motion 基础值或留在后续模块收口清单中；下一轮接入时只迁移动画角色，不改变其业务行为。

## 验证

```text
flutter test test/motion_contract_test.dart
flutter test test/desktop_popover_test.dart
flutter test test/task_formatting_toolbar_persistent_test.dart
flutter test test/feedback_system_test.dart
flutter test
git diff --check
```
