import '../../../models/task.dart';
import 'task_schedule.dart';

/// Recurrence values are kept in a Draft until creation or confirmation. The
/// domain accepts the same small set currently supported by local storage.
class RecurrenceDraft {
  const RecurrenceDraft({this.type = 'NONE', this.config});

  final String type;
  final Map<String, dynamic>? config;

  bool get enabled => type != 'NONE';

  /// Returns a storage-safe rule. Unsupported frequencies and malformed
  /// weekly/monthly configuration are disabled instead of being persisted as
  /// rules that the completion engine cannot advance.
  RecurrenceDraft normalized() {
    final normalizedType = type.trim().toUpperCase();
    switch (normalizedType) {
      case 'NONE':
        return const RecurrenceDraft();
      case 'DAILY':
        return const RecurrenceDraft(type: 'DAILY');
      case 'WEEKLY':
        final weekday = (config?['weekday'] as num?)?.toInt();
        if (config == null) return const RecurrenceDraft(type: 'WEEKLY');
        if (weekday == null || weekday < 1 || weekday > 7) {
          return const RecurrenceDraft();
        }
        return RecurrenceDraft(
            type: 'WEEKLY', config: <String, dynamic>{'weekday': weekday});
      case 'MONTHLY':
        final day = (config?['dayOfMonth'] as num?)?.toInt();
        if (config == null) return const RecurrenceDraft(type: 'MONTHLY');
        if (day == null || day < 1 || day > 31) {
          return const RecurrenceDraft();
        }
        return RecurrenceDraft(
            type: 'MONTHLY', config: <String, dynamic>{'dayOfMonth': day});
      default:
        return const RecurrenceDraft();
    }
  }

  RecurrenceDraft copyWith(
      {String? type, Map<String, dynamic>? config, bool clear = false}) {
    if (clear) return const RecurrenceDraft();
    return RecurrenceDraft(
      type: type ?? this.type,
      config: config ?? this.config,
    );
  }
}

/// All properties needed to create one task.  Quick Add and native capture
/// build this value without mutating a TaskItem; the creator submits it once.
class TaskDraft {
  const TaskDraft({
    required this.title,
    this.listName,
    this.schedule = const TaskScheduleDraft(),
    this.reminderAt,
    this.recurrence = const RecurrenceDraft(),
    this.priority = TaskPriority.none,
    this.tags = const [],
    this.description,
    this.forceUnscheduled = false,
  });

  final String title;
  final String? listName;
  final TaskScheduleDraft schedule;
  final DateTime? reminderAt;
  final RecurrenceDraft recurrence;
  final TaskPriority priority;
  final List<String> tags;
  final String? description;
  final bool forceUnscheduled;

  bool get isValid => title.trim().isNotEmpty;

  TaskDraft copyWith({
    String? title,
    String? listName,
    bool clearListName = false,
    TaskScheduleDraft? schedule,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    RecurrenceDraft? recurrence,
    TaskPriority? priority,
    List<String>? tags,
    String? description,
    bool clearDescription = false,
    bool? forceUnscheduled,
  }) {
    return TaskDraft(
      title: title ?? this.title,
      listName: clearListName ? null : listName ?? this.listName,
      schedule: schedule ?? this.schedule,
      reminderAt: clearReminderAt ? null : reminderAt ?? this.reminderAt,
      recurrence: recurrence ?? this.recurrence,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
      description: clearDescription ? null : description ?? this.description,
      forceUnscheduled: forceUnscheduled ?? this.forceUnscheduled,
    );
  }

  TaskDraft normalized() {
    final normalizedTags = <String>[];
    for (final raw in tags) {
      final tag = raw.trim();
      if (tag.isNotEmpty && !normalizedTags.contains(tag))
        normalizedTags.add(tag);
    }
    final normalizedRecurrence = recurrence.normalized();
    final schedule = forceUnscheduled
        ? const TaskScheduleDraft()
        : TaskScheduleDraft(
            dueAt: this.schedule.normalizedDueAt,
            hasTime: this.schedule.hasTime,
          );
    final reminder = reminderAt == null
        ? null
        : DateTime(reminderAt!.year, reminderAt!.month, reminderAt!.day,
            reminderAt!.hour, reminderAt!.minute);
    return TaskDraft(
      title: title.trim(),
      listName: listName?.trim().isEmpty == true ? null : listName?.trim(),
      schedule: schedule,
      reminderAt: reminder,
      recurrence: normalizedRecurrence,
      priority: priority,
      tags: List.unmodifiable(normalizedTags),
      description:
          description?.trim().isEmpty == true ? null : description?.trim(),
      forceUnscheduled: forceUnscheduled,
    );
  }
}
