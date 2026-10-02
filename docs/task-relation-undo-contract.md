# Task Relation 撤销合同与实施计划

日期：2026-10-02。状态：边界审计与复现已建立，生产实现尚未迁移。

## 已确认的问题

`TaskRelationSelection.apply`对Note先调用`setSourceNote`，再调用`insertReference`。前者记录WorkspaceStore快照，后者由NativeTextView独立UndoManager处理，Coordinator通过`setDocument`保存正文。

`WorkspaceStore.commit(.skip)`会把最新正文更新到已有业务撤销快照。因此业务撤销恢复sourceNoteID，却保留引用。即使先把document/sourceNoteID合成一次快照提交，后续正文输入仍会覆盖该快照中的旧正文。单纯合并保存不等于统一撤销。

证据：TaskRelationSelection.swift、DocumentEditor.swift、NativeTextView.swift、DocumentEditorCoordinator.swift、WorkspaceStore.swift。TaskRelationUndoBoundaryTests是现状刻画测试，明确不代表期望行为；迁移时必须替换其缺陷断言，不能把缺陷冻结成产品合同。

## 目标合同

- Task目标：一次正文引用编辑，不改变parentID/sourceNoteID。
- Note目标：正文引用与sourceNoteID共同构成一次编辑命令；保留原有来源笔记语义，不引入关系图。
- 正文获得焦点后的撤销一次：删除本次插入的引用或恢复被替换的选区，并恢复此前sourceNoteID（包含nil）。重做一次：同时恢复引用和来源。
- 插入前的文字、插入后的独立输入分别撤销，不得与关联命令黏成一组；支持连续关联A、B的逆序撤销和顺序重做。
- 普通业务动作（优先级、标签等）继续用业务撤销；撤销这些动作不能回滚正文，也不能复活已由正文撤销的来源笔记。
- 取消选择不提交，插入被拒绝不先改来源；成功时只产生一次完整模型变化，不向持久化暴露半完成关系。
- 不修改Popup布局、Slash命令目录、Task/Note profile，不新增全局UndoManager。

## 拟定架构：编辑命令拥有跨字段撤销

正文引用本质是编辑命令，撤销归当前文档的UndoManager，而不是再向业务快照栈重复登记一份。

1. Editor暴露通用、与Task/Note无关的编辑事务边界：保存选区、独立undo grouping、成功/拒绝结果、宿主附加撤销/重做回调。不能让Editor引用TaskWorkspaceModel。
2. Task宿主命令保存旧/新sourceNoteID，并将正文和来源通过一次应用层动作提交；不使用`setSourceNote`的常规业务记录路径。
3. WorkspaceStore新增明确的字段补丁/rebase能力，使宿主更新来源时同步更新该任务在既有业务历史中的来源字段。只补对应字段，不能覆盖整Task，也不能把全体非文本字段纳入现有`.skip`。
4. 撤销/重做回调使用稳定taskID；与当前文档绑定及正文undo生命周期一致，不能借当前selectedTaskID写到另一任务。

这不是“将两个UndoManager互相调用”：禁止业务undo触发文本undo或反过来猜测栈顶，禁止清空旧文本历史来掩盖问题。只有关联命令增加宿主补偿记录。

当前文本历史在切换/解绑文档时清空。第一轮不扩展跨文档持久撤销，也不能宣称切回任务仍可撤销旧关联；如果未来要求保留，应统一设计文档级历史，而非单独缓存Relation。

## 分步实施及验收门槛

| 阶段 | 产出 | 验收 |
| --- | --- | --- |
| 1：边界审计 | 本合同、现状复现测试 | 证明两个栈分离，以及快照原子提交被正文rebase打破 |
| 2：字段补丁 | 应用层来源字段更新/rebase API | nil恢复；业务撤销不复活旧来源；其他Task/字段不变 |
| 3：通用编辑事务 | Editor宿主补偿与明确分组边界 | 文本撤销/重做驱动附加字段；拒绝插入无副作用；切换文档遵循原生命周期 |
| 4：Relation接入 | 单一宿主关联命令 | Task引用/Note来源接线；模型一次提交；替换阶段1缺陷断言 |
| 5：整体验收 | 真实测试窗口及日常App操作 | 插入→输入→撤销→撤销→重做；关联A/B；业务动作交错；保持选区及无布局变化 |

阶段2和阶段3写集可分离，适合并行；阶段4由主代理整合，不让两个负责人同时修改Selection。阶段5主代理验收。未完成阶段3前，不把阶段2独立接入生产Relation路径。

## 本轮边界

本轮只建立审计依据和优化合同，不改生产撤销策略。没有滴答Relation截图，现有320 × 300展示保持。测试窗口不能替代日常App的Cmd-Z及重做实机验收。

28项TaskRelationUndoBoundary / TaskRelationInteraction / TaskWorkspaceModel / DocumentEditorState测试通过，日志`/tmp/workfollow-task-relation-undo-boundary-tests.log`。其中两项UndoBoundary通过代表成功复现现状缺陷，不代表原子撤销已经实现。构建来自当前含其他并行修改的工作区，本轮提交不包含这些修改。
