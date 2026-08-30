import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

void main() {
  test('parses a versioned personal migration bundle', () {
    final bundle = MigrationBundle.fromJsonString(jsonEncode({
      'format': personalMigrationFormat,
      'schemaVersion': migrationSchemaVersion,
      'exportedAt': '2026-08-30T08:00:00.000Z',
      'lists': [
        {'id': null, 'name': '项目', 'sortOrder': 4, 'protected': false},
      ],
      'folders': [
        {
          'id': 'folder-project',
          'parentId': null,
          'name': '项目笔记',
          'sortOrder': 0,
          'createdAt': null,
          'updatedAt': null,
        },
      ],
      'tasks': [
        {
          'id': 'web-task-1',
          'title': '完成迁移验收',
          'description': '检查导入后的列表和笔记',
          'status': 'TODO',
          'priority': 'HIGH',
          'dueAt': '2099-08-30T09:30:00.000Z',
          'listName': '项目',
          'tags': ['迁移'],
        },
      ],
      'notes': [
        {
          'id': 'web-note-1',
          'folderId': 'folder-project',
          'title': '验收记录',
          'contentJson': {'type': 'doc'},
          'plainText': '记录迁移后的结果',
          'isFavorite': true,
        },
      ],
    }));

    expect(bundle.tasks, hasLength(1));
    expect(bundle.notes.single.isFavorite, isTrue);
    expect(TaskItem.fromMigration(bundle.tasks.single).priority,
        TaskPriority.high);
    expect(
        TaskItem.fromMigration(bundle.tasks.single).bucket, TaskBucket.later);
  });

  test('rejects an unknown format or schema version', () {
    expect(
      () => MigrationBundle.fromJson({
        'format': 'other-app',
        'schemaVersion': migrationSchemaVersion,
      }),
      throwsA(isA<MigrationFormatException>()),
    );
    expect(
      () => MigrationBundle.fromJson({
        'format': personalMigrationFormat,
        'schemaVersion': 99,
      }),
      throwsA(isA<MigrationFormatException>()),
    );
  });

  test('merges imported records without duplicating existing ids', () async {
    final controller = WorkspaceController();
    final first = MigrationBundle(
      format: personalMigrationFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [],
      folders: const [],
      tasks: const [
        MigrationTaskRecord(
          id: 'web-task-1',
          title: '来自 Web 的任务',
          description: null,
          contentJson: null,
          status: 'TODO',
          priority: 'NONE',
          dueAt: null,
          dueEndAt: null,
          reminderAt: null,
          recurrenceType: 'NONE',
          recurrenceConfig: null,
          listName: '收集箱',
          tags: [],
          createdAt: null,
          updatedAt: null,
          completedAt: null,
        ),
      ],
      notes: const [],
    );

    final firstSummary = await controller.importMigration(first);
    final secondSummary = await controller.importMigration(first);

    expect(firstSummary.importedTasks, 1);
    expect(secondSummary.importedTasks, 0);
    expect(secondSummary.skippedTasks, 1);
    expect(controller.tasks.where((task) => task.id == 'web-task-1'),
        hasLength(1));
  });
}
