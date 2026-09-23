# Native macOS 迁移计划

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

Editor 后续以 NativeDocument/DTO 为持久化模型，不能直接把 NSTextView attributedString 当数据库；Task/Note 共用 DocumentEditor，通过 descriptor/Profile 注入能力。

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
