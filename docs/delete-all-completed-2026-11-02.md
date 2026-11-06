# 已完成列表「全部删除」

日期：2026-11-02

## 需求与入口

「已完成」页的「⋯」（列表操作）菜单末尾增加「全部删除」，一次把该视图里的已完成任务移入垃圾桶。

入口只放在已完成视图：`TaskListMoreMenuPolicy.entries(for:)` 按目的地返回条目，通用五项保持原样，只有 `.completed` 追加「分隔线 + 全部删除」。其它视图（含「已放弃」）菜单集合与顺序不变，`TaskListMoreMenuTests` 逐项断言过。

## 行为

- 集合 = 「已完成」投影叠加当前保存过滤器，与页头计数 `count(for: .completed)` 同一份成员。被过滤器挡在视图外的任务不会被删。
- 走 `TaskWorkspaceModel.deleteAllCompleted()`，内部复用 `TaskActions.batch(_, .delete)`：软删进垃圾桶、父任务连子任务一起进桶、可恢复。
- 整批一次事务，一步撤销。空跑（已完成视图为空）不产生撤销帧。
- 已放弃任务、笔记、已归档清单里的任务不在集合内，投影本身已排除；测试分别钉住。
- 完成后同步清理 `bulkSelection` 里已进垃圾桶的 id，避免批量条继续显示失效计数。

## 确认框

破坏性且一次动整页，先弹主题化确认框（`workfollowAlert`）：

- 标题「全部删除已完成任务」，正文复述数量与去向：「已完成的 N 个任务将移入垃圾桶，可以撤销。」
- 按钮「取消 / 全部删除」，确认按钮走 `.destructive`，不占 Return。
- 数量在**确认框弹出那一刻**取，不是菜单打开时——两者之间可能又勾完几条。

菜单项在已完成为空时置灰（`completedDeletionCount() == 0`）。

## 验证

- `DeleteAllCompletedTests` 7 项：全删与保留待办、软删一步撤销、已放弃/笔记不受影响、保存过滤器收窄集合、父子级联与计数、空视图不产生撤销帧、任务/笔记垃圾桶互不干扰。
- `TaskListMoreMenuTests` 12 项（新增 3 项，其余为原有回归）：菜单条目集合按目的地区分、已完成视图菜单变高且确认后整批进垃圾桶、取消确认不删任何一条、已完成为空时菜单项置灰。
- 定向回归 `TrashIsolationTests`、`NoteTaskMigrationTests`、`BusinessMenuInteractionTests` 全通过。

`WorkspaceSnapshotDebouncerTests.testApplicationFlushPersistsLastEditBeforeDebounceDeadline` 在本次改动前后都失败，涉及 `setDocument` 的持久化 flush，与「全部删除」无关；该失败属于工作区里既有的投影/正文缓存改动，未在本轮处理。

## 未做

- 没有替换日用 App，未做用户实际交互验收。
- 未给「已放弃」视图提供同类入口：需求只落在已完成，且已放弃的删除代价与语义未确认。
