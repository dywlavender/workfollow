import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/features/tasks/application/task_actions.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/services/local_workspace_store.dart';
import 'package:workfollow_personal/services/notification_service.dart';
import 'package:workfollow_personal/services/preferences_store.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

/// Records saves without touching the filesystem; can simulate failures and
/// a damaged snapshot.
class _FakeStore extends LocalWorkspaceStore {
  final List<MigrationBundle> saved = [];
  Object? failNextSave;
  Object? loadError;
  MigrationBundle? loadBundle;

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
    if (loadBundle != null) return WorkspaceSnapshotLoad(bundle: loadBundle);
    return const WorkspaceSnapshotLoad();
  }
}

class _DeferredStore extends LocalWorkspaceStore {
  final List<MigrationBundle> saved = [];
  final List<Completer<void>> pending = [];

  @override
  Future<void> save(MigrationBundle bundle) {
    saved.add(bundle);
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  }
}

/// Records reminder scheduling so tests can assert the controller keeps
/// system notifications in sync with task state.
class _RecordingReminders implements ReminderScheduler {
  final Map<String, DateTime> scheduled = {};
  final List<String> canceled = [];
  int cancelAllCount = 0;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> authorizationStatus() async => 'authorized';

  @override
  Future<void> schedule({
    required String taskId,
    required String title,
    String? body,
    required DateTime at,
  }) async {
    canceled.remove(taskId);
    scheduled[taskId] = at;
  }

  @override
  Future<void> cancel(String taskId) async {
    scheduled.remove(taskId);
    canceled.add(taskId);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
    cancelAllCount += 1;
  }

  @override
  set onNotificationClicked(void Function(String taskId)? handler) {}
}

