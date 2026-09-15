# Web → Flutter macOS 视觉与交互迁移规范

版本：2026-09-15
适用分支：`feature/flutter-personal-desktop`
目标：让 macOS 本地个人版以 Web 端现有实现为可验证的尺寸、排版、颜色和交互基准，同时保留本地版的个人化范围。

## 0. 先定基准：哪些是事实，哪些是取舍

### 0.1 Web 端是迁移基准

本规范中的尺寸、文字角色、颜色角色、间距、圆角和状态语义均先从 Web 端读取，不以截图目测值替代：

| 基准 | 文件 | 责任 |
| --- | --- | --- |
| 令牌和动态主题 | `frontend/src/design-tokens.css`、`frontend/src/modules/theme.ts` | 颜色、字体、字号、字重、行高、间距、圆角、阴影、动效、层级 |
| 组件基础样式 | `frontend/src/styles.css` | 表单、按钮、任务行、任务详情、编辑器、弹框的基础结构 |
| 视觉覆盖 | `frontend/src/redesign.css` | 当前任务工作台、导航、列表、详情、编辑器的最终视觉 |
| 页面尺寸和响应式 | `frontend/src/layout.css` | 工作区列宽、窗口断点、滚动和高度约束 |
| 组件结构和行为 | `frontend/src/views/TodosPage.vue`、`frontend/src/components/task/*`、`frontend/src/components/todo/*`、`frontend/src/components/notes/*` | 页面状态、按钮、菜单、弹框、键盘和数据操作 |

导入顺序也是事实的一部分：`frontend/src/main.ts` 先加载 `design-tokens.css`，再加载 `app.css`；`app.css` 的顺序是 `styles.css` → `redesign.css` → `layout.css`。因此迁移时以最终计算结果为准，不能只复制 `styles.css` 中被后续规则覆盖的值。

### 0.2 Web 的主题矩阵不能和滴答清单截图混成一个基准

Web 支持 13 个配色、3 个明暗模式选项和 4 个背景预设。截图只适合作为 TickTick 的视觉参考，不是代码中的尺寸来源。为了避免“每次凭感觉改一个数字”，先固定一个可验收的 profile：

* **Web parity / neutral（默认验收 profile）**：`default + light + neutral`。页面 `#F7F8FA`，导航 `#F3F5F8`，列表和详情白色，主色 `#4F46E5`。
* **TickTick teal（产品决定后才启用）**：`teal + light + theme`。页面 `#F4FAF9`，导航 `#EDF8F6`，列表 `#FFFFFF`，详情 `#FCFEFE`，主色 `#0F766E`。

如果本地版最终选择截图中的青绿色外观，应把它作为一个明确的 Flutter theme profile，而不是把截图中的青绿色散落写进组件。第一阶段验收仍需能切换到 Web parity profile，以便确认迁移的结构没有被主题差异掩盖。

### 0.3 本地版范围

本轮 macOS 是个人本地版，Web 的团队协作、团队代办、分配、知识库审核、投稿、分享权限和协同状态不迁移到产品功能中。它们只保留在“Web 有、Flutter 不做”的范围表中，不得为了视觉对齐在个人版里重新出现。

应迁移的个人能力：任务视图、清单、标签、任务列表、固定任务详情/编辑栏、日期/提醒/重复/优先级、任务正文、附件和关联、笔记、回收站、设置、搜索、快速录入、撤销和本地保存状态。

### 0.4 本轮执行状态（2026-09-15）

本轮按“审计 → 令牌 → 工作区布局 → 自动化验收”的顺序执行，三个子 agent 分工如下：

| 子任务 | 落地内容 | 验收 |
| --- | --- | --- |
| Web 审计 | 新增本规范，记录最终 CSS cascade、尺寸、角色、断点和未迁移范围 | 文档审查 |
| Flutter 主题 | `WorkFollowTheme` 增加 Web 字体、颜色、间距、圆角、动效、层级和布局契约 | `web_theme_parity_test.dart` 7 项通过 |
| Flutter 布局 | 任务固定列表/详情列、218/430/1px/320 几何、笔记 300/270 列表、上下文第二栏 | `web_layout_parity_test.dart` 3 项通过 |

