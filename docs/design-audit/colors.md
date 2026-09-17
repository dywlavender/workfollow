# D3 Colors 盘点

## 目标规范

组件只消费 `WorkFollowTheme` 的语义色，不知道主题十六进制值。品牌色只用于主要操作、当前导航、链接、明确可交互强调和 Focus；普通 Hover、Selected、正文 Checklist 和成功反馈使用对应的中性或状态 Token。

## 现有事实源

`WorkFollowTheme` 已提供 `textPrimary`、`textSecondary`、`textTertiary`、`border`、`borderStrong`、`accent`、`accentHover`、`accentSoft`、`accentFaint`、`menuSelected`、`menuDivider`、`listRowHover`、`listRowSelected`、`success`、`warning`、`danger`、`shadow`、反馈 HUD 和明暗表面颜色。`WorkFollowColors` 保存原始基元，不应被普通 Widget 直接读取。

## 扫描结果

| 发现 | 数量 | 判断 |
| --- | ---: | --- |
| 主题外 `Color(0x...)` | 31 | 明确的 D3 复核候选 |
| 非透明 `Colors.*` | 21 | 白色图标、危险文字等需按语义判断 |
| `.withValues(...)` / `.withOpacity(...)` | 64 | alpha 不是自动违规，但应确认是否已有 Soft/Faint/Overlay Token |

## 十六进制热点

| 文件 | 数量 | 当前用途 | D3 方向 |
| --- | ---: | --- | --- |
| `widgets/task_menu_style.dart` | 9 | Light 菜单复制了一套文字、边框、accent、危险色 | 删除重复 palette，统一读取 `WorkFollowTheme` |
| `widgets/sidebar.dart` | 7 | Light rail 的局部导航颜色 | 迁移到 rail/navigation 语义 Token，保留主题差异在 Theme 层 |
| `widgets/quick_add.dart` | 6 | 智能输入 token 的日期、时间、重复、标签、清单、优先级 | 建立 Quick Add token 语义，避免组件内写色板 |
| `features/matrix/matrix_models.dart` | 4 | 四象限固定颜色 | 建立 Matrix quadrant 语义色，保留四象限互相区分的要求 |
| `widgets/task_editor_toolbar.dart` | 2 | 高亮背景及暗色文字 | 迁移到文档 Highlight Token；不能使用荧光色散落在 Toolbar |
| 其它 Picker/Panel | 3 | 局部日期/时间/错误状态 | 按 D3 的状态和 surface 语义逐处判断 |

## 允许先保留、但要留记录的值

- `Colors.transparent`：布局占位、点击层和无背景状态，不能拿它代替主题 surface。
- `Colors.white`：按钮上的反色文字、Checklist 勾选等明确的对比色；应在组件规范中说明。
- 黑色 alpha 遮罩和阴影：属于 Overlay/Surface 材质，D3 记录语义，D6 再统一阴影实现。
- 代码块独立 surface：由 `TaskDocumentStyles` 负责，不应被普通正文 Token 替换。

## D3 规则

1. 先判断颜色的语义角色，再决定是否增加 Token；禁止把已有颜色简单换成另一个 hex。
2. `accent`、`success`、`danger` 不能互相代替；状态颜色和品牌颜色各自有明确用途。
3. D3 不改字号、间距、图标、圆角、阴影和布局。

