# Task Inspector 外围操作层

日期：2026-10-01。当前状态：ACTION PANEL STATE CONSOLIDATED；MORE PRIMARY ACTIONS + FOCUS SUBMENU + PARENT PICKER + DUPLICATE / RESOURCE LINKS IMPLEMENTED；完整菜单对标及外部URL实机验收仍待后续轮次。

暂停Editor、Slash、日期、模板和Completed Row功能扩展。暂停不表示此前待验项已全部通过，原文档中的端到端/像素验收欠项继续保留。

## 参考证据与约束

用户提供两张TickTick主菜单截图（clipboard-54a0d872与clipboard-7add03e8）。可见添加子任务、关联主任务、置顶、放弃、标签、上传附件、开始专注右箭头，以及分隔后的任务动态、模板图标、创建副本、复制链接、打开便签、转换为笔记、打印、删除。

模板图标所在行在截图中没有可读文字，“保存为模板”以用户文字要求为准。两图没有展开Focus二级菜单；番茄/正计时两动作和二级层交互以用户明确指令为目标，不冒称截图已证明其内部几何。

## 分笔实施

1. **状态重构（本笔）**：`TaskInspectorActionPresentationState.panel`唯一承载more/tags/attributes/relation。打开替换、明确关闭、More跳Tag、Slash回调、选中任务变化和Escape沿用既有路径。不改变菜单内容、尺寸、颜色或数据操作。
2. **More与Focus二级层**：主菜单按参考归位，复用已有动作。Focus子层独立呈现，不替换或撑高主菜单；右侧优先，右侧不足翻左，垂直clamp；hover缝隙可跨越。Esc先关子层再关More，外部点击全关。只随真实子层引入submenu状态，不预先增加未接线Bool。
3. **关联主任务**：先核对现有Parent关系规则和可选对象，再实现TaskParentPicker；不得用现有Note relation冒充父关系。
4. **副本/链接**：复用已有duplicate，但验收字段/child复制语义；task URL需真实路由闭环后再暴露复制链接入口。
5. **Tag Picker**：Quick Add/Inspector/Slash共享既有Picker，等待展开态截图锁搜索、创建、多选、确认和Esc，不复制新UI。
6. **Relation**：补Task+Note真实语义前，保持已登记TASK-RELATION-GAP-TASK；混合结果/Tab结构等待参考，不临时造Domain。

## Focus子层合同

- 开始番茄专注：`FocusStore.start(taskID: task.id, stopwatch: false)`。
- 开始正计时：`FocusStore.start(taskID: task.id, stopwatch: true)`。
- 复用现有FocusStore，启动成功关菜单，保持当前详情，不假定自动导航到Focus。
- `start`在已有活动会话时返回false，不能把按钮点击当作启动成功或强行覆盖会话。失败反馈需明确验收。
- TASK-FOCUS-GAP-ESTIMATE：暂不显示“预计番茄/时长”假入口，缺Task估算模型及展开态证据。
- 不实现任务动态、便签、打印；也不把尚未实现的其他动作当可点击入口。已有属性/截止/跳过操作的去向应在菜单改造笔明确登记，不能在状态重构中顺手移除。

## 状态重构验收（上一笔）

- 四Bool已从TaskInspectorShell移除，改用单一panel；日期的presentation.activePopover和正文格式栏不在本次合并范围。
- 状态测试锁More→Tag→Relation→Attributes替换及关闭路径。More action只关闭More，Picker自己的完成回调关闭相应panel。
- 33项ActionPanel / Inspector Presentation / Shell Contract / Hierarchy Render / DocumentProfile / PopupEscape回归通过，日志 `/tmp/workfollow-inspector-action-state-tests.log`。
- 没有重新验收More真实窗口点击或二级层截图；未做二级层，不声称本阶段完成。
- 本轮仅提交Inspector状态与文档/测试，工作区已有Task List/Countdown等修改保留。测试构建来自当前工作区，不作为独立干净远端checkout的全项目证明。

## More / Focus 本笔交付与验收

- 已有动作归位：添加子任务（根任务）、置顶、放弃、标签、上传附件、开始专注；分隔后保存模板、转换笔记、删除。关联主任务、副本、复制链接待后续轮次，不展示未接线入口。
- 现有更多属性、截止日期、跳过本周期保留在“其他操作”兼容分组；这是明确的暂存差异，不声称菜单已完全对标。主菜单当前208 × 456pt，Focus子菜单宽176pt。
- Focus采用独立NSPanel，复用AnchoredPropertyPanel并增加submenu定位模式；日期沿用原vertical定位。以所属窗口可见区域计算右侧优先、翻左与垂直限制，主菜单不随子层打开而增高。窗口移动/调整大小后重算子层位置。
- 单一submenu状态只能附着More；打开其他panel清除子层。Hover进入打开，离开触发行不立即关闭，跨缝隙不会由mouseleave撤销；进入其他操作行关闭子层。物理鼠标连续跨越仍待人工验收。
- 两种Focus启动复用FocusStore，成功绑定当前任务、关闭菜单、保持详情；已有会话不被覆盖，Shell显示失败提示。估算入口仍缺失并登记，不造假入口。
- 40项FocusSubmenu / ActionPanel / AnchoredPropertyPanel / InspectorShell / InspectorPresentation / PopupEscape / FocusStore测试通过，日志：`/tmp/workfollow-task-focus-submenu-tests.log`。
- 实际NSWindow + Inspector测试通过应用事件分发点击：子层向左翻转，主菜单frame不变；第一次Escape关闭子层、第二次关闭More；窗口内外部点击关闭全部。独立子层继承主窗口外观，修复截图发现的浅色主窗口/深色子层对比问题。
- 截图：`/tmp/render_task_more_menu.png`（主窗口，不含独立子窗口）；`/tmp/render_task_focus_submenu.png`（独立子层）。已检查子层浅色背景及可读文字；这不是用户日常运行App的全流程像素验收。
- 启动/忙碌保护由真实FocusStore与动作协调器集成测试覆盖；尚未用日常运行App点击按钮完整验收启动提示与鼠标跨层。工作区其他并行修改保留，不纳入此提交。

