# 侧栏两个修正：清单首击无反应 / 清单与智能清单互斥

## 1. 清单点击有时候第一次没有反应

需要区分两个原因。用户本次明确确认：WorkFollow 已在前台，文字点击正常，
靠近清单行上、下边缘更容易没反应。已复现的原因是清单主按钮只按文字自然
高度布局，38 点整行高度设在外层 HStack；灰色行背景与按钮点击区域不一致。
这与窗口激活无关，单独补 `FirstMouseAction` 无法覆盖这个问题。

修正：在清单主按钮的 label 内、`contentShape` 之前明确设置
`NavigationMetrics.rowHeight`。主按钮覆盖整行高度，文字和图标仍垂直居中，
右侧菜单保持独立宽度和操作。智能清单、归档清单、文件夹、标签和笔记目录
的 label 原本已有完整行高，未重复改动。

完整外壳回归使用三个清单，分别点击每行 10%、50%、90% 高度。原代码的
上、下位置未触发切换；修正后九处均一次打开正确清单，并断言按钮高度与
可视行高一致。连同窗口首击、智能清单互斥、跨清单草稿和右键路由，共 8 项
定向回归通过。XCTest 宿主的 WindowServer 激活状态不保证等同真实日用窗口，
因此没有把窗口置前请求当成人工前台验收；本次未重启或安装日用 App。

窗口未激活时的另一个原因：侧栏行（清单、智能清单、标签、过滤器、rail 图标）都是 SwiftUI 按钮。
AppKit 默认不把非 key 窗口的第一次点击交给控件——首击只用于激活窗口，要
第二次点击才触发动作。原生任务行早已用 `acceptsFirstMouse` 修过同款问题
（`NativeTaskRowView`），侧栏行漏了。

修法：新增 `FirstMouseAction`（DesignSystem）。一层透明宿主覆盖在行按钮上，
仅当 `window.isKeyWindow == false` 时接管命中（`hitTest` 返回自身）并直接
执行行动作；key 状态下 `hitTest` 返回 nil，点击行为与从前完全一致，不会
双触发。应用位置：

- 智能清单 / 已完成 / 垃圾桶行（`NavigationColumnView.destinationRow`）
- 清单行（`SidebarListRowView` 主按钮）、归档清单行、文件夹折叠行
- 标签行、过滤器行
- rail 图标按钮

右键不受影响：右键菜单走 `PopupInteractionRegistry` 的本地事件监听，先于
命中测试分发。滚动沿响应链照常传递。

同类排查（2026-11-01 第二轮）：主窗口里其余"用户可能从别的 App 切回来直接
点"的行级目标补齐同一处理——笔记侧栏行、笔记列表行（含垃圾桶恢复/永久删除
按钮）、任务垃圾桶行（选中/恢复/永久删除），以及 `BusinessMenu` 的独立触发
按钮（列表头部排序/更多、侧栏"+"等，一处修全 App 菜单触发共用）。看板卡、
时间线卡、日历卡留待观察：它们是内容区点击目标且带双击等复合手势，窗口
几乎总是已激活时才操作，盲加覆盖层有语义回归风险。

## 2. 清单与今天、明天应同级互斥

根因：`WorkspaceSelectionMemory` 把清单/标签上下文按目的地逐页记忆并在返回
时恢复——单测原先就固定了「回到今天恢复 activeList=工作」这个行为。于是
侧栏会出现「今天」和清单同时高亮，快速添加的落点也会跟着旧清单走。

修法：清单/标签上下文只属于「所有任务」。

- 离开「所有任务」时记录其清单/标签上下文；离开智能清单不记录。
- 回到「所有任务」时恢复；回到任何智能清单一律清空（过滤条件与智能清单
  可以叠加，仍按目的地记忆，保持不变）。
- 选中清单/标签/过滤器时「所有任务」行自己不再显示选中底色
  （`NavigationColumnView.isRowSelected`）：它是三者的宿主，同级一次一个。
- `SidebarListRowView` 的复制清单流程改为先切页再写上下文：切页触发的记忆
  恢复不能盖掉「打开副本」，也不能把清单上下文记进来源智能清单名下。
- `openTaskList`、标签行、过滤器行本来就在切换时清掉其余选中态，不改。

## 验证

- `SidebarSelectionFirstClickTests`（新增）：
  - 真实点击在清单↔今天/明天之间来回，智能清单页不残留清单选中态；
  - 非 key 窗口第一次点击清单行直接打开（不再需要第二击）。
- `WorkspaceContinuityTests`：更新「回到今天恢复清单上下文」的旧断言为
  互斥语义；「所有任务」内的逐页恢复保持不变。
- 回归批次：TaskListSwitchInteractionTests、TaskContextRoutingTests、
  PageNavigationInteractionTests、CommandPaletteTests、
  TaskListEditorInteractionTests、TaskListArchiveTests、
  TaskViewInvalidationTests、TaskListMoreMenuTests、NativeTaskOutlineTests。
