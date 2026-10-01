# Native 交互几何设计规范

日期：2026-10-01。适用：Native 属性行、菜单项、输入控件与弹层；新增及重构入口均须遵循。弹层宿主分类继续使用 [弹框架构契约](native-popup-architecture-audit.md) 的 A～F 策略，不统一固定全部弹框尺寸。

## GEO-001：状态变化与布局变化分离

同一控件从默认切换到 hover、focus、pressed、selected、expanded 时，默认只改变颜色、背景、描边、图标形态和内容；不得隐式改变 padding、spacing、对齐、列槽尺寸或父容器锚点。

需要增加内容或响应窗口尺寸的组件，必须先声明允许变化的区域与保留的锚点。例如全局 Quick Add 可向下有界增高，但保留顶边；日期子卡片独立呈现，不撑大或移动主卡片。禁止用“所有 frame 永远不变”代替组件契约。

## GEO-002：属性行的固定列契约

| 区域 | 默认 / 有值 / 展开 / hover / 编辑态的不变量 |
| --- | --- |
| 行外框 | 同一可用宽度下，行位置与高度保持一致 |
| leading icon | 固定槽宽，图标 X 不变 |
| title / value / input | 共用内容起点；文字换输入框不改变 leading X 与垂直对齐基准 |
| trailing action | `>` / `˅` / `×` 共用固定槽，位置与点击区域不因图标切换而变化 |
| 背景 / focus ring | 使用 background / overlay；不通过额外 padding 或参与布局的边框挤动内容 |

文案宽度可随值变化，不能因此挤动首尾列。清除按钮与打开按钮保持独立事件处理，清除不得再次触发行打开。

组件尺寸使用对应 Metrics 的单一来源；状态样式使用已有主题语义色。不为展开态另设一套几何常量。新增输入框必须检查其原生样式是否增加内部 inset；不能只保证外层 frame 相同。

## GEO-003：实现与验收要求

- 设计阶段列出状态、允许变化项、不变量、提交/关闭规则；缺失时先补合同，不靠局部 padding 猜测。
- 代码评审检查状态条件是否修改 padding、spacing、frame、alignment 或字体度量；如确需变化，引用明确产品合同。
- 用 NSWindow + NSHostingView 或实际弹层宿主测量图标、内容起点、右侧按钮与父框；覆盖默认→有值→展开→hover→关闭，不能只断言 Metrics 常量。
- 属性行坐标回归容差为 0.1pt；截图用于补查文字基线、输入框内部 inset 与视觉对齐，自动几何通过不等于人工视觉验收完成。
- 重构必须保留已有几何和交互断言。扩大到其他入口时逐入口验收，不因共享组件通过就登记为全局已通过。

## 缺陷登记：GEO-BUG-001 / 日期属性行展开右移

- **现象**：点击“时间”“重复”后图标与文字向右移动。
- **已确认原因**：`SchedulePropertyRow` 使用 `presentation.isExpanded ? 10 : 2` 的水平 padding，展开导致内容起点右移 8pt；不是子卡片宽度变小造成。
- **修复**：统一使用 `ScheduleMetrics.propertyRowHorizontalPadding = 2`，展开仅改变背景与 trailing 图标；子卡片保持独立定位。
- **回归资产**：`SchedulePanelInteractionTests.testPropertyColumnsStayFixedWhenOpenedHoveredOrReplacedByTimeEditor` 检查时间/重复在无值、有值、展开、hover 状态的 icon/value/trailing X 与 row frame，包含时间 TextField 替换。
- **验收记录**：相关交互与容器/面板渲染共 11 项自动测试通过。该修复轮未做手动截图验收。其他属性入口仍需按本规范逐项核查。

后续同类问题追加缺陷条目并关联组件与回归测试，不只记录截图或“已调好间距”。
