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
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      hasAttachment: hasAttachment ?? this.hasAttachment,
      subtaskTotal: subtaskTotal ?? this.subtaskTotal,
      subtaskCompleted: subtaskCompleted ?? this.subtaskCompleted,
    );
  }
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
  });

  final String id;
  final String title;
  final String preview;
  final String updatedLabel;
  final String folder;
  final ColorValue accent;
}

/// A tiny value object keeps the model layer independent from Flutter widgets.
class ColorValue {
  const ColorValue(this.value);

  final int value;
}
