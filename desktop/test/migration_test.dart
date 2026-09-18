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

  test('keeps version 1 snapshots readable after the local schema grows', () {
    final bundle = MigrationBundle.fromJson({
      'format': localSnapshotFormat,
      'schemaVersion': 1,
      'lists': [
        {'id': null, 'name': '收集箱', 'sortOrder': 0, 'protected': true},
      ],
      'folders': [],
      'tasks': [
        {
          'id': 'old-task',
          'title': '旧快照任务',
          'status': 'TODO',
          'priority': 'NONE',
          'listName': '收集箱',
          'tags': [],
        },
      ],
      'notes': [],
    });

    expect(bundle.schemaVersion, 1);
    expect(bundle.lists.single.pinned, isFalse);
  });

  test('round trips list colors and pinning', () {
    final bundle = MigrationBundle(
      format: localSnapshotFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [
        MigrationListRecord(
          id: 'list-work',
          name: '工作',
          sortOrder: 0,
          protectedList: false,
          color: '#22AA66',
          pinned: true,
        ),
      ],
      folders: const [],
      tasks: const [
        MigrationTaskRecord(
          id: 'focus-task',
          title: '专注任务',
          description: null,
          contentJson: null,
          status: 'TODO',
          priority: 'HIGH',
          dueAt: null,
          dueEndAt: null,
          reminderAt: null,
          recurrenceType: 'NONE',
          recurrenceConfig: null,
          listName: '工作',
          tags: const [],
          createdAt: null,
          updatedAt: null,
          completedAt: null,
        ),
      ],
      notes: const [],
    );

    final restored = MigrationBundle.fromJson(bundle.toJson());
    expect(restored.lists.single.pinned, isTrue);
    expect(restored.lists.single.color, '#22AA66');
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

  test('edits personal tasks and notes through the local controller', () {
    final controller = WorkspaceController();

    controller.updateTaskTitle('task-01', '新的评审标题');
    controller.updateTaskDescription('task-01', '新的任务描述');
    controller.updateTaskPriority('task-01', TaskPriority.medium);
    controller.updateTaskDue('task-01', DateTime(2099, 8, 30, 9, 30));
    controller.updateTaskReminder('task-01', DateTime(2099, 8, 29));
    controller.updateTaskRecurrence('task-01', 'WEEKLY');
    controller.updateTaskTags('task-01', const ['项目', '项目', '验收']);
    controller.moveTaskToList('task-01', '项目');

    final task = controller.tasks.firstWhere((item) => item.id == 'task-01');
    expect(task.title, '新的评审标题');
    expect(task.description, '新的任务描述');
    expect(task.priority, TaskPriority.medium);
    expect(task.dueAt, isNotNull);
    expect(task.reminderAt, isNotNull);
    expect(task.recurrenceType, 'WEEKLY');
    expect(task.tags, const ['项目', '验收']);
    expect(task.listName, '项目');
    expect(controller.lists.any((list) => list.name == '项目'), isTrue);

    final folder = controller.addFolder('个人想法');
    expect(folder, isNotNull);
    final noteId = controller.addNote(folderId: folder!.id);
    controller.updateNoteTitle(noteId, '新的笔记标题');
    controller.updateNoteBody(noteId, '新的笔记正文');
    controller.toggleNoteFavorite(noteId);

    final note = controller.notes.firstWhere((item) => item.id == noteId);
    expect(note.title, '新的笔记标题');
    expect(note.plainText, '新的笔记正文');
    expect(note.preview, '新的笔记正文');
    expect(note.isFavorite, isTrue);
    expect(note.folderId, folder.id);
    expect(controller.removeNote(noteId), isTrue);
    // Notes go to the trash now: hidden from active lists, still recoverable.
    expect(controller.activeNotes.where((item) => item.id == noteId), isEmpty);
    expect(controller.deletedNotes.map((item) => item.id), contains(noteId));
  });
}
