import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/application/task_projection.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_spans.dart';

const _projection = TaskProjection();

/// A task with a start, and with an end only when [to] says so.
///
/// There is no "multi-day" flag to set: a range is a schedule whose two dates
/// disagree, which is the whole of what the grid reads. [withTime] is left
/// null unless a test is about the clock, so the task's own times decide.
TaskItem _task(
  String id, {
  DateTime? from,
  DateTime? to,
  bool? withTime,
  bool completed = false,
  bool skipped = false,
  bool deleted = false,
  bool abandoned = false,
}) {
  return TaskItem(
    id: id,
    title: id,
    listName: '收集箱',
    bucket: taskBucketForDate(from, completed: completed),
    dueAt: from?.toIso8601String(),
    dueEndAt: to?.toIso8601String(),
    hasDueTime: withTime,
    completed: completed,
    skippedAt: skipped ? DateTime(2026, 1, 1).toIso8601String() : null,
    deletedAt: deleted ? DateTime(2026, 1, 1).toIso8601String() : null,
    abandonedAt: abandoned ? DateTime(2026, 1, 1).toIso8601String() : null,
  );
}

/// The week row that opens on Sunday 13 September 2026 — the row September's
/// own first full week sits in (9/1 is a Tuesday).
List<DateTime> get _week =>
    [for (var day = 13; day <= 19; day++) DateTime(2026, 9, day)];

