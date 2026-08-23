# 四季插画场景实现计划(season-themes.html)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用扁平插画场景层(`.scene`,内联 SVG + `--sc-*` 变量)替换 `design-preview/season-themes.html` 中写实的实拍照片背景层(`.photo`)。

**Architecture:** 单文件改动。新增 fixed 底部场景层(z-index 1,高约 32vh),内含 4 幅按 `body[data-season]` 显隐的内联 SVG;所有填色走现有 `--sc-*` CSS 变量,明暗模式零 JS 联动;删除照片资产。

**Tech Stack:** 纯 HTML/CSS/SVG。验证用 Playwright 浏览器截图(file:// URL + 页面自带的 `?season=&mode=` 参数)。

## Global Constraints

- 只改 `design-preview/season-themes.html`;spec:`docs/superpowers/specs/2026-08-23-season-scene-design.md`
- **JS 一行不改**(切换逻辑、URL 参数解析全部复用)
- 所有场景填色必须 `fill="var(--sc-*)"` 形式,禁止硬编码色值
- 场景层:`position:fixed; left/right/bottom:0; height:32vh; z-index:1; pointer-events:none`,SVG 用 `preserveAspectRatio="xMidYMax slice"`
- 场景静态,不加动画
- **仓库有大量无关 WIP 改动:提交只允许 `git add design-preview/...` 指定路径,禁止 `git add -A` / `git add .`**
- 命名契约:`.scene`(容器)/ `.sc`(svg)/ `.sc-spring` `.sc-summer` `.sc-autumn` `.sc-winter`(显隐开关选择器)

---

### Task 1: 场景层基建 + 春·樱语

**Files:**
- Modify: `design-preview/season-themes.html`(CSS 约 96-114 行照片规则区、HTML 约 437-438 行照片 div 区)

**Interfaces:**
- Produces: `.scene > svg.sc.sc-{season}` 结构;后续任务的夏/秋/冬 SVG 直接往 `.scene` 里追加同构节点

- [x] **Step 1: 删除照片层,写入场景层 CSS**

删除整个注释块 `/* ============ 实景摄影背景层 … */` 及其下 `.photo` 相关 6 条规则(`.photo`、4 条 `background-image`、`.photo::after` 及明暗两条)。

在原位置写入:

```css
/* ============ 扁平插画场景层（每季一幅，填色走 --sc-* 变量） ============ */
.scene {
  position: fixed; left: 0; right: 0; bottom: 0;
  height: 32vh; z-index: 1; pointer-events: none;
}
.scene svg { display: none; width: 100%; height: 100%; }
body[data-season="spring"] .sc-spring,
body[data-season="summer"] .sc-summer,
body[data-season="autumn"] .sc-autumn,
body[data-season="winter"] .sc-winter { display: block; }
```

并把现有规则改为(将 `.photo` 换成 `.scene`):

```css
body.atmo-off .sky, body.atmo-off .scene, body.atmo-off .overlay { opacity: 0; }
```

页面 `<title>` 改为 `WorkFollow · 四季主题效果图 v5 · 扁平插画`。

- [x] **Step 2: HTML 里替换照片 div 为场景容器 + 春季 SVG**

把 `<!-- 实景摄影背景层 -->` 注释和 `<div class="photo" aria-hidden="true"></div>` 替换为:

```html
<!-- 扁平插画场景层 -->
<div class="scene" aria-hidden="true">
  <svg class="sc sc-spring" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
    <!-- 小鸟点缀 -->
    <g stroke="var(--sc-bird)" stroke-width="3" fill="none" stroke-linecap="round">
      <path d="M330 96 q9 -9 18 0 q9 -9 18 0"/>
      <path d="M398 74 q7 -7 14 0 q7 -7 14 0"/>
      <path d="M290 66 q6 -6 12 0 q6 -6 12 0"/>
    </g>
    <!-- 远丘 -->
    <path fill="var(--sc-hillA)" d="M0 208 Q180 150 360 186 T720 176 Q900 148 1080 184 T1440 170 V320 H0 Z"/>
    <!-- 近丘 -->
    <path fill="var(--sc-hillB)" d="M0 262 Q240 214 480 246 T960 238 Q1200 216 1440 250 V320 H0 Z"/>
    <!-- 樱树（点睛） -->
    <g transform="translate(1120 118)">
      <path fill="var(--sc-trunk)" d="M-7 130 C-5 84 -9 52 -16 22 L-4 30 C-2 60 2 92 7 130 Z"/>
      <circle cx="-38" cy="10" r="34" fill="var(--sc-bl2)"/>
      <circle cx="14" cy="-18" r="42" fill="var(--sc-bl1)"/>
      <circle cx="58" cy="18" r="30" fill="var(--sc-bl2)"/>
      <circle cx="-8" cy="26" r="40" fill="var(--sc-bl3)"/>
      <circle cx="36" cy="44" r="24" fill="var(--sc-bl1)"/>
    </g>
  </svg>
</div>
```

注意:鸟在丘后面被盖住没关系(远景层次);若想露出来可把鸟的 `<g>` 移到两条丘 path 之后。

- [x] **Step 3: 浏览器验证春季两种模式**

用 Playwright 打开 `file:///Users/dongyangwei/Documents/学习/代办笔记/workfollow/design-preview/season-themes.html?season=spring&mode=light` 截图;再开 `&mode=dark` 截图。
预期:樱树三色团冠清晰、丘陵两层有前后关系;深色模式下颜色整体转暗但树冠仍偏亮粉;玻璃面板后的场景隐约可见不抢内容;无横向滚动条(`document.documentElement.scrollWidth === clientWidth`)。

- [x] **Step 4: Commit**

```bash
git add design-preview/season-themes.html
git commit -m "design: 季节预览改用插画场景层(基建+春)"
```

---

### Task 2: 夏·青屿 + 秋·柿染

**Files:**
- Modify: `design-preview/season-themes.html`(`.scene` 内追加两幅 SVG)

**Interfaces:**
- Consumes: Task 1 的 `.scene/.sc` 结构与显隐 CSS

- [x] **Step 1: 在 `.scene` 内、春季 SVG 之后追加夏季 SVG**

```html
<svg class="sc sc-summer" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
  <!-- 太阳光环（太阳本体留给天空渐变） -->
  <circle cx="1140" cy="86" r="58" fill="var(--sc-sunring)" opacity=".55"/>
  <!-- 海面上下两段 -->
  <rect y="124" width="1440" height="196" fill="var(--sc-seaT)"/>
  <path fill="var(--sc-seaB)" d="M0 196 Q200 182 420 194 T880 192 T1340 198 L1440 194 V320 H0 Z"/>
  <!-- 小岛剪影（骑在海平线上） -->
  <path fill="var(--sc-island)" d="M150 126 C186 88 232 78 268 96 C288 104 306 118 318 126 Z"/>
  <!-- 浪沫短线 -->
  <g stroke="var(--sc-foam)" stroke-width="4" fill="none" stroke-linecap="round">
    <path d="M120 252 h56"/><path d="M260 276 h44"/><path d="M520 246 h60"/>
    <path d="M700 282 h48"/><path d="M1020 250 h56"/><path d="M1240 278 h44"/>
  </g>
  <!-- 白帆小船（点睛） -->
  <g transform="translate(950 138)">
    <path fill="var(--sc-sail)" d="M0 -44 L0 6 L-30 6 Z"/>
    <path fill="var(--sc-sail)" d="M6 -34 L6 6 L30 6 Z" opacity=".82"/>
    <path fill="var(--sc-hull)" d="M-36 10 L36 10 L24 26 L-24 26 Z"/>
  </g>
</svg>
```

- [x] **Step 2: 追加秋季 SVG**

```html
<svg class="sc sc-autumn" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
  <!-- 远丘两层 -->
  <path fill="var(--sc-backH)" d="M0 168 Q200 116 400 152 T820 142 Q1040 110 1240 150 T1440 140 V320 H0 Z"/>
  <path fill="var(--sc-midH)" d="M0 214 Q260 168 520 200 T1060 192 Q1250 172 1440 202 V320 H0 Z"/>
  <!-- 田地 + 透视田垄 -->
  <rect y="238" width="1440" height="82" fill="var(--sc-field)"/>
  <g stroke="var(--sc-row)" stroke-width="7" stroke-linecap="round">
    <path d="M-20 322 L340 240"/><path d="M220 322 L500 244"/><path d="M470 322 L672 246"/>
    <path d="M740 322 L868 248"/><path d="M1010 322 L1076 250"/><path d="M1270 322 L1292 252"/>
  </g>
  <!-- 三色孤树（点睛） -->
  <g transform="translate(300 150)">
    <path fill="var(--sc-trunk)" d="M-6 90 C-4 58 -8 34 -13 14 L-3 20 C0 46 3 68 6 90 Z"/>
    <circle cx="-26" cy="-2" r="26" fill="var(--sc-t2)"/>
    <circle cx="12" cy="-20" r="32" fill="var(--sc-t1)"/>
    <circle cx="40" cy="6" r="22" fill="var(--sc-t3)"/>
    <circle cx="2" cy="14" r="24" fill="var(--sc-t1)"/>
  </g>
</svg>
```

- [x] **Step 3: 浏览器验证四种组合**

截图 `?season=summer&mode=light|dark`、`?season=autumn&mode=light|dark`。
预期:夏——海平线干净、帆船剪影可读、深色海面不发闷;秋——田垄透视线条向远处收拢、孤树三色叠冠;均无横向溢出。

- [x] **Step 4: Commit**

```bash
git add design-preview/season-themes.html
git commit -m "design: 夏·青屿与秋·柿染插画场景"
```

---

### Task 3: 冬·霜松(含深色限定月星)

**Files:**
- Modify: `design-preview/season-themes.html`(`.scene` 内追加冬季 SVG)

**Interfaces:**
- Consumes: 同 Task 2;另消费 `--sc-moon-op/--sc-stars-op` 变量(浅色为 0、深色为 1,变量块已存在)

- [x] **Step 1: 追加冬季 SVG**

要点:**月/星的透明度必须写在内联 `style` 里**(`style="opacity:var(--sc-stars-op)"`),SVG 表现属性不接受 `var()`。

```html
<svg class="sc sc-winter" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
  <!-- 星星（仅深色可见） -->
  <g fill="var(--sc-moonFill)" style="opacity:var(--sc-stars-op)">
    <circle cx="180" cy="60" r="2"/><circle cx="300" cy="34" r="1.6"/>
    <circle cx="420" cy="76" r="1.4"/><circle cx="520" cy="30" r="2"/>
    <circle cx="700" cy="58" r="1.5"/><circle cx="860" cy="36" r="1.8"/>
    <circle cx="1010" cy="70" r="1.4"/><circle cx="1330" cy="44" r="1.8"/>
  </g>
  <!-- 月亮 + 光环（仅深色可见） -->
  <g style="opacity:var(--sc-moon-op)">
    <circle cx="1210" cy="62" r="46" fill="var(--sc-moonHalo)"/>
    <circle cx="1210" cy="62" r="26" fill="var(--sc-moonFill)"/>
  </g>
  <!-- 雪山两层：backM 山体 + cap 积雪 -->
  <path fill="var(--sc-backM)" d="M0 190 L210 84 L420 190 Z M420 190 L560 108 L760 190 Z M760 190 L940 96 L1160 190 Z M1160 190 L1310 122 L1440 190 Z"/>
  <g fill="var(--sc-cap)">
    <path d="M210 84 L164 108 L184 104 L204 118 L226 102 L248 110 Z"/>
    <path d="M560 108 L524 128 L542 124 L560 136 L580 124 L600 130 Z"/>
    <path d="M940 96 L898 120 L918 116 L938 130 L962 112 L982 122 Z"/>
    <path d="M1310 122 L1278 140 L1296 136 L1312 146 L1330 136 L1346 142 Z"/>
  </g>
  <!-- 近处山影 -->
  <path fill="var(--sc-midM)" d="M0 236 L150 178 L300 230 L470 186 L640 238 L820 196 L1000 240 L1200 200 L1380 238 L1440 226 V320 H0 Z"/>
  <!-- 雪原 + 阴影起伏 -->
  <rect y="258" width="1440" height="62" fill="var(--sc-snowF)"/>
  <path fill="var(--sc-shade)" d="M0 282 Q300 266 640 282 T1440 278 V320 H0 Z"/>
  <!-- 松林小簇（点睛）：trunkW 树干，pine 树身三层，pinecap 积雪尖 -->
  <g transform="translate(160 196)">
    <g transform="scale(1)">
      <rect x="-3" y="58" width="6" height="14" fill="var(--sc-trunkW)"/>
      <path fill="var(--sc-pine)" d="M0 -6 L15 22 H-15 Z M0 12 L19 42 H-19 Z M0 30 L23 62 H-23 Z"/>
      <path fill="var(--sc-pinecap)" d="M0 -6 L9 11 L4 9 L0 13 L-4 9 L-9 11 Z"/>
    </g>
    <g transform="translate(64 22) scale(.72)">
      <rect x="-3" y="58" width="6" height="14" fill="var(--sc-trunkW)"/>
      <path fill="var(--sc-pine)" d="M0 -6 L15 22 H-15 Z M0 12 L19 42 H-19 Z M0 30 L23 62 H-23 Z"/>
      <path fill="var(--sc-pinecap)" d="M0 -6 L9 11 L4 9 L0 13 L-4 9 L-9 11 Z"/>
    </g>
    <g transform="translate(-58 34) scale(.55)">
      <rect x="-3" y="58" width="6" height="14" fill="var(--sc-trunkW)"/>
      <path fill="var(--sc-pine)" d="M0 -6 L15 22 H-15 Z M0 12 L19 42 H-19 Z M0 30 L23 62 H-23 Z"/>
      <path fill="var(--sc-pinecap)" d="M0 -6 L9 11 L4 9 L0 13 L-4 9 L-9 11 Z"/>
    </g>
  </g>
</svg>
```

- [x] **Step 2: 浏览器验证两种模式**

截图 `?season=winter&mode=light|dark`。
预期:浅色——雪山+松林安静清爽,**看不到月亮和星星**;深色——月晕、星点浮现;雪原与面板衔接自然;无横向溢出。

- [x] **Step 3: Commit**

```bash
git add design-preview/season-themes.html
git commit -m "design: 冬·霜松插画场景(深色限定月星)"
```

---

### Task 4: 清理与全矩阵验收

**Files:**
- Modify: `design-preview/season-themes.html`(残留变量、提示文案)
- Delete: `design-preview/assets/spring.jpg` `summer.jpg` `autumn.jpg` `winter.jpg`(目录清空后一并删除)

- [x] **Step 1: 删除不再使用的 `--sc-*` 变量**

逐对删除以下键(明暗两个块里都有):spring 的 `--sc-back` `--sc-wall` `--sc-roof`;summer 的 `--sc-cloud` `--sc-gull` `--sc-sun`;autumn 的 `--sc-goose` `--sc-sun`;winter 的 `--sc-mist`。其余变量(spec 构图表里的)全部保留并在 SVG 中实际使用。

- [x] **Step 2: 更新底部提示文案**

`.sw-hint` 文本由「底部切换季节与明暗 · 「背景」按钮可对比纯色与实景背景图」改为「底部切换季节与明暗 · 「背景」按钮切换天空与插画场景」。

- [x] **Step 3: 删除图片资产**

```bash
git rm design-preview/assets/spring.jpg design-preview/assets/summer.jpg design-preview/assets/autumn.jpg design-preview/assets/winter.jpg
```

- [x] **Step 4: 全矩阵验收**

用 Playwright 遍历 `?season={spring,summer,autumn,winter}&mode={light,dark}` 共 8 组合逐一截图存入 `output/playwright/`。每张检查:
1. 场景色正确随季×明暗变化,与上方天空渐变衔接无断层;
2. `document.documentElement.scrollWidth === clientWidth`(无横向滚动);
3. Network 面板无任何外部图片请求(jpg 已移除);
4. 点「背景 关」:天空+场景同时消失,再点恢复;
5. URL 参数 `atmo=off` 回归正常。

发现构图问题(元素比例、位置、遮挡)就地修 SVG 后重截。

- [x] **Step 5: Commit**

```bash
git add design-preview/season-themes.html
git commit -m "design: 清理照片资产与遗留变量,四季插画场景完成"
```
