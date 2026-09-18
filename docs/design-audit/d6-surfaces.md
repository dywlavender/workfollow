# D6 Surface 迁移记录

> 历史记录：本页的并行工作区边界已在 [D11.1](d11-integration.md) 收回；当前锁定测试不再跳过这些文件。

> 状态：已完成。施工边界是圆角、边框、阴影和 Surface 层级。

## 新增事实源

- `desktop/lib/theme/workfollow_surface_tokens.dart`
  - `WorkFollowSurfaceRole`：surface、input、card、popover、dialog、toast。
  - `WorkFollowSurfaceTokens`：按角色成对提供 fill、radius、border 和 shadow。
  - `WorkFollowShadows`：Level 0–4 以及 Detail 阴影。
- `WorkFollowRadii.checkbox`、`WorkFollowRadii.marker`：自定义 Checkbox 与标记的有名例外。

## 迁移规则

1. 页面内容默认使用 `surface`；输入控件使用 `input`。
2. Card 只在确实需要卡片边界时使用 `card`；raised card 才启用 Level 1。
3. Slash、More、Context、Picker、Toolbar 等浮层统一使用 `popover` 和 Level 2。
4. Command Palette 与 Dialog 使用 Level 3；反馈 HUD 保留 Level 4 的独立层级。
5. Focus ring 和 Selected 状态不通过额外粗边框表达，交互状态留给 D7。

## 迁移范围

| 区域 | 改动 |
| --- | --- |
| Card | `AppCard` 的边框/阴影组合改由 `WorkFollowSurfaceTokens.card` 生成 |
| Popover | 通用与持久 Popover 的 Material elevation、shadowColor 归入 Level 2 |
| Editor | Toolbar、Slash 和 Editor Popover 共享 Popover radius/border/shadow |
| Dialog | Command Palette 使用 Dialog Surface；主题 Dialog/Popup shape 继续读取 `WorkFollowRadii.popover` |
| Feature surfaces | Board、Home、Schedule、Picker 等数字圆角迁移到语义角色 |

## 扫描结果

| 项目 | D0/D5 命中 | D6 结果 |
| --- | ---: | --- |
| `BoxShadow` | 7 个基线 | 业务热点统一到 `WorkFollowShadows`；并行新增文件 deferred |
| 数字 `BorderRadius` | 29 个 | 普通 Widget 数字圆角已迁移；绘制参数与并行文件保留 |
| Popover/Dialog Surface | 多套局部组合 | 统一角色、边框和阴影等级 |

## 并行工作区边界

`today_screen.dart`、`quick_add.dart`、`task_row.dart`、`task_document_styles.dart` 以及新增 Matrix/Feedback/Schedule Options 组件存在其他未提交工作。本轮没有覆盖这些文件；对应 Surface 改造记录在 [白名单](whitelist.md)。
