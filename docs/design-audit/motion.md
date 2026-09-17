# D9 Motion 盘点

## 目标规范

动画使用 `WorkFollowMotion` 的角色，而不是页面内随手写毫秒数。当前已有 `instant` 80ms、`fast` 160ms、`normal` 240ms、任务行 220ms 和标准曲线；反馈 HUD 还需要独立的 enter/exit/spring 角色。

## 扫描结果

| 发现 | 数量 | 热点 |
| --- | ---: | --- |
| 主题外 `Duration(milliseconds: ...)` | 18 | Feedback、App shell、Popover、Settings、Today、Home |
| 主题外 `Curves.*` | 10 | Feedback Host、App shell、Command Palette |
| `Animated*` / `Tween` 等 | 26 | 反馈、页面切换、任务行、命令面板和 Matrix |

## 明确候选

| 文件 | 当前值 | 目标 Motion Role |
| --- | --- | --- |
| `features/feedback/feedback_host.dart` | 420 / 200 / 120ms 与多条曲线 | feedback enter、feedback exit、feedback fade；D9 保留 spring 语义 |
| `features/feedback/feedback_event.dart` | 4000 / 5000 / 2600ms | feedback hold roles；这是停留时间，不是进退动画 |
| `app.dart` | 220 / 180ms | shell panel / page switch |
| `widgets/command_palette.dart` | 180ms + easeOutCubic | command overlay |
| `widgets/desktop_popover.dart` | 100ms | popover |
| `widgets/settings_panel.dart` | 180ms | dialog/panel |
| `screens/today_screen.dart` | 300ms delay | list completion or stagger，需要确认语义 |
| `widgets/task_context_menu_panel.dart` | 220ms hover timer | submenu intent delay，不应与动画时长混为一谈 |

## D9 规则

1. Hold time、hover intent delay、进场动画和退场动画是不同角色，不能只按数字合并。
2. D9 先补齐 Motion Role，再替换调用方；不在这一轮调整布局和视觉颜色。
3. Reduced Motion 与非动画测试路径要继续保留。

