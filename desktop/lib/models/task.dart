import 'migration.dart';

enum TaskBucket {
  overdue,
  today,
  later,

  /// A task without a date. It must never be grouped into Today: capture and
  /// scheduling are separate decisions.
  unscheduled,
}

class TaskSubtask {
  const TaskSubtask({
    required this.id,
    required this.title,
    this.completed = false,
  });

  final String id;
  final String title;
  final bool completed;

  TaskSubtask copyWith({String? title, bool? completed}) => TaskSubtask(
        id: id,
        title: title ?? this.title,
        completed: completed ?? this.completed,
      );

  static TaskSubtask fromJson(Map<String, dynamic> json) => TaskSubtask(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        completed: json['completed'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'completed': completed};
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
    this.subtasks = const [],
    this.sourceNoteId,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.deletedAt,
    this.attachments = const [],
    this.priority = TaskPriority.none,
    this.completed = false,
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
  final List<TaskSubtask> subtasks;

  /// The note this task was generated from (the "回到记录" link).
  final String? sourceNoteId;
  final String? createdAt;
  final String? updatedAt;
  final String? completedAt;
  final String? deletedAt;
  final TaskPriority priority;
  final bool completed;

  /// File names inside the app's attachments folder (relative, so the
  /// workspace stays movable).
  final List<String> attachments;

  bool get hasAttachment => attachments.isNotEmpty;

  int get subtaskTotal => subtasks.length;
  int get subtaskCompleted =>
      subtasks.where((subtask) => subtask.completed).length;

  TaskItem copyWith({
    String? title,
    String? listName,
    TaskBucket? bucket,
    String? timeLabel,
    String? note,
    bool clearNote = false,
    String? description,
    bool clearDescription = false,
    Map<String, dynamic>? contentJson,
    bool clearContentJson = false,
    String? dueAt,
    bool clearDueAt = false,
    String? dueEndAt,
    bool clearDueEndAt = false,
    String? reminderAt,
    bool clearReminderAt = false,
    String? recurrenceType,
    Map<String, dynamic>? recurrenceConfig,
    bool clearRecurrenceConfig = false,
    List<String>? tags,
    List<TaskSubtask>? subtasks,
    String? sourceNoteId,
    bool clearSourceNoteId = false,
    String? createdAt,
    String? updatedAt,
    String? completedAt,
    bool clearCompletedAt = false,
    String? deletedAt,
    bool clearDeletedAt = false,
    TaskPriority? priority,
    bool? completed,
    List<String>? attachments,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      listName: listName ?? this.listName,
      bucket: bucket ?? this.bucket,
      timeLabel: timeLabel ?? this.timeLabel,
      note: clearNote ? note : note ?? this.note,
      description:
          clearDescription ? description : description ?? this.description,
      contentJson:
          clearContentJson ? contentJson : contentJson ?? this.contentJson,
      dueAt: clearDueAt ? dueAt : dueAt ?? this.dueAt,
      dueEndAt: clearDueEndAt ? dueEndAt : dueEndAt ?? this.dueEndAt,
      reminderAt: clearReminderAt ? reminderAt : reminderAt ?? this.reminderAt,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      recurrenceConfig: clearRecurrenceConfig
          ? recurrenceConfig
          : recurrenceConfig ?? this.recurrenceConfig,
      tags: tags ?? this.tags,
      subtasks: subtasks ?? this.subtasks,
      sourceNoteId:
          clearSourceNoteId ? sourceNoteId : sourceNoteId ?? this.sourceNoteId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt:
          clearCompletedAt ? completedAt : completedAt ?? this.completedAt,
      deletedAt: clearDeletedAt ? deletedAt : deletedAt ?? this.deletedAt,
      priority: priority ?? this.priority,
      completed: completed ?? this.completed,
      attachments: attachments ?? this.attachments,
    );
  }

  factory TaskItem.fromMigration(MigrationTaskRecord record) {
    final due = localDateTimeFromStorage(record.dueAt);
    final dueEnd = localDateTimeFromStorage(record.dueEndAt);
    final reminder = localDateTimeFromStorage(record.reminderAt);
    final completed = record.status == 'DONE' || record.status == 'ABANDONED';
    return TaskItem(
      id: record.id,
      title: record.title,
      listName: record.listName,
      bucket: taskBucketForDate(due, completed: completed),
      timeLabel: taskTimeLabelFor(due, completed: completed),
      note: record.description,
      description: record.description,
      contentJson: record.contentJson,
      dueAt: due?.toIso8601String(),
      dueEndAt: dueEnd?.toIso8601String(),
      reminderAt: reminder?.toIso8601String(),
      recurrenceType: record.recurrenceType,
      recurrenceConfig: record.recurrenceConfig,
      tags: List.unmodifiable(record.tags),
      subtasks: record.subtasks
          .map((subtask) => TaskSubtask(
                id: subtask.id,
                title: subtask.title,
                completed: subtask.completed,
              ))
          .toList(),
      sourceNoteId: record.sourceNoteId,
      createdAt: normalizeStoredDateTime(record.createdAt),
      updatedAt: normalizeStoredDateTime(record.updatedAt),
      completedAt: normalizeStoredDateTime(record.completedAt),
      deletedAt: normalizeStoredDateTime(record.deletedAt),
      attachments: List.unmodifiable(record.attachments),
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
      subtasks:
          List.unmodifiable(subtasks.map((subtask) => MigrationSubtaskRecord(
                id: subtask.id,
                title: subtask.title,
                completed: subtask.completed,
              ))),
      sourceNoteId: sourceNoteId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
      deletedAt: deletedAt,
      attachments: List.unmodifiable(attachments),
    );
  }
}

TaskBucket taskBucketForDate(DateTime? due,
    {bool completed = false, DateTime? now}) {
  if (due == null) return TaskBucket.unscheduled;
  final reference = now ?? DateTime.now();
  final startOfToday = DateTime(reference.year, reference.month, reference.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  if (dueDay.isBefore(startOfToday)) return TaskBucket.overdue;
  if (!dueDay.isAfter(startOfToday)) return TaskBucket.today;
  return TaskBucket.later;
}

String? taskTimeLabelFor(DateTime? due, {bool completed = false}) {
  if (completed) return '已完成';
  if (due == null) return null;
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  // A midnight timestamp means an all-day date, not a fake 00:00 deadline.
  final hasClockTime = due.hour != 0 || due.minute != 0;
  final clock = hasClockTime
      ? ' ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}'
      : '';
  final dayOffset = dueDay.difference(startOfToday).inDays;
  if (dayOffset == 0) return '今天$clock';
  if (dayOffset == -1) return '昨天$clock';
  if (dayOffset == 1) return '明天$clock';
  return '${due.month} 月 ${due.day} 日$clock';
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
    this.originalContentJson,
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
  final Map<String, dynamic>? originalContentJson;
  final String? plainText;
  final bool isFavorite;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;

  NoteItem copyWith({
    String? title,
    String? preview,
    String? updatedLabel,
    String? folder,
    ColorValue? accent,
    String? folderId,
    bool clearFolderId = false,
    Map<String, dynamic>? contentJson,
    Map<String, dynamic>? originalContentJson,
    bool clearOriginalContentJson = false,
    String? plainText,
    bool? isFavorite,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return NoteItem(
      id: id,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      updatedLabel: updatedLabel ?? this.updatedLabel,
      folder: folder ?? this.folder,
      accent: accent ?? this.accent,
      folderId: clearFolderId ? folderId : folderId ?? this.folderId,
      contentJson: contentJson ?? this.contentJson,
      originalContentJson: clearOriginalContentJson
          ? originalContentJson
          : originalContentJson ?? this.originalContentJson,
      plainText: plainText ?? this.plainText,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? deletedAt : deletedAt ?? this.deletedAt,
    );
  }

  /// Imported rich documents are kept as the source of truth until the user
  /// explicitly converts the note to a plain-text copy.
  bool get hasPreservedRichContent => originalContentJson != null;

  factory NoteItem.fromMigration(
    MigrationNoteRecord record,
    String folderName,
    ColorValue accent, {
    String? folderIdOverride,
  }) {
    final content = record.contentJson;
    final preserved = record.originalContentJson ??
        (noteContentJsonHasRichStructure(content) ? content : null);
    return NoteItem(
      id: record.id,
      title: record.title,
      preview: notePreviewFromText(record.plainText),
      updatedLabel: noteUpdatedLabelFor(record.updatedAt),
      folder: folderName,
      accent: accent,
      folderId: folderIdOverride ?? record.folderId,
      contentJson: content,
      originalContentJson: preserved,
      plainText: record.plainText,
      isFavorite: record.isFavorite,
      createdAt: normalizeStoredDateTime(record.createdAt),
      updatedAt: normalizeStoredDateTime(record.updatedAt),
      deletedAt: normalizeStoredDateTime(record.deletedAt),
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
      originalContentJson: originalContentJson,
    );
  }
}

String notePreviewFromText(String value) {
  final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return compact.length <= 110 ? compact : '${compact.substring(0, 107)}…';
}

/// The desktop editor writes plain text for local notes. Imported rich content
/// is protected until the user explicitly converts it, so links, lists and
/// other unsupported nodes cannot disappear during an ordinary edit.
Map<String, dynamic> noteContentJsonFromPlainText(String body) {
  final paragraphs = body.isEmpty
      ? const <Map<String, dynamic>>[]
      : body
          .split('\n')
          .map((line) => <String, dynamic>{
                'type': 'paragraph',
                'content': line.isEmpty
                    ? <Map<String, dynamic>>[]
                    : <Map<String, dynamic>>[
                        {'type': 'text', 'text': line},
                      ],
              })
          .toList();
  return {'type': 'doc', 'content': paragraphs};
}

/// Converts an ISO timestamp from a migration file to the user's local time.
/// Dart parses a `Z`/offset timestamp as UTC; comparing its raw date fields to
/// local calendar days would put late-night UTC work on the wrong day.
DateTime? localDateTimeFromStorage(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

String? normalizeStoredDateTime(String? value) =>
    localDateTimeFromStorage(value)?.toIso8601String();

/// Returns the text projection used by the Web editor for a ProseMirror-like
/// JSON document. Block nodes contribute a newline, while inline marks and
/// attributes stay attached to their original nodes.
String notePlainTextFromContentJson(Object? value) {
  if (value is! Map) return '';
  final type = value['type']?.toString();
  if (type == 'text') return value['text']?.toString() ?? '';
  if (type == 'hardBreak') return '\n';
  final children = value['content'];
  final text =
      children is List ? children.map(notePlainTextFromContentJson).join() : '';
  if (const {
    'paragraph',
    'heading',
    'listItem',
    'taskItem',
    'blockquote',
    'codeBlock',
  }.contains(type)) {
    return '$text\n';
  }
  return text;
}

/// Plain paragraphs are the only structure produced by the local editor.
/// Marks, lists, headings, images and other node types therefore identify a
/// document whose source must be protected from a plain-text edit.
bool noteContentJsonHasRichStructure(Map<String, dynamic> document) {
  var rich = false;
  void visit(Object? value) {
    if (rich || value is! Map) return;
    final type = value['type']?.toString();
    if (type != null && !const {'doc', 'paragraph', 'text'}.contains(type)) {
      rich = true;
      return;
    }
    final marks = value['marks'];
    if (marks is List && marks.isNotEmpty) {
      rich = true;
      return;
    }
    final children = value['content'];
    if (children is List) {
      for (final child in children) {
        visit(child);
        if (rich) return;
      }
    }
  }

  visit(document);
  return rich;
}

/// Appends a new line to an imported rich document without rebuilding any of
/// its existing nodes. Returns null for edits that touch the protected source;
/// those edits remain a plain-text draft until explicit conversion.
Map<String, dynamic>? appendToRichContent(
    Map<String, dynamic> document, String newBody) {
  final baseline = notePlainTextFromContentJson(document).trimRight();
  final normalized = newBody;
  if (normalized == baseline) return document;
  if (!normalized.startsWith('$baseline\n')) return null;
  final suffix = normalized.substring(baseline.length + 1);
  if (suffix.isEmpty) return document;
  final root = Map<String, dynamic>.from(document);
  final rawChildren = root['content'];
  final children = rawChildren is List
      ? rawChildren
          .whereType<Map>()
          .map((child) => Map<String, dynamic>.from(child))
          .toList()
      : <Map<String, dynamic>>[];
  for (final line in suffix.split('\n')) {
    children.add({
      'type': 'paragraph',
      'content': line.isEmpty
          ? <Map<String, dynamic>>[]
          : <Map<String, dynamic>>[
              {'type': 'text', 'text': line},
            ],
    });
  }
  root['content'] = children;
  return root;
}

String noteUpdatedLabelFor(String? value) {
  if (value == null) return '刚刚';
  final date = localDateTimeFromStorage(value);
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
