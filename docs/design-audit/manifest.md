# Design Audit Manifest

本文件是 D0 的可追踪清单。每一条记录都应在对应施工轮次更新为 `migrated`、`accepted-exception` 或 `deferred`，不要直接删除历史记录。

## 记录格式

| 字段 | 含义 |
| --- | --- |
| `id` | 稳定的发现编号，后续提交和回归报告引用它 |
| `dimension` | Typography / Icons / Colors / Spacing / Geometry / Surfaces / States / Overlay / Motion |
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
| GEOM-001 | Geometry | `home_screen.dart`, `quick_add.dart`, `sidebar.dart` 等 | 宽高字面值 | `WorkFollowMetrics` / page roles | candidate | D5 |
| SURF-001 | Surfaces | 91 个 `BoxDecoration` | 页面/卡片/Popover 混用 | Surface role matrix | candidate | D6 |
| MOTION-001 | Motion | `feedback_host.dart`、`app.dart`、Popover 等 | 18 个数字 Duration | Motion Roles | candidate | D9 |

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
