# D0 白名单

白名单只说明“为什么可以暂时保留”，不代表永远绕过 Design System。每一项在对应轮次结束时都要复核；如果能表达成语义 Token，仍应迁移。

| 类别 | 文件/值 | 允许原因 | 复核轮次 |
| --- | --- | --- | --- |
| 技术字体 | `widgets/sidebar.dart:542` 的隐藏输入 `fontSize: 1` | 输入承载不可见，不参与视觉层级 | D1 |
| Display 字体 | `WorkFollowMacDisplay.timer`、`slashHeading`、`slashHeadingIndex`、`slashOrderedNumeral` | 计时器和 Slash glyph 是专属显示角色，不是普通正文 | D1 |
| 透明色 | `Colors.transparent` | 无背景点击层、占位层、状态清除；不能代替实际 surface | D3 |
| 反色前景 | `Colors.white` 用于按钮/勾选 | 深色或品牌底上的可读性对比；应由组件角色说明 | D3/D10 |
| 遮罩/阴影黑色 alpha | Popover、Dialog、Command Palette、Feedback HUD | 材质层需要独立 alpha；D6/D8 统一角色后再决定是否保留字面值 | D3/D6/D8 |
| 代码表面 | `TaskDocumentStyles` 的 code surface 与 monospace | 代码块需要独立字体和表面，不能套正文角色 | D1/D3/D6 |
| 绘制 stroke | Matrix/Calendar/Stats 的 CustomPainter 颜色和 stroke | 绘图参数不是普通 Widget 颜色；必须有组件语义说明 | D3/D5 |
| 四象限色 | `MatrixQuadrantStyle` 四种颜色 | 四象限需要彼此区分；应在 D3 收口成 Matrix semantic palette | D3 |
| Hover intent delay | `task_context_menu_panel.dart` 的 220ms Timer | 这是子菜单意图延迟，不是动画 duration | D9 |
| Feedback hold time | `feedback_event.dart` 的 2600/4000/5000ms | 这是内容停留时长，不应和进退场动画混合 | D9 |
| Feedback spring envelope | `feedback_host.dart` 的 200ms 上升/过冲/settle | 完成 HUD 的 bounded motion envelope；时长和曲线由 `WorkFollowMotionTokens` 管理，reduced motion 时禁用 | D9 |
| 几何边界 | Divider/Border 的 1px、Quill 图片/代码/水平线、图表与 CustomPainter stroke | 属于表面边界或内容渲染参数，不是普通控件尺寸 | D5/D6 |
| 响应式几何 | Today / Editor viewport 的 clamp、动态 min/max 约束 | 由 Layout contract 根据可用空间计算，不能替换成固定尺寸 | D5 |
| 并行组件几何 | Matrix、Feedback、Schedule Options 当前工作区新增组件 | 保留并行任务的改动，待对应模块统一收口 | D5/D6 |
| 绘制圆角 | `screens/stats_screen.dart`、`widgets/task_editor_glyph.dart`、`widgets/task_slash_menu.dart` 的 `CustomPainter` | 这是图表或专用 glyph 的绘制几何，不是普通 Surface；保留在绘制层 | D6 |
| 并行 Surface | `quick_add.dart`、`today_screen.dart`、`task_row.dart`、`task_document_styles.dart`、`widgets/matrix/*`、`features/feedback/*`、`task_schedule_options.dart` | 当前由另一项未提交任务维护；本轮不覆盖，后续迁移到 `WorkFollowSurfaceTokens` | D6 |
| 并行 State | `task_row.dart`、`task_document_styles.dart`、`widgets/task_list/*`、`widgets/matrix/*`、`features/feedback/*`、`today_screen.dart`、`quick_add.dart`、`task_schedule_options.dart` | 当前由另一项未提交任务维护；D7 只建立共享状态层，后续接入时保留其业务行为 | D7 |
| 导航专属颜色 | `sidebar.dart` 的 rail、用户清单色和标签色 | 这些是导航/用户内容语义色；D7 统一状态优先级，不把专属选中色误当成全局 palette | D7/D10 |
| Destructive hover 派生色 | `WorkFollowInteractionStyles` 中由 `tokens.danger` 派生的低 alpha tint | D7 只表达 destructive 状态；D3 颜色体系不新增独立 palette | D3/D7 |
| Persistent overlay entry | `widgets/persistent_anchored_popover.dart` 的单一 controller | Toolbar 和 caret Slash 需要跨编辑器点击保持 mounted；业务组件不再直接创建或定位 `OverlayEntry` | D8 |
| 二级 Dialog route | `settings_panel.dart` 的导入预览、恢复选择、恢复确认 | 这些是确认/数据选择 Dialog，不是 anchored Menu / Picker；由 Material `showDialog` 处理 | D8 |

白名单之外的直接 `Color(0x...)`、直接 `Icons.*`、未解释的字号/字距和页面局部动画，默认进入债务总表。