本轮完成的是 Phase 1、Phase 2 的令牌和上下文导航基础，以及 Phase 3/5 的首批几何迁移；统一 Popover 基础设施、列表拖拽持久化、全量 raw 字号清理和实机逐项交互验收仍按下方 Phase 4–6 继续。代码已通过完整 Flutter 测试和 Release 构建，但这不等同于“所有范围项已经完成”。

## 1. Web 令牌 → Flutter 令牌映射

### 1.1 颜色角色

Flutter 只允许组件消费 `WorkFollowTheme` 的语义字段；禁止在 screen/widget 中新增 `Color(0x...)`。颜色值由 theme profile 集中维护。

| Web 令牌 | Web parity / neutral（light） | TickTick teal profile（light） | Flutter 语义字段 |
| --- | --- | --- | --- |
| `--theme-bg-page` / `--color-bg-page` | `#F7F8FA` | `#F4FAF9` | `canvas` |
| `--theme-bg-rail` | `#F1F3F6` | `#E6F5F2` | `rail`（若使用独立一级栏则另设 rail） |
| `--theme-bg-navigation` | `#F3F5F8` | `#EDF8F6` | `sidebar` / `sidebarGradient` |
| `--theme-bg-list` | `#FFFFFF` | `#FFFFFF` | `content` |
| `--theme-bg-detail` | `#FFFFFF` | `#FCFEFE` | `inspector` |
| `--theme-bg-input` | `#FAFBFC` | `#F6FBFA` | 输入框 surface |
| `--theme-bg-hover` | `#F1F3F6` | `#E7F5F2` | hover surface |
| `--theme-bg-selected` | `#EEF2FF` | `#F0FDFA` | `accentSoft` |
| `--theme-text-primary` | `#171A21` | `#171A21` | `textPrimary` |
| `--theme-text-secondary` | `#5F6672` | `#5F6672` | `textSecondary` |
| `--theme-text-tertiary` | `#6B7280` | `#6B7280` | `textTertiary` |
| `--theme-border-light` | `#EAECF0` | `#D8EAE6` | `border` |
| `--theme-border-normal` | `#DDE1E7` | `#C7DDD8` | `borderStrong` |
| `--palette-primary` | `#4F46E5` | `#0F766E` | `accent` |
| `--palette-primary-hover` | `#4338CA` | `#115E59` | `accentHover` |
| `--palette-primary-active` | `#3730A3` | `#134E4A` | pressed state |
| `--palette-primary-soft` | `#EEF2FF` | `#F0FDFA` | `accentSoft` |
| `--status-success-600` | `#237A57` | `#237A57` | `success` |
| `--status-warning-600` | `#A15C08` | `#A15C08` | `warning` |
| `--status-danger-600` | `#B13F50` | `#B13F50` | `danger` |

Web 的季节和风景主题还会将 surface 设置为带 alpha 的颜色，并使用 `--theme-atmosphere`。本地版先不把氛围背景带进任务/笔记验收；如果以后迁移，需要沿用 `canvas → rail/navigation → list → detail → overlay` 的层级，不能给每个滚动容器单独加 blur。

### 1.2 字体、字号、字重和行高

Web 基础字体是 `Inter, "Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif`。macOS Flutter 采用 `.SF Pro Text`，中文回退 `PingFang SC`、`Hiragino Sans GB`、`Arial Unicode MS`；不要对每个组件指定不同字体。

| Web 角色 | 基础值 | 计算含义 | Flutter 目标 |
| --- | ---: | --- | --- |
| `--type-body-*` | 14px / 400 / 1.6 | 普通正文 | `body` |
| `--type-page-title-*` | 22px / 600 / 1.25 | 页面主标题 | `pageTitle` |
| `--type-section-title-*` | 16px / 600 / 1.25 | 分组和面板标题 | `sectionTitle` |
| `--type-panel-title-*` | 14px / 600 / 1.35 | 面板内标题 | `panelTitle` |
| `--type-navigation-*` | 13px / 600 / 1.5 | 第一栏/第二栏导航 | `navigation` |
| `--type-list-title-*` | 13px / 500 / 1.5 | 任务/笔记列表标题 | `taskTitle` / `listTitle` |
| `--type-supporting-*` | 12px / 400 / 1.5 | 描述、摘要、辅助文字 | `supporting` |
| `--type-supporting-compact-*` | 11px / 400 / 1.5 | 列表次级信息 | `supportingCompact` |
| `--type-meta-*` | 10px / 400 / 1.5 | 日期、数量、状态标记 | `metadata` |
| `--type-control-*` | 12px / 600 / 1.5 | 按钮和控件 | `button` |
| `--type-editor-title-*` | 20px / 600 / 1.35 | 编辑器标题 | `editorTitle` |
| `--type-editor-body-*` | 14px / 400 / 1.85 | 富文本正文 | `editorBody` |

