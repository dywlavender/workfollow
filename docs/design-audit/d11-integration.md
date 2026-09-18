# D11.1 最终集成闭环

> 状态：已完成。将并行任务的源码、测试和设计记录收回同一分支，并用同一份规则重新扫描全部 `desktop/lib`。

## 收口内容

- Feedback 的停留时长统一由 `WorkFollowFeedbackTiming` 持有。
- Feedback HUD 和 Quick Add 使用 `WorkFollowSurfaceTokens`，不在业务 Widget 内拼接阴影。
- Today 的拖拽标记、拖拽预览和延迟使用 `TaskListMetrics` 与 `WorkFollowMotion`。
- Matrix 的象限、分组、添加面板、拖拽预览和检查框使用 `MatrixMetrics`。
- Schedule Options / Schedule Panel 的行高、按钮、分隔线和对比前景使用 `TaskScheduleMetrics` 与 `WorkFollowThemeContrast`。
- TaskRow、文档 Checklist 和任务列表 Divider 使用共享半径、描边和 Divider Token。
- 删除 D11 锁定测试中的路径级 deferred allowlist；所有业务 Dart 文件现在都接受同一份扫描。

## 分支完整性

并行新增的 Feedback、Matrix、Task List、Schedule 和日期工作日源码，以及对应的 Widget / Projection / 行为回归测试，均作为当前提交的一部分纳入版本控制。日期弹框验收截图和说明保存在 `docs/task-date-popover-2026-09-16.md` 及 `docs/screenshots/`。

## 复核规则

业务源码只允许使用 Theme、全局 Token 或模块 Metrics。保留的内容渲染、遮罩、绘制和用户数据颜色例外必须写入 [`../design-system/exceptions.md`](../design-system/exceptions.md)，不得通过新增路径跳过锁定测试。

## 验证

```bash
cd desktop
flutter test test/design_system_lock_test.dart
flutter test test/design_system_gallery_test.dart
flutter test
```

`flutter analyze` 若受本机 Flutter SDK 的 macOS analyzer runtime 限制失败，应单独记录，不以扩大白名单代替修复源码。
