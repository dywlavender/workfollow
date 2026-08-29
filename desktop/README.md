# 打勾 macOS 个人版原型

这是 `feature/flutter-personal-desktop` 分支上的 Flutter 桌面原型，按照
[`docs/macos-personal-app-design.md`](../docs/macos-personal-app-design.md) 实现第一轮高保真交互：

- macOS 风格三栏工作台与可折叠侧栏
- 今天、收集箱、计划、全部任务、已完成和自定义清单
- 快速添加、任务详情检查器、子任务信息
- 勾选动效、拖拽入口预留、可撤销完成反馈
- `Command-K` 搜索与命令面板
- 日历月视图、笔记列表与编辑预览
- 浅色/深色主题、低强度四季氛围卡片
- 菜单栏和键盘快捷键的交互契约

## 当前阶段边界

该原型暂时使用内存演示数据，尚未接入 SQLite、系统通知、菜单栏常驻、全局快捷键和正式 macOS Runner。这样做是为了先冻结窗口结构、视觉令牌和核心交互；下一阶段再接入本地数据层和 macOS 能力。

## 运行

在安装 Flutter SDK 和完整 Xcode 后：

```bash
cd desktop
flutter pub get
flutter create --platforms=macos .
flutter run -d macos
```

`flutter create` 只用于生成缺失的 macOS Runner 文件；它不会覆盖 `lib/` 或 `pubspec.yaml` 中的本原型代码。

## 验收重点

1. 窗口宽度 1180 × 760 pt 时三栏比例是否舒适。
2. 窗口缩到 880 × 600 pt 时详情区是否自动收起且仍可完成任务。
3. 连续创建、勾选、撤销和切换清单是否不需要多余确认。
4. 浅色和深色模式下正文、焦点和状态是否清楚。
5. 开启减少动态效果后，信息和操作反馈是否仍然完整。