Web 在有效宽度 ≥1600px 时会把基础字号整体向上调一级：body 15px、body-sm 14px、label 13px、title-sm 17px、heading 23px 等，同时增加 spacing 和 rail 宽度。Flutter 要用一个 `MediaQuery` 计算出的 density/scale profile 一次性调整整套令牌，禁止只放大标题或图标。

颜色层级验收规则：

* 主导航标题、任务标题、笔记标题、编辑器正文使用 `textPrimary`，未选中项不能因为“辅助状态”被误设成 `textSecondary`。
* 分组标题、描述、来源、保存状态和数量使用 `textSecondary` 或 `textTertiary`，必须有明确角色，不直接写灰色。
* 日期、提醒、重复、优先级使用状态色：逾期 `danger`，中优先级 `warning`，完成/保存成功 `success`，普通强调 `accent`。
* 禁用状态使用 `textTertiary` 的透明度和 `border`，不改变布局尺寸。

### 1.3 间距、圆角、阴影和动效

| Web 令牌 | 值 | Flutter 令牌 |
| --- | ---: | --- |
| `--space-1 … --space-8` | 4 / 8 / 12 / 16 / 20 / 24 / 28 / 32px | `WorkFollowSpacing.xxs … xxl`，补齐 `28` |
| `--radius-xs` | 4px | `micro` |
| `--radius-sm` | 6px | `control` |
| `--radius-md` | 8px | `surface` |
| `--radius-lg` | 12px | `card` / `popover` |
| `--radius-full` | 999px | `pill` |
| `--shadow-xs` | `0 1px 2px rgb(17 24 39 / .03)` | 轻卡片阴影 |
| `--shadow-sm` | `0 6px 18px rgb(17 24 39 / .08)` | popover/浮层阴影 |
| `--shadow-dialog` | `0 24px 64px rgb(17 24 39 / .16)` | 对话框阴影 |
| `--motion-duration-fast` | 160ms | 快速 hover/focus |
| `--motion-duration-normal` | 240ms | 面板/列宽过渡 |
| `--motion-ease-standard` | `cubic-bezier(.2, 0, 0, 1)` | Flutter 曲线近似 |

## 2. 工作区尺寸契约

### 2.1 任务工作区

Web 最终规则（`layout.css` 最后加载）如下，Flutter 的 `TaskWorkspace` 必须以同样的列语义实现：

| 有效窗口宽度 | 第一栏任务视图 | 任务列表 | 分隔线 | 固定详情/编辑栏 |
| --- | ---: | ---: | ---: | ---: |
| ≥1120px | 218px | `minmax(360px, 430px)`，可拖拽 | 1px | `minmax(320px, 1fr)` |
| ≥1120px，第一栏折叠 | 0px | `minmax(360px, 430px)` | 1px | `minmax(320px, 1fr)` |
| 1024–1119px | 218px | `minmax(300px, 1fr)` | 无独立拖拽列 | `minmax(280px, 1fr)` |

规则：

* 详情栏在 ≥1120px 始终占位，不因点击任务才创建；没有选中任务显示空状态。点击任务只改变详情内容，不改变三栏结构。
* 任务列表宽度初始 430px，用户拖拽范围必须有最小/最大值并持久化；不能用窗口 `32%` 代替固定工作台契约。
* 第一栏宽度固定为 218px，内部内容可滚动；清单/视图项目默认填满第二栏，不额外设置脱离 Web 契约的 `172px` 最大宽度。若要复刻 TickTick 的窄分类视觉，应另建明确的视觉 profile 并单独验收。
* 任务列表、详情正文各自滚动；父级工作区不因正文高度被撑开。

