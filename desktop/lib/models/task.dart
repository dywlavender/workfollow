import 'migration.dart';

enum TaskBucket {
  overdue,
  today,
  later,
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.listName,
    required this.bucket,
    this.timeLabel,
    this.note,
    this.description,
    this.contentJson,
    this.dueAt,
    this.dueEndAt,
    this.reminderAt,
    this.recurrenceType = 'NONE',
    this.recurrenceConfig,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.priority = TaskPriority.none,
    this.completed = false,
    this.hasAttachment = false,
    this.subtaskTotal = 0,
    this.subtaskCompleted = 0,
  });

  final String id;
  final String title;
  final String listName;
  final TaskBucket bucket;
  final String? timeLabel;
  final String? note;
  final String? description;
  final Map<String, dynamic>? contentJson;
  final String? dueAt;
  final String? dueEndAt;
  final String? reminderAt;
  final String recurrenceType;
  final Map<String, dynamic>? recurrenceConfig;
  final List<String> tags;
  final String? createdAt;
  final String? updatedAt;
  final String? completedAt;
  final TaskPriority priority;
  final bool completed;
  final bool hasAttachment;
  final int subtaskTotal;
  final int subtaskCompleted;

  TaskItem copyWith({
    String? title,
    String? listName,
    TaskBucket? bucket,
    String? timeLabel,
    String? note,
    String? description,
    Map<String, dynamic>? contentJson,
    String? dueAt,
    String? dueEndAt,
    String? reminderAt,
    String? recurrenceType,
    Map<String, dynamic>? recurrenceConfig,
    List<String>? tags,
    String? createdAt,
    String? updatedAt,
    String? completedAt,
    TaskPriority? priority,
    bool? completed,
    bool? hasAttachment,
    int? subtaskTotal,
    int? subtaskCompleted,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      listName: listName ?? this.listName,
      bucket: bucket ?? this.bucket,
      timeLabel: timeLabel ?? this.timeLabel,
      note: note ?? this.note,
      description: description ?? this.description,
      contentJson: contentJson ?? this.contentJson,
      dueAt: dueAt ?? this.dueAt,
      dueEndAt: dueEndAt ?? this.dueEndAt,
      reminderAt: reminderAt ?? this.reminderAt,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      recurrenceConfig: recurrenceConfig ?? this.recurrenceConfig,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      hasAttachment: hasAttachment ?? this.hasAttachment,
      subtaskTotal: subtaskTotal ?? this.subtaskTotal,
      subtaskCompleted: subtaskCompleted ?? this.subtaskCompleted,
    );
  }

  factory TaskItem.fromMigration(MigrationTaskRecord record) {
    final due = record.dueAt == null ? null : DateTime.tryParse(record.dueAt!);
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final dueDay = due == null ? null : DateTime(due.year, due.month, due.day);
    final bucket = dueDay != null && dueDay.isBefore(startOfToday)
        ? TaskBucket.overdue
        : dueDay == null || !dueDay.isAfter(startOfToday)
            ? TaskBucket.today
            : TaskBucket.later;
    final completed = record.status == 'DONE' || record.status == 'ABANDONED';
    return TaskItem(
      id: record.id,
      title: record.title,
      listName: record.listName,
      bucket: bucket,
      timeLabel: _timeLabel(due, completed),
      note: record.description,
      description: record.description,
      contentJson: record.contentJson,
      dueAt: record.dueAt,
      dueEndAt: record.dueEndAt,
      reminderAt: record.reminderAt,
      recurrenceType: record.recurrenceType,
      recurrenceConfig: record.recurrenceConfig,
      tags: List.unmodifiable(record.tags),
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      completedAt: record.completedAt,
      priority: TaskPriority.values.firstWhere(
        (value) => value.name.toUpperCase() == record.priority,
        orElse: () => TaskPriority.none,
      ),
      completed: completed,
    );
  }

  MigrationTaskRecord toMigrationRecord() {
    return MigrationTaskRecord(
      id: id,
      title: title,
      description: description ?? note,
      contentJson: contentJson,
      status: completed ? 'DONE' : 'TODO',
      priority: priority.name.toUpperCase(),
      dueAt: dueAt,
      dueEndAt: dueEndAt,
      reminderAt: reminderAt,
      recurrenceType: recurrenceType,
      recurrenceConfig: recurrenceConfig,
      listName: listName,
      tags: List.unmodifiable(tags),
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
    );
  }
}

String? _timeLabel(DateTime? due, bool completed) {
  if (completed) return '已完成';
  if (due == null) return null;
  final hour = due.hour.toString().padLeft(2, '0');
  final minute = due.minute.toString().padLeft(2, '0');
  return '${due.month} 月 ${due.day} 日 $hour:$minute';
}

enum TaskPriority {
  none,
  low,
  medium,
  high,
}

extension TaskPriorityLabel on TaskPriority {
  String get label => switch (this) {
        TaskPriority.none => '无优先级',
        TaskPriority.low => '低优先级',
        TaskPriority.medium => '中优先级',
        TaskPriority.high => '高优先级',
      };
}

class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    required this.preview,
    required this.updatedLabel,
    required this.folder,
    this.accent = const ColorValue(0xFF7566D9),
    this.folderId,
    this.contentJson,
    this.plainText,
    this.isFavorite = false,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String preview;
  final String updatedLabel;
  final String folder;
  final ColorValue accent;
  final String? folderId;
  final Map<String, dynamic>? contentJson;
  final String? plainText;
  final bool isFavorite;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;

  factory NoteItem.fromMigration(
    MigrationNoteRecord record,
    String folderName,
    ColorValue accent, {
    String? folderIdOverride,
  }) {
    return NoteItem(
      id: record.id,
      title: record.title,
      preview: _previewText(record.plainText),
      updatedLabel: _noteUpdatedLabel(record.updatedAt),
      folder: folderName,
      accent: accent,
      folderId: folderIdOverride ?? record.folderId,
      contentJson: record.contentJson,
      plainText: record.plainText,
      isFavorite: record.isFavorite,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
    );
  }

  MigrationNoteRecord toMigrationRecord() {
    return MigrationNoteRecord(
      id: id,
      folderId: folderId,
      title: title,
      contentJson: contentJson ?? <String, dynamic>{},
      plainText: plainText ?? preview,
      isFavorite: isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

String _previewText(String value) {
  final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return compact.length <= 110 ? compact : '${compact.substring(0, 107)}…';
}

String _noteUpdatedLabel(String? value) {
  if (value == null) return '刚刚';
  final date = DateTime.tryParse(value);
  if (date == null) return '刚刚';
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  return '${date.month} 月 ${date.day} 日';
}

/// A tiny value object keeps the model layer independent from Flutter widgets.
class ColorValue {
  const ColorValue(this.value);

  final int value;
}
