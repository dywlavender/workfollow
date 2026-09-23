# WorkFollow Native 实验

Native macOS 实验版本，不是 Flutter 的替代版本。要求 macOS 14+、支持同步文件组的 Xcode 16+；本轮使用 Xcode 26.6 编译。

## 运行

用 Xcode 打开 `WorkFollow.xcodeproj`，选择 WorkFollow scheme / My Mac，Run。无需第三方依赖。

在仓库根目录也可运行：

```sh
xcodebuild -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/workfollow-native-build CODE_SIGNING_ALLOWED=NO build
open /private/tmp/workfollow-native-build/Build/Products/Debug/WorkFollow.app
```

## 本轮范围

- SwiftUI 图标栏、导航栏、Today / 收集箱 / 已完成任务列表和原生 Task Inspector。
- Task 列表由纯 Swift Domain、`TaskActions` 和 Projection 驱动；完成框独立于行选择，Quick Add 经动作层创建真实 Domain Task。
- Inspector 支持标题实时编辑、完成/恢复、安排日期与截止日期、优先级、固定清单选择和软删除；正文仍为占位。
- 日期选择使用系统 Popover 和图形日期控件；优先级、清单和更多操作使用系统 Menu。
- ⌘N 聚焦新建、⌘K 快速打开、⌘, 设置、⌘1 今天、⌘2 收集箱。
- 跟随系统/浅色/深色；AppKit 保存窗口位置和尺寸。
- 列表宽度 340–470pt，受剩余 Inspector 最小 300pt 约束；紧凑窗口使用导航弹层和列表/详情切换。
- 笔记、两个垃圾桶、日历、四象限仅导航占位，未接业务。

`TaskWorkspaceModel` 只负责选择、展开等展示状态，并通过 `TaskActions` 操作内存 `WorkspaceStore`；任务列表完全来自 Domain 投影，不保留 PreviewTask 副本。数据仍是可丢弃的内存种子，退出重开会重置；仅外观、窗口几何写入独立 bundle `com.workfollow.native.preview` 的偏好。不读取 Flutter 数据目录，不访问正式任务、笔记或附件。

后续范围与验收记录见 [迁移计划](../docs/native-migration-plan.md) 和 [行为基线](../docs/ticktick-parity-matrix.md)。

## Domain / Task List 与测试

`WorkFollow/Domain` 和 `WorkFollow/Application` 是独立纯 Swift 层。WorkFollowTests 覆盖核心动作、一级父子关系、列表/树投影、TaskWorkspaceModel 行为和键盘选择边界。

```sh
xcodebuild -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/workfollow-native-build CODE_SIGNING_ALLOWED=NO test
```

列表获得焦点时 ↑/↓ 切换任务，Return 打开首项或保持所选详情；Quick Add 输入焦点下不接管这些按键。Today Quick Add 设置当天真实 schedule，Inbox Quick Add 不预设日期。Phase 1 全尺寸拖动、窄屏返回和跨屏窗口恢复仍是 IMPLEMENTED / PARTIALLY VERIFIED。

Inspector 正文编辑、提醒、重复、标签、附件、关联、子任务编辑、Persistence、Notes、Calendar、Trash 均未接入；此实验数据不会写入 Flutter 正式数据。Phase 4 的 30 项 XCTest 通过；已在真实 macOS 窗口核对标题实时编辑、日期 Popover 锚点与 Escape、优先级/清单菜单、父子清单联动及完成/恢复。低于 641pt 紧凑布局阈值后的第二次 Escape、Popover 外部关闭和菜单键盘导航仍待实机验收。
