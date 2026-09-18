import '../../features/tasks/application/task_projection.dart';
import '../../models/task.dart';

/// A multi-day task, clipped to one week row.
///
/// A task that runs from Wednesday to the following Tuesday is two of these:
/// one for the row it opens in, one for the row it closes in. Each is drawn as
/// a single rounded box, which is what makes the run read as one thing even
/// though the grid never has it in one piece.
class CalendarSpan {
  const CalendarSpan({
    required this.task,
    required this.startDay,
    required this.endDay,
    required this.fromColumn,
    required this.toColumn,
    required this.lane,
    required this.startsInRow,
    required this.endsInRow,
  });

  final TaskItem task;

  /// The task's real first and last days, which are usually outside this row.
  final DateTime startDay;
  final DateTime endDay;

  /// Columns this piece covers, inclusive, counting Sunday as zero.
  final int fromColumn;
  final int toColumn;

  /// Which bar slot the row put this piece in. Lanes are per row, because a
  /// row is the only unit that has to agree about them.
  final int lane;

  /// The task's own first day falls in this row, so this piece carries the
  /// completion box. A continuation does not: the box marks where the task
  /// begins, and a second one three rows down would be a second beginning.
  final bool startsInRow;

  /// The task's own last day falls in this row, so this piece carries the
  /// clock. The clock belongs to the end of the run, and the run ends once.
  final bool endsInRow;

  int get columnCount => toColumn - fromColumn + 1;

  /// Whether the run started in an earlier row, which is what flattens this
  /// piece's left edge.
  bool get continuesFromPreviousRow => !startsInRow;

  /// Whether the run carries on into a later row, which flattens the right.
  bool get continuesIntoNextRow => !endsInRow;
}

const _projection = TaskProjection();

/// Places one week row's multi-day tasks into bar slots.
///
/// Every task that touches the row gets its own box spanning the columns it
/// covers; tasks whose column ranges overlap are stacked, the earliest start
/// first and the longest first among equals. A task that merely passes through
/// the row takes a lane and nothing else — the *cell* is what has to step
/// aside for it, which is what [spanSlotsOver] answers.
///
/// The lanes are computed per row rather than per month on purpose: a row is
/// the only stretch that has to be internally consistent, and a task that
/// enters mid-week has no lane above it to inherit.
List<CalendarSpan> layOutWeekSpans({
  required List<DateTime> days,
  required List<TaskItem> tasks,
}) {
  if (days.length != 7) {
    throw ArgumentError.value(days.length, 'days', 'a week row holds 7 days');
  }
  final rowStart = days.first;
  final rowEnd = days.last;
  final base = DateTime.utc(rowStart.year, rowStart.month, rowStart.day);
  final last = _daysFrom(base, rowEnd);

  final pending = <_PendingSpan>[];
  for (final task in tasks) {
    final start = _projection.startDayOf(task);
    final end = _projection.endDayOf(task);
    if (start == null || end == null) continue;
    final from = _daysFrom(base, start);
    final to = _daysFrom(base, end);
    if (to < 0 || from > last) continue;
    pending.add(_PendingSpan(
      task: task,
      startDay: start,
      endDay: end,
      fromColumn: from < 0 ? 0 : from,
      toColumn: to > last ? last : to,
      startsInRow: from >= 0,
      endsInRow: to <= last,
    ));
  }

  // `tasks` arrives already ordered by the projection — earliest start first,
  // longest first among equals — and that order is the one the lanes want, so
  // it is not re-sorted here.
  final occupied = <List<List<int>>>[];
  final placed = <CalendarSpan>[];
  for (final span in pending) {
    var lane = 0;
    while (lane < occupied.length &&
        occupied[lane].any((range) =>
            span.fromColumn <= range[1] && range[0] <= span.toColumn)) {
      lane++;
    }
    if (lane == occupied.length) occupied.add(<List<int>>[]);
    occupied[lane].add(<int>[span.fromColumn, span.toColumn]);
    placed.add(CalendarSpan(
      task: span.task,
      startDay: span.startDay,
      endDay: span.endDay,
      fromColumn: span.fromColumn,
      toColumn: span.toColumn,
      lane: lane,
      startsInRow: span.startsInRow,
      endsInRow: span.endsInRow,
    ));
  }
  placed.sort((a, b) =>
      a.lane != b.lane ? a.lane - b.lane : a.fromColumn - b.fromColumn);
  return List.unmodifiable(placed);
}

/// How many bar slots [column]'s own tasks have to leave empty.
///
/// A cell that a band crosses cannot use the band's slot, so its day number is
/// followed by as many empty slots as there are bands over it. The count is
/// the highest lane in play plus one rather than the number of bands, because
/// a row can hand a cell lanes 0 and 2 and leave 1 for a task that does not
/// reach this far.
int spanSlotsOver(List<CalendarSpan> spans, int column) {
  var slots = 0;
  for (final span in spans) {
    if (span.fromColumn <= column && column <= span.toColumn) {
      final below = span.lane + 1;
      if (below > slots) slots = below;
    }
  }
  return slots;
}

/// Whole days from [base] to [day]. Both are floored to their date and the
/// arithmetic runs in UTC, so a daylight-saving step in the window cannot make
/// a one-day gap measure as zero.
int _daysFrom(DateTime base, DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).difference(base).inDays;

class _PendingSpan {
  const _PendingSpan({
    required this.task,
    required this.startDay,
    required this.endDay,
    required this.fromColumn,
    required this.toColumn,
    required this.startsInRow,
    required this.endsInRow,
  });

  final TaskItem task;
  final DateTime startDay;
  final DateTime endDay;
  final int fromColumn;
  final int toColumn;
  final bool startsInRow;
  final bool endsInRow;
}
