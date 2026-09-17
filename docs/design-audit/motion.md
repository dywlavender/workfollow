# D9 Motion 盘点

## 基线扫描

扫描范围为 `desktop/lib/**/*.dart`。D0 基线记录了 18 个主题外数字 `Duration`、10 个主题外 `Curves.*` 和 26 个 `Animated*` / `Tween` 命中。命中数包含业务日期、停留时间、Tooltip 延迟和并行组件，因此不能直接当作违规数量。

## 迁移事实源

动画参数现在由 [`workfollow_motion.dart`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_motion.dart) 的 `WorkFollowMotionRole`、`WorkFollowMotionTokens` 和 `WorkFollowMotionPolicy` 提供。基础值复用主题中的 `WorkFollowMotion.instant` 80ms、`fast` 160ms、`normal` 240ms 和 `standard` 曲线；完成反馈使用 200ms 的 bounded spring envelope。

| 原热点 | D9 状态 | 目标角色 |
| --- | --- | --- |
| `features/feedback/feedback_host.dart` | migrated | `feedbackToastEnter` / `feedbackToastExit` / fade；保留 feedback hold time |
| `app.dart` | migrated | `panelTransition` |
| `widgets/command_palette.dart` | migrated | `panelTransition` |
| `widgets/desktop_popover.dart` | migrated | `popoverEnter` / `popoverExit` |
| `widgets/settings_panel.dart` | migrated | `panelTransition` |
| `widgets/sidebar.dart` | migrated | `hoverTransition` |
| `screens/home_screen.dart` | migrated | `selectionTransition` |
| `screens/today_screen.dart`、`widgets/task_list/*`、`widgets/matrix/*` | deferred | 并行任务完成后接入对应 role |
| `features/feedback/feedback_event.dart` | accepted-exception | hold time，不是进退场动画 |
| `widgets/task_context_menu_panel.dart` | accepted-exception | hover intent delay，不是动画时长 |

## Reduced Motion

`WorkFollowMotionPolicy` 读取 `MediaQueryData.disableAnimations`。启用时所有角色收敛到 80ms linear，Feedback HUD 不运行 spring，只保留短 fade/slide；正常模式的完成 HUD 仍保持上升、轻微过冲、settle 和向下退出。

## D9 规则

1. Hold time、hover intent delay、进场、退场和状态过渡是不同语义，不能按数字相等就合并。
2. 浮层统一使用 fade + 轻微 scale/slide；持久 A Toolbar 使用更轻的 control press 节奏。
3. Shell 面板和页面切换使用 panel role；任务完成使用反馈 role；普通 hover/selection 不得使用 panel 节奏。
4. 并行组件保留原有业务动作，接入 Motion Role 时不得改变颜色、尺寸、布局和交互语义。
