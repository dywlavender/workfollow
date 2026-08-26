# WorkFollow 主题开发指南

这份文档是新增或调整主题时的长期规范。它记录的是当前项目的实现约定和验收方法，不是某一张设计稿的复刻说明。

## 1. 先理解主题由什么组成

WorkFollow 的主题不是只替换一个主色，而是由以下几层共同决定：

1. **配色（palette）**：主色、悬浮色、按下色、柔和背景、深色主色，以及浅色/深色两套区域表面。
2. **背景基调（background）**：`theme`、`neutral`、`mist`、`warm`。`theme` 使用当前配色的区域表面，其他选项使用独立的背景表面。
3. **氛围背景（atmosphere）**：场景主题（四季系列与山水系列）使用渐变、光晕、场景背景和飘落粒子；经典主题保持普通工作台，不强制加入装饰。是否为场景主题由 palette 是否提供 `atmosphere` 决定，与分组解耦。
4. **玻璃层（glass）**：只有开启氛围背景时才降低表面不透明度并启用模糊，让背景能透出来，同时保证文字和控件可读。
5. **组件状态**：选中、悬浮、焦点、禁用、成功和危险状态仍然使用语义令牌，不能因为换了主题而直接写死颜色。

当前代码中的主要事实源：

| 内容 | 文件 |
| --- | --- |
| 配色、背景、浅/深色表面、氛围和场景 | `frontend/src/modules/theme.ts` |
| 语义令牌、组件令牌、玻璃透明度 | `frontend/src/design-tokens.css` |
| 页面和组件如何应用玻璃层、编辑器层级 | `frontend/src/layout.css` |
| 季节/山水场景 DOM、粒子和动效 | `frontend/src/components/SeasonalAtmosphere.vue` |
| 设置页的主题选择交互 | `frontend/src/views/SettingsPage.vue` |
| 主题矩阵测试 | `frontend/src/modules/theme.test.ts` |

不要把长期规范放到 `docs/superpowers/specs/` 或 `plans/` 中。那些目录用于记录某一次改造的方案和执行过程，主题规范应保持稳定、可复用。

## 2. 令牌分层约定

新增颜色或表面时遵守“原始值 → 语义值 → 组件角色”的方向：

```text
主题原始值（theme.ts）
        ↓
语义变量（--theme-*、--color-*）
        ↓
组件角色（--workspace-*、--task-* 等）
```

组件样式只消费语义或组件令牌，不直接引用某个主题的十六进制颜色，也不要在组件里重新定义一套主题颜色。

当前工作台玻璃角色的基线如下。这里的百分比是 `color-mix()` 中源表面的混合比例，不等于最终计算后的 alpha；主题表面本身如果带 alpha，实际透明度会更低。

| 角色 | 经典主题 | 氛围主题基线 | 用途 |
| --- | --- | --- | --- |
| canvas | 透明 | 透明 | 让季节背景成为最底层 |
| rail | 实体 | 72% | 最左侧主导航 |
| navigation | 实体 | 68% | 文件夹、任务导航等 |
| panel | 实体 | 64% | 列表、索引面板 |
| detail | 实体 | 74% | 阅读详情、普通详情面板 |
| editor | 实体 | 58% | 笔记和任务正文编辑区 |
| input | 实体 | 80% | 输入框、选择框 |
| dialog | 实体 | 84% | 弹窗 |
| menu | 实体 | 76% | 下拉菜单、浮层 |

### 玻璃层最重要的经验

- 一个视觉区域只保留一个主要的玻璃背景拥有者。外层和滚动内容层同时刷白色半透明背景，会叠加成近似白板，季节背景就会消失。
- 编辑器正文滚动容器通常应该透明；标题栏、工具栏、底部操作区可以使用更致密的 `detail` 层。
- 输入框、弹窗和菜单要比大面积编辑区更不透明，优先保证文字、边界和焦点状态清楚。
- `backdrop-filter` 会影响包含 `position: fixed` 子元素的定位和合成。沉浸式编辑器的祖先不要随意加滤镜；需要覆盖侧栏时，要同时检查 stacking context 和父级 `z-index`，不能只提高子元素的 `z-index`。

玻璃令牌和浮层层级是同一个实现契约：

