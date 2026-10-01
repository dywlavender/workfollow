# TASK-LIST-COMPLETED-001

2026-10-01：完成态视觉去强调。基准为用户补充的 TickTick 已完成任务截图；不推导截图未证明的metadata隐藏或行高变化。

## 三条合同

1. 完成框用 `taskCompletedCheckbox` 中性灰填充、白色勾，不使用accent。18pt点击槽、14.58pt绘制盒保留，点击仍执行恢复。未完成按原优先级描边，放弃状态图标不变。
2. 完成态标题、正文预览、metadata独立使用语义颜色；浅色依次为A6 / D0 / E0中性灰。深色单独映射为A0 / 85 / 70，不把浅色截图颜色硬套深色。预览只在完成态改为12.5pt regular，普通预览仍为medium。整个任务行不叠opacity，不移除已有metadata。
3. 完成行divider从标题列开始，根任务58pt，子任务每层再加24pt；普通行divider保持原值。完成组count独立弱化，组标题字重、30pt header和任务50pt最小行高不变。

## 验收

- `TaskCompletedRowRenderTests`：浅/深中性颜色角色顺序、divider几何、实际NSWindow渲染和实际鼠标点击恢复路径。
- 新构建的隔离完成行截图已目检：`/tmp/render_completed_row_light.png`、`/tmp/render_completed_row_dark.png`。浅色完成框已灰化，预览与metadata依次变浅，divider与preview起点一致。
- 60项Completed Render / Tree Geometry / Task Domain / Workspace / List Defaults测试通过；日志 `/tmp/workfollow-completed-row-tests.log`。
- 本轮是组件窗口截图验收，不称为整页同尺寸TickTick像素一致；Header count是源码角色修改，未单独进行完整分组截图测试。
- 工作区已有任务列表、批量交互和倒计时未提交改动。本轮只暂存自身TaskListView增量及相关token/metrics/test/doc，保留其他修改。测试使用当前工作区，不冒充干净远端checkout验收。
