import 'task_draft.dart';
import 'task_schedule.dart';

/// One confirmed calendar edit, including the dependent reminder and repeat rule.
class TaskScheduleSettings {
  const TaskScheduleSettings({
    this.schedule = const TaskScheduleDraft(),
    this.endAt,
    this.reminderAt,
    this.recurrence = const RecurrenceDraft(),
  });
  final TaskScheduleDraft schedule;
  final DateTime? endAt;
  final DateTime? reminderAt;
  final RecurrenceDraft recurrence;
}
