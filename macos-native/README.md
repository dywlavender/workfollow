# WorkFollow Native 实验

> 当前以 [功能迁移清单](../docs/native-feature-migration-status.md) 为准。已扩展任务/笔记/垃圾桶、四象限、日历、富文本、提醒、附件及独立预览持久化。本批只编译，交互与回归待统一验收；下面早期阶段记录不代表这些新增功能已经验收。

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
- Inspector 支持标题实时编辑、完成/恢复、安排日期与截止日期、优先级、固定清单选择和软删除；正文已接入 NSTextView 纯文本编辑。
- 正文支持原生撤销/重做及 ⌘F 查找；撤销历史按正文视图隔离，切换任务时重置。尚未实现格式、Slash、附件和持久化。
- 日期选择使用系统 Popover 和图形日期控件；优先级、清单和更多操作使用系统 Menu。
- ⌘N 聚焦新建、⌘K 快速打开、⌘, 设置、⌘1 今天、⌘2 收集箱。
- 跟随系统/浅色/深色；AppKit 保存窗口位置和尺寸。
- 列表宽度 340–470pt，受剩余 Inspector 最小 300pt 约束；紧凑窗口使用导航弹层和列表/详情切换。
- 笔记、两个垃圾桶、日历、四象限仅导航占位，未接业务。

`TaskWorkspaceModel` 通过 `TaskActions` 操作 `WorkspaceStore`，列表来自 Domain 投影。首次启动无快照时载入示例任务；后续编辑同步原子保存至独立 `Application Support/WorkFollowNativePreview/workspace.json`，重启重载，读取失败会停止自动保存并提示。附件副本也存于该独立目录。不读取 Flutter 正式任务、笔记或附件。

后续范围与验收记录见 [迁移计划](../docs/native-migration-plan.md) 和 [行为基线](../docs/ticktick-parity-matrix.md)。

## Domain / Task List 与测试

`WorkFollow/Domain` 和 `WorkFollow/Application` 是独立纯 Swift 层。WorkFollowTests 覆盖核心动作、一级父子关系、列表/树投影、TaskWorkspaceModel 行为和键盘选择边界。

```sh
xcodebuild -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/workfollow-native-build CODE_SIGNING_ALLOWED=NO test
```

列表获得焦点时 ↑/↓ 切换任务，Return 打开首项或保持所选详情；Quick Add 输入焦点下不接管这些按键。Today Quick Add 设置当天真实 schedule，Inbox Quick Add 不预设日期。Phase 1 全尺寸拖动、窄屏返回和跨屏窗口恢复仍是 IMPLEMENTED / PARTIALLY VERIFIED。

提醒、重复、标签、附件、关联、Persistence、Notes、Calendar、Trash 尚未接入完整业务；此实验数据不会写入 Flutter 正式数据。当前 41 项 XCTest 通过。正文中文多行粘贴、撤销/重做、查找、跨任务隔离已实机验证；中文输入法候选窗仍待专门实测。Phase 4 的日期 Popover、优先级/清单菜单、父子清单联动及完成/恢复已有验收记录；低于 641pt 紧凑布局阈值后的第二次 Escape、Popover 外部关闭和菜单键盘导航仍待实机验收。