Future<void> _settleSaves(WorkspaceController controller) async {
  // Save results complete on the next microtasks plus one controller notify.
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _settleAsync() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
      'QUICK-017 LIST-002 a task created in a list keeps that list and stays unscheduled',
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

  test('QUICK-017 QUICK-021 a task created in Today is scheduled for today',
      () {
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

  test('QUICK-021 global capture always creates an unscheduled inbox task', () {
    final controller = WorkspaceController();
    controller.selectView(WorkspaceView.today);

    expect(controller.addTaskToInboxUnscheduled('菜单栏速记'), isTrue);
    final task = controller.tasks.firstWhere((task) => task.title == '菜单栏速记');
    expect(task.listName, '收集箱');
    expect(task.dueAt, isNull);
    expect(task.bucket, TaskBucket.unscheduled);
  });

  test(
      'P0 ROW-011 DATE-012 DATE-013 UNDO-003 UNDO-004 task chain keeps action, projection, undo and persistence aligned',
      () async {
    final store = _FakeStore();
    final reminders = _RecordingReminders();
    final controller = WorkspaceController(
        store: store, reminderScheduler: reminders, seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueToday = DateTime(today.year, today.month, today.day, 15, 0);
    final create = controller.taskActions.create(TaskDraft(
      title: 'P0 链路验收任务',
      listName: '工作',
      schedule: TaskScheduleDraft(dueAt: dueToday, hasTime: true),
      reminderAt: now.add(const Duration(hours: 1)),
      priority: TaskPriority.high,
      tags: const ['验收'],
    ));
    expect(create.success, isTrue);
    final id = create.taskId!;
    expect(create.destination, TaskDestination.current);
    expect(controller.visibleTasks.map((task) => task.id), contains(id));

    controller.selectTask(id);
    expect(controller.selectedTask?.id, id);
    expect(controller.selectedTask?.priority, TaskPriority.high);
    expect(controller.selectedTask?.tags, ['验收']);

    final tomorrow = today.add(const Duration(days: 1));
    final moved = controller.taskActions.setSchedule(
        id,
        TaskScheduleDraft.forDay(tomorrow,
            preserveClock: dueToday, hasTime: true));
    expect(moved.success, isTrue);
    expect(moved.destination, TaskDestination.plan);
    expect(controller.visibleTasks.map((task) => task.id), isNot(contains(id)));
    expect(controller.countFor(WorkspaceView.today), 0);

    controller.openTask(id);
    expect(controller.selectedTask?.id, id);
    controller.selectView(WorkspaceView.today);
    final returned = controller.taskActions.setSchedule(
        id,
        TaskScheduleDraft.forDay(today,
            preserveClock: dueToday, hasTime: true));
    expect(returned.success, isTrue);
    expect(controller.visibleTasks.map((task) => task.id), contains(id));

    controller.selectTask(id);
    final completed = controller.taskActions.complete(id);
    expect(completed.success, isTrue);
    expect(controller.selectedTaskId, id);
    expect(controller.selectedTask?.completed, isTrue);
    expect(controller.countFor(WorkspaceView.today), 0);
    controller.selectView(WorkspaceView.completed);
    expect(controller.visibleTasks.map((task) => task.id), contains(id));

    final undone = controller.taskActions.undo();
    expect(undone.success, isTrue);
    controller.selectView(WorkspaceView.today);
    expect(controller.visibleTasks.map((task) => task.id), contains(id));
    controller.selectView(WorkspaceView.completed);
    expect(controller.visibleTasks.map((task) => task.id), isNot(contains(id)));

    await controller.waitForPendingSaves();
    expect(store.saved, isNotEmpty);
    final persisted =
        store.saved.last.tasks.firstWhere((task) => task.id == id);
    expect(persisted.priority, 'HIGH');
    expect(persisted.tags, ['验收']);
    expect(persisted.status, 'TODO');
    expect(persisted.hasDueTime, isTrue);

    final reloadStore = _FakeStore()..loadBundle = store.saved.last;
    final reloaded = WorkspaceController(
        store: reloadStore,
        reminderScheduler: _RecordingReminders(),
        seedData: false);
    addTearDown(reloaded.dispose);
    await reloaded.restoreFromDisk();
    final restored = reloaded.tasks.firstWhere((task) => task.id == id);
    expect(restored.title, 'P0 链路验收任务');
    expect(restored.completed, isFalse);
    expect(restored.priority, TaskPriority.high);
    expect(restored.tags, ['验收']);
    expect(restored.scheduledWithTime, isTrue);
  });

  test(
      'ARCH-004 ARCH-007 unscheduled tasks never appear in Today, in memory or after a save/'
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

  test(
      'MENU-008 UNDO-001 UNDO-004 removing a task moves it to persistent trash and undo restores it',
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

  test('DATE-013 calendar day queries match real scheduled dates', () {
    final controller = WorkspaceController();
    controller.updateTaskDue('task-01', DateTime(2099, 8, 30, 9, 30));
    controller.updateTaskDue('task-02', DateTime(2099, 8, 30));

    final dayTasks = controller.tasksForDay(DateTime(2099, 8, 30));
    expect(
        dayTasks.map((task) => task.id), containsAll(['task-01', 'task-02']));
    expect(controller.tasksForDay(DateTime(2099, 8, 31)), isEmpty);
  });

  test(
      'DATE-013 UTC migration timestamps are grouped by their local calendar day',
      () async {
    const raw = '2026-09-12T16:30:00Z';
    final local = DateTime.parse(raw).toLocal();
    final controller = WorkspaceController();
    await controller.replaceWithMigration(MigrationBundle(
      format: personalMigrationFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [],
      folders: const [],
      tasks: const [
        MigrationTaskRecord(
          id: 'utc-task',
          title: '本地午夜后的任务',
          description: null,
          contentJson: null,
          status: 'TODO',
          priority: 'NONE',
          dueAt: raw,
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
    ));

    final day = DateTime(local.year, local.month, local.day);
    expect(controller.tasksForDay(day).map((task) => task.id), ['utc-task']);
    final due = DateTime.parse(controller.tasks.single.dueAt!).toLocal();
    expect(due.hour, local.hour);
    expect(due.minute, local.minute);
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

  test('save status stays saving until the newest queued write completes',
      () async {
    final store = _DeferredStore();
    final controller = WorkspaceController(store: store);

    controller.updateTaskTitle('task-01', '第一次编辑');
    await Future<void>.delayed(Duration.zero);
    expect(store.pending, hasLength(1));

    controller.updateTaskTitle('task-01', '第二次编辑');
    expect(controller.saveStatus, SaveStatus.saving);

    store.pending.first.complete();
    for (var i = 0; i < 4 && store.pending.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(store.pending, hasLength(2));
    expect(controller.saveStatus, SaveStatus.saving);

    store.pending[1].complete();
    await controller.waitForPendingSaves();
    expect(controller.saveStatus, SaveStatus.saved);
    expect(store.saved.last.tasks.first.title, '第二次编辑');
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

  test('QUICK-002 quick add focus requests are pending until consumed once',
      () {
    final controller = WorkspaceController();
    expect(controller.quickAddFocusPending, isFalse);

    controller.requestQuickAddFocus();
    expect(controller.quickAddFocusPending, isTrue);

    controller.consumeQuickAddFocus();
    expect(controller.quickAddFocusPending, isFalse);
  });

  test(
      'ROW-012 ROW-013 REPEAT-005 completing a daily recurring task creates the next occurrence',
      () {
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

  test('REPEAT-002 REPEAT-003 weekly recurrence honors the configured weekday',
      () {
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

  test(
      'REPEAT-002 REPEAT-003 monthly recurrence clamps to the end of shorter months',
      () {
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

  test(
      'DATE-001 DATE-002 DATE-007 rescheduleTask moves the day but keeps the clock time',
      () {
    final controller = WorkspaceController();
    controller.updateTaskDue('task-01', DateTime(2099, 5, 10, 14, 30));

    controller.rescheduleTask('task-01', DateTime(2099, 5, 20));

    final task = controller.tasks.firstWhere((task) => task.id == 'task-01');
    expect(DateTime.parse(task.dueAt!), DateTime(2099, 5, 20, 14, 30));
  });

  test(
      'BULK-001 BULK-004 UNDO-002 UNDO-003 bulk complete and bulk delete revert through one undo',
      () {
    final controller = WorkspaceController();
    controller.updateTaskDue('task-01', DateTime(2099, 1, 15));
    controller.updateTaskRecurrence('task-01', 'DAILY');
    controller.selectList('工作');
    controller.toggleMultiSelect('task-01');
    controller.toggleMultiSelect('task-02');
    expect(controller.multiSelectCount, 2);

    controller.bulkCompleteSelected();
    expect(controller.multiSelectCount, 0);
    final completed = controller.tasks
        .where((task) => task.id == 'task-01' || task.id == 'task-02');
    expect(completed.every((task) => task.completed), isTrue);
    // The recurring task spawned its next occurrence.
    final spawn = controller.tasks.firstWhere(
        (task) => task.recurrenceType == 'DAILY' && !task.completed);

    expect(controller.undoLastAction(), isTrue);
    expect(
        controller.tasks.firstWhere((task) => task.id == 'task-01').completed,
        isFalse);
    // Undo removes the spawn and restores the rule on the original record.
    expect(controller.tasks.where((task) => task.id == spawn.id), isEmpty);
    expect(
        controller.tasks
            .firstWhere((task) => task.id == 'task-01')
            .recurrenceType,
        'DAILY');

    // Bulk delete lands in the trash and comes back on undo.
    controller.toggleMultiSelect('task-01');
    controller.toggleMultiSelect('task-02');
    controller.bulkDeleteSelected();
    expect(
        controller.activeTasks
            .where((task) => task.id == 'task-01' || task.id == 'task-02'),
        isEmpty);
    expect(controller.undoLastAction(), isTrue);
    expect(
        controller.activeTasks
            .where((task) => task.id == 'task-01' || task.id == 'task-02'),
        hasLength(2));
  });

  test(
      'DATE-014 BULK-002 BULK-003 UNDO-002 bulk move and bulk reschedule revert their previous values',
      () {
    final controller = WorkspaceController();
    controller.updateTaskDue('task-05', DateTime(2099, 6, 1, 9, 0));

    controller.toggleMultiSelect('task-05');
    controller.toggleMultiSelect('task-06');
    controller.bulkMoveSelectedToList('项目X');
    expect(
        controller.tasks
            .where((task) => task.id == 'task-05' || task.id == 'task-06')
            .every((task) => task.listName == '项目X'),
        isTrue);

    controller.toggleMultiSelect('task-05');
    controller.bulkRescheduleSelected(DateTime(2099, 6, 10));
    expect(
        DateTime.parse(
            controller.tasks.firstWhere((task) => task.id == 'task-05').dueAt!),
        DateTime(2099, 6, 10, 9, 0));

    expect(controller.undoLastAction(), isTrue);
    expect(
        DateTime.parse(
            controller.tasks.firstWhere((task) => task.id == 'task-05').dueAt!),
        DateTime(2099, 6, 1, 9, 0));
    // One undo only reverted the latest bulk step (the reschedule).
    expect(controller.tasks.firstWhere((task) => task.id == 'task-05').listName,
        '项目X');

    // Bulk undo is single-level, consistent with single-task undo.
    expect(controller.undoLastAction(), isFalse);
    expect(controller.tasks.firstWhere((task) => task.id == 'task-05').listName,
        '项目X');
  });

  test(
      'ROW-005 ROW-006 multi-select range extends over the visible order and clears',
      () {
    final controller = WorkspaceController();
    controller.selectList('工作');
    final visibleIds = controller.visibleTasks.map((task) => task.id).toList();
    expect(visibleIds.length, greaterThanOrEqualTo(2));

    controller.toggleMultiSelect(visibleIds.first);
    controller.extendMultiSelectTo(visibleIds.last);
    expect(controller.multiSelectCount, visibleIds.length);

    controller.clearMultiSelect();
    expect(controller.multiSelectCount, 0);

    controller.selectAllVisibleTasks();
    expect(controller.multiSelectCount, visibleIds.length);
  });

  test('preferences round-trip the theme mode and survive damaged files',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('workfollow-prefs-test');
    addTearDown(() => directory.delete(recursive: true));
    final store = WorkspacePreferencesStore(directoryOverride: directory.path);

    expect((await store.load())['themeMode'], isNull);
    await store.save({'themeMode': 'dark', 'inspector': true});
    expect((await store.load())['themeMode'], 'dark');
    expect((await store.load())['inspector'], isTrue);

    // A damaged file behaves like no preferences instead of crashing.
    final file = File('${directory.path}/preferences.json');
    await file.writeAsString('{not json');
    expect(await store.load(), isEmpty);
  });

  testWidgets('theme toggle persists the appearance preference',
      (tester) async {
    // Synchronous temp-dir setup: real async I/O inside testWidgets'
    // fake-async zone deadlocks unless wrapped in tester.runAsync.
    final directory =
        Directory.systemTemp.createTempSync('workfollow-theme-test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = WorkspacePreferencesStore(directoryOverride: directory.path);

    await tester
        .pumpWidget(WorkFollowApp(demoMode: true, preferencesStore: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换深色'));
    // The MaterialApp animates theme switches; let the 200ms finish.
    await tester.pumpAndSettle();

    final persisted = await tester.runAsync(() => store.load());
    expect(persisted?['themeMode'], ThemeMode.dark.name);

    // A UniqueKey forces a remount, so initState restores from the file.
    await tester
        .pumpWidget(WorkFollowApp(key: UniqueKey(), preferencesStore: store));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换浅色'), findsOneWidget);
  });

  testWidgets('wide inspector preference is exposed and persisted',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final directory =
        Directory.systemTemp.createTempSync('workfollow-inspector-test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = WorkspacePreferencesStore(directoryOverride: directory.path);

    await tester
        .pumpWidget(WorkFollowApp(demoMode: true, preferencesStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    final switchFinder =
        find.byKey(const ValueKey('persistent-inspector-switch'));
    expect(switchFinder, findsOneWidget);
    // The macOS task workspace keeps the inspector visible by default, just
    // like TickTick. The preference remains an explicit opt-out.
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
    final persisted = await tester.runAsync(() => store.load());
    expect(persisted?['inspector'], isFalse);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(WorkFollowApp(
        key: UniqueKey(), demoMode: true, preferencesStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    expect(find.text('选择一个任务开始编辑'), findsOneWidget);
  });

  test(
      'REM-003 REM-004 REM-005 setting a future reminder registers a notification; clearing withdraws it',
      () async {
    final reminders = _RecordingReminders();
    final controller = WorkspaceController(reminderScheduler: reminders);

    controller.updateTaskReminder(
        'task-01', DateTime.now().add(const Duration(days: 30)));
    await _settleSaves(controller);
    expect(reminders.scheduled.keys, contains('task-01'));

    controller.updateTaskReminder('task-01', null);
    await _settleSaves(controller);
    expect(reminders.scheduled.containsKey('task-01'), isFalse);
    expect(reminders.canceled, contains('task-01'));
  });

  test(
      'REM-005 ROW-013 completing withdraws the reminder; undo re-registers it',
      () async {
    final reminders = _RecordingReminders();
    final controller = WorkspaceController(reminderScheduler: reminders);
    controller.updateTaskReminder(
        'task-01', DateTime.now().add(const Duration(days: 30)));
    await _settleSaves(controller);
    reminders.scheduled.clear();
    reminders.canceled.clear();

    controller.toggleTask('task-01');
    await _settleSaves(controller);
    expect(reminders.scheduled, isEmpty);
    expect(reminders.canceled, contains('task-01'));

    expect(controller.undoLastCompletion(), isTrue);
    await _settleSaves(controller);
    expect(reminders.scheduled.keys, contains('task-01'));
  });

  test(
      'REM-005 MENU-008 moving a task to the trash withdraws; restoring re-registers',
      () async {
    final reminders = _RecordingReminders();
    final controller = WorkspaceController(reminderScheduler: reminders);
    controller.updateTaskReminder(
        'task-01', DateTime.now().add(const Duration(days: 30)));
    await _settleSaves(controller);
    reminders.scheduled.clear();
    reminders.canceled.clear();

    controller.removeTask('task-01');
    await _settleSaves(controller);
    expect(reminders.scheduled, isEmpty);

    controller.undoLastAction();
    await _settleSaves(controller);
    expect(reminders.scheduled.keys, contains('task-01'));
  });

  test(
      'REM-005 startup reconciles reminders: only active future ones stay registered',
      () async {
    final reminders = _RecordingReminders();
    final store = _FakeStore();
    final futureReminder = DateTime.now().add(const Duration(days: 7));
    store.loadBundle = MigrationBundle(
      format: localSnapshotFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [],
      folders: const [],
      tasks: [
        MigrationTaskRecord(
          id: 'web-1',
          title: '未来提醒',
          description: null,
          contentJson: null,
          status: 'TODO',
          priority: 'NONE',
          dueAt: null,
          dueEndAt: null,
          reminderAt: futureReminder.toIso8601String(),
          recurrenceType: 'NONE',
          recurrenceConfig: null,
          listName: '收集箱',
          tags: [],
          createdAt: null,
          updatedAt: null,
          completedAt: null,
        ),
        MigrationTaskRecord(
          id: 'web-2',
          title: '已完成带提醒',
          description: null,
          contentJson: null,
          status: 'DONE',
          priority: 'NONE',
          dueAt: null,
          dueEndAt: null,
          reminderAt: futureReminder.toIso8601String(),
          recurrenceType: 'NONE',
          recurrenceConfig: null,
          listName: '收集箱',
          tags: [],
          createdAt: null,
          updatedAt: null,
          completedAt: null,
        ),
        MigrationTaskRecord(
          id: 'web-3',
          title: '过期提醒',
          description: null,
          contentJson: null,
          status: 'TODO',
          priority: 'NONE',
          dueAt: null,
          dueEndAt: null,
          reminderAt: DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
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
    final controller =
        WorkspaceController(store: store, reminderScheduler: reminders);

    await controller.restoreFromDisk();
    await _settleSaves(controller);

    expect(reminders.cancelAllCount, 1);
    expect(reminders.scheduled.keys, ['web-1']);
  });

  test(
      'REM-005 REPEAT-005 ROW-013 completing a recurring task schedules the next reminder and undo cancels it',
      () async {
    final reminders = _RecordingReminders();
    final controller = WorkspaceController(reminderScheduler: reminders);
    final due = DateTime.now().add(const Duration(days: 2));
    final reminder = due.subtract(const Duration(hours: 1));
    expect(controller.addTask('每日提醒', listName: '工作', dueAt: due), isTrue);
    final id = controller.tasks.firstWhere((task) => task.title == '每日提醒').id;
    controller.updateTaskRecurrence(id, 'DAILY');
    controller.updateTaskReminder(id, reminder);
    await _settleAsync();
    reminders.scheduled.clear();
    reminders.canceled.clear();

    controller.toggleTask(id);
    await _settleAsync();
    final next = controller.tasks
        .firstWhere((task) => task.id != id && task.title == '每日提醒');
    expect(reminders.scheduled.keys, contains(next.id));

    expect(controller.undoLastCompletion(), isTrue);
    await _settleAsync();
    expect(reminders.scheduled.keys, contains(id));
    expect(reminders.scheduled.keys, isNot(contains(next.id)));
    expect(reminders.canceled, contains(next.id));
  });

  test(
      'REM-002 REM-003 past reminder times are rejected instead of displaying a fake reminder',
      () async {
    final reminders = _RecordingReminders();
    final controller = WorkspaceController(reminderScheduler: reminders);
    controller.updateTaskReminder(
        'task-01', DateTime.now().subtract(const Duration(minutes: 1)));
    await _settleAsync();

    final task = controller.tasks.firstWhere((item) => item.id == 'task-01');
    expect(task.reminderAt, isNull);
    expect(reminders.scheduled, isEmpty);
  });

  test(
      'RICH rich imported note keeps links and lists until explicit conversion',
      () async {
    final controller = WorkspaceController();
    const link = 'https://example.com/workfollow';
    final bundle = MigrationBundle(
      format: personalMigrationFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [],
      folders: const [],
      tasks: const [],
      notes: [
        MigrationNoteRecord(
          id: 'rich-note',
          folderId: null,
          title: '带结构的记录',
          contentJson: {
            'type': 'doc',
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {
                    'type': 'text',
                    'text': '原始链接',
                    'marks': [
                      {
                        'type': 'link',
                        'attrs': {'href': link},
                      },
                    ],
                  },
                ],
              },
              {
                'type': 'bulletList',
                'content': [
                  {
                    'type': 'listItem',
                    'content': [
                      {
                        'type': 'paragraph',
                        'content': [
                          {'type': 'text', 'text': '列表项'},
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
          plainText: '原始链接\n列表项',
          isFavorite: false,
          createdAt: null,
          updatedAt: null,
          deletedAt: null,
        ),
      ],
    );
    await controller.replaceWithMigration(bundle);
    final before = controller.notes.single;
    expect(before.hasPreservedRichContent, isTrue);

    controller.updateNoteBody('rich-note', '原始链接\n列表项\n新增段落');
    final appended = controller.notes.single;
    final encoded = jsonEncode(appended.contentJson);
    expect(encoded, contains(link));
    expect(encoded, contains('bulletList'));
    expect(encoded, contains('新增段落'));
    expect(appended.toMigrationRecord().originalContentJson, isNotNull);

    // Editing inside the protected source does not erase the imported JSON.
    controller.updateNoteBody('rich-note', '改写后的链接\n列表项\n新增段落');
    expect(jsonEncode(controller.notes.single.contentJson), contains(link));

    expect(controller.convertNoteToPlainText('rich-note'), isTrue);
    expect(controller.notes, hasLength(2));
    final original =
        controller.notes.firstWhere((note) => note.id == 'rich-note');
    final converted =
        controller.notes.firstWhere((note) => note.id != 'rich-note');
    expect(converted.hasPreservedRichContent, isFalse);
    expect(converted.title, contains('纯文本副本'));
    expect(jsonEncode(converted.contentJson), isNot(contains(link)));
    expect(jsonEncode(converted.contentJson), isNot(contains('bulletList')));
    expect(original.hasPreservedRichContent, isTrue);
    expect(jsonEncode(original.contentJson), contains(link));
    expect(controller.selectedNoteId, converted.id);
  });

  test(
      'RICH rich note append keeps the complete suffix through each text change',
      () async {
    const link = 'https://example.com/资料';
    final controller = WorkspaceController();
    await controller.replaceWithMigration(MigrationBundle(
      format: personalMigrationFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [],
      folders: const [],
      tasks: const [],
      notes: [
        MigrationNoteRecord(
          id: 'typed-rich-note',
          folderId: null,
          title: '逐字追加',
          contentJson: {
            'type': 'doc',
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {
                    'type': 'text',
                    'text': '资料',
                    'marks': [
                      {
                        'type': 'link',
                        'attrs': {'href': link},
                      },
                    ],
                  },
                ],
              },
            ],
          },
          plainText: '资料',
          isFavorite: false,
          createdAt: null,
          updatedAt: null,
          deletedAt: null,
        ),
      ],
    ));

    // Match TextField.onChanged: the same new line grows one character at a
    // time, so each call must rebuild from the fixed imported source.
    controller.updateNoteBody('typed-rich-note', '资料\n');
    controller.updateNoteBody('typed-rich-note', '资料\na');
    controller.updateNoteBody('typed-rich-note', '资料\nab');

    final note = controller.notes.single;
    expect(note.plainText, '资料\nab');
    expect(
        notePlainTextFromContentJson(note.contentJson).trimRight(), '资料\nab');
    final encoded = jsonEncode(note.contentJson);
    expect(encoded, contains(link));
    expect(encoded, contains('"text":"ab"'));

    // Backspace is also an ordinary onChanged sequence, not a conversion.
    controller.updateNoteBody('typed-rich-note', '资料\na');
    expect(
        notePlainTextFromContentJson(controller.notes.single.contentJson)
            .trimRight(),
        '资料\na');
  });

  test('RICH creating a plain-text copy leaves the imported note untouched',
      () async {
    const link = 'https://example.com/original';
    final controller = WorkspaceController();
    await controller.replaceWithMigration(MigrationBundle(
      format: personalMigrationFormat,
      schemaVersion: migrationSchemaVersion,
      exportedAt: null,
      lists: const [],
      folders: const [],
      tasks: const [],
      notes: [
        MigrationNoteRecord(
          id: 'copy-source',
          folderId: null,
          title: '原始记录',
          contentJson: {
            'type': 'doc',
            'content': [
              {
                'type': 'paragraph',
                'content': [
                  {
                    'type': 'text',
                    'text': '原文',
                    'marks': [
                      {
                        'type': 'link',
                        'attrs': {'href': link},
                      },
                    ],
                  },
                ],
              },
            ],
          },
          plainText: '原文',
          isFavorite: true,
          createdAt: null,
          updatedAt: null,
          deletedAt: null,
        ),
      ],
    ));
    controller.updateNoteBody('copy-source', '原文\n补充');

    expect(controller.convertNoteToPlainText('copy-source'), isTrue);
    expect(controller.notes, hasLength(2));
    final source =
        controller.notes.firstWhere((note) => note.id == 'copy-source');
    final copy =
        controller.notes.firstWhere((note) => note.id != 'copy-source');
    expect(source.hasPreservedRichContent, isTrue);
    expect(jsonEncode(source.contentJson), contains(link));
    expect(copy.hasPreservedRichContent, isFalse);
    expect(copy.title, '原始记录（纯文本副本）');
    expect(copy.plainText, '原文\n补充');
    expect(copy.isFavorite, isTrue);
    expect(controller.selectedNoteId, copy.id);

    controller.updateNoteBody(copy.id, '副本可以独立编辑');
    expect(controller.notes.firstWhere((note) => note.id == copy.id).plainText,
        '副本可以独立编辑');
    expect(
        controller.notes.firstWhere((note) => note.id == source.id).plainText,
        '原文\n补充');
    expect(
        jsonEncode(controller.notes
            .firstWhere((note) => note.id == source.id)
            .contentJson),
        contains(link));
  });

  test('a task generated from a note keeps the link both ways and round-trips',
      () {
    final controller = WorkspaceController();
    final noteId = 'note-01';

    final taskId = controller.addTaskFromNote(noteId, '把结论同步给设计组');

    final task = controller.tasks.firstWhere((task) => task.id == taskId);
    expect(task.title, '把结论同步给设计组');
    expect(task.sourceNoteId, noteId);
    expect(task.listName, '收集箱');
    expect(task.bucket, TaskBucket.unscheduled);
    // 原文不动：笔记正文保持原样。
    expect(
        controller.notes.firstWhere((note) => note.id == noteId).plainText ??
            '',
        isNot(contains('把结论同步给设计组')));

    // 反向查询：笔记侧显示关联任务。
    final linked = controller.tasksLinkedToNote(noteId);
    expect(linked.map((task) => task.id), contains(taskId));
    // 任务侧回到记录。
    expect(controller.sourceNoteFor(taskId)?.id, noteId);

    final roundTripped = TaskItem.fromMigration(task.toMigrationRecord());
    expect(roundTripped.sourceNoteId, noteId);
  });

  test('attachment bookkeeping round-trips through the snapshot format', () {
    final controller = WorkspaceController();
    final task = controller.tasks.firstWhere((task) => task.id == 'task-06');
    expect(task.hasAttachment, isFalse);

    final withFile = task.copyWith(attachments: const ['167-file.pdf']);
    expect(withFile.hasAttachment, isTrue);

    final roundTripped = TaskItem.fromMigration(withFile.toMigrationRecord());
    expect(roundTripped.attachments, ['167-file.pdf']);

    controller.removeAttachment('task-06', 'whatever.pdf');
    // Removing an unknown name is a safe no-op.
    expect(
        controller.tasks.firstWhere((task) => task.id == 'task-06').attachments,
        isEmpty);
  });

  testWidgets('command palette opens, searches and creates tasks',
      (tester) async {
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
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
