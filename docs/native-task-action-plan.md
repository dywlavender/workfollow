# Task Inspector 外围操作层

日期：2026-10-01。当前状态：ACTION PANEL STATE CONSOLIDATED；MORE / FOCUS SUBMENU PARITY PENDING。

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

## Focus子层合同（下一笔）

- 开始番茄专注：`FocusStore.start(taskID: task.id, stopwatch: false)`。
- 开始正计时：`FocusStore.start(taskID: task.id, stopwatch: true)`。
- 复用现有FocusStore，启动成功关菜单，保持当前详情，不假定自动导航到Focus。
- `start`在已有活动会话时返回false，不能把按钮点击当作启动成功或强行覆盖会话。失败反馈需明确验收。
- TASK-FOCUS-GAP-ESTIMATE：暂不显示“预计番茄/时长”假入口，缺Task估算模型及展开态证据。
- 不实现任务动态、便签、打印；也不把尚未实现的其他动作当可点击入口。已有属性/截止/跳过操作的去向应在菜单改造笔明确登记，不能在状态重构中顺手移除。

## 本笔验收

- 四Bool已从TaskInspectorShell移除，改用单一panel；日期的presentation.activePopover和正文格式栏不在本次合并范围。
- 状态测试锁More→Tag→Relation→Attributes替换及关闭路径。More action只关闭More，Picker自己的完成回调关闭相应panel。
- 33项ActionPanel / Inspector Presentation / Shell Contract / Hierarchy Render / DocumentProfile / PopupEscape回归通过，日志 `/tmp/workfollow-inspector-action-state-tests.log`。
- 没有重新验收More真实窗口点击或二级层截图；未做二级层，不声称本阶段完成。
- 本轮仅提交Inspector状态与文档/测试，工作区已有Task List/Countdown等修改保留。测试构建来自当前工作区，不作为独立干净远端checkout的全项目证明。
