# D4 间距体系改造

## 范围

本轮只处理留白：`Padding`、`EdgeInsets`、`SizedBox` 作为间隔使用时的宽高、`Wrap/Grid` 的 `spacing`、`runSpacing`、`mainAxisSpacing`、`crossAxisSpacing`、Popover 的 `gap`，以及组件之间的内容间距。字体、颜色、图标、控件高度、圆角、边框、阴影、动画和业务行为保持原有语义。

## 事实源

通用间距仍由 [`WorkFollowSpacing`](/Users/dongyangwei/Documents/学习/代办笔记/workfollow-flutter-personal/desktop/lib/theme/workfollow_theme.dart:151) 提供：

```text
space1 … space8 = 4 / 8 / 12 / 16 / 20 / 24 / 28 / 32
```

重复结构使用语义角色：

| 角色 | 用途 |
| --- | --- |
| `pageHorizontalPadding` / `pageTopPadding` | 页面级 gutter |
| `sectionGap` / `contentGap` | 页面区块之间的留白 |
| `taskRowHorizontalPadding` / `taskRowVerticalPadding` | 任务行节奏 |
| `menuItemHorizontalPadding` / `menuItemVerticalPadding` | 菜单项内边距 |
| `popoverPadding` / `popoverSafeArea` | 弹层内容与视口安全边距 |
| `inspector*Padding` | Inspector 内容区节奏 |
| `editorParagraphGap` | 文档段落间距 |
| `toolbarItemGap` | 格式工具栏横向节奏 |

小于基础刻度的值也有明确名称，例如 `microGap`、`tightGap`、`inlineGap`、`controlGap`。它们保留截图校准值，组件不再直接写数字。

## 迁移结果

- Task List 的行内边距、标题/描述间距、元数据间距继续由 `TaskListMetrics` 统一转发到 `WorkFollowSpacing`。
- Sidebar、Today、Home、Calendar、Board、Habits、Notes、Stats、Trash 的页面 gutter 与卡片留白已改为基础刻度或页面语义角色。
- Inspector 的 inline/wide 两种内容 padding 已收口到 `inspector*Padding`。
- Slash、格式工具栏、More、Context Menu、日期/清单/标签/重复 Picker 和通用 Popover 使用共享的菜单、弹层和工具栏间距。
- Quill 的标题、列表、引用、代码块和段落间距使用 `WorkFollowSpacing`，因此正文入口不会各自解释空白。
- Matrix、反馈 HUD、Schedule Options 等当前工作区新增组件也已映射到同一套 Token。

## 扫描对比

| 项目 | D0 基线 | D4 结果 |
| --- | ---: | ---: |
| `EdgeInsets.*` | 224 | 249（含语义 Token 与技术/布局例外） |
| `SizedBox` | 291 | 291（间隔值已 Token 化；固定几何值留给 D5） |
| `Padding` | 99 | 99 |
| `spacing` / `runSpacing` / `mainAxisSpacing` / `crossAxisSpacing` / `gap` | 40 | 42（含当前工作区新增 Matrix/Schedule 组件） |
| 业务代码中的 `WorkFollowSpacing` 引用 | — | 686 |

计数是语法命中数，不等于违规数。D4 后剩余的裸数字只出现在固定几何、边框高度、条件表达式或 Token 定义中；页面和组件留白使用语义 Token。用户内容尺寸、图形绘制值和 D5 的宽高值继续保留在各自 Metrics 中。

## 例外白名单

- `SizedBox(width: 235)` 等固定 pane/内容宽度：属于 D5 几何，不在 D4 调整。
- `height: 1` 的 Divider/Border：属于边框几何。
- Matrix、图表和内容卡片的固定内容尺寸：保持组件 Metrics，避免把尺寸误当间距。
- `EdgeInsets.zero` 或 `WorkFollowSpacing.zero`：明确表示没有留白。

## 验收

- 普通页面和弹层的留白从 `WorkFollowSpacing` 或组件 Metrics 读取。
- 页面级 gutter、TaskRow、Inspector、菜单和 Picker 的同类间距有单一语义来源。
- `7/9/11/13` 等校准值只通过带语义的 Token 出现。
- `task_spacing_contract_test.dart` 验证基础刻度、任务列表与 Inspector 角色的委托关系。
