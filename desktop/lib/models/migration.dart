import 'dart:convert';

const personalMigrationFormat = 'workfollow-personal-migration';
const localSnapshotFormat = 'workfollow-local-snapshot';

/// Version 2 adds optional list pinning and task focus counts. The
/// reader below still accepts version 1 so snapshots exported by an older
/// desktop build remain importable.
const migrationSchemaVersion = 2;
const supportedMigrationSchemaVersions = <int>{1, migrationSchemaVersion};

class MigrationFormatException implements Exception {
  const MigrationFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MigrationListRecord {
  const MigrationListRecord({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.protectedList,
    this.color,
    this.pinned = false,
  });

  final String? id;
  final String name;
  final int sortOrder;
  final bool protectedList;

  /// Optional ARGB/hex colour chosen by the user. Older migration files do
  /// not contain this field; the desktop client derives a stable palette
  /// colour from the list name when it is absent.
  final String? color;
  final bool pinned;

  factory MigrationListRecord.fromJson(Map<String, dynamic> json) {
    return MigrationListRecord(
      id: _nullableString(json['id']),
      name: _requiredString(json, 'name'),
      sortOrder: _intValue(json['sortOrder']),
      protectedList: _boolValue(json['protected']),
      color: _nullableString(json['color']),
      pinned: _boolValue(json['pinned']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sortOrder': sortOrder,
        'protected': protectedList,
        if (color != null && color!.trim().isNotEmpty) 'color': color,
        if (pinned) 'pinned': true,
      };
}

class MigrationFolderRecord {
  const MigrationFolderRecord({
    required this.id,
    required this.parentId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? parentId;
  final String name;
  final int sortOrder;
  final String? createdAt;
  final String? updatedAt;

  factory MigrationFolderRecord.fromJson(Map<String, dynamic> json) {
    return MigrationFolderRecord(
      id: _requiredString(json, 'id'),
      parentId: _nullableString(json['parentId']),
      name: _requiredString(json, 'name'),
      sortOrder: _intValue(json['sortOrder']),
      createdAt: _nullableString(json['createdAt']),
      updatedAt: _nullableString(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'parentId': parentId,
        'name': name,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

/// One checklist entry under a task. Absent in older files, optional since.
class MigrationSubtaskRecord {
  const MigrationSubtaskRecord({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  factory MigrationSubtaskRecord.fromJson(Map<String, dynamic> json) {
    return MigrationSubtaskRecord(
      id: _stringValue(json['id']),
      title: _stringValue(json['title']),
      completed: _boolValue(json['completed']),
    );
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'completed': completed};
}

class MigrationTaskRecord {
  const MigrationTaskRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.contentJson,
    required this.status,
    required this.priority,
    required this.dueAt,
    required this.dueEndAt,
    this.deadlineAt,
    this.hasDueTime,
    required this.reminderAt,
    this.reminderOffsets = const [],
    required this.recurrenceType,
    required this.recurrenceConfig,
    required this.listName,
    required this.tags,
    this.subtasks = const [],
    this.sourceNoteId,
    this.attachments = const [],
    this.focusCount = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
    this.deletedAt,
    this.skippedAt,
    this.isPinned = false,
    this.abandonedAt,
    this.convertedNoteId,
  });

  final String id;
  final String title;
  final String? description;
  final Map<String, dynamic>? contentJson;
  final String status;
  final String priority;
  final String? dueAt;
  final String? dueEndAt;
  final String? deadlineAt;
  final bool? hasDueTime;
  final String? reminderAt;
  final List<int> reminderOffsets;
  final String recurrenceType;
  final Map<String, dynamic>? recurrenceConfig;
  final String listName;
  final List<String> tags;
  final List<MigrationSubtaskRecord> subtasks;
  final String? sourceNoteId;
  final List<String> attachments;
  final int focusCount;
  final String? createdAt;
  final String? updatedAt;
  final String? completedAt;
  final String? deletedAt;

  /// Optional timestamp for a recurring occurrence that was skipped. Older
  /// snapshots omit this field and continue to deserialize unchanged.
  final String? skippedAt;
  final bool isPinned;
  final String? abandonedAt;
  final String? convertedNoteId;

  factory MigrationTaskRecord.fromJson(Map<String, dynamic> json) {
    return MigrationTaskRecord(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      description: _nullableString(json['description']),
      contentJson: _mapValue(json['contentJson']),
      status: _stringValue(json['status'], fallback: 'TODO'),
      priority: _stringValue(json['priority'], fallback: 'NONE'),
      dueAt: _nullableString(json['dueAt']),
      dueEndAt: _nullableString(json['dueEndAt']),
      deadlineAt: _nullableString(json['deadlineAt']),
      hasDueTime:
          json['hasDueTime'] is bool ? json['hasDueTime'] as bool : null,
      reminderAt: _nullableString(json['reminderAt']),
      reminderOffsets: (json['reminderOffsets'] as List? ?? const [])
          .whereType<num>()
          .map((n) => n.toInt())
          .toSet()
          .toList()
        ..sort(),
      recurrenceType: _stringValue(json['recurrenceType'], fallback: 'NONE'),
      recurrenceConfig: _mapValue(json['recurrenceConfig']),
      listName: _stringValue(json['listName'], fallback: '收集箱'),
      tags: _stringList(json['tags']),
      subtasks: _records(json['subtasks'], MigrationSubtaskRecord.fromJson),
      sourceNoteId: _nullableString(json['sourceNoteId']),
      attachments: _stringList(json['attachments']),
      focusCount: _intValue(json['focusCount']),
      createdAt: _nullableString(json['createdAt']),
      updatedAt: _nullableString(json['updatedAt']),
      completedAt: _nullableString(json['completedAt']),
      deletedAt: _nullableString(json['deletedAt']),
      skippedAt: _nullableString(json['skippedAt']),
      isPinned: json['isPinned'] == true,
      abandonedAt: _nullableString(json['abandonedAt']),
      convertedNoteId: _nullableString(json['convertedNoteId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'contentJson': contentJson,
        'status': status,
        'priority': priority,
        'dueAt': dueAt,
        'dueEndAt': dueEndAt,
        'deadlineAt': deadlineAt,
        'hasDueTime': hasDueTime,
        'reminderAt': reminderAt,
        if (reminderOffsets.isNotEmpty) 'reminderOffsets': reminderOffsets,
        'recurrenceType': recurrenceType,
        'recurrenceConfig': recurrenceConfig,
        'listName': listName,
        'tags': tags,
        'subtasks': subtasks.map((item) => item.toJson()).toList(),
        'sourceNoteId': sourceNoteId,
        'attachments': attachments,
        if (focusCount > 0) 'focusCount': focusCount,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'completedAt': completedAt,
        'deletedAt': deletedAt,
        'skippedAt': skippedAt,
        'isPinned': isPinned,
        'abandonedAt': abandonedAt,
        'convertedNoteId': convertedNoteId,
      };
}

class MigrationNoteRecord {
  const MigrationNoteRecord({
    required this.id,
    required this.folderId,
    required this.title,
    required this.contentJson,
    required this.plainText,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.originalContentJson,
  });

  final String id;
  final String? folderId;
  final String title;
  final Map<String, dynamic> contentJson;
  final String plainText;
  final bool isFavorite;
  final String? createdAt;
  final String? updatedAt;
  final String? deletedAt;

  /// When the desktop editor is still in protected rich-content mode, this
  /// keeps the imported source alongside the plain-text projection. Older
  /// migration files simply omit the field.
  final Map<String, dynamic>? originalContentJson;

  factory MigrationNoteRecord.fromJson(Map<String, dynamic> json) {
    return MigrationNoteRecord(
      id: _requiredString(json, 'id'),
      folderId: _nullableString(json['folderId']),
      title: _requiredString(json, 'title'),
      contentJson: _mapValue(json['contentJson']) ?? <String, dynamic>{},
      plainText: _stringValue(json['plainText']),
      isFavorite: _boolValue(json['isFavorite']),
      createdAt: _nullableString(json['createdAt']),
      updatedAt: _nullableString(json['updatedAt']),
      deletedAt: _nullableString(json['deletedAt']),
      originalContentJson: _mapValue(json['originalContentJson']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'folderId': folderId,
        'title': title,
        'contentJson': contentJson,
        'plainText': plainText,
        'isFavorite': isFavorite,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
        if (originalContentJson != null)
          'originalContentJson': originalContentJson,
      };
}

class MigrationBundle {
  const MigrationBundle({
    required this.format,
    required this.schemaVersion,
    required this.exportedAt,
    required this.lists,
    required this.folders,
    required this.tasks,
    required this.notes,
    this.embeddedFiles = const {},
  });

  final String format;
  final int schemaVersion;
  final String? exportedAt;
  final List<MigrationListRecord> lists;
  final List<MigrationFolderRecord> folders;
  final List<MigrationTaskRecord> tasks;
  final List<MigrationNoteRecord> notes;
  final Map<String, String> embeddedFiles;

  bool get isLocalSnapshot => format == localSnapshotFormat;

  factory MigrationBundle.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const MigrationFormatException('导入文件必须是 JSON 对象。');
    }
    return MigrationBundle.fromJson(Map<String, dynamic>.from(decoded));
  }

  factory MigrationBundle.fromJson(Map<String, dynamic> json) {
    final format = _stringValue(json['format']);
    if (format != personalMigrationFormat && format != localSnapshotFormat) {
      throw const MigrationFormatException('这不是打勾个人版的数据文件。');
    }
    final schemaVersion = _intValue(json['schemaVersion']);
    if (!supportedMigrationSchemaVersions.contains(schemaVersion)) {
      throw MigrationFormatException('暂不支持数据文件版本 $schemaVersion，请先升级 macOS 版。');
    }

    return MigrationBundle(
      format: format,
      schemaVersion: schemaVersion,
      exportedAt: _nullableString(json['exportedAt']),
      lists: _records(json['lists'], MigrationListRecord.fromJson),
      folders: _records(json['folders'], MigrationFolderRecord.fromJson),
      tasks: _records(json['tasks'], MigrationTaskRecord.fromJson),
      notes: _records(json['notes'], MigrationNoteRecord.fromJson),
      embeddedFiles: {
        for (final entry in (_mapValue(json['attachmentFiles']) ?? {}).entries)
          if (entry.value is String) entry.key: entry.value as String
      },
    );
  }

  Map<String, dynamic> toJson({String? outputFormat}) => {
        'format': outputFormat ?? format,
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt,
        'lists': lists.map((item) => item.toJson()).toList(),
        'folders': folders.map((item) => item.toJson()).toList(),
        'tasks': tasks.map((item) => item.toJson()).toList(),
        'notes': notes.map((item) => item.toJson()).toList(),
        if (embeddedFiles.isNotEmpty) 'attachmentFiles': embeddedFiles,
      };
}

List<T> _records<T>(Object? raw, T Function(Map<String, dynamic>) factory) {
  if (raw == null) return <T>[];
  if (raw is! List) {
    throw const MigrationFormatException('数据文件中的集合字段格式不正确。');
  }
  return raw.map((item) {
    if (item is! Map) {
      throw const MigrationFormatException('数据文件中的记录格式不正确。');
    }
    return factory(Map<String, dynamic>.from(item));
  }).toList();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _nullableString(json[key]);
  if (value == null || value.trim().isEmpty) {
    throw MigrationFormatException('数据文件缺少有效的 $key。');
  }
  return value;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

String _stringValue(Object? value, {String fallback = ''}) =>
    _nullableString(value) ?? fallback;

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_stringValue(value)) ?? 0;
}

bool _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return _stringValue(value).toLowerCase() == 'true';
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

List<String> _stringList(Object? value) {
  if (value is! List) return <String>[];
  return value.whereType<Object>().map((item) => item.toString()).toList();
}

List<int> _intList(Object? value) {
  if (value is! List) return <int>[];
  return value
      .whereType<Object>()
      .map((item) => item is num ? item.toInt() : int.tryParse(item.toString()))
      .whereType<int>()
      .toList();
}
