import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme/workfollow_theme.dart';
import '../task_completion_box.dart';
import 'calendar_spans.dart';

/// A bar's clock, as `HH:mm`, or null when there is none to print.
///
/// [TaskItem.displayTimeLabel] is the task row's label — "9 月 21 日 15:00" —
/// and the cell a bar sits in already says which day it is, so printing the
/// date here would repeat the cell and take the room the title needs. A task
/// without a time of day is all-day and has no clock; "全天" would be a word
/// for the absence of one.
String? _clockOf(DateTime? at, {required bool withTime}) {
  if (!withTime || at == null) return null;
  return '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}

/// One task inside a month cell.
///
/// This is not a [TaskRow] at a smaller size. A day cell has to hold a whole
/// day's work in a strip of vertical space, so the bar is a single line — a
/// completion box, the title, and the clock — and everything a full row would
/// show as text is carried by colour instead: the tint is the task's own list
/// colour, the same value the task's row uses in every other view, so the
/// month agrees with the rest of the product about which list a task belongs
/// to without printing the list's name.
///
/// The bar is deliberately inert. Dragging, dropping and opening belong to the
/// grid that arranges these bars, which is the only place that knows what a
/// position in the month means.
class CalendarTaskBar extends StatelessWidget {
  const CalendarTaskBar({
    super.key,
    required this.task,
    required this.listColor,
    this.onTap,
    this.dragging = false,
  });

  final TaskItem task;

  /// The task's list colour, already resolved from the controller.
  final Color listColor;

  final VoidCallback? onTap;

  /// Paints the translucent placeholder a drag leaves behind in its cell.
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final radius = BorderRadius.circular(CalendarMetrics.taskBarRadius);
    return Opacity(
      opacity: dragging ? .35 : 1,
      child: Material(
        color: listColor.withValues(alpha: .12),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            height: CalendarMetrics.taskBarHeight,
            child: _BarLine(
              task: task,
              listColor: listColor,
              showBox: true,
              clock: _clockOf(
                localDateTimeFromStorage(task.dueAt),
                withTime: task.scheduledWithTime,
              ),
              clockColor: tokens.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One week row's share of a multi-day task.
///
/// The band is one box spanning as many columns as the piece covers, which is
/// the whole point: a run of five days is drawn as one thing rather than five
/// neighbours that happen to share a colour, and nothing is redrawn at the
/// cell edges. Only the two ends that are the task's real ends are rounded; a
/// side the row boundary cuts runs square and to the edge, so the piece above
/// it can pick the band up without a seam.
///
/// What a piece carries follows the same rule. The completion box marks where
/// the task begins, so only the piece holding the first day has one. The clock
/// belongs to the end of the run, so only the piece holding the last day
/// prints it. The title is on every piece: a band that resumed on Wednesday
/// with no words on it would be a coloured bar nobody could name.
class CalendarTaskSpan extends StatelessWidget {
  const CalendarTaskSpan({
    super.key,
    required this.span,
    required this.listColor,
    this.onTap,
    this.dragging = false,
  });

  final CalendarSpan span;

  final Color listColor;

  final VoidCallback? onTap;

  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    const corner = Radius.circular(CalendarMetrics.taskBarRadius);
    final radius = BorderRadius.horizontal(
      left: span.continuesFromPreviousRow ? Radius.zero : corner,
      right: span.continuesIntoNextRow ? Radius.zero : corner,
    );
    // The clock is taken from the task's end rather than its start: the band
    // reads left to right, so the time printed at its far end has to be the
    // time it finishes. An all-day run ends at midnight and prints nothing.
    return Opacity(
      opacity: dragging ? .35 : 1,
      child: Material(
        color: listColor.withValues(alpha: .12),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            height: CalendarMetrics.taskBarHeight,
            child: _BarLine(
              task: span.task,
              listColor: listColor,
              showBox: span.startsInRow,
              // Gated on the task having a time of day, the same way a
              // single-day bar is. An all-day run is stored with its end at
              // that day's midnight — the schedule panel writes `end` as
              // `DateUtils.dateOnly` when there is no clock — so printing the
              // end unconditionally would label every all-day band "00:00".
              clock: span.endsInRow
                  ? _clockOf(
                      localDateTimeFromStorage(span.task.dueEndAt),
                      withTime: span.task.scheduledWithTime,
                    )
                  : null,
              clockColor: tokens.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The inside of any bar in the month grid.
///
/// Both kinds of bar are the same strip of colour with the same box, title and
/// clock at the same sizes, so the parts live here rather than twice over.
class _BarLine extends StatelessWidget {
  const _BarLine({
    required this.task,
    required this.listColor,
    required this.showBox,
    required this.clock,
    required this.clockColor,
  });

  final TaskItem task;
  final Color listColor;
  final bool showBox;
  final String? clock;
  final Color clockColor;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final completed = task.completed;
    final label = clock;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: WorkFollowSpacing.denseGap),
      child: Row(
        children: [
          if (showBox) ...[
            // The same box a task row draws, at the size this strip has room
            // for. An open one takes the list colour so the bar says which
            // list it belongs to even before the eye reaches the title; a
            // finished one drops to grey, as a done task does everywhere.
            TaskCompletionBox(
              size: CalendarMetrics.taskBarCheckboxSize,
              completed: completed,
              openColor: listColor,
            ),
            const SizedBox(width: WorkFollowSpacing.denseGap),
          ],
          Expanded(
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Completion is carried by ink and nothing else: a finished task
              // steps back to grey, the same way a task row does. A rule struck
              // through the title would say it a second time and, at this size,
              // take more off the words than the colour already does.
              style: TextStyle(
                fontSize: WorkFollowMacTypography.listMeta,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.regular,
                color: completed ? tokens.textTertiary : tokens.textPrimary,
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: WorkFollowSpacing.denseGap),
            Text(
              label,
              style: TextStyle(
                fontSize: WorkFollowMacTypography.caption,
                height: WorkFollowMacTypography.lineControl,
                color: clockColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The trailing row of a cell that has more tasks than it has room for.
///
/// It is the cell's own affordance rather than a summary of the day: the count
/// says how many bars are missing, and tapping it selects the day so the rest
/// of the list is one step away.
class CalendarTaskOverflow extends StatelessWidget {
  const CalendarTaskOverflow({
    super.key,
    required this.hiddenCount,
    this.onTap,
  });

  final int hiddenCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CalendarMetrics.taskBarRadius),
      child: SizedBox(
        height: CalendarMetrics.taskBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: WorkFollowSpacing.denseGap),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '+$hiddenCount',
              style: TextStyle(
                fontSize: WorkFollowMacTypography.caption,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.medium,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