- `--glass-blur-*`、`--glass-saturation-*` 只定义材质，不决定组件位置。
- 季节主题的飘落粒子层使用 `--layer-season-fall`（30），是独立的 `position: fixed` 根元素：浮在工作台壳层（`--layer-shell`）之上、随手记等局部浮层（`--layer-local-overlay`）之下。花瓣、雪花、雨丝等粒子会从面板前方飘过，但不会盖住悬浮按钮、菜单和弹窗；沉浸编辑时被编辑器覆盖，不打扰写作。
- `--layer-local-overlay` 只用于不会离开当前面板的菜单。
- 日期、优先级、右键菜单等可能跨面板或脱离滚动容器的浮层必须挂到 `body`，使用 `--layer-popover`。
- 对话框使用 `--layer-dialog`，搜索和反馈层使用更高的专用层级。
- 不要把 `backdrop-filter` 加到浮层的祖先滚动容器上；如果一个面板需要玻璃效果，应让面板本身或伪元素成为唯一的玻璃拥有者。

笔记和任务编辑器应遵循相同的层级契约：

```text
编辑器外层：editor glass + blur
标题/工具栏/底部：detail glass + 较轻 blur
正文滚动容器：transparent
正文内容：保持清晰的文字与焦点样式
```

## 3. 新增一个主题的步骤

### 第一步：确定主题类型

- 普通配色：只提供浅色/深色表面，不加入动态场景（`group: 'classic'`）。
- 季节主题：设置 `group: 'season'`，同时提供 `atmosphere.light/dark` 和 `scene.light/dark`。
- 山水主题：设置 `group: 'scenic'`，同样提供 `atmosphere.light/dark` 和 `scene.light/dark`。与季节主题共用同一套场景机制、玻璃层和粒子层契约。

不要只做浅色场景。用户可能使用深色模式，场景颜色、文字对比度和玻璃层都必须有对应的深色版本。

### 第二步：补齐配色对象

在 `appearancePalettes` 中补齐：

- `primary`、`primaryHover`、`primaryPressed`
- `soft`、`darkSoft`
- `darkPrimary`、`darkPrimaryHover`、`darkPrimaryPressed`
- `light` 和 `dark` 两套完整的 `AppearanceSurfaceSet`

每套表面至少覆盖：`page`、`rail`、`navigation`、`list`、`detail`、`input`、`hover`、`muted`、`borderLight`、`borderNormal`。

主色要分别检查正常、悬浮、按下和禁用状态；不要用同一个亮色同时承担背景、文字和按钮前景。

### 第三步：检查背景基调兼容性

`AppearanceBackground` 类型、`appearanceBackgrounds` 列表、设置页选项、`themeVariables()` 和测试必须保持同步。背景基调不是主题的别名：选择 `neutral`、`mist` 或 `warm` 时，应替换区域表面，但仍保留当前配色的交互色。

### 第四步：接入场景（仅季节/山水主题）

- 场景层必须是 `pointer-events: none`，不能阻挡按钮和编辑器。
- 场景层必须有 `aria-hidden`，装饰不进入辅助技术阅读顺序。
- 粒子、漂浮物等动效必须响应 `prefers-reduced-motion: reduce`。
- 飘落粒子层是独立的 `position: fixed` 根元素（`--layer-season-fall`），不要放回 `.seasonal-atmosphere` 容器内——容器是 `--layer-atmosphere` 层叠上下文，子元素无法浮到壳层之上。
- 场景不能承担信息、按钮或关键对比度；关闭氛围背景后页面仍应完整可用。

### 第五步：确认根节点状态

主题切换最终通过根节点状态驱动 CSS：

```text
data-palette    当前配色
data-mode       已解析的 light/dark
data-background 当前背景基调
data-atmosphere on/off
```

新增主题不要绕过 `applyAppearance()` 直接给某个页面写内联颜色。季节配色切换时，氛围开关和场景变量也必须随之更新。

## 4. 页面应用规则

新增页面或组件时，先判断它属于哪一种表面角色，再使用对应令牌：

| 页面元素 | 推荐角色 |
| --- | --- |
| 主导航 | `--workspace-glass-rail` |
| 页面级导航、文件夹栏 | `--workspace-glass-navigation` |
| 列表、索引 | `--workspace-glass-panel` |
| 阅读详情、普通面板 | `--workspace-glass-detail` |
| 正文编辑器 | `--workspace-glass-editor` |
| 输入控件 | `--workspace-glass-input` |
| 对话框 | `--workspace-glass-dialog` |
| 菜单、Popover | `--workspace-glass-menu` |

组件如果拥有一个需要脱离面板绘制的浮层，应优先使用 `Teleport`，不要依赖子元素不断增加 `z-index` 穿透父级层叠上下文。局部菜单只有在不跨越面板边界、且祖先没有裁剪风险时才保留为普通绝对定位元素。

经典主题必须保持原有稳定表面；只在 `html[data-atmosphere="on"]` 下启用透明度和模糊规则。这样新增场景主题（四季/山水）不会误伤默认、经典或纯色背景。

