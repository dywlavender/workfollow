# Exceptions and active boundaries

这里记录不能直接套普通 Token 的值。例外需要有语义 owner；没有记录的 primitive 默认视为违规。

| 位置 | 当前值/形式 | 分类 | 原因与 owner |
| --- | --- | --- | --- |
| `theme/` Token 源 | 原始 Hex、`Icons.*`、Duration、Curve、shadow primitive | A · Token source | 这是语义层和 primitive 层的唯一事实源；业务 Widget 不得复制。 |
| `widgets/sidebar.dart` | `WorkFollowMacDisplay.accessibilityHidden`、透明点击层 | C · 技术值 | 保留无障碍/自动化 target，不参与可见排版。 |
| `widgets/focus_timer_dialog.dart` | `WorkFollowMacTracking.timer` | C · Display | 固定宽度倒计时需要正字距，属于计时器显示角色。 |
| `theme/workfollow_theme.dart` | `TaskMenuMetrics.dividerHeight` | B · Module metric | 菜单 Divider 的 13pt 高度包含上下呼吸空间，不是普通行高。 |
| `widgets/task_editor_glyph.dart` | 自定义 Path 坐标、`lineNone` | C · Drawn glyph | H1/H2/H3、B/I/U 等文字 glyph 没有可复用 Material 图标。 |
| `widgets/note_document_editor.dart` | 水平线 embed 高度 24 | C · Content render | Quill embed 的块级内容尺寸，不是普通控件高度。 |
| `screens/board_screen.dart` | drag marker 边框 1.4 | C · Board stroke | 拖拽目标的可见指示线，属于 Board 绘制参数。 |
| `screens/habits_screen.dart` | 自定义习惯标记 stroke 1.2/2 | C · Drawn control | CustomPainter/形状边缘需要独立笔画。 |
| `screens/notes_screen.dart` | 编辑器边框 1.4 | C · Editor stroke | 文档编辑 surface 的边缘校准值。 |
| `Color(value)` 清单/习惯/图表颜色 | 用户保存的内容颜色 | D · User data | 颜色来自用户或数据，不是 UI Chrome。 |
| `command_palette.dart`、`settings_panel.dart` | black alpha barrier | C · Overlay material | Dialog 遮罩需要独立半透明材质；由统一 Dialog API 管理。 |
| `features/feedback/feedback_event.dart` | 2600/4000/5000ms | C · Content policy | HUD 停留时间由反馈类型决定，不与 Motion enter/exit 混合。 |
| `screens/today_screen.dart`、`screens/matrix_screen.dart`、`widgets/quick_add.dart`、`widgets/task_document_styles.dart`、`widgets/task_inspector.dart`、`widgets/task_row.dart`、`widgets/task_schedule_options.dart`、`widgets/task_schedule_panel.dart` | 当前工作区未提交改动 | C · Active boundary | 另一项并行任务仍在维护；D11 lock test 明确跳过这些路径，合并后必须重新扫描。 |
| `features/feedback/feedback_controller.dart`、`feedback_event.dart`、`feedback_host.dart`、`feedback_scope.dart`、`feedback_sound_service.dart`、`feedback_toast.dart`、`features/matrix/matrix_models.dart`、`matrix_projection.dart`、`features/tasks/domain/chinese_work_calendar.dart`、`features/tasks/presentation/task_feedback_mapper.dart`、`widgets/matrix/matrix_add_surface.dart`、`matrix_board.dart`、`matrix_group.dart`、`matrix_quadrant.dart`、`matrix_task_editor_popover.dart`、`matrix_task_row.dart`、`widgets/task_list/task_group_header.dart`、`task_list_divider.dart`、`task_list_header.dart`、`task_list_row.dart`、`task_list_row_transition.dart`、`task_metadata_trail.dart` | 当前工作区新增组件 | C · Active boundary | 同上；白名单按文件编码，新文件不会自动继承例外。 |

`desktop/test/design_system_lock_test.dart` 将上述边界编码为窄 allowlist。新增业务文件不会自动继承例外。
