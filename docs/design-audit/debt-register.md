# 设计债务总表

这是一份按“文件 + 组件 + 问题类型”聚合的全项目登记表。一个组件同类问题的多次命中合并为一条记录，`命中数`保留扫描证据；因此表格可读、可追踪，同时不会把同一问题复制几十遍。每条记录都包含文件、组件、问题类型、当前写法、目标 Token、严重程度和计划轮次。

严重程度：

- **P0**：已经绕过唯一事实源，容易造成同语义视觉分叉。
- **P1**：重复量大或会影响多页面一致性，需要在对应轮次集中处理。
- **P2**：需要设计判断、可能是合法特例，先登记再决定。

## Typography

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `widgets/matrix/matrix_add_surface.dart:267` | `_MatrixAddSurfaceState` | Typography | `fontSize: 18` | `WorkFollowMacTypography.control` 或 Matrix Control Role | P1 | D1 |
| `widgets/matrix/matrix_quadrant.dart:132` | `_MatrixQuadrant` | Typography | `fontSize: 11` | `WorkFollowMacTypography.caption` 或 Matrix Label Role | P1 | D1 |
| `widgets/sidebar.dart:542` | 隐藏输入 | Typography | `fontSize: 1` | 白名单中的技术例外 | P2 | D1 |
| `widgets/task_inspector.dart` 等 8 处 | Inspector/Editor 基线 | Typography | `Theme.of(context).textTheme.*` | 明确的 `WorkFollowMacTypography` 角色 | P0 | D1 |
| `screens/trash_screen.dart:118` | `_TrashSectionLabel` | Typography | `letterSpacing: .45` | `WorkFollowMacTracking.none` 或有记录的 Caption Role | P1 | D1 |
| `widgets/focus_timer_dialog.dart:87` | Timer display | Typography | `letterSpacing: 1.2` | `WorkFollowMacDisplay.timer` | P2 | D1 |

## Icons

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `widgets/task_editor_toolbar.dart:197` | 时间插入按钮 | Icon | `Icons.history` | `WorkFollowIcons.history` / 已有 `historyToggle` | P0 | D2 |
| `widgets/task_editor_toolbar.dart:318` | Picker 选中标记 | Icon | `Icons.check` | `WorkFollowIcons.check` | P0 | D2 |
| `widgets/task_context_menu_panel.dart:170` | 明日动作 | Icon | `Icons.wb_twilight_outlined` | `WorkFollowIcons.tomorrow` 或独立语义映射 | P1 | D2 |
| `widgets/task_schedule_panel.dart:281,287,293,557` | 日期导航 | Icon | 直接 chevron/circle glyph（4 次） | `collapse` / `circle` / `chevronNext` | P0 | D2 |
| `widgets/task_schedule_options.dart:170` | 选项头部 | Icon | 直接 down/close glyph（2 次） | `expandMore` / `close` | P0 | D2 |

## Colors

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `widgets/task_menu_style.dart` | `TaskMenuStyle.colors` | Color | Light 菜单复制 9 个 hex | `WorkFollowTheme` 菜单和状态语义色 | P0 | D3 |
| `widgets/sidebar.dart:14-20` | Light rail/context navigation | Color | 7 个局部 hex 常量 | rail/navigation semantic colors | P0 | D3 |
| `widgets/quick_add.dart:90-95` | `_SmartTextEditingController` | Color | 6 个 token 高亮 hex | Quick Add token roles | P1 | D3 |
| `features/matrix/matrix_models.dart:31-46` | `MatrixQuadrantStyle` | Color | 4 个象限 hex | Matrix quadrant semantic colors | P1 | D3 |
| `widgets/task_editor_toolbar.dart:264-276` | 高亮工具 | Color | 高亮背景和暗色文字 hex | Document Highlight Token | P0 | D3 |
| `widgets/task_context_menu_panel.dart:399` | 日期菜单 | Color | `Color(0xFFF5F5F5)` | `tokens.menuSelected` / surface role | P1 | D3 |
| `widgets/task_schedule_panel.dart:401` | 日期状态 | Color | `Color(0xfffe6d72)` | `tokens.danger` 或 Schedule Status Role | P1 | D3 |
| `widgets/task_schedule_options.dart:17` | Schedule surface | Color | `Color(0xfff6f6f6)` | `tokens.canvas` / input surface | P1 | D3 |
| `screens/home_screen.dart`、`screens/calendar_screen.dart` 等 | 各页面状态 | Color | 非透明 `Colors.*`（21 次） | Theme semantic roles | P1 | D3 |
| 全项目多个组件 | 透明/alpha 状态 | Color | `.withValues` / `.withOpacity`（64 次） | Soft/Faint/Overlay 或明确 alpha role | P2 | D3 |