### 操作反馈统一走全局反馈服务

操作结果提示（成功/失败）和任务完成提示由 `frontend/src/stores/feedback.ts` 统一管理，`FeedbackHost.vue` 在 `App.vue` 挂载一次，渲染在 `--layer-toast` 层：

| API | 展示位置 | 时长 | 用途 |
| --- | --- | --- | --- |
| `feedback.success(text)` | 右上角堆叠 | 2600ms | 操作成功（创建、保存、删除完成等） |
| `feedback.error(text)` | 右上角堆叠 | 6000ms | 操作失败，保留后端 `detail` 时优先展示 |
| `feedback.completed(text?)` | 底部居中 | 2200ms | 任务完成的“仪式感”提示 |

约定：

- 业务代码只调用 feedback store，不要再新建页面级 `actionError`/`notice` 横幅、`ActionFeedback` 实例或手写 `setTimeout` 提示。
- 页面级**加载失败**（首次读不到数据，整页空白的场景）仍用页面内的 `state-message`/`loadError` 呈现，不挤占右上角反馈；操作类失败一律走 `feedback.error`。
- 表单字段的即时校验错误留在表单附近展示，不进全局反馈。
- 破坏性操作（删除、退出、解散、清空）的确认用 `ConfirmDialog`，不要用 `window.confirm`；`ConfirmDialog` 打开时会自动聚焦确认按钮。

## 5. 视觉验收清单

每新增一个主题，至少检查以下矩阵：

1. 浅色 + 深色。
2. `theme` 背景 + `neutral` 背景；如果项目继续保留，也检查 `mist`、`warm`。
3. 首页、任务、日历、笔记、团队知识库、通知、设置。
4. 笔记普通编辑器、沉浸式编辑器、任务编辑器。
5. 输入框、弹窗、菜单、空状态、选中/悬浮/焦点/禁用状态。
6. 内容较长时的滚动、固定侧栏和固定浮层。

重点不是“能看到背景”这一项，而是同时满足：

- 背景在大面积空白处可见；
- 正文、标题、按钮和边界仍清楚；
- 玻璃层没有叠加成不透明白块；
- 沉浸式编辑器能覆盖正确区域，关闭后页面层级恢复；
- 经典主题的视觉不被季节规则改变。

## 6. 自动验证

前端改完后至少运行：

```bash
cd frontend
npm run tokens:check
npm run type-check
npm run test -- --run
npm run build
```

另外执行：

```bash
git diff --check
```

自动测试应覆盖：

- 所有主题都存在浅色/深色表面；
- 场景主题（四季/山水）都有浅色/深色氛围和场景变量；
- 所有背景基调都能生成对应的 Naive UI 颜色；
- 主色的文字前景具备对比度保护；
- 旧的主题偏好不会污染新主题默认值。

自动测试通过后仍要做实际浏览器截图。透明度、模糊、stacking context 和固定层覆盖关系，单靠 TypeScript 或单元测试无法证明。

主题矩阵的截图可以一键生成（依赖全局 playwright 和系统 Chrome，需要 dev server 与后端在本地运行）：

```bash
cd frontend
npm run visual:check                       # 全部主题 × 明暗的工作台 + 设置页
SUFFIX=after npm run visual:check          # 改动后再跑一轮,文件名带 after 便于对比
PALETTES=winter,damo SUFFIX=spot node scripts/visual-check.mjs   # 抽查部分主题
```

输出在仓库根 `output/playwright/theme-baseline/`（该目录已被 gitignore，基线仅保留在本地）。建议流程：改动前跑 `npm run visual:check` 作为基线，改完用 `SUFFIX=after` 再跑一轮，同名文件肉眼对比。

## 7. 常见错误

- 只改 `theme.ts` 的主色，没有补齐区域表面，导致某些页面仍是旧白底。
- 把所有白色容器都改成透明，结果正文和控件对比度不足。
- 在外层面板和正文滚动容器同时加玻璃背景，导致背景“看不见”。
- 只给浅色模式配场景色，深色模式出现刺眼亮色或看不见的元素。
- 给固定沉浸层的祖先加 `backdrop-filter`，导致编辑器覆盖范围或定位异常。
- 在组件 CSS 里写主题专属颜色，后续新增主题时只能继续堆覆盖规则。
- 只看设置页色板，不看实际业务页面、菜单和弹窗。
- 为桌面端项目重新引入移动端媒体查询，破坏当前固定桌面布局约定。

新增主题的目标是“新增一组完整语义值”，而不是“在旧 CSS 后面再加一组覆盖”。
