# D1–D11 真实工作量排序

下面的排序来自 D0 扫描量和跨文件扩散范围。数量是语法命中，`迁移单元`按“同一组件/同一规则可一次处理”的粒度估计；它比直接把每个命中当成一天更可靠，但仍需在每轮截图回归后校准。

## 工作量排名

| 排名 | 轮次 | 主题 | 扫描证据 | 估计迁移单元 | 工作量 | 依赖/说明 |
| ---: | --- | --- | --- | ---: | --- | --- |
| 1 | D4 | Spacing | 224 `EdgeInsets`、291 `SizedBox`、99 `Padding`、40 gap/spacing | 约 35–50 个页面/组件角色 | XL | 数量最大，必须在 Geometry 前完成语义分层 |
| 2 | D5 | Geometry | 29 个数字圆角、162 个数字宽度、231 个数字高度 | 约 30–45 个控件族 | XL | 数字高度混合行高和布局高，需逐族确认 |
| 3 | D3 | Colors | 31 个主题外 hex、21 个非透明 `Colors.*`、64 个 alpha 变换 | 约 25–35 个颜色角色 | L | 影响 Light/Dark、状态和 Matrix/Quick Add |
| 4 | D7 | States | selected 60、Hover 78、Focus 71、Disabled 32、Active 16 | 约 20–30 个控件状态矩阵 | L | 依赖颜色和 Geometry 的语义稳定 |
| 5 | D6 | Surfaces | 91 `BoxDecoration`、7 `BoxShadow`、27 `Border.*`、29 个数字圆角 | 约 18–25 个 Surface 角色 | L | 依赖 D3/D4/D5 的角色命名 |
| 6 | D8 | Menu / Overlay | 34 个弹层 API，18 个文件；菜单/Picker/Toolbar 多入口 | 约 12–18 个浮层族 | M-L | 需统一 Focus、placement、flip 和视觉 |
| 7 | D10 | Light / Dark | 32 个 brightness 判断，10 个文件 | 约 10–15 个明暗对照面 | M | 必须在颜色和 Surface 收口后做截图矩阵 |
| 8 | D9 | Motion | 18 个数字 Duration、10 个 Curves、26 个 Animated/Tween 命中 | 约 10–15 个 Motion Role | M | hold、intent delay、transition 要分开 |
| 9 | D2 | Icons | 9 个直接 `Icons.*`，另有 2 组重复语义候选 | 约 8–12 个映射 | S-M | 低数量、高确定性，适合早期冻结 |
| 10 | D1 | Typography | 3 个数字字号、8 个 Material textTheme、2 个字距 | 约 8–13 个角色 | S-M | 依赖少，且是其它视觉比较的基线 |
| 11 | D11 | Cleanup / Design Lock | 扫描规则、白名单、Golden/静态检查 | 约 8–12 条规则 | M | 必须等 D1–D10 完成后才能锁定 |

## 实施顺序

工作量排名不改变施工依赖。实际仍按以下顺序推进：

```text
D0 → D1 → D2 → D3 → D4 → D5 → D6 → D7 → D8 → D9 → D10 → D11
```

D1 和 D2 数量小但先做，是因为它们能先冻结文字和图标事实源；D4/D5/D3 的量最大，必须预留独立回归批次，不能与其它维度混改。

## 每轮退出条件

1. 债务总表中该轮记录全部标记为 `migrated`、`accepted-exception` 或 `deferred`。
2. 白名单变更有原因和组件范围。
3. Today、Recent、Inbox、Task Detail、Notes、Calendar、Matrix、Board、Habits、Stats、Settings 与所有浮层完成回归。
4. `git diff --check` 和该轮测试通过；有视觉变化时补 Light/Dark 截图。

