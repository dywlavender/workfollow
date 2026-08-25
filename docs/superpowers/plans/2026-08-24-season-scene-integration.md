# 四季场景接入实现计划

> **状态:已作废(2026-08-24)。** 本计划未执行;四季场景已由 `c24ca55 新增四季主题` 以另一套架构实现——`frontend/src/components/SeasonalAtmosphere.vue`(Vue 响应式驱动,含天空/极光/颗粒/场景层)而非本计划的纯 CSS `SeasonScene.vue` + `season-scene.css` 方案。保留本文档仅作设计过程记录,请勿按此执行。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将效果图验收过的四季插画场景 + 飘落物接入 `workfollow/frontend`,纯 CSS 驱动,零 JS 逻辑改动。

**Architecture:** 新增 `SeasonScene.vue`(场景层 + 飘落层两个 fixed 元素)与 `season-scene.css`(`--sc-*` 变量、显隐、动画);挂载在 `App.vue` 全局;显隐与明暗由既有 `data-palette`/`data-mode` 属性驱动。

**Tech Stack:** Vue 3 SFC(纯模板)、CSS。验证:`npm run type-check && npm run build` + Playwright 对登录页截图(通过 `addInitScript` 预设 localStorage 的 `workfollow-appearance-v2-palette/mode`)。

## Global Constraints

- spec:`docs/superpowers/specs/2026-08-24-season-scene-integration.md`
- 不改 `theme.ts`、`stores/`、任何现有组件的 JS
- 场景层填色一律 `var(--sc-*)`;飘落物沿用效果图固定色
- `--sc-*` 数值、SVG 路径、keyframes 均从 `design-preview/season-themes.html` 原样移植(樱树在 `translate(300 118)`、帆船 `translate(430 138)`、孤树 `translate(300 150)`、松簇 `translate(300 196)`——注意不是计划初稿里的旧坐标)
- 提交只 stage 本任务文件(frontend 三个文件 + docs),仓库有大量无关 WIP
- 场景层 z-index -1(与 body::before 同层、DOM 靠后);飘落层 z-index 30

---

### Task 1: 场景层组件 + 变量样式 + 挂载

**Files:**
- Create: `frontend/src/components/SeasonScene.vue`
- Create: `frontend/src/season-scene.css`
- Modify: `frontend/src/App.vue`(挂载)、`frontend/src/app.css`(import)

**Interfaces:**
- Produces: `<SeasonScene />` 组件(无 props);`.season-scene`/`.sc-{season}`/`.season-fall`/`.fall-item` CSS 契约,Task 2 的飘落层复用同一文件

- [ ] **Step 1: 写入 `season-scene.css`**

内容 = 效果图的 `--sc-*` 八个变量块(spring/summer/autumn/winter × light/dark,已清理版)+ 场景层样式 + 显隐规则。选择器前缀全部用 `html[data-palette="…"]`;`.season-scene` 定位:`position:fixed; left:0; right:0; bottom:0; height:32vh; z-index:-1; pointer-events:none`,svg 默认 `display:none`,按 palette 放行。

- [ ] **Step 2: 写入 `SeasonScene.vue` 场景层**

`<template>` 根为 `<div class="season-decor" aria-hidden="true">`,内含 `.season-scene` 容器与 4 幅 SVG(从效果图 `design-preview/season-themes.html` 的 `.scene` 内原样复制,含 Task 1 修正后的坐标)。无 `<script>`。

- [ ] **Step 3: 挂载与导入**

`App.vue`:`NConfigProvider` 内、`v-if="isAuthenticatedPage"` 分支之前加 `<SeasonScene />`(import 之)。`app.css`:`@import './season-scene.css';` 置于 redesign 与 layout 之间。

- [ ] **Step 4: 类型检查 + 构建**

Run: `cd frontend && npm run type-check && npm run build`
Expected: 均通过。

- [ ] **Step 5: 登录页视觉验证**

扩展截图脚本:`page.addInitScript` 预设 `localStorage['workfollow-appearance-v2-palette']='spring'`、`…-mode='light'`,访问 `http://127.0.0.1:5173` 截登录页;换 palette/mode 重复。预期:登录页底部出现对应场景,面板半透明处可透出。

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components/SeasonScene.vue frontend/src/season-scene.css frontend/src/App.vue frontend/src/app.css docs/
git commit -m "feat: 四季插画场景接入应用(场景层)"
```

---

### Task 2: 飘落层 + 动画 + 全矩阵回归

**Files:**
- Modify: `frontend/src/components/SeasonScene.vue`(追加 `.season-fall` 层)
- Modify: `frontend/src/season-scene.css`(追加 keyframes、reduced-motion)

- [ ] **Step 1: 飘落层模板**

`.season-fall` 内按效果图移植三组各 6 枚 `.fall-item`(`.petal` 春 / `.leaf` 秋 / `.flake` 冬),保留 `--dur/--delay/left` 内联参数;夏季无飘落物。

- [ ] **Step 2: 动画样式**

keyframes `petal-fall/leaf-fall/flake-fall` 原样移植;`.petal/.leaf/.flake` 尺寸透明度同效果图;显隐按 palette;末尾追加:

```css
@media (prefers-reduced-motion: reduce) {
  .season-fall .fall-item { animation: none !important; }
}
```

- [ ] **Step 3: 全矩阵回归**

截图:登录页 4 季 × 明暗 + 经典配色(靛蓝,应无场景无飘落物)。检查:场景/飘落物随季切换;`prefers-reduced-motion` 模拟(playwright `page.emulateMedia({ reducedMotion: 'reduce' })`)下无动画;弹窗层级(手动确认 z-index 30 < naive-ui 弹层)。

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/SeasonScene.vue frontend/src/season-scene.css docs/
git commit -m "feat: 四季飘落物动画接入与全矩阵回归"
```
