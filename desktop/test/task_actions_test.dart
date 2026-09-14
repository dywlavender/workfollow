import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/application/task_projection.dart';
import 'package:workfollow_personal/features/tasks/application/task_selection_controller.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

void main() {
  test('TaskCreator submits one complete draft', () {
    final controller = WorkspaceController(seedData: false);
    final due = DateTime.now().add(const Duration(days: 2, hours: 3));
    final result = controller.createTask(TaskDraft(
      title: '完整草稿',
      listName: '工作',
      schedule: TaskScheduleDraft(dueAt: due, hasTime: true),
      reminderAt: due.add(const Duration(minutes: 5)),
      recurrence: const RecurrenceDraft(type: 'WEEKLY', config: {'weekday': 2}),
      priority: TaskPriority.high,
      tags: const ['项目', '项目'],
      description: '一次创建完成',
    ));

    expect(result.success, isTrue);
    expect(result.taskId, isNotNull);
    final task = controller.tasks.single;
    expect(task.title, '完整草稿');
    expect(task.listName, '工作');
    expect(task.priority, TaskPriority.high);
    expect(task.tags, ['项目']);
    expect(task.description, '一次创建完成');
    expect(task.recurrenceType, 'WEEKLY');
    expect(task.dueAt, isNotNull);
    expect(task.reminderAt, isNotNull);
    controller.dispose();
  });

  test('action result owns destination and undo instead of row projection logic', () async {
    final controller = WorkspaceController(seedData: false);
    controller.selectView(WorkspaceView.today);
    controller.addTask('待完成');
    final id = controller.tasks.single.id;
    final result = controller.taskActions.complete(id);
    expect(result.success, isTrue);
    expect(result.taskId, id);
    expect(result.undo, isNotNull);
    expect(result.message, contains('完成'));
    expect(controller.tasks.single.completed, isTrue);
    expect(await result.undo!.execute(), isTrue);
    controller.dispose();
  });

  test('selection controller supports range and adjacent selection independently', () {
    final selection = TaskSelectionController();
    selection.select('b');
    selection.toggleMulti('b');
    selection.extendTo('d', ['a', 'b', 'c', 'd', 'e']);
    expect(selection.multiSelectedTaskIds, {'b', 'c', 'd'});
    expect(selection.adjacent('d', 1, ['a', 'b', 'c', 'd', 'e']), 'e');
    expect(selection.multiSelectedTaskIds, isEmpty);
  });

  test('projection keeps smart-list rules in one pure object', () {
    final now = DateTime(2030, 1, 10, 9);
    final projection = TaskProjection(clock: () => now);
    TaskItem task(String id, DateTime? due) => TaskItem(
          id: id,
          title: id,
          listName: '收集箱',
          bucket: taskBucketForDate(due, now: now),
          dueAt: due?.toIso8601String(),
        );
    final tasks = [
      task('overdue', DateTime(2030, 1, 9)),
      task('today', now),
      task('future', DateTime(2030, 1, 20)),
    ];
    expect(
        projection.visible(tasks: tasks, view: 'recent').map((item) => item.id),
        ['overdue', 'today']);
    expect(projection.visible(tasks: tasks, view: 'overdue').single.id,
        'overdue');
    expect(projection.count(tasks: tasks, view: 'today'), 2);
  });

  test('schedule and recurrence drafts keep explicit time and valid rules', () {
    final clock = DateTime(2030, 1, 10, 9, 30);
    final schedule = TaskScheduleDraft.forDay(clock,
        preserveClock: DateTime(2029, 12, 1, 23, 45), hasTime: true);
    expect(schedule.normalizedDueAt, DateTime(2030, 1, 10, 23, 45));
    expect(const RecurrenceDraft(type: 'WEEKLY').normalized().type, 'WEEKLY');
    expect(
        const RecurrenceDraft(type: 'WEEKLY', config: {'weekday': 8})
            .normalized()
            .type,
        'NONE');
    expect(
        const RecurrenceDraft(type: 'MONTHLY', config: {'dayOfMonth': 31})
            .normalized()
            .config,
        {'dayOfMonth': 31});
  });

  test('setter actions expose a snapshot undo and bulk actions report no-op',
      () async {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('可编辑', listName: '收集箱');
    final id = controller.tasks.single.id;
    final result = controller.taskActions.setPriority(id, TaskPriority.high);
    expect(result.success, isTrue);
    expect(result.undo, isNotNull);
    expect(controller.tasks.single.priority, TaskPriority.high);
    expect(await result.undo!.execute(), isTrue);
    expect(controller.tasks.single.priority, TaskPriority.none);
    final noOp = controller.taskActions.bulkComplete(const <String>[]);
    expect(noOp.success, isFalse);
    controller.dispose();
  });
}
