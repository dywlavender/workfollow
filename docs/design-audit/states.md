# D7 States 盘点

## 扫描结果

- `selected:` 语法命中 60 次，分布在 18 个文件。
- Hover 相关（`hovering`、`onEnter`、`onExit` 等）命中 78 次，分布在 12 个文件。
- Focus 相关命中 71 次，分布在 21 个文件。
- Disabled/enabled 相关命中 32 次，分布在 10 个文件。
- Active 相关命中 16 次，分布在 4 个文件。

这些数字包含状态字段、回调和注释，表示需要复核的实现面，不直接等于状态缺陷数量。

## 当前状态族

| 控件族 | 现状 | D7 目标 |
| --- | --- | --- |
| Rail/Navigation/List/Tag | `sidebar.dart` 自己组合 selected、hover、文字颜色和字重 | 一个 navigation state matrix，selected 与 hover 互不冒充 |
| Task List Row | 新旧 `TaskListRow`/`TaskRow` 并存，状态分支不同 | 统一 `TaskListColors`、focus ring 和完成态 |
| Inspector Property Button | active、selected、focus 分散在属性按钮和 Picker 中 | control state matrix |
| Picker/Calendar Day | selected 常直接使用 accent，hover/focus 不完整 | picker selected/hover/focus roles |
| Checklist | 文档样式层已有 hover，但状态与菜单 Token 绑定 | 独立 checklist state role，保持中性完成态 |
| Matrix/Card | hover、selected 和阴影组合在页面组件内 | Matrix card state matrix |
| Settings Controls | Tab、Switch、Segmented control 各自处理 active/selected | settings control matrix |

## D7 检查问题

1. Hover、Selected、Focused 是否使用同一颜色或同一边框。
2. Mouse selected 与 keyboard focus 是否能同时表达而不互相覆盖。
3. Disabled 是否仍保留足够的文字/图标对比度。
4. 状态变化是否误触发尺寸、字体或布局变化。
5. Light/Dark 是否各自拥有同一状态角色，而不是在组件中写 `if (dark)`。

