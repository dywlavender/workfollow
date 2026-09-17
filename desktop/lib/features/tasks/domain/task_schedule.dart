import '../../../models/task.dart';

/// A pending schedule value used by editors before the user confirms a
/// picker.  It deliberately carries the explicit all-day flag so midnight
/// never gets confused with a timed task.
class TaskScheduleDraft {
  const TaskScheduleDraft({this.dueAt, this.hasTime = false});

  /// Builds a day-level schedule while preserving a task's clock when one is
  /// already present. Date menu actions use this factory so Today/Tomorrow
  /// cannot drift into subtly different midnight semantics.
  factory TaskScheduleDraft.forDay(DateTime day,
      {DateTime? preserveClock, bool? hasTime}) {
    final timed = hasTime ??
        (preserveClock != null &&
            (preserveClock.hour != 0 || preserveClock.minute != 0));
    return TaskScheduleDraft(
      dueAt: DateTime(
          day.year,
          day.month,
          day.day,
          timed ? (preserveClock?.hour ?? day.hour) : 0,
          timed ? (preserveClock?.minute ?? day.minute) : 0),
      hasTime: timed,
    );
  }

  final DateTime? dueAt;
  final bool hasTime;

  bool get isEmpty => dueAt == null;

  TaskScheduleDraft copyWith(
      {DateTime? dueAt, bool? hasTime, bool clear = false}) {
    if (clear) return const TaskScheduleDraft();
    return TaskScheduleDraft(
      dueAt: dueAt ?? this.dueAt,
      hasTime: hasTime ?? this.hasTime,
    );
  }

  factory TaskScheduleDraft.fromTask(TaskItem task) => TaskScheduleDraft(
        dueAt: localDateTimeFromStorage(task.dueAt),
        hasTime: task.scheduledWithTime,
      );

  /// Normalizes picker values to local wall-clock minute precision.
  DateTime? get normalizedDueAt {
    final value = dueAt;
    if (value == null) return null;
    return DateTime(value.year, value.month, value.day,
        hasTime ? value.hour : 0, hasTime ? value.minute : 0);
  }

  @override
  bool operator ==(Object other) {
    return other is TaskScheduleDraft &&
        other.normalizedDueAt == normalizedDueAt &&
        other.hasTime == hasTime;
  }

  @override
  int get hashCode => Object.hash(normalizedDueAt, hasTime);
}
