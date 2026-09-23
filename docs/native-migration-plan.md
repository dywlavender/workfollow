# Native macOS 迁移计划

当前状态：

- **Phase 1: IMPLEMENTED / PARTIALLY VERIFIED**。代码完成不等于全尺寸、跨屏窗口恢复全部验收。
- **Phase 2 第一批: IMPLEMENTED / UNIT TEST VERIFIED**。纯 Swift 核心规则已落地，尚未与 SwiftUI 或持久化接线。
- **Phase 3: IMPLEMENTED / TEST + LIVE UI VERIFIED**。Today / Inbox / Completed 由正式 Domain 投影驱动；任务仍仅保存在内存中，不含持久化。
- **Phase 4: IMPLEMENTED / UNIT TEST + LIVE UI PARTIALLY VERIFIED**。Inspector 编辑和系统控件已接线；真实窗口已核对标题实时编辑、Popover、优先级/清单菜单、Escape、父子清单联动及完成/恢复。低于紧凑布局阈值时的第二次 Escape 尚未实机核对。

## 决策与边界

从 `feature/flutter-personal-desktop` 创建 `experiment/macos-native`；独立工作区 `workfollow-macos-native`。Flutter 留在 `desktop/` 作为产品行为基准，本轮不修改它。原 Flutter 工作区的暂存设计素材不带入实验工作区。

本次只交付第一批 Shell。能启动不等于 Native 已达到 Flutter 水平，更不能据此判断重写收益。收益判断必须等到 Inspector / NSTextView 的 IME、焦点、选择和浮层实测。

SwiftUI 负责组合、普通控件和状态；AppKit 负责窗口、复杂编辑器、菜单/浮层和 responder 交互。当前未实现的层不预建空抽象。

## 阶段与退出条件

| 阶段 | 范围 | 验收门槛 |
| --- | --- | --- |
| 0 | Flutter 行为 Contract、截图基线 | 分清现有行为、目标行为、未验证项；争议以证据判断 |
| 1 | Native Shell、内存示例、主题、菜单、窗口 | 启动、导航、选择、宽窄布局和焦点可用 |
| 2 | Domain + Application | TaskActions、Store、Projection、Tree 纯单元测试；View 不写业务 |
| 3 | Task List | 新建→Today→选中→完成→恢复；无第二份 UI 任务状态 |
| 4 | Inspector | Header/Body/Footer、Popover、Responder、Escape；第一次方向判断 |
| 5 | NSTextView Editor | 先输入/IME/选择/粘贴/撤销，再文档模型、格式、Slash；核心 Go/No-Go |
| 6 | Task 完整闭环 | 日期、提醒、重复、标签、附件、关联、一级子任务、删除/恢复/Undo |
| 7 | Notes | 共用编辑器，独立 Profile；选中文字创建任务 |
| 8 | Trash→Matrix→Calendar | 独立投影，任务/笔记垃圾桶隔离；日期计算与 UI 分离 |
| 9 | macOS 系统能力 | 快速捕获、全局快捷键、通知、Dock、文件、分享、拖放 |
| 10 | 数据迁移 | Flutter Export→Native Preview Import；逐项核对后才设计正式迁移和备份 |
| 11 | Native / Flutter 对比 | 实测 IME、焦点、浮层、拖放、内存、启动、维护成本，决定是否继续 |
| 12 | 发布 | 全模块、持久化、迁移验收后签名、公证、发布；保留 Flutter 回退路径 |

第二批先迁 Domain + TaskActions；不要扩展 `PreviewTask` 充当正式实体。目标链路为 View → TaskActions → WorkspaceStore → Repository。独立 Preview Store 可位于 `Application Support/WorkFollowNativePreview`，严禁两端同时读写 Flutter 正式目录。

## Phase 2 第一批结果（2026-09-23）

