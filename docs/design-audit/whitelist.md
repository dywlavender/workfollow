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
| 几何边界 | Divider/Border 的 1px、Quill 图片/代码/水平线、图表与 CustomPainter stroke | 属于表面边界或内容渲染参数，不是普通控件尺寸 | D5/D6 |
| 响应式几何 | Today / Editor viewport 的 clamp、动态 min/max 约束 | 由 Layout contract 根据可用空间计算，不能替换成固定尺寸 | D5 |
| 并行组件几何 | Matrix、Feedback、Schedule Options 当前工作区新增组件 | 保留并行任务的改动，待对应模块统一收口 | D5/D6 |

白名单之外的直接 `Color(0x...)`、直接 `Icons.*`、未解释的字号/字距和页面局部动画，默认进入债务总表。