## 关联主任务合同

- 这是已有任务的父子关系操作，不是Task/Note relation。遵守当前一层层级：目标必须是root；来源不能拥有子任务（包括已删除记录，避免恢复时破坏层级）。来源/目标均须未删除、未转换、未关闭且未跳过。
- 允许已有child换到另一root；任务保留正文、日期、提醒等字段，清单跟随目标，childOrder追加到目标末尾。一次原子commit，一次撤销恢复；当前选中任务不切换，bulkSelection不参与。
- Picker复用互斥actionPanel，More→parent替换More并关闭Focus子层。搜索任务标题或清单名，单选草稿；仅确定提交，取消/Escape/外部关闭不写任务。提交时Domain再次校验候选，失败保留面板并提示。
- 没有TickTick父选择器展开态证据。280 × 340pt搜索/单选/取消确定是当前项目的暂定实现，不是已通过的TickTick视觉合同。暂不增加解除父关系入口，等待后续产品行为证据。
- `Task.parentID`改为可修改属性；动作从任务值副本出发，仅修改父关系、清单、childOrder与updatedAt，避免后续新增字段在重建Task时遗漏。id/createdAt仍不可变。
- 64项ParentAction / ParentPicker / ActionPanel / TaskDomain / WorkspaceModel / InspectorShell / FocusSubmenu测试通过，日志：`/tmp/workfollow-task-parent-tests.log`。Domain覆盖跨清单重挂、末尾顺序、字段保留、一次撤销、同parent无新增undo及一层限制。
- 实际NSWindow点击验收：More→parent替换主菜单，尺寸280 × 340pt，外部点击关闭且任务未变；Picker候选点击仅更新草稿，确定提交；Escape通过与Inspector一致的PopupEscapeRouter取消。截图：`/tmp/render_task_parent_picker.png`，已检查底部按钮完整、标题/清单与搜索可读。尚未验收日常运行App与TickTick父选择器的像素差异。
- Workspace已有其他并行修改，本笔仅收录assignParent方法，不连带提交批量选择/分组改动。构建基于当前工作区，不能当成干净远端checkout的全项目测试。

## 副本 / 链接合同

- More第二组新增“创建副本”“复制链接”，复用Workspace现有副本反馈与撤销，不改变复制后仍选中原任务的既有行为。
- 副本沿用既有产品语义：新身份、创建/更新时间，恢复为未完成且不置顶；保留标题/正文/标签/优先级/日期/提醒（含reminderOffsets）/重复规则/附件引用/来源笔记。Root副本复制未删除、未跳过且未转换的children，新children指向新root；child单独复制留在原parent并追加顺序。一次commit、一次undo。附件仍引用既有文件，不额外复制物理文件。
- 链接使用`workfollow://task/<UUID>`；它是当前Native本地数据引用，不是共享Web链接，不保证另一台机器有对应任务。复制只写剪贴板，不改任务或bulk状态。
- `NativeResourceLink`解析task/note，`NativeResourceLinkRouter`统一导航。Task打开清除清单/标签/筛选/批量状态，必要时展开parent；活动任务去所有任务，关闭任务去已完成；缺失、已删除、已转换或跳过目标不切换选中任务，并由应用反馈不可用。
- 保留原Note链接，通过同一路由打开。Editor平台命令/Slash不变，只替换Host提供的打开链接回调。
- 主App声明URL scheme；NativeLifecycleDelegate接收系统URL，冷启动交由Receiver排队，主场景就绪后路由；激活已有主窗口，只有不存在主窗口时才创建。不会强行设置系统默认URL处理应用。
- 多版本共存时Launch Services默认处理目标、日常运行App外部点击与冷启动仍需实机验收；不能把解析/路由测试当作默认应用注册验收。缺少TickTick副本选择策略截图，保留当前项目既有策略。
- 71项NativeResourceLink / TaskDuplicateAction / ActionPanel / TaskDomain / ParentPicker / FocusSubmenu / DocumentProfile / ListMeta回归通过，日志：`/tmp/workfollow-task-copy-link-tests.log`。构建后Bundle的URL声明已检查；隔离剪贴板验证同时写文本和URL类型（首轮发现NSURL单类型无法粘贴为普通文本，已修复）。
- 实际Inspector窗口点击“创建副本”新增任务且关闭菜单，原任务仍被选中，撤销移除副本。菜单截图：`/tmp/render_task_more_duplicate_link.png`，已检查两入口及主分组可读；既有“其他操作”兼容分组继续在ScrollView中，不声称整张菜单已完全对标。
- 路由测试确认筛选清理、父任务展开、关闭任务跳转、目标选择、重复同页打开不遗留导航token、Note兼容与冷启动队列；这不是外部应用/Launch Services端到端验收。未操作用户默认应用关联或通用剪贴板进行测试。