### 2.2 应用一级栏和任务第二栏

Web 的一级栏由 `--workspace-rail-width` 控制：基础 152px，≥1600px 为 160px。当前 macOS 个人版可以保留“窄图标 rail + 可读上下文栏”的原生适配，但必须保证：

* rail 是独立视觉平面，宽度、图标、激活态和底部设置/主题按钮不混入任务第二栏。
* 点击一级入口后，第二栏由 `ContextNavigation` 按模块切换；任务栏只展示任务视图、清单、标签，笔记栏只展示笔记视图/文件夹，日历/四象限/看板/习惯/统计只展示本模块的最小导航。
* 第二栏标题和未选中项目使用 `textPrimary`；分组标签、数量和辅助描述才使用次级色。
* personal 版不要出现 Web 的团队协作入口、团队知识库、通知 badge 和成员分配按钮。

### 2.3 笔记工作区

| 有效窗口宽度 | 文件夹/导航 | 笔记列表 | 编辑器 |
| --- | ---: | ---: | ---: |
| ≥1280px | 220px | 300px | 剩余空间 |
| 1024–1279px | 190px | 270px | 剩余空间（最小 420px） |

笔记页面与任务页面共享 shell、颜色和 typography，但不共享任务属性按钮。文件夹栏、笔记列表栏、编辑器栏分别拥有边界和滚动；选中的笔记用 `accentSoft`/accent 左侧标识；空状态和新建菜单不能把任务操作带入笔记栏。

## 3. 任务页面逐项迁移规格

### 3.1 任务第二栏（视图、清单）

Web 结构来自 `TodosPage.vue`：

1. 分组：`代办视图`、可选的 `协作`、`记录`、`清单`。
2. 个人版只保留个人视图和清单；建议顺序为 `所有`、`今天`、`本周`、`无日期`、`本月`、`已完成`，是否展示“记录”由产品决定。
3. 每一行由图标、标题、右侧数量组成；hint 不在桌面常态显示，只有辅助说明或无障碍标签保留。
4. active 行用 `accentSoft`，标题和图标使用 `accent` 或 profile 指定的 active foreground；数量不要单独形成大色块。
5. 清单标题右侧“+”创建清单；自定义清单 hover/focus 时才显示重命名/删除，不改变行宽。
6. 当前选中的第一栏模块必须决定第二栏内容，不能无论选择笔记、日历、回收站还是统计都渲染完整任务导航。

Flutter 对应：`desktop/lib/widgets/sidebar.dart` 的 `AppRail`、`_ContextNavigation`、`_TaskNavigation`；任务数据由 `WorkspaceController` 提供，视觉只消费 theme/metrics。

### 3.2 任务列表头部和快速录入

Web 最终任务列表头部：

* 列表 header 高度 58px，左右内边距 18px；标题 16px/600，左侧是导航折叠按钮；排序和更多按钮 30–32px hit target。
* 快速录入栏在列表内固定可见，不是点击后才出现的第二个编辑器。外层上下间距约 10px，输入框高度 52px（普通触发态 48px），圆角 12px。
* 输入框右侧日期 chip 和更多设置按钮在同一行；Return 创建，Esc 先关闭当前面板、再退出输入焦点；解析到日期/重复/标签时显示 recognition row，取消单个 token 不影响标题。
* 日期面板、更多面板、清单子菜单、标签子菜单同一时间只允许打开一个；子菜单有返回按钮，点击外部或 Esc 收起。

Flutter 对应：`desktop/lib/screens/today_screen.dart`、`desktop/lib/widgets/quick_add.dart`、`task_date_picker.dart`、`task_list_picker.dart`、`task_tag_picker.dart`、`task_repeat_picker.dart`。

### 3.3 任务分组、行和操作

Web `TaskListGrouped.vue` 的分组顺序是：逾期、今天、明天、未来、未安排、终态（已完成/已放弃）。每个分组标题高度约 34px，分组间距 8px。

任务行最终规则：