## Spacing

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `widgets/sidebar.dart` | Rail、Navigation、List item | Spacing | 18 个 `EdgeInsets`、12 个 `SizedBox` | `WorkFollowSpacing` + navigation semantic aliases | P1 | D4 |
| `widgets/settings_panel.dart` | Settings sections | Spacing | 14 个 `EdgeInsets`、29 个 `SizedBox` | settings section/field spacing | P1 | D4 |
| `screens/calendar_screen.dart` | Calendar grid/Pills | Spacing | 13 个 `EdgeInsets`、12 个 `SizedBox` | calendar cell/grid spacing | P1 | D4 |
| `screens/notes_screen.dart` | Note index/detail/editor | Spacing | 12 个 `EdgeInsets`、19 个 `SizedBox` | note pane/editor semantic spacing | P1 | D4 |
| `widgets/quick_add.dart` | Input/token/property rows | Spacing | 10 个 `EdgeInsets`、11 个 `SizedBox` | Quick Add semantic spacing | P1 | D4 |
| `screens/board_screen.dart` | Columns/Cards | Spacing | 9 个 `EdgeInsets`、12 个 `SizedBox` | board column/card spacing | P1 | D4 |
| `screens/today_screen.dart` | Task workspace | Spacing | 9 个 `EdgeInsets`，部分已使用 `TaskListMetrics` | Task list/Inspector spacing | P1 | D4 |
| 全项目 | Wrap/Grid/Column | Spacing | 数字 `gap/spacing` 40 次 | Primitive scale 或组件语义 alias | P1 | D4 |

## Geometry

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `screens/home_screen.dart` | Dashboard cards/calendar | Geometry | 重复面板、Quick Add、任务标记和小日历尺寸已命名 | `HomeMetrics` | P1 | migrated · D5 |
| `widgets/quick_add.dart` | Quick Add field/panel | Geometry | 并行任务正在调整的属性面板仍有局部尺寸 | Quick Add metrics | P1 | deferred · D5 |
| `widgets/sidebar.dart` | Rail/navigation | Geometry | rail/footer/brand、颜色选择器和色块已命名 | `SidebarMetrics` / `WorkFollowLayout` | P1 | migrated · D5 |
| `screens/habits_screen.dart` | Habit cards | Geometry | 对话框、习惯标记、历史格和 metadata 尺寸已命名 | `HabitsMetrics` | P1 | migrated · D5 |
| `screens/notes_screen.dart` | Note pane | Geometry | 索引、Header、搜索、新建、空状态和关联任务尺寸已命名 | `NotesMetrics` | P1 | migrated · D5 |
| `widgets/task_schedule_panel.dart` | Schedule picker | Geometry | 面板、快捷日期、属性行和子弹层上限已命名 | `TaskScheduleMetrics` | P1 | migrated · D5 |
| `widgets/task_schedule_panel.dart`、`widgets/task_editor_toolbar.dart` | Picker/Toolbar | Geometry | 行高、工具栏控制槽和弹层宽高已命名；圆角留给 D6 | `TaskEditorMetrics` / `WorkFollowRadii` | P1 | migrated · D5 / D6 |
| `widgets/matrix/*` | Matrix cards/quadrants | Geometry | 并行新增组件的卡片几何保留，页面 Header/新增面板已命名 | `MatrixMetrics` + module whitelist | P1 | deferred · D5 |

## Surfaces

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `theme/workfollow_surface_tokens.dart` | Surface role matrix | Surface | 页面、Input、Card、Popover、Dialog、Toast 以前各自组合圆角/边框/阴影 | `WorkFollowSurfaceTokens` | P0 | migrated · D6 |
| `widgets/app_surfaces.dart` | `AppCard` | Surface | Card 自己维护 border 与 BoxShadow | `WorkFollowSurfaceTokens.card` / `WorkFollowShadows.level1` | P0 | migrated · D6 |
| `widgets/desktop_popover.dart`、`persistent_anchored_popover.dart` | Popover | Shadow | Material elevation 与黑色 shadowColor 分散 | `WorkFollowShadows.level2` | P0 | migrated · D6 |
| `widgets/task_editor_popover.dart`、`task_slash_menu.dart` | Editor/Slash Popover | Surface | Toolbar/Slash 使用局部 radius、blur、offset | `WorkFollowSurfaceTokens.popover` | P0 | migrated · D6 |
| `widgets/command_palette.dart` | Command Palette | Surface | 独立大 blur/offset 组合 | `WorkFollowSurfaceTokens.dialog` / `WorkFollowShadows.level3` | P1 | migrated · D6 |
| `widgets/quick_add.dart`、`screens/today_screen.dart`、`widgets/matrix/*`、`features/feedback/*` | 并行 Surface | Surface | 其他任务未提交的 BoxShadow/数字圆角 | 对应 Surface role | P1 | deferred · D6 |

