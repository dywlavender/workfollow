import 'package:flutter/material.dart';

import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';

/// The title row of a task list: `[视图图标] 最近 7 天            ⇅  …`.
///
/// One line, one icon and a 19pt title. The eyebrow pill and the subtitle the
/// older header carried are gone: a list page is a working surface, and a
/// three-line hero above the first task pushed the actual work off the fold.
class TaskListHeader extends StatelessWidget {
  const TaskListHeader(
      {super.key, required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      height: TaskListMetrics.headerHeight,
      child: Row(children: [
        AppIcon(icon,
            key: const ValueKey('list-view-icon'),
            size: TaskListMetrics.headerIconSize,
            color: tokens.textSecondary),
        const SizedBox(width: TaskListMetrics.headerIconGap),
        Expanded(
            child: Text(title,
                key: const ValueKey('list-view-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: WorkFollowMacTypography.pageTitle,
                    height: WorkFollowMacTypography.lineTight,
                    fontWeight: WorkFollowMacWeight.semibold,
                    letterSpacing: WorkFollowMacTracking.none))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