* 最小高度 48px，左右内边距 8px；复选框列约 26px，内容列自适应，尾部日期/时间独立对齐。
* 标题 13px/500，描述 11px/400，元数据 10px/400；标题保持主文字黑色，描述和清单名才是辅助灰色。
* 选中态只使用浅色 surface，不增加粗边框；hover/focus 有明确背景；完成态降低透明度并保留可恢复操作。
* 逾期日期使用 danger，今天带时间使用 accent，优先级使用 danger/warning/accent；重复、提醒、标签和清单元信息保持紧凑，不把所有属性变成按钮。
* 日期按钮点击直接打开日期编辑 popover；行内更多按钮只在 hover/focus/selected 显示，右键同样打开完整上下文菜单。
* 任务行更多菜单顺序：设置日期、设置提醒、设置重复、优先级、移动到清单、添加标签；分隔线后是完成/恢复、放弃、复制、复制链接、删除。删除为 danger，其余使用主文字。

Flutter 对应：`desktop/lib/widgets/task_row.dart`、`task_context_menu.dart`、`task_more_menu.dart`、`task_date_picker.dart`、`task_priority_picker.dart`、`task_list_picker.dart`、`task_tag_picker.dart`。

### 3.4 固定任务详情/编辑栏

Web 在桌面任务工作区把详情作为固定第三栏；Flutter 必须保持同样的“选中前后栏位不跳动”体验。详情分为三层：

1. **顶部属性条**：完成 checkbox、分隔线、日期按钮、（个人版不显示团队分配）、优先级、更多。高度约 58px；属性图标 18px 左右，按钮 hit target 32px。
2. **正文编辑区**：标题和正文都在详情栏内，正文滚动；编辑工具栏固定在正文区域顶部，不能随着正文第一行滚出视口。标题 20px/600，正文 14px/1.85；正文宽度有可读上限，不随详情栏无限拉伸。
3. **底部状态条**：来源/清单、保存状态和更多小操作保持在详情底部；保存状态可见但不能抢占正文空间。

详情操作映射：

| 操作 | 触发 | 结果 |
| --- | --- | --- |
| 完成/恢复 | 顶部 checkbox 或列表 checkbox | 状态更新，列表分组和详情状态同步 |
| 日期 | 顶部日期 chip、列表日期 | 打开锚定于触发按钮的日期面板 |
| 优先级 | flag 按钮、行菜单 | 打开锚定于 flag 的优先级菜单 |
| 正文格式 | 固定 toolbar、选中文本 bubble menu、`/` | 只影响正文，保持原链接/结构 |
| 标签 | 属性/`/`/行菜单 | 只更新标签，面板不覆盖输入焦点 |
| 子任务/附件/关联 | 正文 `+` 或 slash command | 插入正文块或关联数据 |
| 更多 | 顶部更多 | 只显示当前任务可用的来源/删除等操作 |
| 关闭详情 | 仅窄窗或明确关闭入口 | 桌面宽窗默认不因双击/单击关闭固定栏 |

Flutter 对应：`desktop/lib/widgets/task_inspector.dart`、`task_document_editor.dart`、`task_editor_toolbar.dart`、`save_status_footer.dart`。当前 `persistentInspector` 默认应为 true；若保留设置开关，关闭只作为明确的 list-only 选项，不得改变默认验收截图。

### 3.5 Popover / Menu 几何系统

所有菜单必须使用统一的 anchor → overlay 定位器，不允许每个按钮手写不同 `top/left`：

* anchor 取按钮在全局坐标的 `Rect`；菜单优先贴 anchor 的下/右侧，超出窗口时按四个边界翻转或 clamp。
* 日期菜单宽度约 340px，优先级约 175px，任务上下文菜单约 232px，slash menu 约 260px；这些值只能出现在 popover token 中。
* 菜单与触发按钮间距约 6px；menu row 35–40px，左右内边距 8px，图标 16–18px，文字 13px。
* z-order 统一：shell < local overlay < popover < dialog < search < toast；点击外部、Esc 和路由切换都要关闭浮层。
* 菜单位置测试必须覆盖：顶部按钮、底部按钮、右边缘、窄窗、任务列表滚动后、详情滚动后；验证菜单跟随当前 anchor 而不是停在旧坐标。

