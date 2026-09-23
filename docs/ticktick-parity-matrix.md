# Flutter → Native 行为基线

以实验分支切出时的 Flutter 源码、测试及已有截图为基线。下表是迁移必须保留或验证的 Contract，不代表本轮重新跑过所有 Flutter 测试，也不代表 Native 已完成这些功能。

## Contract

| 模块 | 契约 | Flutter 证据入口 | Native 第一批 |
| --- | --- | --- | --- |
| Task Row | 完成框点击不能同时打开详情；行选择是另一点击区域 | `desktop/test/task_list_projection_test.dart`、`desktop/lib/screens/today_screen.dart` | 独立按钮，实测通过 |
| Projection | 完成后是否保留由当前页面投影决定，View 不自行维护第二份列表 | `desktop/lib/features/tasks/application/task_list_projection.dart` | 仅内存简化投影，待正式迁移 |
| Inspector | Escape 先关闭最内层浮层，再退编辑焦点；窄屏返回，宽屏保持详情 | `desktop/test/task_inspector_layout_test.dart`、`task_editor_popovers_test.dart` | 仅详情空壳，完整焦点契约待验证 |
| Child | 只能一级；子任务有自己的标题、正文、日期 | `desktop/test/task_tree_rules_test.dart`、`task_child_inspector_test.dart` | 未实现 |
| Child 完成 | 完成子任务不影响父/兄弟；完成父任务带动子树；恢复父任务不强制恢复孩子；Undo 恢复原快照 | `desktop/test/task_tree_rules_test.dart` SUB-080/081/136/137 | 未实现，不能简化为双向级联 |
| Note | 选中文字可创建任务，Task/Note 共享编辑器基础能力 | `desktop/test/note_document_editor_test.dart`、`document_editor_custom_command_test.dart` | 导航占位 |
| Editor | Slash / Formatting / Selection 浮层生命周期独立；能力经 Profile/descriptor 注入 | `desktop/test/document_editor_shell_test.dart`、`task_document_commands_test.dart` | 未实现，不先写 NSTextView |
| Schedule | 安排日期与截止日期是不同字段和语义；无日期不能默认为今天 | `desktop/lib/models/task.dart`、`desktop/lib/features/tasks/domain/task_schedule.dart` | 仅示例 scheduledToday，不作为日期模型 |
| Trash | 任务和笔记只显示各自内容；删除时间倒序、不分组；恢复重新进入正常投影；清空需确认且仅作用于当前类型 | `desktop/test/trash_screen_test.dart`、`notes_trash_screen_test.dart` | 两个独立导航占位，无删除动作 |
| Matrix | 四象限使用统一任务数据与任务编辑器，不能维护简化任务副本 | `desktop/test/matrix_projection_test.dart` | 导航占位 |

若 Contract 与实际 Flutter 实测发生冲突，记录差异并确认产品规则，不借 Native 重写顺便改行为。

## Phase 2 第一批补充

上表“Native 第一批”列记录的是 Shell 基线，不覆盖后续实现状态。现新增独立 Domain/Application 和 12 项核心规则测试（另有 smoke、Preview keyboard 共计 14 项），通过 `xcodebuild test`，未替换当前 UI 的示例 Store。

- Today/Inbox 的页面记录包含匹配的已完成任务；待办计数只算开放任务。Completed 按完成日倒序分组。
- 已迁父子完成/恢复、单层创建、独立安排日期/优先级、树去重/展开、父任务移清单级联。
- 已迁软删除及同批子任务恢复；尚未迁垃圾桶 UI、清空、永久删除。
- 全套 Escape/Editor、Note、Matrix、Calendar 和跨屏恢复仍是待验证或未实现。
- 现存 Flutter `needsAttentionToday` 的 deadline 条件为截止时间不晚于当天零点；Native 首批保持此条件，不擅自把任意“今天晚些时候截止”纳入。后续若修改须双端同步契约。

## 截图基线目录

复用已有 `docs/screenshots/` 原图，不把新的 Native 截图冒充 Flutter 基线。

| 页面 | 已有基准 | 缺项 |
| --- | --- | --- |
| Today | `screenshots/tasks-list.png`、`screenshots/task-list-groups.png` | 需要后续复拍确认与冻结版本一致 |
| Inbox | 暂无专门命名截图 | 待补 |
| Inspector | `screenshots/task-editor.png`、`screenshots/task-editor-detail.png` | 后续复拍 |
| Child | `screenshots/subtask-child-detail.png`、`screenshots/subtask-parent-filled.png` | 后续复拍 |
| Notes | `screenshots/notes-workspace.png`、`screenshots/notes-narrow-dark.png` | 后续复拍 |
| Calendar | `desktop/test/calendar_capture_test.dart` 提供捕获入口 | 尚未归档到本基线 |
| Matrix | `desktop/test/matrix_projection_test.dart` 提供行为测试 | 截图待补 |
| Trash | `desktop/test/trash_capture_test.dart` 提供任务/笔记捕获入口 | 尚未归档到本基线 |

基线未齐全；Phase 0 状态为进行中。下一批 Domain 前先补业务 Contract 对应的纯测试，迁各功能时补齐对应截图，不以视觉近似代替行为验收。
