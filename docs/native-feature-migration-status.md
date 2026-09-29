# Native 功能迁移清单（2026-09-25）

## 当前状态：实现存在，不代表产品对齐

施工分支继续使用 `experiment/macos-native`。从本日起不回滚技术底座、不继续扩产品功能；先以 Flutter 当前实现为基准逐条校正。详细行为契约见 [`native-parity-contract.md`](native-parity-contract.md)。

保留并复用的技术资产：Task Domain / Projection、`NSTextView` / TextKit、`NativeDocument` / `DocumentProfile` / `SlashSession`、`PersistenceCoordinator`、Reminder Service、Attachment Infrastructure、Recurrence 基础模型。它们的存在不代表外层产品交互已经通过验收。

| 产品面 | 当前状态 |
| --- | --- |
| Task List | 已有原生实现；正在按微契约审计，`NOT PARITY VERIFIED` |
| Task Inspector、Task Editor、日期/提醒/重复弹层 | `IMPLEMENTED AS PROTOTYPE / NOT PARITY VERIFIED` |
| Notes / Note Trash | `IMPLEMENTED AS PROTOTYPE / NOT PARITY VERIFIED`；暂停继续开发 |
| Matrix | `IMPLEMENTED AS PROTOTYPE / NOT PARITY VERIFIED`；暂停继续开发 |
| Calendar | `IMPLEMENTED AS PROTOTYPE / NOT PARITY VERIFIED`；暂停继续开发 |
| Task Trash | `IMPLEMENTED AS PROTOTYPE / NOT PARITY VERIFIED` |

当前唯一主链：`Task List → Task Inspector → Task Editor → Child Task → Date / Reminder / Repeat → Task Trash`。Task List 通过契约验收后再继续 Inspector 和 Editor；这条主链全部通过前，不恢复 Notes、Calendar、Matrix 的开发。通过后按 `Notes → Note Trash → Matrix → Calendar` 顺序推进。每次行为改动限 1–3 个微契约，提交说明需明确消除的 Flutter/Native 差异。

下文的 Stage 与功能表保留为技术实现记录，不再用来宣称某个产品页面“迁移完成”或“与 Flutter 等价”。

2026-09-25 优先级纠偏进度：`TASK-LIST-001/002/004/005/007/011/013` 已有对应实现或修正；其中 deadline-only Today、Inbox 完成项清单隔离、移除独立“过期”目的地和 Shift 多选锚点有回归测试。随后补齐 Quick Add 星期映射与取消 token 识别后保留原文、日期面板清除与右键清除的不同副作用，并分别保留 Undo。`TASK-LIST-014` 全局搜索/路由已实现并移除页内搜索控件；`TASK-LIST-015` 修正了右键添加子任务的父级选择与标题焦点流程，并把标签改为可搜索、多选、创建、取消/确认。`TASK-LIST-016` 增加就地日期/提醒/重复草稿面板，并确保明确清空、取消、手动日期及移除日期 token 在创建路径中有独立语义。Task List/Tree Flutter 定向测试历史结果为 51/51；最新 Native XCTest 105/105，Flutter Quick Add 焦点基准 3/3、命令面板基准 1/1，Flutter 日期/菜单及任务动作/日期弹层定向测试合计 60/60。父子完成/Undo、重复规则选择并重启后的 Preview 持久化已在真实 Native Preview 窗口核对；当前 Mac 锁定，Quick Add、日期清除、命令面板和右键菜单新增操作没有真实窗口验收。其他尚未核对的契约仍按下方状态保留，不据此宣称 Task List 或整条主链通过 parity。

2026-09-28 日程子面板纠偏：日期弹框的「时间 / 提醒 / 重复 / 重复结束」子面板改为**独立浮层**——点属性行从行下方弹出（SwiftUI popover），浮在主面板之上，主面板尺寸与布局完全不动；浮层里只有选项，不重复属性行的当前值（Flutter 的子菜单头部其实就是属性行本身）。清空入口移入选项（时间「清除时间」/ 重复「不重复」/ 重复结束「永不结束」/ 提醒取消全部勾选后确定）。曾试过"弹框内 offset 悬浮""预留高度""手风琴式内置"三种做法，都会裁剪或把主弹框撑长，均被否定。详见 [`schedule-options-flutter-parity-2026-09-28.md`](schedule-options-flutter-parity-2026-09-28.md)。真机截图逐项核对（主弹框全程 507），Native XCTest 全量通过；仍未宣称整页 parity。

## Stage A（2026-09-24）

