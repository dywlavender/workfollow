# Design Audit Manifest

本文件是 D0 的可追踪清单。每一条记录都应在对应施工轮次更新为 `migrated`、`accepted-exception` 或 `deferred`，不要直接删除历史记录。

## 记录格式

| 字段 | 含义 |
| --- | --- |
| `id` | 稳定的发现编号，后续提交和回归报告引用它 |
| `dimension` | Typography / Icons / Colors / Spacing / Geometry / Surfaces / States / Overlay / Motion / Light-Dark |
| `location` | 文件与行号 |
| `current` | 当前实现或命中值 |
| `target` | 目标 Token、语义角色或需新增的角色 |
| `status` | `candidate`、`migrated`、`accepted-exception`、`deferred` |
| `round` | 计划迁移轮次 |
| `reason` | 选择目标或保留例外的依据 |

## D0 汇总

| id | dimension | location / scope | current | target | status | round |
| --- | --- | --- | --- | --- | --- | --- |
| TYPO-001 | Typography | `widgets/matrix/matrix_add_surface.dart:267` | `fontSize: 18` | `control` 或 Matrix Control Role | candidate | D1 |
| TYPO-002 | Typography | `widgets/matrix/matrix_quadrant.dart:132` | `fontSize: 11` | `caption` 或 Matrix Quadrant Label Role | candidate | D1 |
| TYPO-003 | Typography | `widgets/sidebar.dart:542` | 隐藏输入 `fontSize: 1` | 技术例外 | accepted-exception | D1 |
| TYPO-004 | Typography | 8 处 `Theme.of(...).textTheme` | Material text theme | 明确的 macOS 语义角色 | candidate | D1 |
| TYPO-005 | Typography | `screens/trash_screen.dart:118` | `letterSpacing: .45` | `none` 或有记录的 Caption tracking | candidate | D1 |
| TYPO-006 | Typography | `widgets/focus_timer_dialog.dart:87` | `letterSpacing: 1.2` | `WorkFollowMacDisplay.timer` | accepted-exception | D1 |
| ICON-001 | Icons | `widgets/task_editor_toolbar.dart:197` | `Icons.history` | `WorkFollowIcons.history` / `historyToggle` | candidate | D2 |
| ICON-002 | Icons | `widgets/task_editor_toolbar.dart:318` | `Icons.check` | `WorkFollowIcons.check` | candidate | D2 |
| ICON-003 | Icons | `widgets/task_context_menu_panel.dart:170` | `Icons.wb_twilight_outlined` | `tomorrow` 或独立语义映射 | candidate | D2 |
| ICON-004 | Icons | `widgets/task_schedule_panel.dart` | 4 个直接 chevron/circle glyph | `WorkFollowIcons` 映射 | candidate | D2 |
| ICON-005 | Icons | `widgets/task_schedule_options.dart:170` | 直接 down/close glyph | `expandMore` / `close` | candidate | D2 |
| COLOR-001 | Colors | `widgets/task_menu_style.dart` | 9 个浅色 hex 覆盖 | `WorkFollowTheme` | migrated | D3 |
| COLOR-002 | Colors | `widgets/sidebar.dart` | 7 个局部导航 hex | `WorkFollowColorTokens.lightNavigation*` | migrated | D3 |
| COLOR-003 | Colors | `widgets/quick_add.dart` | 6 个智能 token hex | Quick Add semantic roles | migrated | D3 |
| COLOR-004 | Colors | `features/matrix/matrix_models.dart` | 4 个象限 hex | `WorkFollowColorTokens.matrix*` | migrated | D3 |
| COLOR-005 | Colors | `widgets/task_editor_toolbar.dart` | 高亮 hex | Document Highlight Token | migrated | D3 |
| COLOR-006 | Colors | `widgets/task_context_menu_panel.dart:389` | 浅色 selected hex | `menuSelected` | migrated | D3 |
| COLOR-007 | Colors | `widgets/task_schedule_options.dart:16` | 浅色 field hex | `menuSelected` / `canvas` | migrated | D3 |
| COLOR-008 | Colors | `widgets/task_schedule_panel.dart:405` | 工作日/休息日红绿 hex | `warning` / `success` calendar roles | migrated | D3 |
| COLOR-009 | Colors | 用户清单/习惯/图表颜色 | `Color(value)` / saved content color | user-content/data palette whitelist | accepted-exception | D3 |
| COLOR-010 | Colors | More/Context/List/Command menus | `accentFaint` used for hover/selected fills | `menuSelected` | migrated | D3 |
| COLOR-011 | Colors | `theme/workfollow_theme.dart` global hover | Theme default hover reused accent soft | `listRowHover` | migrated | D3 |
| SPACE-001 | Spacing | `sidebar.dart`, `settings_panel.dart`, `calendar_screen.dart` 等 | 多套局部 EdgeInsets/SizedBox | `WorkFollowSpacing` + semantic aliases | migrated | D4 |
| GEOM-001 | Geometry | `home_screen.dart`, `sidebar.dart`, `notes_screen.dart` 等 | 宽高字面值 | `WorkFollowMetrics` / page roles | migrated | D5 |
| GEOM-002 | Geometry | `task_editor_*`, `task_*_picker.dart`, `task_inspector.dart` | 编辑器/Picker/Inspector 各自维护宽高 | `TaskEditorMetrics` / `TaskPickerMetrics` / `TaskInspectorMetrics` | migrated | D5 |
| GEOM-003 | Geometry | `task_context_menu_panel.dart`, `task_more_menu.dart`, `command_palette.dart` | 菜单行和弹层约束有多套数字 | `TaskMenuMetrics` / `CommandPaletteMetrics` / `WorkFollowMetrics` | migrated | D5 |
| GEOM-004 | Geometry | `today_screen.dart`, 并行新增 Matrix/Feedback 组件 | 动态约束或并行改动中的固定尺寸 | Layout contract / 模块白名单 | deferred | D5/D6 |
| SURF-001 | Surfaces | 91 个 `BoxDecoration` | 页面/卡片/Popover 混用 | `WorkFollowSurfaceTokens` surface role matrix | migrated | D6 |
| SURF-002 | Surfaces | 6 个基线 `BoxShadow` 与局部 elevation | blur/offset 在 Card、Popover、Dialog 间重复 | `WorkFollowShadows` Level 0–4 | migrated | D6 |
| SURF-003 | Surfaces | Quick Add、Today、Feedback、Matrix 的并行阴影 | 其他任务未提交的 Surface 组合 | `WorkFollowShadows` 对应角色 | deferred | D6 |
| STATE-001 | States | `theme/workfollow_interaction_states.dart` | 状态优先级与 Material overlay 分散在组件中 | `WorkFollowInteractionStyles` | migrated | D7 |
| STATE-002 | States | `desktop_popover.dart`、More/Context/Slash/Command 菜单 | focused、hover、selected 共用局部背景 | 统一菜单状态矩阵与 focus ring | migrated | D7 |
| STATE-003 | States | `sidebar.dart` | navigation/list/tag 自己组合 pressed、focus、hover、selected | `customFill` + `focusBorder` | migrated | D7 |
| STATE-004 | States | `task_date_picker.dart`、`task_schedule_panel.dart`、`settings_panel.dart` | Picker/Settings 直接维护 selected/hover | 共享 control/picker overlay | migrated | D7 |
| STATE-005 | States | `task_row.dart`、`task_list/*`、`task_document_styles.dart`、Matrix/Feedback/QuickAdd | 并行任务中的状态分支 | 接入 `WorkFollowInteractionStyles` | deferred | D7 后续 |
| OVERLAY-001 | Overlay | `desktop_popover.dart`、`task_editor_popover.dart` | Menu / Picker 的定位、翻转、clamp 和 focus policy 多入口 | `DesktopOverlayPolicy` + `calculatePopoverGeometry` | migrated | D8 |
| OVERLAY-002 | Overlay | `task_document_editor.dart`、`note_document_editor.dart`、`persistent_anchored_popover.dart` | Slash / Toolbar 自己创建或维护 `OverlayEntry` | Persistent anchored overlay controller | migrated | D8 |
| OVERLAY-003 | Overlay | `command_palette.dart`、`settings_panel.dart` | 顶层浮层各自调用 `showGeneralDialog` | `showDesktopDialog` | migrated | D8 |
| OVERLAY-004 | Overlay | `sidebar.dart`、`habits_screen.dart`、Context / More | Material `showMenu` 与桌面菜单并存 | `showDesktopMenu` | migrated | D8 |
| OVERLAY-005 | Overlay | `settings_panel.dart` 内部确认流程 | 真正的二级 Dialog 仍使用 `showDialog` | Dialog 白名单 | deferred · intentional | D8 |
| MOTION-001 | Motion | `features/feedback/feedback_host.dart` | 420/200/120ms、ease 曲线、TweenSequence | `feedbackToastEnter` / `feedbackToastExit` / fade / spring envelope | migrated | D9 |
| MOTION-002 | Motion | `app.dart`、`widgets/command_palette.dart`、`widgets/settings_panel.dart` | 220/180ms、ease 曲线 | `panelTransition` | migrated | D9 |
| MOTION-003 | Motion | `widgets/desktop_popover.dart`、`persistent_anchored_popover.dart` | 100ms、只有 Fade，持久浮层无进退场 | `popoverEnter` / `popoverExit` / `controlPress` | migrated | D9 |
| MOTION-004 | Motion | `widgets/sidebar.dart`、`screens/home_screen.dart` | 120/150ms | `hoverTransition` / `selectionTransition` | migrated | D9 |
| MOTION-005 | Motion | `screens/today_screen.dart`、`widgets/task_list/*`、`widgets/matrix/*` | 并行任务中的状态/任务行动画 | 对应 task/list/collapse roles | deferred | D9 后续 |
| MOTION-006 | Motion | `features/feedback/feedback_event.dart` | 4000/5000/2600ms | feedback hold time | accepted-exception | D9 |
| MOTION-007 | Motion | `widgets/task_context_menu_panel.dart` | 220ms Timer | submenu hover intent delay | accepted-exception | D9 |
| THEME-001 | Light-Dark | `theme/workfollow_theme.dart` | 明暗状态色和前景对比度不均 | Light/Dark semantic roles + readable foreground | migrated | D10 |
| THEME-002 | Light-Dark | `theme/workfollow_theme_parity.dart` | 各组件自行判断白/黑前景 | `WorkFollowThemeContrast` | migrated | D10 |
| THEME-003 | Light-Dark | `widgets/sidebar.dart` | Widget 内散落 Light/Dark rail 分支 | `WorkFollowColorTokens.navigation*` | migrated | D10 |
| THEME-004 | Light-Dark | `screens/home_screen.dart`, `screens/calendar_screen.dart`, `screens/notes_screen.dart`, `widgets/task_tag_picker.dart` | 有色表面固定使用白色前景 | `WorkFollowThemeContrast.foregroundOn` | migrated | D10 |
| THEME-005 | Light-Dark | `widgets/command_palette.dart`, `widgets/settings_panel.dart` | 黑色 alpha 遮罩 | Overlay barrier exception | accepted-exception | D10 |
| THEME-006 | Light-Dark | `widgets/task_document_styles.dart`, `widgets/task_schedule_options.dart`, `widgets/task_schedule_panel.dart`, `widgets/task_row.dart`, `widgets/task_list/*`, `widgets/matrix/*`, `features/feedback/*` | 并行任务中的 Checklist/Schedule/Row/Matrix/Feedback 明暗分支 | 对应语义 Token；保留并行工作区 | deferred | D10 后续 |

## 重新扫描命令

从仓库根目录执行以下命令可复核 D0 的范围；命中数量随并行工作区变化是正常的：

```bash
rg --files desktop/lib -g '*.dart'
rg -n --glob '*.dart' 'fontSize:|fontWeight:|fontFamily:|letterSpacing:|TextStyle\(' desktop/lib
rg -n --glob '*.dart' '\b(Icons|CupertinoIcons)\.' desktop/lib
rg -n --glob '*.dart' 'Color\(0x|Colors\.|withValues\(|withOpacity\(' desktop/lib
rg -n --glob '*.dart' 'EdgeInsets\.|SizedBox\(|Padding\(|gap:|spacing:' desktop/lib
rg -n --glob '*.dart' 'BorderRadius\.|BoxDecoration\(|BoxShadow\(|Duration\(|Curves\.' desktop/lib
```

命令用于发现候选；迁移前必须阅读所在组件的上下文，并在本清单中记录结论。
