# 四季插画场景接入真实应用 — 设计

日期:2026-08-24 · 状态:已确认(用户批准,含飘落物)
前置:`2026-08-23-season-scene-design.md`(效果图中已验收的场景设计)

## 目标

把效果图中已验收的四季扁平插画场景 + 飘落物动画接入真实前端(`workfollow/frontend`),复用现有主题系统,不改任何 JS 逻辑。

## 现状地基(已确认)

- `modules/theme.ts` 的 `applyAppearance()` 在 `<html>` 上维护 `data-palette`(含 `spring/summer/autumn/winter`)、`data-mode`、`data-atmosphere`;四季配色已存在(`group: 'season'`)。
- 天空渐变由 `layout.css` 的 `body::before`(fixed, z-index -1)按 `--theme-atmosphere` 渲染,全局生效(含登录页)。
- 四季面板 surface 本身为半透明设计,背景层可透出。

## 方案

1. **新增 `src/components/SeasonScene.vue`**:纯模板组件,含两个 fixed 层——
   - `.season-scene`(场景层,4 幅 SVG,移植自效果图)
   - `.season-fall`(飘落层,春花瓣/秋枫叶/冬雪花各 6 枚,夏季无;填充色沿用效果图的季节固定色,不随明暗变化,与效果图一致)
   无 props、无 store 访问、无生命周期逻辑。
2. **新增 `src/season-scene.css`**:
   - `--sc-*` 变量按 `html[data-palette="…"][data-mode="…"]` 分组,数值从效果图原样移植;
   - `.season-scene`:`position:fixed; left/right/bottom:0; height:32vh; z-index:-1; pointer-events:none`(与 `body::before` 同层,DOM 顺序保证画在天空之上);
   - `.season-fall`:`position:fixed; inset:0; z-index:30; pointer-events:none`(低于 naive-ui 弹层,高于页面内容);
   - 显隐:`html[data-palette="spring"] .season-scene .sc-spring { display:block }` 模式,非四季配色时全部 `display:none`;
   - 飘落 keyframes 移植自效果图;`prefers-reduced-motion: reduce` 下 `animation: none`(元素静止于视口外 top:-50px,等效隐藏)。
3. **`App.vue`**:在 `NConfigProvider` 内、认证分支之外挂一次 `<SeasonScene />(登录页同样生效,与 body::before 行为一致)。
4. **`app.css`**:`@import './season-scene.css'` 插在 redesign.css 之后、layout.css 之前(遵循"layout 最后"的级联约定)。

## 明确不做

- 不改 `theme.ts` / `stores/app.ts` / 任何组件 JS。
- 不加设置项开关(选四季配色即出现场景,选经典配色即消失)。
- 飘落物填充色不做明暗适配(与效果图行为一致)。

## 验收

- [ ] `npm run type-check`、`npm run build` 通过。
- [ ] 四季 × 明暗 8 组合:场景正确、与天空衔接自然;经典配色(如靛蓝)无场景无飘落物。
- [ ] 飘落物不阻挡任何点击(pointer-events none);naive-ui 弹窗在飘落物之上。
- [ ] `prefers-reduced-motion: reduce` 时无动画。
- [ ] 登录页(未登录)同样可见场景。