- 新增 WorkFollowTests XCTest target，并加入共享 scheme 的 TestAction。
- Domain：Task、TaskPriority、TaskStatus、TaskSchedule、TaskList，均为 Foundation 值类型。
- Application：TaskActions、TaskActionResult、WorkspaceStore、TaskListProjection、TaskTreeProjection。
- 单一内存 Store；动作统一写入快照，投影只读；注入 clock 和 Calendar，测试不依赖当天日期和系统时区。
- 已迁：创建、改标题、优先级、安排日期、完成/恢复、软删除/恢复删除、移清单、一级子任务、Today/Inbox/Completed、树展开与子行去重。
- 没有扩展 PreviewTask，也没有把正式 Domain 接入 SwiftUI；Inspector、编辑器、Persistence、Notes、Calendar 均未改造。

规则核对发现：Flutter Today/Inbox 页面保留其范围内已完成任务；只有待办计数和开放分组移除它们。因此测试是“完成移出 Today 开放任务，仍在已完成分组”，不是“整个 Today 删除该记录”。PreviewWorkspace 仍保留原先简化逻辑，不能当正式投影依据。

完成父任务带动未完成的活动子任务，已完成孩子保留原完成时间；恢复父任务不恢复孩子。删除父任务带动未删除孩子；从垃圾桶恢复仅恢复同批删除的孩子。移动父任务带动未删除孩子。这里未迁重复任务、放弃/跳过/转换状态、Undo、标签、置顶、全文档正文、持久化及完整清单管理，不宣称完整 Flutter Domain parity。

验证结果：

- `xcodebuild test`：14 项 XCTest 全通过（12 项 Domain/Projection，1 项键盘选择状态，1 项测试 Target smoke）。
- 实际 Native 窗口：↓ 首选/下一行、↑ 上一行、Return 保持所选详情，未误触完成。
- ⌘N 后方向键仍交给输入框，未改变列表选中项。
- 基础键盘导航是本轮唯一 UI 行为补口，不扩大 Phase 1 的全尺寸验收结论。

复跑命令（仓库根目录）：

```sh
xcodebuild -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/workfollow-native-build CODE_SIGNING_ALLOWED=NO test
```

Intel Mac 将 destination 的 arch 改为 x86_64。测试需要 macOS testmanagerd 权限；在限制沙箱里编译成功但 runner 启动失败不算测试通过。

Editor 后续以 NativeDocument/DTO 为持久化模型，不能直接把 NSTextView attributedString 当数据库；Task/Note 共用 DocumentEditor，通过 descriptor/Profile 注入能力。

## Phase 3 Task List 接线结果（2026-09-23）

- `AppNavigation` 独立持有页面导航；`TaskWorkspaceModel` 仅管理选中项、展开状态，并将所有任务改动路由到 `TaskActions` / `WorkspaceStore`。
- 移除 `PreviewTask` / `PreviewWorkspace` 和 Preview 键盘状态测试；Today、Inbox、Completed 列表/数量来自 `TaskListProjection`，子行来自 `TaskTreeProjection`。
- Quick Add：Today 创建有当天开始时间的任务，Inbox 创建无日期任务；完成/恢复更新开放计数并保留当前列表的已完成分组。Completed 使用 completed projection。
- Task Row 接受 Domain `Task`；父子级联、真实任务选中、只读 Inspector 均已在运行中的 Native 窗口核对。UI 仅展示，不写第二份任务状态。
- 新增 7 项 `TaskWorkspaceModelTests`，覆盖 Today/Inbox 新建、完成/恢复、树展开与匹配子任务、父级移动及子任务不能独立换清单、选择/展开状态。
- 当前 `xcodebuild test` 共 21 项通过；实际窗口验证了 Today/Inbox 投影、完成父任务后的级联和数量更新、选中任务的 Inspector 内容。

限制仍明确：没有数据库或重启持久化，样例数据每次启动重置；Inspector 只读；重复、提醒、标签、附件、Notes、Calendar、Trash 仍未进入本阶段。Phase 1 的多尺寸/跨屏验收状态不因本阶段 UI 接线而改变。

## Phase 4 Task Inspector 实现结果（2026-09-23）

