# D3 颜色体系改造

## 范围

本轮只处理颜色语义。字体、图标、间距、尺寸、圆角、边框、阴影、动画和布局保持不变。组件读取 `WorkFollowTheme` 或 `WorkFollowColorTokens` 的角色色；颜色值只在主题/Token 层定义。

## 改造前扫描

D0 对 `desktop/lib/**/*.dart` 的基线扫描结果：

| 规则 | 数量 | 处理方式 |
| --- | ---: | --- |
| 主题外 `Color(0x...)` | 31 | 迁移到语义 Token；数据颜色保留白名单 |
| 非透明 `Colors.*` | 21 | 逐处判断；危险色、菜单色迁移 |
| `.withValues(...)` / `.withOpacity(...)` | 64 | 只有已有语义 Token 才保留 alpha |

主要债务集中在：

| 文件/组件 | 原问题 | 目标 |
| --- | --- | --- |
| `task_menu_style.dart` | 浅色菜单复制文字、边框、品牌色和状态色 | 直接读取 `WorkFollowTheme` |
| `sidebar.dart` | 侧栏内嵌 7 个浅色 Hex | `WorkFollowColorTokens.lightNavigation*` |
| `quick_add.dart` | 六种智能输入 token 各自维护 Hex 色板 | 统一的 Quick Add 语义映射 |
| `task_editor_toolbar.dart` | 高亮背景和文字使用荧光 Hex | `accentSoft` / `textPrimary` |
| `task_context_menu_panel.dart` | 选中行局部写死浅灰 | `menuSelected` |
| `task_schedule_options.dart` | 日期字段局部写死浅灰 | `menuSelected` / `canvas` |
| `task_schedule_panel.dart` | 工作日/休息日标记局部写死红绿 | `warning` / `success` |
| `matrix_models.dart` | 四象限组件内写死 4 个 Hex | `WorkFollowColorTokens.matrix*` 数据可视化色板 |

## 改造后扫描

在本轮迁移后，契约扫描得到：

| 规则 | 结果 |
| --- | ---: |
| 业务 Widget 中主题外裸 `Color(0x...)` | `0` |
| 业务 Widget 中直接使用红/绿/灰等 Material 语义色 | `0` |
| 允许的 `Colors.transparent`、反色白字、遮罩/阴影黑色 alpha | 按白名单保留 |

这表示颜色字面值已经从普通业务组件移到主题或专属 Token 层；用户清单、习惯、笔记和图表中的 `Color(value)` 仍按内容颜色白名单保留。

## 本轮规则

### 文字和表面

- 普通文字使用 `textPrimary`、`textSecondary`、`textTertiary`；禁用态通过次级/三级文字的语义 alpha 表达。
- `textDisabled`、`focusRing`、`documentHighlight` 和 `documentHighlightText` 是从主题角色派生的组件语义，不允许组件重新写 alpha 或 Hex。
- 菜单、Picker、Command Palette 使用 `overlay`、`menuSelected`、`menuDivider`，不再用 `accentFaint` 表示普通 Hover/Selected。
- 任务列表继续使用 `listRowHover` / `listRowSelected` 的中性填充。
- 反馈 HUD 使用 `feedbackSurface`、`feedbackText`、`feedbackAction`，不与普通 Overlay 混用。

### 状态色

- `accent` 只用于主要操作、当前导航、链接、Focus 和明确激活状态。
- `success` 只表示完成/成功；`warning` 表示需要注意；`danger` 表示逾期、删除和失败。
- 文档检查项的完成标记仍使用中性灰和次级文字，不使用 success green。
- 日历工作日/休息日是日历语义标记，分别映射到 warning/success。

### 文档高亮

Quill 旧 Delta 仍可能保存 `background` 属性值。该值由 `TaskDocumentCommands` 从 Token 层取得以保持兼容；`TaskDocumentStyles.customStyleBuilder` 将渲染统一为当前主题的 `accentSoft`，避免入口不同导致荧光色或字体/颜色漂移。

## 明确白名单

以下值属于用户内容或数据可视化，不能强行替换成 UI Chrome 颜色：

- 清单、习惯和笔记保存的用户自定义颜色；
- Board/Calendar/Stats 图表中的清单色和数据色；
- Matrix 四象限互相区分的固定数据可视化色板（集中在 `WorkFollowColorTokens`）；
- 中国工作日/节假日文字本身；
- 图片、附件和内容本身的颜色；
- `Colors.transparent` 的点击层/占位层；
- 深色底上的 `Colors.white` 对比文字和勾选；
- Popover/Dialog/Feedback HUD 的黑色 alpha 遮罩和阴影。

## 验收

`task_color_contract_test.dart` 扫描业务 Widget，要求主题外不再出现裸 `Color(0x...)`，也不允许直接使用红/绿/灰等产品语义色。Token 文件和上述白名单由测试明确排除，避免把数据颜色误判为 UI 颜色。
