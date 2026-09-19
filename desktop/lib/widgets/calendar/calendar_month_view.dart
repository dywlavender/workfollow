import 'package:flutter/material.dart';

import '../../state/workspace_controller.dart';
import '../../theme/workfollow_surface_tokens.dart';
import '../../theme/workfollow_theme.dart';
import 'calendar_day_cell.dart';
import 'calendar_spans.dart';
import 'calendar_task_bar.dart';

/// The month grid's column headers.
///
/// Sunday first, which is the same origin [CalendarMonthView] lays its cells
/// out from. The two have to agree: a header order that disagrees with the
/// leading offset does not mislabel one column, it shifts every date in the
/// month onto the wrong weekday.
class CalendarWeekHeader extends StatelessWidget {
  const CalendarWeekHeader({super.key});

  static const List<String> labels = [
    '周日',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      height: CalendarMetrics.weekHeaderHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: tokens.border, width: WorkFollowMetrics.dividerThickness),
        ),
      ),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: CalendarMetrics.weekHeaderPadding),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: WorkFollowMacTypography.listMeta,
                      fontWeight: WorkFollowMacWeight.regular,
                      color: tokens.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The month, as one continuous grid of days.
///
/// A month begins on the weekday it begins on, so the grid opens with the
/// closing days of the previous month and ends with the opening days of the
/// next. Those days are real cells: they carry their own tasks and they can be
/// dropped on. The row count follows the month instead of being padded to six,
/// so a month that fits in five weeks draws five.
///
/// Each row is a stack of three layers rather than a plain row of cells, and
/// the order is the design. The cells go down first with their own bars. The
/// row's multi-day bands come next, on top of the cells' backgrounds so a band
/// reads as one block of colour rather than as paint hidden behind six of
/// them. Today's wash follows, because a band passing through today has to be
/// tinted by the day like everything else in the cell. The hairlines go last,
/// so they cross the bands instead of stopping at them.
///
/// The view is handed the controller rather than a fistful of callbacks because
/// a day needs four separate answers from it — which tasks fall on the date,
/// which multi-day tasks cross the week, what colour each task's list is, and
/// where a dragged task should land — and threading all four through the grid
/// would not make the grid any simpler.
class CalendarMonthView extends StatelessWidget {
  const CalendarMonthView({
    super.key,
    required this.month,
    required this.controller,
    this.selectedDay,
    this.showCompleted = true,
    this.onSelectDay,
    this.onOpenTask,
    this.onCreateTask,
    this.today,
  });

  /// Any day of the month to show; the day of the month is ignored.
  final DateTime month;

  final WorkspaceController controller;
  final DateTime? selectedDay;

  /// Completed tasks are part of what a day looked like, so they stay in the
  /// grid unless the page asks for them to be hidden.
  final bool showCompleted;

  final void Function(DateTime day)? onSelectDay;

  /// Both take the cell's own context so the page can anchor a floating editor
  /// or the new-task composer to the square that was clicked.
  final void Function(String taskId, BuildContext anchor)? onOpenTask;
  final void Function(DateTime day, BuildContext anchor)? onCreateTask;