- 保存：PersistenceCoordinator 使用独立串行队列，400ms debounce；编码和原子写入移出主线程。flush 等待此前写入并保存最新快照；退出前结束编辑并异步 flush，保存失败取消退出。当前没有 Workspace 切换入口，未来切换必须调用同一 flush。
- Reminder：仅通知投影改变才重新调度；包含有效提醒任务的 ID、时间、标题和清单。正文、标签等变化不会产生系统通知调用。完成/删除会移出投影；显式授权后强制刷新。
- Undo：正文/标题不新增任务撤销记录；文本变化回填已有快照，撤销任务操作不覆盖后来编辑的正文。原生文本撤销继续归 NSTextView。
- Query（旧模型能力）：`TaskListQuery` 仍可在投影/基础设施测试中按搜索、清单、标签过滤后生成树；只命中的子任务可提升为根结果。当前产品页已移除页内搜索与筛选控件，用户搜索走全局命令面板，不执行树过滤；清单/标签入口由导航列进入 All。
- 时间：应用统一注入 clock/calendar，覆盖任务重复、Planning、提醒默认值/调度、Notes 时间戳。
- 验证：完整 xcodebuild test **48/48 通过，0 跳过、0 失败**，其中新增 7 项基础设施测试。未进行全量 UI/IME/性能/系统通知人工验收。

## Stage B 第一轮：编辑器边界与 Slash Session（2026-09-24）

- 共享编辑器、Coordinator、State 统一使用 documentID；切换文档时关闭 Slash、清空文本 Undo、重置输入格式，避免同实例跨文档污染。
- DocumentProfile 注入命令和选区操作，DocumentCommand / DocumentSelectionAction 描述行为；共享编辑器不判断任务或笔记类型。任务宿主注入“创建子任务”（只对父任务提供）；笔记宿主注入“所选文字创建关联任务”。
- Slash 改为保留文本焦点的非激活浮层：输入搜索（中文标题/英文关键字）、分类标签、↑↓循环选择、Enter 执行、Esc 关闭并保留文字；执行只移除当前 /query。URL/路径内部的斜杠不触发；输入法组合时不接管候选键。
- 浮层限制在屏幕范围内，失焦/点击正文/卸载时关闭。UI、中文输入法真实候选交互、缩放滚动仍待最终人工验收。
- 完整 xcodebuild test **55/55 通过，0 失败、0 跳过**，新增 7 项覆盖 UTF-16 范围、查询、键盘索引、注入隔离、执行、Esc、URL 与跨文档重绑定。
- Stage B 尚未完成，后续进度见下方。

## Stage B 第二轮：正文操作（2026-09-24）

- Checklist：格式菜单/Slash 提供待办清单和勾选格式，段落状态存入 DocumentBlockKind.checklist；使用原生列表标记渲染。鼠标直接点击勾选标记的交互尚未实现。
- Link：原生对话框添加/修改链接，光标在链接内时修改完整链接；选区保留已有文本及格式，没有选区则插入地址。格式菜单可移除链接。修复 NSTextView 替换时继承旧链接属性的问题，改为显式属性替换并登记 Undo。
- 正文附件：Slash/格式菜单选文件，沿用 Native 独立附件目录导入；正文保存引用并渲染文件名附件块，双击打开；支持撤销/重做，跨文档异步回调不会插入另一文档。当前不提供图片预览。
- 兼容：DocumentRun 新增可选 attachment 字段，旧 JSON 无此字段仍可读取；本轮无版本号切换。后续附件引用索引/清理必须同时扫描正文 runs 和任务/笔记附件数组，当前不物理回收附件。
- 新增测试覆盖旧 JSON、TextKit/JSON 附件往返、清单状态、链接格式保留/移除、附件撤销和格式操作不丢文件引用。完整测试 61/61 通过；真实列表标记显示、附件双击、弹框/IME 仍待最终 UI 验收。
- 剩余：Checklist 直接点击切换、Divider、图片预览/粘贴、文件拖入、关联块、富文本粘贴完整度及统一格式操作界面。

## 当前代码实现盘点（不代表产品对齐）

### Stage C 第一轮：日期与重复（2026-09-24，历史记录）

- 按用户要求暂停编辑器剩余工作，优先任务业务。
- 本轮完整 xcodebuild test：67/67 通过，0 失败、0 跳过；新增 6 项覆盖月底连续性、间隔/次数、结束日边界、日期时间保留、日期清除隔离及重复完成撤销。
- 列表、Matrix、Calendar 行日期为独立按钮；无日期任务也可打开日期弹框。详情安排日期/截止日期复用 TaskDatePopover。
- 日期弹框使用草稿：今天/明天/下周、自选日期、指定时间、清除、取消、确认。改天保留时间，取消不提交；两种日期互不覆盖。提醒与重复仍从更多属性独立设置，未宣称已复刻完整日期/时间段面板。
- 日历及四象限拖动改天保留原指定时间；截止日期、提醒不跟随普通改天自动平移。
- RecurrenceRule 为可选 Codable 字段，旧快照可读；支持日/周/月/年的间隔、含当天的结束日期、含当前实例的剩余次数。月末钳制后保留原日期目标（1/31 → 2/28 → 3/31）。完成直接重复任务扣减次数，Undo 撤销完成及新实例；父实例复制孩子时保留孩子自己的规则，不扣减孩子次数。
- 未完成：指定星期/月份、多星期、法定工作日历、跳过/放弃、转换笔记、批量操作、清单标签管理，以及日期范围/时轴拖动。真实弹框位置和尺寸仍待统一 UI 验收。

