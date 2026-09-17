import '../../../models/task.dart';
import 'task_schedule.dart';

/// Recurrence values are kept in a Draft until creation or confirmation. The
/// domain accepts the same small set currently supported by local storage.
class RecurrenceDraft {
  const RecurrenceDraft({this.type = 'NONE', this.config});

  final String type;
  final Map<String, dynamic>? config;

  bool get enabled => type != 'NONE';

  /// Normalizes calendar rules and their optional inclusive end boundary.
  RecurrenceDraft normalized() {
    final kind = type.trim().toUpperCase();
    if (!{
      'DAILY',
      'WEEKLY',
      'MONTHLY',
      'YEARLY',
      'WEEKDAYS',
      'WEEKENDS',
      'WORKDAYS',
      'HOLIDAYS'
    }.contains(kind)) return const RecurrenceDraft();
    final values = <String, dynamic>{};
    if (kind == 'WEEKLY' && config?['weekday'] != null) {
      final day = (config!['weekday'] as num).toInt();
      if (day < 1 || day > 7) return const RecurrenceDraft();
      values['weekday'] = day;
    } else if (kind == 'WEEKLY' &&
        config != null &&
        !config!.containsKey('count') &&
        !config!.containsKey('endDate')) {
      return const RecurrenceDraft();
    }
    if ((kind == 'MONTHLY' || kind == 'YEARLY') &&
        config?['dayOfMonth'] != null) {
      final day = (config!['dayOfMonth'] as num).toInt();
      if (day < 1 || day > 31) return const RecurrenceDraft();
      values['dayOfMonth'] = day;
    }
    if (kind == 'YEARLY' && config?['month'] != null) {
      final month = (config!['month'] as num).toInt();
      if (month < 1 || month > 12) return const RecurrenceDraft();
      values['month'] = month;
    }
    final end = DateTime.tryParse(config?['endDate']?.toString() ?? '');
    final count = (config?['count'] as num?)?.toInt();
    if (end != null)
      values['endDate'] =
          DateTime(end.year, end.month, end.day).toIso8601String();
    else if (count != null && count > 0) values['count'] = count;
    return RecurrenceDraft(type: kind, config: values.isEmpty ? null : values);
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