Flutter 对应：`desktop/lib/widgets/desktop_popover.dart` 及所有 `task_*_picker.dart`/`task_*_menu.dart`。这部分是独立基础设施，不在业务 widget 中复制定位算法。

## 4. 笔记页面逐项迁移规格

### 4.1 导航和列表

Web `NoteNavigation.vue` 的个人导航为：最近、全部、收件箱、收藏；下方是我的文件夹。团队导航全部不迁移。笔记列表 `NoteList.vue`：header 只显示当前笔记视图标题和新建菜单；列表行显示标题和更新时间，选中态使用 accent/左侧标识，删除按钮 hover/focus 显示。

Flutter 对应：`desktop/lib/screens/notes_screen.dart`、`note_document_editor.dart`。笔记不能复用任务清单的日期分组、优先级、完成 checkbox 或任务更多菜单。

### 4.2 笔记编辑器

笔记编辑器和任务正文共用字体角色、Rich Document 结构和 toolbar icon scale，但 surface、标题、附件区和保存状态按笔记页面契约排列。编辑工具栏高度约 42px、按钮 hit target 28–32px、正文 14px/1.85；颜色/链接/表格/附件菜单应沿用同一个 popover 几何系统。

## 5. Flutter 代码落地顺序

按依赖关系执行，完成一层再进入下一层：

### Phase 0：建立基线（只读）

1. 在 Web 1440×900、1280×800、1120×800、1024×768 固定窗口截取任务无选中/有选中/菜单打开/编辑器打开；笔记同样截取三栏和编辑器。
2. 用浏览器 computed style 记录实际列宽、header 高度、row 高度、字号、颜色；记录当前 Flutter 同一窗口的数值和截图。
3. 建立差异表，先消除“当前包是不是最新”“旧进程未退出”造成的误判；每次验收显示 app bundle、可执行文件时间和当前 git 提交说明。

### Phase 1：令牌和基础组件

1. 完成 `WorkFollowTheme` 的语义颜色、字体、字号、行高、spacing、radii、shadow、motion 和 breakpoint profile。
2. `AppIcon`、`AppIconButton`、`SoftPill`、`SectionLabel`、`AppSurface` 只接受语义 token；删除新增的 raw `TextStyle(fontSize: ...)` 和 raw `Color`。
3. 先用 Web parity / neutral profile 通过设计系统测试，再加 TickTick teal profile。

### Phase 2：shell 和上下文导航

1. 实现一级 rail 与第二栏独立 surface、尺寸和激活态。
2. 将 `WorkspaceView` 映射为上下文导航状态；每个一级入口只能渲染自己的最小按钮集合。
3. 对齐任务第二栏的 218px 宽度、分组、清单行、数量和 hover actions；明确清单宽度是否采用 Web full-width 或 TickTick variant。

### Phase 3：任务列表工作区

1. 固化 218 / 430 / 1 / rest 的三栏布局及 1024–1119 断点。
2. 对齐 list header、快速录入、日期分组、任务行、日期尾部和 hover actions。
3. 接入真实拖拽/键盘调整列表宽度，并持久化。

### Phase 4：固定详情和编辑器

1. 固化详情 top / body / footer 三层，不再使用点击任务临时弹出的独立编辑页面。
2. 对齐标题、正文、toolbar、bubble menu、来源和保存状态。
3. 用统一 Popover 系统改造日期、提醒、重复、优先级、标签、更多、slash、附件和关联菜单。

### Phase 5：笔记、回收站和设置

1. 笔记按 220 / 300 / rest 三栏迁移，删除任务专属操作。
2. 回收站是否复用任务工作区由产品范围决定；如果保持独立数据页面，视觉仍消费同一套 list/detail surface、字体和图标 token。
3. 设置只保留个人本地数据、外观、迁移、备份/恢复等本地能力。

### Phase 6：验证和交付

1. 运行单元/Widget 测试、静态分析、macOS release build。
2. 每个目标窗口生成 Flutter 截图，与 Web baseline 并排检查；所有变化记录在验收表，不用“看起来差不多”关闭。
3. 先提交代码和构建产物，再在确认退出旧进程后启动最新 bundle 验收。

## 6. 最小验收清单

### 结构和尺寸

