# 四季主题插画场景设计（替换实景照片背景）

日期：2026-08-23 · 状态：已确认（用户批准）
范围：仅 `design-preview/season-themes.html` 效果图；接入真实应用另行决策。

## 背景与问题

season-themes.html v4 用四张实拍照片（`assets/{spring,summer,autumn,winter}.jpg`，共约 1.3MB）作背景层 `.photo`（z-index 1）。用户反馈：太写实，与页面其余全部风格化元素（CSS 渐变天空、玻璃面板、极光、噪点、SVG 飘落物）割裂。文件中还遗留整套未被使用的 `--sc-*` 场景配色变量，说明更早版本曾是插画场景。

## 已确认的决策

1. **方向**：扁平插画场景（CSS/SVG），弃用位图素材。
2. **密度**：分层剪影 + 每季一个点睛元素；不画完整场景（玻璃面板遮住约六成画面，细节多反而显忙）。
3. **实现**：内联 SVG，填色复用遗留的 `--sc-*` 变量，明暗模式经现有变量块自动联动。

## 架构改动

- 删除 `.photo` 层规则与 4 张 jpg。
- 新增 `.scene` 层：`position:fixed; inset:auto 0 0 0; height:~32vh; z-index:1`，内含 4 幅内联 SVG，按 `body[data-season]` 控制显隐。
- 所有填色 `fill="var(--sc-*)"`；JS 不改；「背景 开/关」按钮语义改为隐藏 sky+scene（复用 `atmo-off` 类）。
- `grain`、`aurora`、飘落物、切换器均不动。

## 四季构图（远景剪影 → 中景 → 点睛元素）

| 季 | 远景 | 中景 | 点睛 |
|---|---|---|---|
| 春·樱语 | 丘陵两层 `hillA/hillB` | 樱树干 `trunk` | 三色团冠 `bl1/bl2/bl3` + 小鸟 `bird` |
| 夏·青屿 | 海面两段 `seaT/seaB` + 岛 `island` | — | 白帆船 `sail+hull` + 光环 `sunring` |
| 秋·柿染 | 远丘 `backH/midH` | 田垄条纹 `field+row` | 三色孤树 `t1/t2/t3` |
| 冬·霜松 | 雪山 `backM/cap + midM` | 雪原 `snowF/shade` + 松簇 `pine/pinecap` | 月亮+星星（仅深色，`--sc-moon-op/--sc-stars-op`） |

不再使用的 `--sc-*` 变量（如 spring 的 `wall/roof`）随清理一并删除。

## 动效

场景静态。现有 `prefers-reduced-motion` 规则不受影响。

## 验收

- [ ] 4 季 × 明暗共 8 种组合：场景配色正确、与天空衔接自然。
- [ ] 宽窄视口无横向滚动，场景裁切不变形（`preserveAspectRatio="xMidYMax slice"`）。
- [ ] 「背景 关」时天空+场景同时隐藏。
- [ ] 移除 jpg 后页面无外部图片请求。
- [ ] 现有交互（季节/明暗切换、URL 参数）不回归。