## States

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `widgets/sidebar.dart` | Rail、Navigation、List、Tag | State | selected 25、hover 34，多层嵌套颜色/字重分支 | `TaskListColors` + navigation state matrix | P0 | D7 |
| `widgets/task_inspector.dart` | Property buttons | State | active 6、selected 3、focus 3 | control selected/focus roles | P1 | D7 |
| `widgets/task_list/task_list_row.dart` | Task row | State | hover/selected/focus 分支 4/1/3 | `TaskListColors` + focus ring | P0 | D7 |
| `widgets/task_row.dart` | Legacy task row | State | hover/focus 分支 7/6 | 与共享 TaskListRow 状态矩阵一致 | P0 | D7 |
| `widgets/task_document_styles.dart` | Checklist | State | hover 2，使用 `menuSelected` 和透明 hoverColor | Document checklist state role | P1 | D7 |
| `widgets/task_date_picker.dart` | Calendar day | State | selected 日格直接使用 accent/transparent | picker selected/hover/focus roles | P1 | D7 |
| `widgets/settings_panel.dart` | Tabs/Switches | State | selected/active 色分支 4+ | settings control state roles | P1 | D7 |
| `widgets/matrix/matrix_quadrant.dart`、`matrix_task_row.dart` | Matrix cards | State | hover/selected 直接组合颜色和阴影 | Matrix state matrix | P1 | D7 |

## Overlay / Menu

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `widgets/desktop_popover.dart` | 通用 Popover | Overlay | 定位基础统一，但 surface、shadow、focus policy 分散在调用方 | `TaskMenuStyle`/Overlay spec | P0 | D8 |
| `widgets/task_editor_popover.dart`、`persistent_anchored_popover.dart` | Editor Popover/Toolbar | Overlay | 两套 surfaceDecoration 和圆角/阴影参数 | Overlay surface role | P0 | D8 |
| `widgets/task_context_menu_panel.dart`、`task_more_menu.dart` | Task menus | Overlay | 行高、颜色和 disabled/selected 规则各自维护 | Context/More menu roles | P0 | D8 |
| `widgets/task_slash_menu.dart` | Slash menu | Overlay | 独立 metrics、glyph painter 和 focus/selection | Command menu role | P1 | D8 |
| `widgets/task_date_picker.dart`、`task_list_picker.dart`、`task_tag_picker.dart` | Property Pickers | Overlay | 各自宽度、padding、selected/empty 状态 | Picker role | P1 | D8 |
| `widgets/command_palette.dart`、`settings_panel.dart` | Global overlays | Overlay | 各自 transition/barrier/surface | Dialog/Command palette roles | P1 | D8 |

## Motion

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `features/feedback/feedback_host.dart` | Feedback HUD | Motion | 420/200/120ms、ease 曲线、TweenSequence | feedback enter/exit/fade/spring roles | P1 | D9 |
| `features/feedback/feedback_event.dart` | Feedback hold | Motion | 4000/5000/2600ms | feedback hold roles | P2 | D9 |
| `app.dart` | Shell pane/page switch | Motion | 220/180ms、easeOutCubic/easeIn | shell/panel transition roles | P1 | D9 |
| `widgets/command_palette.dart` | Command palette | Motion | 180ms + easeOutCubic | command overlay role | P1 | D9 |
| `widgets/desktop_popover.dart`、`settings_panel.dart` | Popover/Dialog | Motion | 100/180ms | popover/dialog roles | P1 | D9 |
| `screens/home_screen.dart`、`screens/today_screen.dart` | Task/list transitions | Motion | 150ms、300ms delay | task row/stagger roles | P1 | D9 |
| `widgets/task_context_menu_panel.dart` | Submenu intent | Motion | 220ms Timer | hover intent delay（与动画分离） | P2 | D9 |

## Light / Dark

| 文件 | 组件 | 问题类型 | 当前写法（命中数） | 应归属 Token | 严重程度 | 计划轮次 |
| --- | --- | --- | --- | --- | --- | --- |
| `widgets/sidebar.dart` | Light rail/navigation | Theme parity | 独立 7 个 light hex + 15 个 brightness 判断 | `WorkFollowTheme` rail/navigation surface | P0 | D10 |
| `widgets/task_menu_style.dart` | Task menus | Theme parity | Light 分支复制颜色，Dark 直接返回 tokens | Theme extension 的明暗值 | P0 | D10 |
| `widgets/task_document_styles.dart` | Checklist | Theme parity | 亮/暗模式决定 checked fill 与 check color | Document style + semantic contrast roles | P1 | D10 |
| `widgets/task_schedule_options.dart` | Schedule field | Theme parity | brightness 分支返回固定浅色 `#f6f6f6` | input surface token | P1 | D10 |
| `widgets/command_palette.dart`、`settings_panel.dart` 等 | Overlay surfaces | Theme parity | barrier/foreground 使用直接 black/white | Overlay semantic contrast roles | P1 | D10 |
