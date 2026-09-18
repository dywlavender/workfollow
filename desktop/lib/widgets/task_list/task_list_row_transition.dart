import 'package:flutter/material.dart';

import '../../theme/workfollow_theme.dart';

/// Shared state transition for task rows.
///
/// The list decides which group owns a task; this widget only animates a row
/// when its state changes in place (for example a restored task in the
/// completed view). The key deliberately includes the closed state so a
/// completion is a real visual state change instead of a silent rebuild.
class TaskListRowTransition extends StatelessWidget {
  const TaskListRowTransition({
    super.key,
    required this.taskId,
    required this.closed,
    required this.child,
  });

  final String taskId;
  final bool closed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: WorkFollowMotion.taskRow,
      switchInCurve: WorkFollowMotion.standard,
      switchOutCurve: WorkFollowMotion.taskRowExit,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final position = Tween<Offset>(
          begin: Offset(0, -WorkFollowMotion.taskRowSlide),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: position, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey('$taskId:$closed'),
        child: child,
      ),
    );
  }
}