- [ ] 1440px 窗口任务页：第一栏 218px、列表初始 430px、1px 分隔线、详情始终占位。
- [ ] 1280px 窗口：任务标题、快速录入和详情正文不挤压；列表/详情分别滚动。
- [ ] 1024–1119px：列宽降级为 218 / list / detail，详情仍可编辑，不出现横向溢出。
- [ ] 第一栏切换到笔记、日历、看板、习惯、统计、回收站后，第二栏只显示对应模块按钮。
- [ ] 清单行不出现不在基准中的固定 172px 截断；若使用 TickTick 窄分类变体，有独立设计 token 和验收截图。

### 字体和颜色

- [ ] 第二栏未选中标题为 `textPrimary`，不是整栏灰色；分组标签/数量才是次级色。
- [ ] 任务标题、笔记标题、编辑器正文、按钮文字分别命中指定 typography role；没有局部 raw font size。
- [ ] 列表、详情、导航、rail surface 层级与所选 profile 一致；不存在仍使用旧紫灰色的孤立区域。
- [ ] 逾期/优先级/完成/今天时间颜色分别命中 danger/warning/success/accent。
- [ ] 所有图标使用语义 icon catalog 和规定 size/stroke；不能只改文字而保留旧图标尺寸。

### 任务操作

- [ ] 点击任务只更新固定详情栏内容，三栏不跳变。
- [ ] 单击日期、提醒、重复、优先级、标签、更多都从触发按钮旁打开，靠近边缘时自动翻转/clamp。
- [ ] 右键任务和行内更多打开同一套菜单；菜单顺序、分组和 danger 删除项一致。
- [ ] Return 创建快速任务；Esc 按“关闭子菜单 → 关闭面板 → 释放输入焦点”顺序工作。
- [ ] 编辑标题/正文后保存状态正确，退出后重新打开内容保持；原链接、表格、附件和富文本结构不丢失。

### 笔记操作

- [ ] 笔记导航只展示个人笔记视图和文件夹；不出现任务日期/优先级/完成操作。
- [ ] 笔记列表选中、删除、新建菜单和编辑器 toolbar 的尺寸/颜色与任务共用基础 token。
- [ ] 笔记编辑器正文滚动、保存状态、附件/链接/表格菜单可用，菜单位置遵循统一 popover 系统。

### 工程质量

- [ ] `flutter test --no-pub` 全部通过，新增尺寸/颜色/交互探针覆盖本规范关键数字。
- [ ] `dart analyze desktop` 无 error、无 warning；弃用提示需有记录和后续计划。
- [ ] `flutter build macos --release --no-pub` 成功；启动的是本次构建 bundle，不是旧进程或旧副本。
- [ ] 交付记录包含窗口尺寸、profile、bundle 路径、构建时间、测试结果和未迁移范围。

## 7. 当前已知偏差（迁移开始前必须处理）

以下是从当前 Flutter 实现可以直接确认的偏差，不应继续用局部调数字掩盖：

1. 当前 macOS shell 将一级 rail 与第二栏组合为约 242px（52px + 190px），而 Web 任务工作区的任务视图栏是 218px；必须明确这是“原生双层 shell”还是要完全按 Web 三栏比例迁移。
2. 当前 Flutter 有 `listItemMaxWidth = 172` 的 TickTick 视觉特例；Web 端清单项目是第二栏内的 full-width 行，二者不能同时被称为 Web parity。
3. 当前 Flutter 已有独立 `rail`、`sidebarGradient` 和青绿色 profile，但 Web 的默认验收 profile 是 `default + neutral` 的中性灰白；必须在验收记录中写明选择的 profile。
4. Flutter 仍有部分 screen 内联 `TextStyle` 和固定字号；令牌迁移未完成前，单张截图不能证明全局字体已经对齐。
5. Web 任务详情在桌面宽窗是固定第三栏；任何“点一下才展示编辑栏”的 Flutter 行为都属于结构偏差，不是动画问题。

完成迁移的判定不是“某个按钮看起来像”，而是：同一 profile、同一窗口尺寸下，shell 列宽、组件密度、文字层级、颜色角色、图标规格和最小操作路径都能从本规范逐项复核。
