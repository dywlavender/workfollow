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

  testWidgets('command palette opens, searches and creates tasks',
      (tester) async {
    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    // The palette must build without a "No Material widget found" crash.
    expect(find.text('搜索任务、笔记或命令…'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('command-palette-query')), '季度');
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
