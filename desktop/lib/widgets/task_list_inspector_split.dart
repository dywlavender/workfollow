import 'package:flutter/material.dart';

import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'app_surfaces.dart';

/// The wide task-workspace layout shared by task lists such as 已完成 and 垃圾桶.
/// Keeping the pane geometry and resize target in one component prevents the
/// two views from acquiring subtly different breakpoints or drag behaviour.
class TaskListInspectorSplit extends StatelessWidget {
  const TaskListInspectorSplit({
    super.key,
    required this.list,
    required this.inspector,
    required this.listWidth,
    required this.onResize,
  });

  final Widget list;
  final Widget inspector;
  final double listWidth;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('web-task-list-pane'),
          width: listWidth,
          child: list,
        ),
        _TaskPaneDivider(
          key: const ValueKey('task-pane-divider'),
          onDrag: onResize,
        ),
        Expanded(
          child: ConstrainedBox(
            key: const ValueKey('web-task-detail-pane'),
            constraints: const BoxConstraints(
                minWidth: WorkFollowLayout.taskDetailMinWidth),
            child: ColoredBox(color: tokens.content, child: inspector),
          ),
        ),
      ],
    );
  }
}

/// Empty state for the persistent wide-window inspector.
class EmptyTaskInspector extends StatelessWidget {
  const EmptyTaskInspector({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WorkFollowSpacing.pageBottomSpace),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(WorkFollowIcons.touch,
                size: WorkFollowMetrics.headerIcon, color: tokens.textTertiary),
            const SizedBox(height: WorkFollowSpacing.space3),
            Text('选择一个任务开始编辑',
                style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: WorkFollowMacTypography.listTitle,
                    height: WorkFollowMacTypography.lineControl,
                    fontWeight: WorkFollowMacWeight.semibold)),
            const SizedBox(height: WorkFollowSpacing.inlineGap),
            Text('标题、备注、日期和子任务都会在这里展开。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: WorkFollowMacTypography.supporting,
                    height: WorkFollowMacTypography.lineList)),
          ],
        ),
      ),
    );
  }
}

/// A one-pixel visual divider with a larger invisible resize target.
class _TaskPaneDivider extends StatefulWidget {
  const _TaskPaneDivider({super.key, required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_TaskPaneDivider> createState() => _TaskPaneDividerState();
}

class _TaskPaneDividerState extends State<_TaskPaneDivider> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      width: WorkFollowLayout.taskListDividerWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: hovering ? tokens.accent : tokens.border,
            ),
          ),
          Positioned(
            left: -6,
            right: -6,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              onEnter: (_) => setState(() => hovering = true),
              onExit: (_) => setState(() => hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    widget.onDrag(details.delta.dx),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
