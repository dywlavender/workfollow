import 'package:flutter/material.dart';

import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';

/// One heading inside a task list: `˅ 已过期 4          顺延`.
///
/// The list used to mark a group with a 7pt coloured dot — warning orange for
/// overdue, success green for completed — so a group heading read as a status
/// badge and half the list wore a colour that carried no information. A
/// heading is a label: the chevron says it folds, the label stays in the normal
/// text colour whatever the group means, and only the count is muted. Group
/// meaning belongs to the rows, where the dates already say it.
class TaskGroupHeader extends StatelessWidget {
  const TaskGroupHeader({
    super.key,
    required this.title,
    required this.count,
    this.trailing,
    this.expanded = true,
    this.onToggle,
  });

  final String title;
  final int count;

  /// Optional action pinned to the right edge of the heading — the overdue
  /// group's 顺延 lives here rather than being assembled by the screen.
  final Widget? trailing;

  /// Folding state; drives the chevron direction.
  final bool expanded;

  /// Null for groups that are not foldable: the chevron is still drawn so
  /// every heading scans the same way, but the row is not interactive.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final heading = SizedBox(
      height: TaskListMetrics.groupHeaderHeight,
      child: Row(children: [
        AppIcon(
            expanded ? WorkFollowIcons.expandMore : WorkFollowIcons.chevronNext,
            key: ValueKey('group-chevron-$title'),
            size: TaskListMetrics.groupChevronIconSize,
            color: tokens.textTertiary),
        const SizedBox(width: WorkFollowSpacing.inlineGap),
        Text(title,
            style: TextStyle(
                fontSize: WorkFollowMacTypography.sectionTitle,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.semibold,
                color: tokens.textPrimary)),
        const SizedBox(width: WorkFollowSpacing.inlineGap),
        Text('$count',
            style: TextStyle(
                fontSize: WorkFollowMacTypography.listMeta,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.regular,
                color: tokens.textTertiary)),
        if (trailing != null) ...[const Spacer(), trailing!],
      ]),
    );
    if (onToggle == null) return heading;
    return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
            onTap: onToggle, behavior: HitTestBehavior.opaque, child: heading));
  }
}
