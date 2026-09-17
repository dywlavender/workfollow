import '../../../models/task.dart';
import 'chinese_work_calendar.dart';

/// Shared calendar calculation for completion, skipping and the picker preview.
class RecurrenceEngine {
  const RecurrenceEngine._();

  static Map<String, dynamic>? followingConfig(TaskItem task) {
    final config = task.recurrenceConfig;
    if (config == null) return null;
    return {
      ...config,
      if (config['count'] is num) 'count': (config['count'] as num).toInt() - 1
    };
  }

  static DateTime? nextOccurrence(TaskItem task,
      {DateTime? from, DateTime? reference}) {
    final type = task.recurrenceType.toUpperCase();
    final config = task.recurrenceConfig;
    if (type == 'NONE' || ((config?['count'] as num?)?.toInt() ?? 2) <= 1)
      return null;
    final now = reference ?? DateTime.now();
    final base = from ??
        localDateTimeFromStorage(task.dueAt) ??
        DateTime(now.year, now.month, now.day);
    DateTime next;
    DateTime plusDays(int days) => DateTime(
        base.year, base.month, base.day + days, base.hour, base.minute);
    switch (type) {
      case 'DAILY':
        next = plusDays(1);
      case 'WEEKLY':
        final weekday = (config?['weekday'] as num?)?.toInt() ?? base.weekday;
        final distance = (weekday - base.weekday + 7) % 7;
        next = plusDays(distance == 0 ? 7 : distance);
      case 'MONTHLY':
      case 'YEARLY':
        final month = type == 'MONTHLY'
            ? base.month + 1
            : (config?['month'] as num?)?.toInt() ?? base.month;
        final year = type == 'YEARLY' ? base.year + 1 : base.year;
        final targetDay = (config?['dayOfMonth'] as num?)?.toInt() ?? base.day;
        final last = DateTime(year, month + 1, 0).day;
        next = DateTime(
            year, month, targetDay.clamp(1, last), base.hour, base.minute);
      case 'WEEKDAYS':
      case 'WEEKENDS':
      case 'WORKDAYS':
      case 'HOLIDAYS':
        var days = 1;
        bool matches(DateTime day) => switch (type) {
              'WEEKDAYS' => day.weekday <= DateTime.friday,
              'WEEKENDS' => day.weekday >= DateTime.saturday,
              'WORKDAYS' => ChineseWorkCalendar.isWorkday(day),
              _ => !ChineseWorkCalendar.isWorkday(day),
            };
        while (!matches(plusDays(days))) {
          days++;
        }
        next = plusDays(days);
      default:
        return null;
    }
    final end = DateTime.tryParse(config?['endDate']?.toString() ?? '');
    if (end != null &&
        DateTime(next.year, next.month, next.day)
            .isAfter(DateTime(end.year, end.month, end.day))) return null;
    return next;
  }

  static Set<DateTime> preview(TaskItem task, DateTime through) {
    var current = task;
    final result = <DateTime>{};
    while (true) {
      final next = nextOccurrence(current);
      if (next == null || next.isAfter(through)) return result;
      result.add(DateTime(next.year, next.month, next.day));
      current = current.copyWith(
          dueAt: next.toIso8601String(),
          recurrenceConfig: followingConfig(current));
    }
  }
}
