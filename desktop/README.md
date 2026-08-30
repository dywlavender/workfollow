# 打勾 macOS 个人版原型

这是 `feature/flutter-personal-desktop` 分支上的 Flutter 桌面原型，按照
[`docs/macos-personal-app-design.md`](../docs/macos-personal-app-design.md) 实现第一轮高保真交互：

- 与 Web 信息架构对齐的 macOS 工作台：全局导航、任务二级导航、列表和详情检查器
- 首页工作台、任务四区布局，以及窄窗口下的渐进式收起
- 今天、收集箱、计划、全部任务、已完成和自定义清单
- 快速添加、任务详情检查器、子任务信息
- 勾选动效、拖拽入口预留、可撤销完成反馈
- `Command-K` 搜索与命令面板
- 日历月视图、文件夹/笔记列表/编辑器三栏笔记工作区
- 浅色/深色主题、低强度四季氛围卡片
- 菜单栏和键盘快捷键的交互契约

## 当前阶段边界

该原型暂时使用内存演示数据，尚未接入 SQLite、系统通知、菜单栏常驻和真正的全局快捷键；macOS Runner 已生成，可以直接编译运行。这样做是为了先冻结窗口结构、视觉令牌和核心交互；下一阶段再接入本地数据层和 macOS 能力。

## 运行

在安装 Flutter SDK 和完整 Xcode 后：

```bash
cd desktop
flutter pub get
flutter run -d macos
```

如果在全新工作副本中发现 `macos/` 目录缺失，再执行 `flutter create --platforms=macos .` 生成 Runner 文件；正常情况下无需重复执行。

## 自动验证

```bash
flutter analyze
flutter test
flutter build macos --release
```

当前原型的测试数据在内存中，重启应用后会恢复为演示数据。

## 验收重点

1. 窗口宽度 1280 × 760 pt 时全局导航、任务导航、列表和详情比例是否舒适。
2. 窗口缩到 880 × 600 pt 时详情区是否自动收起且仍可完成任务。
3. 连续创建、勾选、撤销和切换清单是否不需要多余确认。
4. 浅色和深色模式下正文、焦点和状态是否清楚。
5. 开启减少动态效果后，信息和操作反馈是否仍然完整。
