import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

/// The corner of a completion box, whatever size it is drawn at.
///
/// One silhouette for one control. A box in a calendar strip is 11pt and one on
/// a board card is 24pt, and they are the same shape because the radius is a
/// fraction of the box rather than a number someone picked per screen. The
/// fraction is the task row's — its 20pt box with a 5pt corner is the shape the
/// rest of the product matches.
double taskCompletionBoxRadius(double size) =>
    size * WorkFollowRadii.checkbox / TaskListMetrics.checkboxSize;

/// The outline an open task's completion box carries.
///
/// Priority is the one property a collapsed row has nowhere else to show, so
/// the box's edge is where it lives. The mapping sits here rather than beside
/// the row because the same task draws this box in more than one place, and a
/// task cannot be a red box in the list and a grey one in its own editor.
Color taskPriorityColor(TaskPriority priority, WorkFollowTheme tokens) =>
    switch (priority) {
      TaskPriority.high => tokens.danger,
      TaskPriority.medium => tokens.warning,
      TaskPriority.low => tokens.accent,
      TaskPriority.none => tokens.borderStrong,
    };

/// The fill a *completed* task's box takes, wherever that box is drawn.
///
/// One task draws this box in the list, in its own editor's header, in the
/// editor's child rows, on a board card and on a calendar bar. The fill has to
/// be one value for all of them: a task cannot be green in its editor and
/// graphite in the list. It is the completed neutral rather than the muted ink
/// the box used to take — that ink is the *text* weight of a finished row, and
/// at box size it read as a dark chip instead of a finished one.
Color taskCompletionFill(WorkFollowTheme tokens) =>
    tokens.content.computeLuminance() > .5
        ? WorkFollowColors.neutralCompleted
        : tokens.textTertiary;

/// A completion box, drawn rather than taken from the icon set.
///
/// Wherever a task appears it is marked by this shape — or by the platform's own
/// checkbox drawn at this same corner — so the box means one thing and looks one
/// way in a task row, in the editor's header and in a day cell alike. Drawing it
/// instead of using an icon is what makes that true: an icon brings its own
/// corner, its own stroke and its own idea of what a tick looks like, and no two
/// places get to differ by accident.
///
/// It reports state and does not take input. Everywhere a task can be completed
/// the box already sits inside something that is the target — the row's own
/// control, the header's button, the whole of a calendar item — and a second,
/// smaller target inside that one would be one more thing to aim at and miss.
class TaskCompletionBox extends StatelessWidget {
  const TaskCompletionBox({
    super.key,
    required this.size,
    required this.completed,
    this.openColor,
    this.doneColor,
  });

  /// The side of the box, which sets its corner too.
  final double size;

  final bool completed;

  /// The outline of a box that is still open. Left unset it takes the muted ink.
  final Color? openColor;

  /// The fill of a box that is done. Left unset it takes the completed
  /// neutral, which is how a finished task reads everywhere else in the
  /// product — including in the editor's own header, so the same task is the
  /// same box on both sides of the window.
  final Color? doneColor;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final radius = taskCompletionBoxRadius(size);
    if (completed) {
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: doneColor ?? taskCompletionFill(tokens),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Center(
            child: AppIcon(WorkFollowIcons.check,
                size: size * .68, color: tokens.content),
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: openColor ?? tokens.textSecondary,
          // Thin in proportion to the box, the way a task row's is, but never
          // so thin that a small box stops reading as having an edge.
          width: math.max(
            1,
            size *
                WorkFollowMetrics.checkboxBorderWidth /
                TaskListMetrics.checkboxSize,
          ),
        ),
      ),
    );
  }
}
