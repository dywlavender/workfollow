import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/application/task_projection.dart';
import 'package:workfollow_personal/features/tasks/application/task_selection_controller.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

void main() {
  test('ARCH-002 ARCH-003 QUICK-017 TaskCreator submits one complete draft',
      () {
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

  test('ARCH-006 DATE-012 UNDO-001 action result owns destination and undo',
      () async {
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

  test(
      'ARCH-005 KEY-003 ROW-004 ROW-005 ROW-006 selection controller supports range and adjacent selection',
      () {
    final selection = TaskSelectionController();
    selection.select('b');
    selection.toggleMulti('b');
    selection.extendTo('d', ['a', 'b', 'c', 'd', 'e']);
    expect(selection.multiSelectedTaskIds, {'b', 'c', 'd'});
    expect(selection.adjacent('d', 1, ['a', 'b', 'c', 'd', 'e']), 'e');
    expect(selection.multiSelectedTaskIds, isEmpty);
  });

  test('ARCH-009 ROW-001 opening a task clears stale bulk selection', () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('第一个任务');
    controller.addTask('第二个任务');
    final firstId = controller.tasks[0].id;
    final secondId = controller.tasks[1].id;

    controller.toggleMultiSelect(secondId);
    expect(controller.multiSelectedTaskIds, {secondId});

    controller.openTask(firstId);
    expect(controller.selectedTaskId, firstId);
    expect(controller.multiSelectedTaskIds, isEmpty);
  });

  test(
      'ARCH-004 DATE-013 LIST-004 TAG-003 projection keeps smart-list rules in one pure object',
      () {
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
    expect(
        projection.visible(tasks: tasks, view: 'overdue').single.id, 'overdue');
    expect(projection.count(tasks: tasks, view: 'today'), 2);
  });

  test(
      'ARCH-002 DATE-007 DATE-008 REPEAT-002 REPEAT-003 drafts keep explicit time and valid rules',
      () {
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

  test(
      'ARCH-001 ARCH-007 UNDO-004 BULK-001 setter actions expose snapshot undo and bulk no-op',
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

  test('MENU-007 duplicate returns one concise originating-surface feedback',
      () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('可复制任务');
    final sourceId = controller.tasks.single.id;

    final result = controller.taskActions.duplicate(sourceId);

    expect(result.success, isTrue);
    expect(result.showFeedback, isTrue);
    expect(controller.tasks, hasLength(2));
    expect(controller.tasks.first.title, '可复制任务（副本）');
    controller.dispose();
  });

  test('UNDO-001 creating in the current projection exposes global undo', () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final created = controller.createTask(const TaskDraft(title: '可撤销新增'));

    expect(created.success, isTrue);
    expect(created.undo, isNotNull);
    expect(controller.actionVersion, 1);
    expect(controller.taskActions.undo().success, isTrue);
    expect(controller.tasks, isEmpty);
  });

  test('DATE-008 clearing an empty schedule never leaves a time-only task', () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('待安排', forceUnscheduled: true);
    final id = controller.tasks.single.id;

    final result = controller.taskActions
        .setSchedule(id, const TaskScheduleDraft(dueAt: null, hasTime: true));

    expect(result.success, isFalse);
    expect(controller.tasks.single.dueAt, isNull);
    expect(controller.tasks.single.hasDueTime, isFalse);
    controller.dispose();
  });

  test(
      'DOCUMENT-001 setContent keeps a structured document and plain projection',
      () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('文档任务');
    final id = controller.tasks.single.id;
    final content = {
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': '带链接',
              'marks': [
                {
                  'type': 'link',
                  'attrs': {'href': 'https://example.com'}
                }
              ]
            }
          ]
        }
      ],
      'quillDelta': [
        {
          'insert': '带链接',
          'attributes': {'link': 'https://example.com'}
        },
        {'insert': '\n'}
      ],
    };

    final result = controller.taskActions.setContent(id, content, '带链接');
    expect(result.success, isTrue);
    expect(controller.tasks.single.contentJson?['quillDelta'], isNotNull);
    expect(controller.tasks.single.description, '带链接');
    expect(controller.tasks.single.note, '带链接');
    expect(result.undo, isNotNull);
  });

  test('DOCUMENT-002 source note relation is an action-scoped mutation', () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('关联任务');
    final id = controller.tasks.single.id;
    final noteId = controller.addNote(title: '关联原文');

    final linked = controller.taskActions.setSourceNote(id, noteId);
    expect(linked.success, isTrue);
    expect(controller.tasks.single.sourceNoteId, noteId);
    expect(controller.sourceNoteFor(id)?.id, noteId);

    expect(controller.taskActions.undo().success, isTrue);
    expect(controller.tasks.single.sourceNoteId, isNull);
  });

  test('DATE-009 DEADLINE-003 REPEAT-004 clear actions remove their property',
      () {
    final controller = WorkspaceController(seedData: false);
    final due = DateTime.now().add(const Duration(days: 2));
    controller.addTask('清理属性', dueAt: due, hasTime: true);
    final id = controller.tasks.single.id;
    final reminder = DateTime.now().add(const Duration(hours: 2));
    controller.updateTaskReminder(id, reminder);
    controller.updateTaskRecurrence(id, 'DAILY');
    controller.updateTaskDeadline(id, due.add(const Duration(days: 1)));

    expect(controller.taskActions.clearSchedule(id).success, isTrue);
    expect(controller.taskActions.clearReminder(id).success, isTrue);
    expect(controller.taskActions.clearRecurrence(id).success, isTrue);
    expect(controller.taskActions.clearDeadline(id).success, isTrue);

    final task = controller.tasks.single;
    expect(task.dueAt, isNull);
    expect(task.hasDueTime, isFalse);
    expect(task.reminderAt, isNull);
    expect(task.recurrenceType, 'NONE');
    expect(task.deadlineAt, isNull);
    controller.dispose();
  });

  test('QUICK-022 invalid creation keeps the draft boundary side-effect free',
      () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);

    final empty = controller.createTask(const TaskDraft(title: '   '));
    expect(empty.success, isFalse);
    expect(empty.error?.code, 'empty-title');
    expect(controller.tasks, isEmpty);

    final valid = controller.createTask(const TaskDraft(title: '保留原任务'));
    expect(valid.success, isTrue);
    final id = valid.taskId!;
    final before = controller.tasks.single.reminderAt;
    final past = controller.taskActions
        .setReminder(id, DateTime.now().subtract(const Duration(minutes: 1)));
    expect(past.success, isFalse);
    expect(past.error?.code, 'past-reminder');
    expect(controller.tasks.single.reminderAt, before);
  });

  test(
      'QUICK-021 smart capture returns an ActionResult and global Undo restores properties',
      () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);

    final created = controller.createTaskFromSmartInput(
      '明天 #工作 !!!准备评审',
      now: DateTime(2030, 1, 10, 9),
    );
    expect(created.success, isTrue);
    final id = created.taskId!;
    expect(controller.tasks.single.title, '准备评审');
    expect(controller.tasks.single.tags, ['工作']);
    expect(controller.tasks.single.priority, TaskPriority.high);

    final changed = controller.taskActions.setPriority(id, TaskPriority.low);
    expect(changed.success, isTrue);
    expect(controller.tasks.single.priority, TaskPriority.low);
    expect(controller.taskActions.undo().success, isTrue);
    expect(controller.tasks.single.priority, TaskPriority.high);
  });

  test('UNDO-001 completion undo keeps its own command after a later edit', () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('完成后继续编辑');
    final id = controller.tasks.single.id;

    final completed = controller.taskActions.complete(id);
    expect(completed.success, isTrue);
    expect(controller.tasks.single.completed, isTrue);

    // The global undo slot now belongs to the later property action. The
    // completion result itself remains a stable, action-scoped command.
    controller.taskActions.setPriority(id, TaskPriority.high);
    expect(controller.taskActions.undo().success, isTrue);
    expect(controller.tasks.single.priority, TaskPriority.none);
    expect(controller.tasks.single.completed, isTrue);

    expect(completed.undo, isNotNull);
    expect(completed.undo!.execute(), isTrue);
    expect(controller.tasks.single.completed, isFalse);
  });

  test('UNDO-001 delete undo restores the deleted snapshot', () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('可撤销删除');
    final id = controller.tasks.single.id;

    final deleted = controller.taskActions.delete(id);
    expect(deleted.success, isTrue);
    expect(controller.tasks.single.deletedAt, isNotNull);
    expect(controller.taskActions.undo().success, isTrue);
    expect(controller.tasks.single.deletedAt, isNull);
    expect(controller.selectedTaskId, id);
  });
}
