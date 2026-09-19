import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/services/notification_service.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

/// S7: parent/child business rules and smart-list projection.
void main() {
  WorkspaceController build() => WorkspaceController(seedData: false);

  test('SUB-080 completing a child leaves the parent and siblings alone', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.createChildTask(parentId, title: '乙')!;
    c.taskActions.complete(a);
    expect(c.tasks.firstWhere((t) => t.id == a).completed, isTrue);
    expect(c.tasks.firstWhere((t) => t.id == parentId).completed, isFalse);
    expect(c.completedChildCount(parentId), 1);
  });

  test('SUB-081 completing a parent does not touch the children', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    final b = c.createChildTask(parentId, title: '乙')!;
    c.taskActions.complete(parentId);
    expect(c.tasks.firstWhere((t) => t.id == parentId).completed, isTrue);
    expect(c.tasks.firstWhere((t) => t.id == a).completed, isFalse);
    expect(c.tasks.firstWhere((t) => t.id == b).completed, isFalse);
  });

  test('SUB-083 deleting a parent cascade soft-deletes its children', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.createChildTask(parentId, title: '乙')!;
    final parentStamp = DateTime.now().toIso8601String();
    c.taskActions.delete(parentId);
    expect(c.tasks.firstWhere((t) => t.id == parentId).deletedAt, isNotNull);
    final child = c.tasks.firstWhere((t) => t.id == a);
    expect(child.deletedAt, isNotNull);
    // Same-stamp cascade: trash keeps the grouping restorable.
    expect(child.deletedAt, isNot(parentStamp));
    expect(child.deletedAt!.substring(0, 10),
        DateTime.now().toIso8601String().substring(0, 10));
    expect(c.childCount(parentId), 0);
  });

  test('SUB-070/083 restoring a parent revives exactly the cascade', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    final b = c.createChildTask(parentId, title: '乙')!;
    // B was deleted on its own BEFORE the parent cascade.
    c.taskActions.delete(b);
    await_.delayed(const Duration(milliseconds: 5));
    c.taskActions.delete(parentId);
    c.restoreTask(parentId);
    expect(c.tasks.firstWhere((t) => t.id == parentId).deletedAt, isNull);
    expect(c.tasks.firstWhere((t) => t.id == a).deletedAt, isNull,
        reason: 'cascade child comes back with the parent');
    expect(c.tasks.firstWhere((t) => t.id == b).deletedAt, isNotNull,
        reason: 'an independently deleted child stays in the trash');
  });

  test('SUB-084/123 moving a parent moves its active children', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    c.addList('个人');
    final a = c.createChildTask(parentId, title: '甲')!;
    c.taskActions.moveToList(parentId, '个人');
    expect(c.tasks.firstWhere((t) => t.id == parentId).listName, '个人');
    expect(c.tasks.firstWhere((t) => t.id == a).listName, '个人');
  });

  test('SUB-086/087 a child with its own date projects into Today alone', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.taskActions.setSchedule(
        a, TaskScheduleDraft(dueAt: DateTime.now(), hasTime: false));
    c.selectView(WorkspaceView.today);
    // The parent has no date and the child matches today: the child becomes
    // a projection root instead of disappearing behind its parent.
    expect(c.visibleTasks.map((t) => t.id), contains(a));
  });

  test(
      'SUB-088 when parent and child both match, the child renders nested once',
      () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.taskActions.setSchedule(
        a, TaskScheduleDraft(dueAt: DateTime.now(), hasTime: false));
    c.taskActions.setSchedule(
        parentId, TaskScheduleDraft(dueAt: DateTime.now(), hasTime: false));
    c.selectView(WorkspaceView.today);
    // The flat list carries the parent only; the child renders nested.
    expect(c.visibleTasks.where((t) => t.id == parentId), hasLength(1));
    expect(c.visibleTasks.where((t) => t.id == a), isEmpty);
    expect(c.childRowsFor(parentId).map((t) => t.id), [a]);
  });

  test('SUB-089 an overdue child enters Overdue on its own dates', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.taskActions.setSchedule(
        a, TaskScheduleDraft(dueAt: DateTime(2020, 1, 1), hasTime: false));
    c.selectView(WorkspaceView.overdue);
    expect(c.visibleTasks.map((t) => t.id), contains(a));
  });

  test('SUB-090 Completed projects by each task own completed flag', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.taskActions.complete(a);
    c.selectView(WorkspaceView.completed);
    expect(c.visibleTasks.map((t) => t.id), contains(a));
    expect(c.visibleTasks.map((t) => t.id), isNot(contains(parentId)));
  });

  test('SUB-091 the calendar reads a child own dueAt', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final childId = c.createChildTask(c.tasks.single.id)!;
    final day = DateTime(2030, 5, 18);
    c.taskActions.setScheduleSettings(
        childId,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(dueAt: day, hasTime: false)));
    expect(c.tasksForDay(day).map((t) => t.id), contains(childId));
  });

  test('SUB-094 a list view shows every child of an expanded parent', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    c.createChildTask(parentId, title: '甲');
    final b = c.createChildTask(parentId, title: '乙')!;
    c.taskActions.setSchedule(
        b, TaskScheduleDraft(dueAt: DateTime(2030, 1, 1), hasTime: false));
    c.selectView(WorkspaceView.all);
    c.childRowsFor(parentId);
    expect(c.childRowsFor(parentId).length, 2);
  });

  test('SUB-121/122 a child refuses a standalone list move in TaskActions', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.addList('个人');
    final result = c.taskActions.moveToList(a, '个人');
    expect(result.success, isFalse);
    expect(result.error?.code, 'child-list-move-not-supported');
    // The child stays on its parent's list.
    expect(c.tasks.firstWhere((t) => t.id == a).listName,
        c.tasks.firstWhere((t) => t.id == parentId).listName);
  });

  test('SUB-096 bulk move skips standalone children and cascades parents', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    c.addTask('独立任务');
    final rootId = c.tasks.firstWhere((t) => t.id != parentId).id;
    c.addList('个人');
    final childId = c.createChildTask(parentId, title: '甲')!;
    // A child-only bulk selection must not split the tree.
    c.taskActions.bulkMove([childId], '个人');
    expect(c.tasks.firstWhere((t) => t.id == childId).listName, isNot('个人'));
    // Selected roots move; a selected parent carries its active children.
    c.taskActions.bulkMove([parentId, rootId], '个人');
    expect(c.tasks.firstWhere((t) => t.id == parentId).listName, '个人');
    expect(c.tasks.firstWhere((t) => t.id == rootId).listName, '个人');
    expect(c.tasks.firstWhere((t) => t.id == childId).listName, '个人');
  });

  test('SUB-125/126 purging a parent removes its children from the trash too',
      () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    final b = c.createChildTask(parentId, title: '乙')!;
    // B was trashed on its own before the parent cascade.
    c.taskActions.delete(b);
    await_.delayed(const Duration(milliseconds: 5));
    c.taskActions.delete(parentId);
    expect(c.deletedTasks.map((t) => t.id), containsAll([parentId, a, b]));
    c.purgeTask(parentId);
    final remaining = c.tasks.map((t) => t.id).toSet();
    expect(remaining, isNot(contains(parentId)));
    expect(remaining, isNot(contains(a)),
        reason: 'the cascade child is destroyed with its parent');
    expect(remaining, isNot(contains(b)),
        reason:
            'an independently trashed child still cannot outlive its parent');
    // SUB-126: no orphan survives pointing at the purged parent.
    expect(c.tasks.where((t) => t.parentTaskId == parentId), isEmpty);
  });

  test('SUB-124 purging a standalone child leaves the parent alone', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    c.taskActions.delete(a);
    c.purgeTask(a);
    expect(c.tasks.map((t) => t.id), isNot(contains(a)));
    expect(c.tasks.map((t) => t.id), contains(parentId));
    expect(c.childCount(parentId), 0);
  });

  test('SUB-127 purging a parent withdraws parent and child reminders', () {
    final reminders = _RecordingReminders();
    final c =
        WorkspaceController(seedData: false, reminderScheduler: reminders);
    addTearDown(c.dispose);
    c.addTask('父任务');
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId, title: '甲')!;
    final when = DateTime.now().add(const Duration(hours: 2));
    c.updateTaskReminder(parentId, when);
    c.updateTaskReminder(childId, when);
    c.taskActions.delete(parentId);
    c.purgeTask(parentId);
    expect(reminders.canceled, containsAll([parentId, childId]));
  });

  test('SUB-128 a purged subtree cannot be restored', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '甲')!;
    final b = c.createChildTask(parentId, title: '乙')!;
    c.taskActions.delete(parentId);
    c.purgeTask(parentId);
    // The rows are gone, so trash restore is a silent no-op.
    c.restoreTask(parentId);
    c.restoreTask(a);
    c.restoreTask(b);
    expect(c.tasks.map((t) => t.id), isNot(contains(parentId)));
    expect(c.tasks.map((t) => t.id), isNot(contains(a)));
    expect(c.tasks.map((t) => t.id), isNot(contains(b)));
    expect(c.deletedTasks, isEmpty);
  });

  test('SUB-130 a recurring parent carries its children into the next cycle',
      () {
    final c = build();
    addTearDown(c.dispose);
    final created = c.createTask(TaskDraft(
        title: '每周回顾',
        schedule:
            TaskScheduleDraft(dueAt: DateTime(2026, 9, 21), hasTime: false),
        recurrence: const RecurrenceDraft(type: 'WEEKLY')));
    final parentId = created.taskId!;
    final done = c.createChildTask(parentId, title: '已完成项')!;
    final open = c.createChildTask(parentId, title: '未完成项')!;
    c.taskActions.complete(done);
    c.taskActions.setSchedule(
        open, TaskScheduleDraft(dueAt: DateTime(2026, 9, 22), hasTime: false));
    c.taskActions.complete(parentId);
    // The historical record keeps its children but stops recurring.
    final old = c.tasks.firstWhere((t) => t.id == parentId);
    expect(old.completed, isTrue);
    expect(old.recurrenceType.toUpperCase(), 'NONE');
    expect(c.childrenOf(parentId).length, 2);
    // The next occurrence is a fresh root carrying the rule and the whole
    // checklist, reset to incomplete.
    final spawn = c.tasks.singleWhere((t) =>
        t.id != parentId &&
        !t.isChildTask &&
        t.recurrenceType.toUpperCase() == 'WEEKLY');
    expect(spawn.completed, isFalse);
    expect(c.childrenOf(spawn.id).map((t) => t.title), ['已完成项', '未完成项']);
    for (final carried in c.childrenOf(spawn.id)) {
      expect(carried.completed, isFalse, reason: carried.title);
      expect(carried.completedAt, isNull);
      expect(carried.recurrenceType.toUpperCase(), 'NONE');
    }
    // A dated child rides the same recurrence delta as the parent (+7 days).
    final carriedOpen =
        c.childrenOf(spawn.id).firstWhere((task) => task.title == '未完成项');
    expect(DateTime.parse(carriedOpen.dueAt!),
        DateTime.parse(spawn.dueAt!).add(const Duration(days: 1)));
    // The undated child stays undated.
    final carriedDone =
        c.childrenOf(spawn.id).firstWhere((task) => task.title == '已完成项');
    expect(carriedDone.dueAt, isNull);
  });

  test('SUB-131 undoing the completion removes the carried children too', () {
    final c = build();
    addTearDown(c.dispose);
    final created = c.createTask(TaskDraft(
        title: '每周回顾',
        schedule:
            TaskScheduleDraft(dueAt: DateTime(2026, 9, 21), hasTime: false),
        recurrence: const RecurrenceDraft(type: 'WEEKLY')));
    final parentId = created.taskId!;
    c.createChildTask(parentId, title: '甲');
    c.createChildTask(parentId, title: '乙');
    c.taskActions.complete(parentId);
    final spawn = c.tasks.singleWhere((t) =>
        t.id != parentId &&
        !t.isChildTask &&
        t.recurrenceType.toUpperCase() == 'WEEKLY');
    expect(c.undoLastAction(), isTrue);
    expect(c.tasks.any((t) => t.id == spawn.id), isFalse);
    expect(c.tasks.where((t) => t.parentTaskId == spawn.id), isEmpty);
    final parent = c.tasks.firstWhere((t) => t.id == parentId);
    expect(parent.recurrenceType.toUpperCase(), 'WEEKLY');
    expect(parent.completed, isFalse);
    expect(c.childrenOf(parentId).length, 2);
  });

  test('SUB-132 a recurring child repeats inside its parent', () {
    final c = build()..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId, title: '每日打卡')!;
    c.taskActions.setSchedule(childId,
        TaskScheduleDraft(dueAt: DateTime(2026, 9, 21), hasTime: false));
    c.updateTaskRecurrence(childId, 'DAILY');
    c.taskActions.complete(childId);
    // The next occurrence is born a child of the same parent, not a root.
    final respawn = c.tasks
        .singleWhere((t) => t.parentTaskId == parentId && t.id != childId);
    expect(respawn.completed, isFalse);
    expect(respawn.isChildTask, isTrue);
    expect(respawn.recurrenceType.toUpperCase(), 'DAILY');
    // The old record stays completed inside the parent.
    expect(c.tasks.firstWhere((t) => t.id == childId).completed, isTrue);
  });
}

/// Records reminder withdrawals so purge tests can assert the controller
/// actually cancels notifications instead of leaving them registered.
class _RecordingReminders extends NotificationService {
  final canceled = <String>[];
  @override
  Future<void> cancel(String taskId) async {
    canceled.add(taskId);
  }
}

// tiny shim so the cascade test can let the clock tick between deletes
class await_ {
  static Future<void> delayed(Duration d) => Future<void>.delayed(d);
}