  /// Today, injected so a test can pin which day is circled.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final now = today ?? DateTime.now();
    final firstDay = DateTime(month.year, month.month, 1);
    // Dart counts weekdays from Monday as 1, so a Sunday is 7 and `% 7` puts
    // the week's start back on column zero.
    final leading = firstDay.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((leading + daysInMonth) / 7).ceil();
    return Container(
      // The sheet, and nothing around it. No border and no radius: the grid is
      // drawn to the window's edges, so a frame of its own would either double
      // the rail's line on the left or draw a line where the window simply
      // ends. The one line the top needs is the week header's bottom border,
      // which is also the line between the weekday names and the first week.
      color: tokens.content,
      child: Column(
        children: [
          const CalendarWeekHeader(),
          Expanded(
            child: Column(
              children: [
                for (var row = 0; row < rows; row++)
                  Expanded(
                    child: _WeekRow(
                      month: month,
                      leading: leading,
                      rowIndex: row,
                      rowCount: rows,
                      today: now,
                      selectedDay: selectedDay,
                      controller: controller,
                      showCompleted: showCompleted,
                      onSelectDay: onSelectDay,
                      onOpenTask: onOpenTask,
                      onCreateTask: onCreateTask,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One week of the grid, drawn as cells plus the bands that cross them.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.month,
    required this.leading,
    required this.rowIndex,
    required this.rowCount,
    required this.today,
    required this.selectedDay,
    required this.controller,
    required this.showCompleted,
    this.onSelectDay,
    this.onOpenTask,
    this.onCreateTask,
  });

  final DateTime month;
  final int leading;
  final int rowIndex;
  final int rowCount;
  final DateTime today;
  final DateTime? selectedDay;
  final WorkspaceController controller;
  final bool showCompleted;
  final void Function(DateTime day)? onSelectDay;
  final void Function(String taskId, BuildContext anchor)? onOpenTask;
  final void Function(DateTime day, BuildContext anchor)? onCreateTask;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final days = <DateTime>[
      for (var column = 0; column < 7; column++)
        DateTime(month.year, month.month, rowIndex * 7 + column - leading + 1),
    ];
    // Bands are laid out for the whole week at once: whether one can share a
    // lane with another is a question about columns, and columns only exist
    // in a row.
    final spans = layOutWeekSpans(
      days: days,
      tasks: controller.multiDayTasksWithin(days.first, days.last),
    ).where((span) => showCompleted || !span.task.completed).toList();
    final todayColumn = _columnOf(days, today);
    return LayoutBuilder(builder: (context, constraints) {
      final columnWidth = constraints.maxWidth / 7;
      return Stack(
        key: ValueKey('calendar-week-row-$rowIndex'),
        children: [
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _cell(days[column], column, spans),
                ),
            ],
          ),
          if (spans.isNotEmpty)
            Positioned.fill(
              key: ValueKey('calendar-span-layer-$rowIndex'),
              child: _SpanLayer(
                spans: spans,
                columnWidth: columnWidth,
                listColorFor: (listName) =>
                    Color(controller.colorValueForList(listName)),
                onOpenTask: onOpenTask,
              ),
            ),
          if (todayColumn != null)
            Positioned(
              key: ValueKey('calendar-today-wash-${calendarDayKey(today)}'),
              left: todayColumn * columnWidth,
              width: columnWidth,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: ColoredBox(
                  color: tokens.accent
                      .withValues(alpha: CalendarMetrics.todayCellAlpha),
                ),
              ),
            ),
          Positioned.fill(
            key: ValueKey('calendar-row-hairlines-$rowIndex'),
            child: IgnorePointer(
              child: _RowHairlines(
                rowIndex: rowIndex,
                showBottom: rowIndex < rowCount - 1,
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _cell(
    DateTime date,
    int column,
    List<CalendarSpan> spans,
  ) {
    final inMonth = date.year == month.year && date.month == month.month;
    final selected = selectedDay;
    final tasks = controller.singleDayTasksForDay(date);
    return CalendarDayCell(
      date: date,
      inMonth: inMonth,
      isToday: _sameDay(date, today),
      selected: selected != null && _sameDay(date, selected),
      skipSlots: spanSlotsOver(spans, column),
      tasks: showCompleted
          ? tasks
          : tasks.where((task) => !task.completed).toList(),
      listColorFor: (listName) => Color(controller.colorValueForList(listName)),
      onSelect: onSelectDay == null ? null : () => onSelectDay!(date),
      onOpenTask: onOpenTask,
      onCreate:
          onCreateTask == null ? null : (anchor) => onCreateTask!(date, anchor),
      onDropTask: (taskId) => controller.rescheduleTask(taskId, date),
    );
  }

  static int? _columnOf(List<DateTime> days, DateTime day) {
    for (var column = 0; column < days.length; column++) {
      if (_sameDay(days[column], day)) return column;
    }
    return null;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// The multi-day bands of one week row.
///
/// Each band is one box at the columns it covers, so it is painted once rather
/// than stitched from the cells underneath it. A band whose run continues out
/// of the row runs flush to that edge: the piece above it ended flush too, and
/// an inset here would show as a notch in the middle of a task.
class _SpanLayer extends StatelessWidget {
  const _SpanLayer({
    required this.spans,
    required this.columnWidth,
    required this.listColorFor,
    this.onOpenTask,
  });

  final List<CalendarSpan> spans;
  final double columnWidth;
  final Color Function(String listName) listColorFor;
  final void Function(String taskId, BuildContext anchor)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    const slack = CalendarMetrics.taskBarHeight + CalendarMetrics.taskBarGap;
    return Stack(
      children: [
        for (final span in spans)
          Positioned(
            left: span.fromColumn * columnWidth +
                (span.continuesFromPreviousRow
                    ? 0
                    : CalendarMetrics.cellHorizontalPadding),
            width: span.columnCount * columnWidth -
                (span.continuesFromPreviousRow
                    ? 0
                    : CalendarMetrics.cellHorizontalPadding) -
                (span.continuesIntoNextRow
                    ? 0
                    : CalendarMetrics.cellHorizontalPadding),
            top: CalendarMetrics.cellTopPadding +
                CalendarMetrics.dayCellSize +
                CalendarMetrics.dayNumberGap +
                span.lane * slack,
            height: CalendarMetrics.taskBarHeight,
            child: _band(context, span),
          ),
      ],
    );
  }

  Widget _band(BuildContext context, CalendarSpan span) {
    final tokens = WorkFollowTheme.of(context);
    final color = listColorFor(span.task.listName);
    final open = onOpenTask;
    final band = CalendarTaskSpan(
      key: ValueKey('calendar-span-${span.task.id}-${span.fromColumn}'),
      span: span,
      listColor: color,
      onTap: open == null ? null : () => open(span.task.id, context),
    );
    return Draggable<String>(
      data: span.task.id,
      // Dropping a band moves the whole run, not the piece that was grabbed:
      // the task's range is what it is, and a drag says where it goes next.
      feedback: SizedBox(
        width: span.columnCount * columnWidth,
        child: Container(
          padding: const EdgeInsets.all(WorkFollowSpacing.hairlineGap),
          decoration: WorkFollowSurfaceTokens.popover(
            tokens,
            radius: BorderRadius.circular(WorkFollowRadii.sm),
          ),
          child: CalendarTaskSpan(span: span, listColor: color),
        ),
      ),
      childWhenDragging:
          CalendarTaskSpan(span: span, listColor: color, dragging: true),
      child: band,
    );
  }
}

/// The grid's hairlines, over everything.
///
/// They are drawn here rather than on each cell because a band crosses them:
/// a cell's own border sits under the band's colour, so the line would stop at
/// every band instead of running through it. The last column and the last row
/// are left off, so the grid's outer edge is one line and not two.
///
/// Each line is keyed by its own row and column. The whole point of moving
/// them off the cell is that the line between two days is painted once and by
/// a different widget than either day, and that is not something a test can
/// tell from the days' own paint.
///
/// The boxes are stretched rather than sized to their content, and that is not
/// a detail: an empty box with a border asks for its smallest size, which in a
/// row whose cross axis is loose is zero. A zero-height box draws its right
/// border as a line of length zero — the grid loses every vertical rule — and
/// the row centres what is left, so its bottom border lands through the middle
/// of the week instead of under it.
class _RowHairlines extends StatelessWidget {
  const _RowHairlines({required this.rowIndex, required this.showBottom});

  final int rowIndex;
  final bool showBottom;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final line = BorderSide(
        color: tokens.border, width: WorkFollowMetrics.dividerThickness);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var column = 0; column < 7; column++)
          Expanded(
            child: DecoratedBox(
              key: ValueKey('calendar-hairline-$rowIndex-$column'),
              decoration: BoxDecoration(
                border: Border(
                  right: column < 6 ? line : BorderSide.none,
                  bottom: showBottom ? line : BorderSide.none,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