void main() {
  group('reading a task as a range of days', () {
    test('an end on a later day is a run; an end on its own day is a clock',
        () {
      final run = _task('run', from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 18));
      expect(_projection.spansMultipleDays(run), isTrue);
      expect(_projection.startDayOf(run), DateTime(2026, 9, 14));
      expect(_projection.endDayOf(run), DateTime(2026, 9, 18));

      // The schedule panel writes an all-day range's end as that day's
      // midnight, and a timed task's end as the minute it finishes. Both mean
      // the same day when the dates agree, which is a time range, not a run.
      final timed = _task('timed',
          from: DateTime(2026, 9, 14, 14), to: DateTime(2026, 9, 14, 15));
      expect(_projection.spansMultipleDays(timed), isFalse);
      expect(_projection.endDayOf(timed), DateTime(2026, 9, 14));

      final allDaySameDay =
          _task('allday', from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 14));
      expect(_projection.spansMultipleDays(allDaySameDay), isFalse);

      // No end at all is the same case, and so is no date: a task the grid
      // cannot place is not a run either.
      expect(_projection.spansMultipleDays(_task('open', from: DateTime(2026, 9, 14))),
          isFalse);
      expect(_projection.spansMultipleDays(_task('none')), isFalse);
      expect(_projection.endDayOf(_task('none')), isNull);
    });

    test('a run is drawn by the row, while a list still reads it by its start',
        () {
      final run = _task('run', from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 18));
      final single = _task('single', from: DateTime(2026, 9, 14));
      final tasks = [run, single];

      // The month grid asks for this one: a run must not also appear as a bar
      // in its own cell, or the grid would say the task twice.
      expect(_projection.singleDayForDay(tasks, DateTime(2026, 9, 14)),
          [single]);

      // Every other view reads a task by the day it starts, so the run has to
      // survive the plain query — dropping it would hide the task from the
      // lists and the board as well.
      expect(_projection.forDay(tasks, DateTime(2026, 9, 14)), [run, single]);

      // A day in the middle of the run belongs to the run and to nothing else:
      // the cell is stepping aside for a band, not holding a task.
      expect(_projection.forDay(tasks, DateTime(2026, 9, 16)), isEmpty);
      expect(_projection.singleDayForDay(tasks, DateTime(2026, 9, 16)), isEmpty);
    });

    test('the week query takes the runs that touch the row, earliest first',
        () {
      final before = _task('before',
          from: DateTime(2026, 9, 8), to: DateTime(2026, 9, 15));
      final long = _task('long',
          from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 18));
      final short = _task('short',
          from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 15));
      final late = _task('late',
          from: DateTime(2026, 9, 16), to: DateTime(2026, 9, 20));
      final nextRow = _task('next',
          from: DateTime(2026, 9, 20), to: DateTime(2026, 9, 21));
      final earlierRow = _task('earlier',
          from: DateTime(2026, 9, 7), to: DateTime(2026, 9, 9));

      final hits = _projection.multiDayWithin(
        [long, short, late, nextRow, before, earlierRow],
        DateTime(2026, 9, 13),
        DateTime(2026, 9, 19),
      );

      // A run that ended before the row opened and one that starts after it
      // closed are both out; a run that merely starts before the row is in.
      expect(hits.map((task) => task.id),
          ['before', 'long', 'short', 'late']);
    });

    test('a hidden run takes no lane, but a finished one still does', () {
      final skipped = _task('skipped',
          from: DateTime(2026, 9, 14),
          to: DateTime(2026, 9, 18),
          skipped: true);
      final deleted = _task('deleted',
          from: DateTime(2026, 9, 14),
          to: DateTime(2026, 9, 18),
          deleted: true);
      final abandoned = _task('abandoned',
          from: DateTime(2026, 9, 14),
          to: DateTime(2026, 9, 18),
          abandoned: true);

      expect(
          _projection.multiDayWithin(
              [skipped, deleted, abandoned], DateTime(2026, 9, 13), DateTime(2026, 9, 19)),
          isEmpty);

      // Completed is not hidden. A finished run is part of what the week
      // looked like, and whether it is drawn is the page's decision rather
      // than something the range query has already made for it.
      final done = _task('done',
          from: DateTime(2026, 9, 14),
          to: DateTime(2026, 9, 18),
          completed: true);
      expect(
          _projection
              .multiDayWithin([done], DateTime(2026, 9, 13), DateTime(2026, 9, 19))
              .map((task) => task.id),
          ['done']);
    });
  });

  group('laying a week row out', () {
    test('a run is clipped to the row it is drawn in', () {
      final overTheEdge = _task('over',
          from: DateTime(2026, 9, 11), to: DateTime(2026, 9, 15));
      final intoNext = _task('next',
          from: DateTime(2026, 9, 17), to: DateTime(2026, 9, 23));

      final spans = layOutWeekSpans(days: _week, tasks: [overTheEdge, intoNext]);

      // Wednesday into the following Tuesday, so the row sees 9/13 through
      // 9/15: three columns, and the left edge is not the task's own.
      final head = spans.firstWhere((span) => span.task.id == 'over');
      expect(head.fromColumn, 0);
      expect(head.toColumn, 2);
      expect(head.columnCount, 3);
      expect(head.startsInRow, isFalse);
      expect(head.endsInRow, isTrue);
      expect(head.continuesFromPreviousRow, isTrue);
      expect(head.continuesIntoNextRow, isFalse);

      final tail = spans.firstWhere((span) => span.task.id == 'next');
      expect(tail.fromColumn, 4);
      expect(tail.toColumn, 6);
      expect(tail.columnCount, 3);
      expect(tail.startsInRow, isTrue);
      expect(tail.endsInRow, isFalse);
      expect(tail.continuesIntoNextRow, isTrue);

      // Both pieces remember the task's real range, which is what lets the
      // corners be told apart: the piece above is flat on the right because
      // the task does not end there.
      expect(head.startDay, DateTime(2026, 9, 11));
      expect(head.endDay, DateTime(2026, 9, 15));
      expect(tail.endDay, DateTime(2026, 9, 23));
    });

    test('runs that miss the row are left out entirely', () {
      final before = _task('before',
          from: DateTime(2026, 9, 8), to: DateTime(2026, 9, 10));
      final after = _task('after',
          from: DateTime(2026, 9, 21), to: DateTime(2026, 9, 22));
      expect(
          layOutWeekSpans(days: _week, tasks: [before, after]), isEmpty);
    });

    test('overlapping runs stack, and a gap lets the next one back up', () {
      final long = _task('long',
          from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 18));
      final short = _task('short',
          from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 15));
      final late = _task('late',
          from: DateTime(2026, 9, 18), to: DateTime(2026, 9, 20));
      final weekend = _task('weekend',
          from: DateTime(2026, 9, 19), to: DateTime(2026, 9, 20));

      final spans = layOutWeekSpans(
          days: _week, tasks: [long, short, late, weekend]);
      final lane = {for (final span in spans) span.task.id: span.lane};

      // The long run opened first, so it takes the top lane. The short one
      // opened the same day and overlaps it, so it goes below. 9/18 onward
      // overlaps the long run's tail as well and takes the same second lane,
      // but 9/19 is clear of the long run and goes back up beside it.
      expect(lane['long'], 0);
      expect(lane['short'], 1);
      expect(lane['late'], 1);
      expect(lane['weekend'], 0);

      // Reading order: the top lane left to right, then the lane below it.
      expect(spans.map((span) => span.task.id), ['long', 'weekend', 'short', 'late']);
      expect(spans.map((span) => span.lane), [0, 0, 1, 1]);
    });

    test('a row is seven days and nothing else', () {
      expect(
          () => layOutWeekSpans(
              days: _week.take(6).toList(), tasks: const []),
          throwsArgumentError);
    });
  });

  group('making room for a band', () {
    CalendarSpan spanAt(int column, int toColumn, {required int lane}) =>
        CalendarSpan(
          task: _task('t', from: DateTime(2026, 9, 14), to: DateTime(2026, 9, 18)),
          startDay: DateTime(2026, 9, 14),
          endDay: DateTime(2026, 9, 18),
          fromColumn: column,
          toColumn: toColumn,
          lane: lane,
          startsInRow: true,
          endsInRow: true,
        );

    test('a cell steps aside by the deepest band over it, not by the count',
        () {
      // Lanes 0 and 2, with 1 left empty because a band that does not reach
      // this far is using it elsewhere in the row. A cell under both has to
      // leave three slots, not two: the bands above it are where they are.
      final spans = [spanAt(1, 5, lane: 0), spanAt(3, 4, lane: 2)];

      expect(spanSlotsOver(spans, 3), 3);
      expect(spanSlotsOver(spans, 4), 3);
      // Column 1 is under the top band alone, so it steps down one slot:
      // the cell asks how deep the bands over it go, not how many there are.
      expect(spanSlotsOver(spans, 1), 1);
      expect(spanSlotsOver(spans, 5), 1);
      // And a column no band reaches keeps all of its height.
      expect(spanSlotsOver(spans, 6), 0);
      expect(spanSlotsOver(spans, 0), 0);
    });

    test('a cell no band crosses keeps its whole height', () {
      expect(spanSlotsOver(const [], 0), 0);
    });
  });
}