| 模块 | 当前代码范围（均未完成产品对齐验收） |
| --- | --- |
| 任务导航原型 | 今天、收集箱、所有任务、最近 7 天、已完成、垃圾桶；搜索、清单/标签过滤；`NOT PARITY VERIFIED` |
| 任务操作原型 | 新建、标题、正文、完成/恢复、删除、一级子任务创建/进入/返回父任务、移动到现有或新清单；`NOT PARITY VERIFIED` |
| 任务属性原型 | 优先级、安排日期、截止日期、指定时间、标签、提醒时间、每日/每周/每月/每年重复；`NOT PARITY VERIFIED` |
| 重复 | 完成直接重复任务创建下次实例；父任务带动完成的孩子不单独生成重复链；父重复实例复制子任务 |
| 任务撤销 | 列表头撤销上一条任务数据操作，最多 50 个内存快照；永久删除/清空会清除撤销栈，不能复活被永久删除的内容 |
| 文本编辑原型 | 独立 NSTextView 撤销、原生查找、富文本投影与 Document 模型双向转换；标题、引用、代码、列表、粗斜体、下划线、删除线、高亮；Slash 原生格式菜单；`NOT PARITY VERIFIED` |
| 笔记原型 | 新建、编辑、搜索、收藏、文件夹编辑/过滤；共用 DocumentEditor；选中文字右键创建关联任务并可跳转；`NOT PARITY VERIFIED` |
| 两个垃圾桶原型 | 各自内容、删除时间倒序、不分组、恢复、单条永久删除、确认清空等；`NOT PARITY VERIFIED` |
| 四象限原型 | 四个象限、清单/已完成分组、完成切换、新建、拖拽移动、共用任务详情；`NOT PARITY VERIFIED` |
| 日历原型 | 月/周日期网格、前后翻页、今天、按日新建、任务完成、共用详情、拖动改安排日期；`NOT PARITY VERIFIED` |
| 附件 | 任务/笔记选文件复制至 Native 独立目录、打开、Finder 定位、移除关联；原文件不改动 |
| 提醒 | 用户点击允许后申请系统通知权限；按任务提醒时间排程，完成/删除后取消待发送提醒；重复实例平移提醒时间 |
| 预览持久化 | Codable 快照原子写入、启动重载、错误提示；读取失败停用自动保存，避免覆盖原文件 |

## 数据隔离

独立目录：`~/Library/Application Support/WorkFollowNativePreview/`。

- `workspace.json`：任务、笔记、正文结构、属性及附件关联；初版 schema 1。
- `Attachments/`：导入的附件副本。移除关联或清空垃圾桶暂不清理物理文件，因为重复实例可能共享文件；后续需集中做引用回收。
- 不读取/写入 Flutter 的 `Application Support/WorkFollow`。没有执行正式数据迁移。
- 本轮为验证 TASK-LIST-009/010 启动了最新 Native 构建，只切换导航、折叠/展开分组及父子行；未执行任务内容操作，也未申请通知权限。窗口展示的是已有 Preview 数据。

## 尚待迁移（不能算功能齐全）

- 完整复刻 Flutter 重复规则与业务日历语义；Native 已有间隔/结束条件基础模型及重复实例、跳过、放弃原型，但并非完整产品 parity；任务转换为笔记仍待实现。
- 批量选择与完成/删除/移动/改期原型已经接线，修饰键窗口交互与边界行为仍待实机验收，不能算 parity verified。
- Checklist、图片/附件正文嵌入、分隔线、完整链接编辑、任务/笔记 Slash Profile 和搜索筛选式 Slash 面板。
- 日历时轴布局、跨日条、时段拖拽/缩放；当前周视图是按天网格，不是 Flutter 时轴等价版。
- 完整清单/标签/文件夹管理、排序与拖动、所有上下文菜单和快捷输入属性。
- 菜单栏快速捕获、全局快捷键、通知点击跳转、原生分享等系统集成。
- Flutter 导出→Native 导入、附件对账、正式迁移备份、签名/公证/发布。

## 统一验收时重点

本轮新增功能均需验证；历史 41 项测试通过只适用于之前的文本基础版本，不能外推到当前修改。统一覆盖数据重载、正文格式往返、IME、Undo、重复父子链、两类垃圾桶隔离、附件/通知、四象限规则及日历拖动，再做多尺寸/深浅色截图。编译成功不代替以上结论。
