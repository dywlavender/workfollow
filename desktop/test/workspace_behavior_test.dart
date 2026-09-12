import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/services/local_workspace_store.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

/// Records saves without touching the filesystem; can simulate failures and
/// a damaged snapshot.
class _FakeStore extends LocalWorkspaceStore {
  final List<MigrationBundle> saved = [];
  Object? failNextSave;
  Object? loadError;

  @override
  Future<void> save(MigrationBundle bundle) async {
    if (failNextSave != null) {
      final error = failNextSave;
      failNextSave = null;
      throw error!;
    }
    saved.add(bundle);
  }

  @override
  Future<WorkspaceSnapshotLoad> load() async {
    if (loadError != null) {
      final error = loadError;
      loadError = null;
      return WorkspaceSnapshotLoad(error: error);
    }
    return const WorkspaceSnapshotLoad();
  }
}

Future<void> _settleSaves(WorkspaceController controller) async {
  // Save results complete on the next microtasks plus one controller notify.
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a task created in a list keeps that list and stays unscheduled',
      () async {
    final controller = WorkspaceController();
    controller.selectList('工作');

    expect(controller.addTask('写周报'), isTrue);

    final task = controller.tasks.firstWhere((task) => task.title == '写周报');
    expect(task.listName, '工作');
    expect(task.dueAt, isNull);
    expect(task.bucket, TaskBucket.unscheduled);
    // It is visible right where it was created.
    expect(controller.visibleTasks.any((task) => task.title == '写周报'), isTrue);
  });

  test('a task created in Today is scheduled for today', () {
    final controller = WorkspaceController();
    controller.selectView(WorkspaceView.today);

    expect(controller.addTask('买菜'), isTrue);

    final task = controller.tasks.firstWhere((task) => task.title == '买菜');
    expect(task.bucket, TaskBucket.today);
    expect(task.dueAt, isNotNull);
    final due = DateTime.parse(task.dueAt!);
    final now = DateTime.now();
    expect(DateUtils.isSameDay(due, DateTime(now.year, now.month, now.day)),
        isTrue);
  });

  test(
      'unscheduled tasks never appear in Today, in memory or after a save/'
      'load round trip', () {
    final controller = WorkspaceController();
    controller.selectList('工作');
    controller.addTask('无边框的想法');

    controller.selectView(WorkspaceView.today);
    expect(
        controller.visibleTasks.any((task) => task.title == '无边框的想法'), isFalse);

    final task = controller.tasks.firstWhere((task) => task.title == '无边框的想法');
    final roundTripped = TaskItem.fromMigration(task.toMigrationRecord());
    expect(roundTripped.bucket, TaskBucket.unscheduled);
  });

  test('updating a note body keeps plainText and contentJson in sync', () {
    final controller = WorkspaceController();
    final noteId = controller.addNote();

    controller.updateNoteBody(noteId, '第一段\n第二段');

    final note = controller.notes.firstWhere((note) => note.id == noteId);
    expect(note.plainText, '第一段\n第二段');
    expect(note.preview, '第一段 第二段');
    final content = note.contentJson!;
    expect(content['type'], 'doc');
    final paragraphs =
        (content['content'] as List).cast<Map<String, dynamic>>();
    expect(paragraphs, hasLength(2));
    final firstText =
        ((paragraphs.first['content'] as List).first as Map)['text'];
    expect(firstText, '第一段');
    // Round trip keeps the regenerated body.
    final record = note.toMigrationRecord();
    expect(record.plainText, '第一段\n第二段');
  });

  test('removing a task moves it to a persistent trash and undo restores it',
      () async {
    final store = _FakeStore();
    final controller = WorkspaceController(store: store);

    controller.removeTask('task-01');
    expect(controller.deletedTasks.map((task) => task.id), contains('task-01'));
    expect(controller.activeTasks.map((task) => task.id),
        isNot(contains('task-01')));
    expect(controller.countFor(WorkspaceView.trash), 1);

    expect(controller.undoLastAction(), isTrue);
    expect(controller.deletedTasks, isEmpty);
    expect(controller.activeTasks.map((task) => task.id), contains('task-01'));

    // Removing again and purging leaves no trace.
    controller.removeTask('task-01');
    controller.purgeTask('task-01');
    expect(controller.tasks.every((task) => task.id != 'task-01'), isTrue);
  });

  test('removing a note moves it to the trash, with toast undo', () {
    final controller = WorkspaceController();
    controller.removeNote('note-01');
    expect(controller.deletedNotes.map((note) => note.id), contains('note-01'));
    expect(controller.activeNotes.map((note) => note.id),
        isNot(contains('note-01')));

    expect(controller.undoLastAction(), isTrue);
    expect(controller.activeNotes.map((note) => note.id), contains('note-01'));
  });

  test('openNote selects the exact note; openTask lands on its view', () {
    final controller = WorkspaceController();
    final secondId = controller.addNote();
    controller.selectNote('note-01');

    controller.openNote(secondId);
    expect(controller.view, WorkspaceView.notes);
    expect(controller.selectedNoteId, secondId);

    controller.openTask('task-04');
    expect(controller.selectedTaskId, 'task-04');
    expect(controller.isTaskView, isTrue);
  });

  test('calendar day queries match real scheduled dates', () {
    final controller = WorkspaceController();
    controller.updateTaskDue('task-01', DateTime(2099, 8, 30, 9, 30));
    controller.updateTaskDue('task-02', DateTime(2099, 8, 30));

    final dayTasks = controller.tasksForDay(DateTime(2099, 8, 30));
    expect(
        dayTasks.map((task) => task.id), containsAll(['task-01', 'task-02']));
    expect(controller.tasksForDay(DateTime(2099, 8, 31)), isEmpty);
  });

  test('save status follows real write results', () async {
    final store = _FakeStore();
    final controller = WorkspaceController(store: store);

    controller.updateTaskTitle('task-01', '真实的保存状态');
    await _settleSaves(controller);
    expect(controller.saveStatus, SaveStatus.saved);
    expect(controller.lastSavedAt, isNotNull);
    expect(store.saved, isNotEmpty);

    store.failNextSave =
        const FileSystemException('disk full', 'workspace.json');
    controller.updateTaskTitle('task-01', '这一次会失败');
    await _settleSaves(controller);
    expect(controller.saveStatus, SaveStatus.failed);
    expect(controller.saveError, isNotNull);

    controller.updateTaskTitle('task-01', '恢复写入');
    await _settleSaves(controller);
    expect(controller.saveStatus, SaveStatus.saved);
  });

  test('a damaged snapshot pauses auto-save instead of overwriting it',
      () async {
    final store = _FakeStore();
    final controller = WorkspaceController(store: store);
    store.loadError = const FormatException('broken json');

    await controller.restoreFromDisk();
    expect(controller.loadError, isNotNull);

    final savesBefore = store.saved.length;
    controller.updateTaskTitle('task-01', '不应写入');
    await _settleSaves(controller);
    expect(store.saved.length, savesBefore);
    expect(controller.saveStatus, SaveStatus.failed);
  });

  test('replacing the workspace clears starter content before import',
      () async {
    final store = _FakeStore();
    final controller = WorkspaceController(store: store);
    expect(controller.activeTasks, isNotEmpty);

    final bundle = MigrationBundle(
      format: personalMigrationFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [
        MigrationListRecord(
            id: 'list-web', name: '项目', sortOrder: 0, protectedList: false),
      ],
      folders: const [],
      tasks: const [
        MigrationTaskRecord(
          id: 'task-01',
          title: '来自 Web 的同名任务',
          description: null,
          contentJson: null,
          status: 'TODO',
          priority: 'NONE',
          dueAt: null,
          dueEndAt: null,
          reminderAt: null,
          recurrenceType: 'NONE',
          recurrenceConfig: null,
          listName: '项目',
          tags: [],
          createdAt: null,
          updatedAt: null,
          completedAt: null,
        ),
      ],
      notes: const [],
    );

    final summary = await controller.replaceWithMigration(bundle);
    // Replace mode never silently merges starter records into real data.
    expect(summary.importedTasks, 1);
    expect(controller.tasks, hasLength(1));
    expect(controller.tasks.single.title, '来自 Web 的同名任务');
    expect(controller.lists.map((list) => list.name), contains('项目'));
  });

  test('notes filters live in the controller and new notes follow them', () {
    final controller = WorkspaceController();
    expect(controller.notesFolderFilter, isNull);

    controller.setNotesFavoritesOnly(true);
    expect(controller.notesFavoritesOnly, isTrue);

    controller.setNotesFolderFilter('folder-work');
    expect(controller.notesFavoritesOnly, isFalse);
    expect(controller.notesFolderFilter, 'folder-work');

    final id = controller.addNoteInCurrentFolder();
    final note = controller.notes.firstWhere((note) => note.id == id);
    expect(note.folderId, 'folder-work');
    expect(controller.view, WorkspaceView.notes);
    expect(controller.selectedNoteId, id);
  });

  test('quick add focus requests are pending until consumed once', () {
    final controller = WorkspaceController();
    expect(controller.quickAddFocusPending, isFalse);

    controller.requestQuickAddFocus();
    expect(controller.quickAddFocusPending, isTrue);

    controller.consumeQuickAddFocus();
    expect(controller.quickAddFocusPending, isFalse);
  });

  test('completing a daily recurring task creates the next occurrence', () {
    final controller = WorkspaceController();
    controller.updateTaskDue('task-01', DateTime(2099, 1, 15, 14, 0));
    controller.updateTaskRecurrence('task-01', 'DAILY');

    controller.toggleTask('task-01');

    final completed =
        controller.tasks.firstWhere((task) => task.id == 'task-01');
    expect(completed.completed, isTrue);
    // The next occurrence keeps the title, list and rule, scheduled +1 day.
    final spawned = controller.tasks.firstWhere(
        (task) => task.id != 'task-01' && task.title == completed.title);
    expect(spawned.completed, isFalse);
    expect(spawned.recurrenceType, 'DAILY');
    expect(spawned.listName, completed.listName);
    expect(DateTime.parse(spawned.dueAt!), DateTime(2099, 1, 16, 14, 0));

    // Undo removes the generated task and restores the rule on the original.
    expect(controller.undoLastCompletion(), isTrue);
    expect(controller.tasks.where((task) => task.id == spawned.id), isEmpty);
    final restored =
        controller.tasks.firstWhere((task) => task.id == 'task-01');
    expect(restored.completed, isFalse);
    expect(restored.recurrenceType, 'DAILY');
  });

  test('weekly recurrence honors the configured weekday', () {
    final controller = WorkspaceController();
    final due = DateTime(2099, 3, 4);
    controller.updateTaskDue('task-02', due);
    final targetWeekday = due.weekday == 7 ? 1 : due.weekday + 1;
    controller.updateTaskRecurrence('task-02', 'WEEKLY',
        config: {'weekday': targetWeekday});

    controller.toggleTask('task-02');

    var expected = due.add(const Duration(days: 1));
    while (expected.weekday != targetWeekday) {
      expected = expected.add(const Duration(days: 1));
    }
    final spawned = controller.tasks.firstWhere((task) =>
        task.id != 'task-02' &&
        task.completed == false &&
        task.recurrenceType == 'WEEKLY');
    expect(DateTime.parse(spawned.dueAt!),
        DateTime(expected.year, expected.month, expected.day));
  });

  test('monthly recurrence clamps to the end of shorter months', () {
    final controller = WorkspaceController();
    controller.updateTaskDue('task-03', DateTime(2099, 1, 31));
    controller.updateTaskRecurrence('task-03', 'MONTHLY');

    controller.toggleTask('task-03');

    final spawned = controller.tasks.firstWhere(
        (task) => task.id != 'task-03' && task.recurrenceType == 'MONTHLY');
    // 2099 is not a leap year: the 31st lands on Feb 28.
    expect(DateTime.parse(spawned.dueAt!), DateTime(2099, 2, 28));
  });

  test('subtasks can be added, toggled and removed, and survive a round trip',
      () {
    final controller = WorkspaceController();

    expect(controller.addSubtask('task-02', '第一步'), isTrue);
    final task = controller.tasks.firstWhere((task) => task.id == 'task-02');
    final subtask = task.subtasks.single;
    expect(task.subtaskTotal, 1);
    expect(task.subtaskCompleted, 0);

    expect(controller.toggleSubtask('task-02', subtask.id), isTrue);
    expect(
        controller.tasks
            .firstWhere((task) => task.id == 'task-02')
            .subtaskCompleted,
        1);

    final roundTripped = TaskItem.fromMigration(task.toMigrationRecord());
    expect(roundTripped.subtasks, hasLength(1));
    expect(roundTripped.subtasks.single.title, '第一步');

    expect(controller.removeSubtask('task-02', subtask.id), isTrue);
    expect(controller.tasks.firstWhere((task) => task.id == 'task-02').subtasks,
        isEmpty);
  });

  test(
      'renaming a list moves its tasks; deleting a list returns them to the inbox',
      () {
    final controller = WorkspaceController();

    expect(controller.renameList('工作', '项目A'), isTrue);
    expect(controller.tasks.where((task) => task.listName == '工作'), isEmpty);
    expect(controller.lists.map((list) => list.name), contains('项目A'));
    // Guard rails: the inbox keeps its name, duplicates are rejected.
    expect(controller.renameList('收集箱', '别的'), isFalse);
    expect(controller.renameList('项目A', '项目A'), isFalse);

    expect(controller.deleteList('项目A'), isTrue);
    expect(controller.lists.any((list) => list.name == '项目A'), isFalse);
    final moved =
        controller.tasks.firstWhere((task) => task.title == '准备季度产品评审演示文稿');
    expect(moved.listName, '收集箱');
  });

  testWidgets('command palette opens, searches and creates tasks',
      (tester) async {
    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    // The palette must build without a "No Material widget found" crash.
    expect(find.text('搜索任务、笔记或命令…'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('command-palette-query')), '季度');
    await tester.pump();
    expect(find.text('新建任务「季度」'), findsOneWidget);
    // The existing seed task matches the query too (its home panel copy stays
    // in the tree behind the dialog).
    expect(find.text('准备季度产品评审演示文稿'), findsWidgets);

    // The palette row sits above the home panel copy in the tree.
    await tester.tap(find.text('准备季度产品评审演示文稿').last);
    await tester.pumpAndSettle();
    // openTask lands on the owning view with the task selected.
    expect(find.text('准备季度产品评审演示文稿'), findsWidgets);
  });
}
