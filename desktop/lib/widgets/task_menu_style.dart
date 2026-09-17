import 'package:flutter/material.dart';
import '../theme/workfollow_theme.dart';

/// Task menu proportions. Color roles come from the shared theme so every
/// picker, command menu and context menu uses the same neutral interaction
/// surface.
class TaskMenuStyle {
  static const width = 264.0;
  static const rowHeight = 44.0;

  /// Source-compatible alias; menu consumers use WorkFollowMetrics directly.
  @Deprecated('Use WorkFollowMetrics.fieldIcon')
  static const iconSize = WorkFollowMetrics.fieldIcon;

  static WorkFollowTheme colors(BuildContext context) {
    return WorkFollowTheme.of(context);
  }
}
