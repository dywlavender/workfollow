import 'package:flutter/material.dart';

import '../../theme/workfollow_theme.dart';

/// The hairline between two task rows.
///
/// It starts after the checkbox column, never at the row's left edge, so the
/// checkbox and the line form one column and the titles keep a clean vertical.
/// The inset is derived from [TaskListMetrics], not written as a literal, so
/// moving the row padding moves the line with it.
class TaskListDivider extends StatelessWidget {
  const TaskListDivider(
      {super.key, this.inset = TaskListMetrics.dividerLeftInset});

  final double inset;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
        height: WorkFollowMetrics.dividerThickness,
        margin: EdgeInsets.only(left: inset),
        color: tokens.border);
  }
}