- 新增 `TaskWorkspaceModel.setTitle` / `setPriority` / due-date / deadline Actions；Inspector 不访问 Store，所有改动经 `TaskActions`。
- 标题使用原生 SwiftUI `TextField` 实时写入任务；以任务 ID 隔离输入草稿，切换任务时重置焦点与临时 Inspector 状态。
- `TaskInspectorPresentationState` 集中处理 Escape：Popover → 编辑焦点 → 窄屏返回列表；宽屏无编辑状态时保留 Inspector。状态层有 XCTest 覆盖。
- 安排日期和截止日期为两个独立原生 SwiftUI Popover：今天、明天、下周、无日期、图形日期选择。更新其中一项保留另一项；安排日期编辑清除时间部分。
- 优先级通过系统 Menu 选择无/低/中/高；清单从收集箱、工作、学习、个人固定选项选择。子任务清单入口 disabled，父任务仍按 Domain 规则带动子任务。
- Header 提供完成/恢复；Footer 的 More 仅有软删除；正文是不可编辑占位，没有加入 `TextEditor` / 富文本 / 持久化。
- 新增标题草稿切换、优先级、日期字段独立性、清单约束、删除选中任务和 Inspector 状态的测试。当前共 30 项 XCTest 通过。
- 真实窗口截图核验：标题输入实时反映到任务行；第一次 Escape 退出标题输入焦点，第二次 Escape 在宽布局保留 Inspector。安排日期 Popover 锚在日期按钮下方，含快捷日期、月历和无日期，Escape 只关闭 Popover；优先级与清单系统菜单可选。More 菜单仅显示软删除。
- 真实操作核验父任务移动清单会带动子任务；子任务清单入口 disabled。完成父任务会完成活动子任务；恢复父任务不会强制恢复已完成子任务。上述仅作用于内存演示数据，重启后已恢复种子状态。

仍待实机核对：Popover 外部点击关闭、菜单键盘导航，以及窄布局第二次 Escape 返回列表。此次真实窗口可测试的最窄平铺宽度约 756pt，仍大于 `splitMinimum` 641pt，故紧凑布局返回行为目前由 `TaskInspectorPresentationState` XCTest 覆盖，不能算实机通过。Phase 4 保持部分验证状态。

## 第一批实现与实测（2026-09-23）

已实现：Xcode 工程、三栏 Shell、导航、Today/Inbox/Completed 内存示例、独立完成框、选中详情空壳、主题设置、原生菜单、窗口几何保存、约束内拖动列宽和紧凑布局。

已执行：

- Xcode Debug build 成功（macOS，未签名开发构建）。
- 启动真实 Native 窗口并检查浅色、深色截图；任务选择后右侧标题/日期/清单正确显示。
- ⌘N + Return 创建示例任务，Today 数量增加；独立完成框将其移出 Today、增加已完成数量，未打开详情。
- ⌘K 打开页面选择 sheet，Escape 关闭；⌘, 打开系统 Settings 窗口；深色选择反映到主窗口。

尚未完成验收：360/760/1024/1280/1440+ 全尺寸连续拖动、窄屏返回、重启后的窗口恢复、跨屏尺寸恢复。当前 UI 自动化拖动没有实际改变窗口，不能将代码存在视为这些项目通过。中文 IME 也不在本轮实测结论内。

第一批不包含：数据库、正式数据、完整 TaskActions、正文编辑、子任务、日期弹层、提醒、通知、日历/四象限业务、迁移与发布。

## 验收复跑

1. 运行 README 的 build，Xcode Run 或打开生成的 app。
2. 今天点击行→详情显示；按 Escape，宽屏详情保持。
3. ⌘N 输入示例任务，Return；点该任务完成框，验证今天移除、已完成出现、详情不被打开。
4. ⌘K 搜索页面并 Return；⌘, 分别切换三种主题。
5. 连续缩放至 360、760、1024、1280、1440+pt；检查导航入口、点击区域、紧凑详情返回和文本截断。
6. 拖动列表右边界，确认 340–470pt 且 Inspector 不低于 300pt；退出再启动核对窗口几何。

阶段 0 截图缺项及行为 Contract 见 [行为基线](ticktick-parity-matrix.md)。未齐全前不得宣布 Phase 0 全部验收。
