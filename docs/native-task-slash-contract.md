# Task Slash Round 1

日期：2026-10-01（2026-10-16 更新）。状态：COMMAND / NATIVE RENDER VERIFIED；**TICKTICK COMMAND LIST + SECTION VERIFIED（12 项逐项一致、四节 3 分隔已对齐；图标逐项一致、菜单几何实测基本一致：宽 ≈156 vs 160、行高 ≈33 vs 34）**；HOST END-TO-END PENDING。

真机复验（2026-10-17）：`WorkFollow.app` 实际运行中 Slash 菜单四节 3 分隔与 12 项渲染与滴答一致（截图 `docs/audits/ticktick-rea-2026-10-16/native-slash-menu-live.png`）；同期修复"粘贴不触发输入期转换"缺陷（`paste` 改走 `insertText`，测试 `testPastedContentTriggersLikeTyping`）。

## 清单与边界

TaskDocumentProfile 决定 Task 清单，NoteDocumentProfile 独立决定 Note 清单。Core 提供稳定格式描述和执行 adapter，不决定生产宿主顺序。旧 `DocumentProfile(taskSlash/noteSlash:)` 保留兼容入口，暂不删除。

父任务：H1、H2、H3、无序、有序、检查项、引用、分割线、附件、子任务、标签、关联任务/笔记。子任务只移除“子任务”。正文检查项不创建 Task；业务 action 经窄宿主回调路由。

## 本轮合同与证据

| 合同 | 自动证据 | 范围限制 |
|---|---|---|
| 父12项 / 子11项，稳定ID顺序 | DocumentProfileTests 实际 factory | 不用合成数组代替生产 factory |
| 格式只改当前block / 消费触发符 | SlashSessionTests 原行范围测试 | 保留 `/` 与 `、` 的现有触发政策 |
| 检查项只改文档 / 子任务走真实创建通道 | testTaskSlashChecklistAndChildUseDifferentMutationChannels | pendingChildTitleEditorID 与 parentID 已验；真实文本框firstResponder待验 |
| 标签/关联先关Slash并消费触发符再调用宿主 | testTaskSlashBusinessPickersConsumeTriggerBeforeCallingHost | Picker选项、保存、焦点回归不是本测试的覆盖范围 |
| H1 / 检查项 / 分割线一次Undo恢复 `/` | testTaskSlashFormatAndDividerAreSingleUndoOperations | 直接调用显式分开输入/执行两事件；不撤销宿主业务创建 |
| hover与键盘同一selection，Escape保留 `/` 且不调用宿主 | testHoverKeyboardAndEscapeShareOneTaskSlashSelection | hover调用真实状态处理器，未模拟物理鼠标移动 |
| 父/子/hover/底部翻转实际NSPanel渲染 | testTaskSlashWindowsRenderParentChildHoverAndBottomFlip | 固定视口fixture，不等同完整Inspector |
| 滚动/窗口移动/缩放后跟随光标 | testSlashFollowsViewportAndWindowChanges | 实际NSScrollView/NSWindow；主页面祖先ScrollView另行验收 |

窗口渲染锁现有宽160pt、父高443pt、子高409pt（2026-10-16 分节对齐后：12 / 11 行各含 3 条分节细线）；菜单不改变固定编辑视口frame、不夺正文firstResponder，底部翻转且位于窗口安全区。四图已目检：`/tmp/render_task_slash_parent.png`、`/tmp/render_task_slash_child.png`、`/tmp/render_task_slash_hover.png`、`/tmp/render_task_slash_bottom.png`。截图是当前构建的隔离窗口，不是旧App截图。

跟随测试发现首次呈现读取未完成布局的caret坐标。保留即时呈现，新增首轮布局后一次校正，文档身份与当前panel匹配才执行，关闭/重绑后不重新打开。既有NSPanel/SlashSession、观察者与关闭规则保留。

103项Editor/Note/Popup/Inspector回归通过，日志：`/tmp/workfollow-task-slash-tests.log`。构建使用当前工作区，其中存在其他模块的未提交改动；本轮不提交那些文件，不把此日志当作独立干净checkout的全项目验收。

## 滴答实测参照与比对（2026-10-16）

参照：滴答 macOS 8.0.80 实测（正文出现 `/` 即弹出；截图 `docs/audits/ticktick-rea-2026-10-16/ticktick-slash-menu.png`）。

滴答菜单 12 项（实测顺序）：一级标题、二级标题、三级标题、无序列表、有序列表、检查项、引用、水平分割线、附件、子任务、标签、关联任务/笔记。

**比对结论：本地父任务 Slash 12 项与滴答实测逐项一致（项目、顺序、文案三项均同）**——命令清单层面的 TickTick parity 成立。

仍待对齐 / 未验证：

- **分节线（已对齐，2026-10-16）**：滴答 4 节 3 条分隔（3 标题｜3 列表｜引用+分割线｜4 插入）；本地已细分 `group`（标题｜列表｜格式｜插入）并按分隔条数计算菜单高度（父 12 行 443pt、子 11 行 409pt），渲染锁测试与全量回归通过。
- **图标（已对齐，2026-10-16）**：本地分节渲染图 `native-slash-menu-sectioned.png` 与滴答截图逐项比对，**12 项图标与 4 节 3 分隔位置全部一致**。
- **菜单几何（实测基本一致，2026-10-16）**：滴答 1:1 截图实测**宽 ≈156pt / 行高 ≈33pt**（AX 外框 240×505 含阴影，不作依据）；本地 160 / 34，差 1–4pt，亚 5pt 精调未做。
- **子任务菜单**：滴答子任务级 Slash 未测（本地子 11 项 = 父移除“子任务”）。
- **键盘交互**：滴答菜单未经真实键盘验证（AX 合成按键未驱动菜单，不能据此判定不支持键盘）。

## 未闭合项

- TASK-RELATION-GAP-TASK：TaskInspectorShell.relationPicker 当前仅检索未删除Note，文案保持目标“关联任务/笔记”。没有增加假Task关联能力。
- 子任务首建后的inline child标题焦点、标签选取/关闭、笔记关联插入/选择及连续Escape需要完整Task宿主窗口验收。不得把回调测试当作已完成全部业务闭环。
- TickTick 命令清单 / 分节 / 图标 / 几何已于 2026-10-16 完成比对（见上节；几何差 1–4pt 未精调）；剩余未签：子任务级菜单、键盘交互。
- `/q`关闭保留现状，不称为已验证的TickTick搜索合同；附件能力不扩展。

下一笔只验上述宿主闭环并修实际差异，必要时补Task/Note窗口级fixture。完成前Task Slash不冻结，不推进到More/Tag/Relation的新功能开发。
