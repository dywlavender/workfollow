import 'package:flutter/material.dart';

import '../../features/tasks/domain/chinese_work_calendar.dart';
import '../../models/task.dart';
import '../../theme/workfollow_surface_tokens.dart';
import '../../theme/workfollow_theme.dart';
import '../../theme/workfollow_theme_parity.dart';
import 'calendar_task_bar.dart';

/// Stable key fragment for one day, so the grid and the tests address the same
/// cell and the same overflow row.
String calendarDayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The words a day's number is drawn with.
///
/// The first of a month is spelled out with its month — "9月1日" rather than
/// "1". A month grid always opens with the closing days of the month before it
/// and closes with the opening days of the month after, so a bare "1" at either
/// end of a row is genuinely ambiguous: three months are on screen and the cell
/// does not otherwise say which one a first belongs to. Every other day is
/// unambiguous, because a month holds only one of each.
///
/// This is public so the tests can ask the same question the cell answers
/// instead of restating the rule.
String calendarDayLabel(DateTime date) =>
    date.day == 1 ? '${date.month}月1日' : '${date.day}';

/// One square of the month grid.
///
/// The cell is a sheet of paper with a date on it, not a card: it has no
/// radius, no margin and no fill of its own beyond the page's. The space it
/// has is spent on task bars, and when it runs out of room the bars stop and a
/// count says how many are left.
///
/// Two gestures live here, and they are deliberately different in weight.
/// A click selects the day — the grid keeps the page's current day, which is
/// what the toolbar's plus button dates a new task from. A double click creates
/// one on that day.
///
/// The two layers that carry those gestures are siblings, not ancestor and
/// descendant, and that is the whole point of the layout. A double-click
/// recogniser holds the gesture arena from the first click until its deadline
/// passes, so anything below it in the tree waits out that deadline before it
/// can act. If the bars were inside this cell's gesture surface, every click on
/// a task would inherit a third of a second of silence before the editor
/// opened. The day's own surface sits in the stack underneath the day's
/// contents instead: a press that lands on a bar is hit there, never reaches
/// the surface, and resolves the moment the pointer comes up.
///
/// What the cell does *not* own is anything that has to cross between cells.
/// The hairlines, the wash on today and the multi-day bands are all drawn by
/// the week row above it, because a band has to sit on top of the background
/// of the cells it passes through and under their lines, which no single cell
/// in the row can arrange.
class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.tasks,
    required this.listColorFor,
    this.skipSlots = 0,
    this.onSelect,
    this.onOpenTask,
    this.onCreate,
    this.onDropTask,
  });

  final DateTime date;

  /// Whether the day belongs to the month on screen. The trailing days of the
  /// neighbouring months keep their cell, their number, their tasks and their
  /// gestures — a month that starts mid-week begins with the days before it,
  /// the way a paper calendar does. They are drawn back a step in ink: the
  /// number takes [WorkFollowTheme.textTertiary] and the cell takes the page's
  /// own background instead of the sheet's, which is enough to say "not this
  /// month" without looking switched off.
  final bool inMonth;

  final bool isToday;

  /// The page's current day, marked on the number alone.
  final bool selected;

  /// The day's own tasks — the ones that both start and finish here. A task
  /// that runs across days is drawn by the row as one band, so it is not in
  /// this list; were it here as well the cell would show it twice.
  final List<TaskItem> tasks;

  /// How many bar slots the row's multi-day bands have already taken in this
  /// column. The cell's own bars start below them, so the day number is
  /// followed by that much empty space and the day still reads top to bottom.
  final int skipSlots;

  final Color Function(String listName) listColorFor;

  final VoidCallback? onSelect;

  /// Opens a task. The cell lends its own context because the surfaces a page
  /// opens over itself are anchored to what the pointer hit, and the cell is
  /// the nearest box the grid can hand over.
  final void Function(String taskId, BuildContext anchor)? onOpenTask;
  final void Function(BuildContext anchor)? onCreate;
  final void Function(String taskId)? onDropTask;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          onDropTask != null && details.data.isNotEmpty,
      onAcceptWithDetails: (details) => onDropTask?.call(details.data),
      builder: (context, candidate, rejected) {
        final dropping = candidate.isNotEmpty;
        return Container(
          key: ValueKey('calendar-day-${calendarDayKey(date)}'),
          // No fill of its own beyond the page's. Today's wash and the drag
          // highlight both have to sit above the bars, so they are the row's
          // to paint; what is left here is the paper.
          color: inMonth ? tokens.content : tokens.canvas,
          child: Stack(
            children: [
              // The day's own surface, underneath its contents. A press that
              // lands on a bar is hit by the layer above and never arrives
              // here, which is what keeps the double-click recogniser from
              // holding the arena under every task in the cell.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSelect,
                  onDoubleTap:
                      onCreate == null ? null : () => onCreate!(context),
                ),
              ),
              if (dropping)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: tokens.accent
                          .withValues(alpha: CalendarMetrics.dropHighlightAlpha),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      CalendarMetrics.cellHorizontalPadding,
                      CalendarMetrics.cellTopPadding,
                      CalendarMetrics.cellHorizontalPadding,
                      CalendarMetrics.cellBottomPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The number is decoration: a click on it belongs to the
                      // day surface below, like a click anywhere else in the
                      // cell that is not a task bar.
                      IgnorePointer(child: _dayNumber(tokens)),
                      const SizedBox(height: CalendarMetrics.dayNumberGap),
                      Expanded(child: _bars(context, tokens)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dayNumber(WorkFollowTheme tokens) {
    final foreground = isToday
        ? WorkFollowThemeContrast.foregroundOn(tokens.accent)
        : !inMonth
            ? tokens.textTertiary
            : selected
                ? tokens.accent
                : tokens.textPrimary;
    final label = calendarDayLabel(date);
    final festival = ChineseWorkCalendar.label(date);
    return SizedBox(
      height: CalendarMetrics.dayCellSize,
      child: Row(
        children: [
          // The marker is a capsule, not a fixed circle, so that it can hold the
          // month a first of the month carries. At a fixed 24pt "9月1日" would
          // either be clipped or hang outside the fill. An ordinary day is
          // unchanged: a 24pt square rounded by half its own height is the
          // circle this marker has always been.
          Container(
            key: ValueKey('calendar-day-marker-${calendarDayKey(date)}'),
            height: CalendarMetrics.dayCellSize,
            constraints:
                const BoxConstraints(minWidth: CalendarMetrics.dayCellSize),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
                horizontal: date.day == 1 ? WorkFollowSpacing.denseGap : 0),
            decoration: BoxDecoration(
              color: isToday ? tokens.accent : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(CalendarMetrics.dayCellSize / 2),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: WorkFollowMacTypography.listBody,
                height: WorkFollowMacTypography.lineTight,
                fontWeight: WorkFollowMacWeight.medium,
                color: foreground,
              ),
            ),
          ),
          // What the day *is*, when it is something: the green the schedule
          // panel's picker already gives a holiday, kept out of the accent
          // because that is what the page uses to say what it is pointing at.
          Expanded(
            child: festival == null
                ? const SizedBox.shrink()
                : Text(
                    festival,
                    key: ValueKey('calendar-day-festival-${calendarDayKey(date)}'),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: WorkFollowMacTypography.caption,
                      height: WorkFollowMacTypography.lineTight,
                      fontWeight: WorkFollowMacWeight.regular,
                      color: tokens.success,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// As many bars as the cell's height allows, once the row's bands have taken
  /// their slots.
  ///
  /// The cell measures itself rather than being told how many tasks to show,
  /// because the row height depends on the window: a tall window shows five
  /// bars where a short one shows two, and the overflow count follows. One slot
  /// is given back to the count when there is anything to count; with room for
  /// a single bar the count would take the only slot and the day would look
  /// empty, so a one-bar cell shows its first task and drops the count.
  Widget _bars(BuildContext context, WorkFollowTheme tokens) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      const slot = CalendarMetrics.taskBarHeight + CalendarMetrics.taskBarGap;
      final capacity =
          ((constraints.maxHeight + CalendarMetrics.taskBarGap) / slot).floor() -
              skipSlots;
      if (capacity < 1) return const SizedBox.shrink();
      final overflowing = tasks.length > capacity;
      final counting = overflowing && capacity > 1;
      final visibleCount =
          overflowing ? (counting ? capacity - 1 : capacity) : tasks.length;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (skipSlots > 0) SizedBox(height: skipSlots * slot),
          for (var index = 0; index < visibleCount; index++) ...[
            if (index > 0) const SizedBox(height: CalendarMetrics.taskBarGap),
            _bar(
              context,
              tokens,
              tasks[index],
              barWidth: constraints.maxWidth,
            ),
          ],
          if (counting) ...[
            const SizedBox(height: CalendarMetrics.taskBarGap),
            CalendarTaskOverflow(
              key: ValueKey('calendar-day-overflow-${calendarDayKey(date)}'),
              hiddenCount: tasks.length - visibleCount,
              onTap: onSelect,
            ),
          ],
        ],
      );
    });
  }

  Widget _bar(
    BuildContext context,
    WorkFollowTheme tokens,
    TaskItem task, {
    required double barWidth,
  }) {
    final color = listColorFor(task.listName);
    final open = onOpenTask;
    final bar = CalendarTaskBar(
      key: ValueKey('calendar-task-${task.id}'),
      task: task,
      listColor: color,
      onTap: open == null ? null : () => open(task.id, context),
    );
    // Pick-up follows drop: a task is draggable exactly when the grid has
    // somewhere to put it down, not when it happens to have an editor.
    if (onDropTask == null) return bar;
    return Draggable<String>(
      data: task.id,
      // The preview is the bar at the width it has in its own cell. Without a
      // width the unconstrained overlay would shrink the title to nothing.
      feedback: Container(
        width: barWidth,
        padding: const EdgeInsets.all(WorkFollowSpacing.hairlineGap),
        decoration: WorkFollowSurfaceTokens.popover(
          tokens,
          radius: BorderRadius.circular(WorkFollowRadii.sm),
        ),
        child: CalendarTaskBar(task: task, listColor: color),
      ),
      childWhenDragging:
          CalendarTaskBar(task: task, listColor: color, dragging: true),
      child: bar,
    );
  }
}
