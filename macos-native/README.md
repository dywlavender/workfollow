# WorkFollow Native 实验

第一批：可运行的 macOS Shell，不是 Flutter 的替代版本。要求 macOS 14+、支持同步文件组的 Xcode 16+；本轮使用 Xcode 26.6 编译。

## 运行

用 Xcode 打开 `WorkFollow.xcodeproj`，选择 WorkFollow scheme / My Mac，Run。无需第三方依赖。

在仓库根目录也可运行：

```sh
xcodebuild -project macos-native/WorkFollow.xcodeproj -scheme WorkFollow -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/workfollow-native-build CODE_SIGNING_ALLOWED=NO build
open /private/tmp/workfollow-native-build/Build/Products/Debug/WorkFollow.app
```

## 本轮范围

- SwiftUI 图标栏、导航栏、Today 示例列表、任务选择、Inspector 只读空壳。
- Return 创建示例任务；完成框独立于行选择；今天/收集箱/已完成为内存投影。
- ⌘N 聚焦新建、⌘K 快速打开、⌘, 设置、⌘1 今天、⌘2 收集箱。
- 跟随系统/浅色/深色；AppKit 保存窗口位置和尺寸。
- 列表宽度 340–470pt，受剩余 Inspector 最小 300pt 约束；紧凑窗口使用导航弹层和列表/详情切换。
- 笔记、两个垃圾桶、日历、四象限仅导航占位，未接业务。

`PreviewWorkspace` 是可丢弃的演示状态，不是正式 Domain。任务只在内存中，退出重开恢复种子数据。仅外观、窗口几何写入独立 bundle `com.workfollow.native.preview` 的偏好；不读取 Flutter 数据目录，不访问正式任务、笔记或附件。

后续范围与验收记录见 [迁移计划](../docs/native-migration-plan.md) 和 [行为基线](../docs/ticktick-parity-matrix.md)。
