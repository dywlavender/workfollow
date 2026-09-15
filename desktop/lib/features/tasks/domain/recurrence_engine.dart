import '../../../models/task.dart';

/// Calculates the next occurrence for every recurring task action.
///
/// The engine is deliberately pure: completing or skipping an occurrence is
/// responsible for deciding how records are written, while this class owns
/// only the calendar rule. Keeping that boundary shared prevents completion
/// and skip from drifting apart over time.
class RecurrenceEngine {
  const RecurrenceEngine._();

  static DateTime? nextOccurrence(
    TaskItem task, {
    DateTime? from,
    DateTime? reference,
  }) {
    final type = task.recurrenceType.toUpperCase();
    if (type == 'NONE') return null;
    final due = from ?? localDateTimeFromStorage(task.dueAt);
    final now = reference ?? DateTime.now();
    final base = due ?? DateTime(now.year, now.month, now.day);
    final config = task.recurrenceConfig;

    switch (type) {
      case 'DAILY':
        return base.add(const Duration(days: 1));
      case 'WEEKLY':
        final weekday = (config?['weekday'] as num?)?.toInt();
        if (weekday != null &&
            weekday >= DateTime.monday &&
            weekday <= DateTime.sunday) {
          var next = base.add(const Duration(days: 1));
          while (next.weekday != weekday) {
            next = next.add(const Duration(days: 1));
          }
          return next;
        }
        return base.add(const Duration(days: 7));
      case 'MONTHLY':
        final configuredDay = (config?['dayOfMonth'] as num?)?.toInt();
        final targetDay =
            configuredDay != null && configuredDay >= 1 && configuredDay <= 31
                ? configuredDay
                : base.day;
        var year = base.year;
        var month = base.month + 1;
        if (month > 12) {
          month = 1;
          year += 1;
        }
        final lastDay = DateTime(year, month + 1, 0).day;
        return DateTime(
          year,
          month,
          targetDay > lastDay ? lastDay : targetDay,
          base.hour,
          base.minute,
        );
      default:
        return null;
    }
  }
}
