import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

void main() {
  test(
      'QUICK-004 QUICK-005 QUICK-006 QUICK-007 QUICK-008 QUICK-009 REM-006 smart capture applies title, date, list, tag, priority and recurrence together',
      () {
    final controller = WorkspaceController(seedData: false);
    final now = DateTime.now();
    expect(controller.addTaskFromSmartInput(
        '每天 明早9点 #工作 @个人 !!!准备评审', now: now),
        isTrue);
    final task = controller.tasks.single;
    expect(task.title, '准备评审');
    expect(task.listName, '个人');
    expect(task.tags, ['工作']);
    expect(task.priority, TaskPriority.high);
    expect(task.recurrenceType, 'DAILY');
    expect(task.scheduledWithTime, isTrue);
    expect(task.reminderAt, isNotNull);
    expect(localDateTimeFromStorage(task.dueAt)!.day,
        now.add(const Duration(days: 1)).day);
    controller.dispose();
  });

  test(
      'TAG-003 PRIORITY-004 tag filtering and list colors stay in the controller projection',
      () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('写提案', listName: '工作');
    final firstId = controller.tasks.first.id;
    controller.updateTaskTags(firstId, ['项目']);
    controller.addTask('买菜', listName: '个人');

    expect(controller.allTags(), {'项目': 1});
    controller.selectTag('项目');
    expect(controller.viewTitle, '标签：项目');
    expect(controller.visibleTasks.map((task) => task.title), ['写提案']);

    final before = controller.colorValueForList('工作');
    expect(controller.updateListColor('工作', '#22AA66'), isTrue);
    expect(controller.colorValueForList('工作'), isNot(before));
    expect(
        controller.snapshot.lists.firstWhere((list) => list.name == '工作').color,
        '#22AA66');
    controller.dispose();
  });

  test(
      'QUICK-008 unknown smart-entry lists are kept in the title instead of created',
      () {
    final controller = WorkspaceController(seedData: false);
    expect(controller.addTaskFromSmartInput('整理资料 @不存在清单'), isTrue);
    expect(controller.tasks.single.title, '整理资料 @不存在清单');
    expect(controller.lists.any((list) => list.name == '不存在清单'), isFalse);
    controller.dispose();
  });

  test('QUICK-008 unknown-only smart-entry markers remain a usable title', () {
    final controller = WorkspaceController(seedData: false);
    expect(controller.addTaskFromSmartInput('@稍后再分清单'), isTrue);
    expect(controller.tasks.single.title, '@稍后再分清单');
    expect(controller.tasks.single.listName, '收集箱');
    controller.dispose();
  });

  test(
      'PRIORITY-004 matrix projection classifies urgency and preserves priority on today drop',
      () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('季度计划', listName: '工作');
    final id = controller.tasks.single.id;
    controller.updateTaskPriority(id, TaskPriority.high);
    final later = DateTime.now().add(const Duration(days: 12));
    controller.updateTaskDue(id, later, hasTime: false);
    expect(controller.matrixQuadrantFor(controller.tasks.single),
        MatrixQuadrant.schedule);
    controller.moveTaskToMatrix(id, MatrixQuadrant.doNow);
    final task = controller.tasks.single;
    expect(task.priority, TaskPriority.high);
    expect(localDateTimeFromStorage(task.dueAt)!.day, DateTime.now().day);
    controller.dispose();
  });

  test('focus sessions accumulate on the task and in the snapshot', () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('专注写作');
    final taskId = controller.tasks.single.id;
    controller.recordFocusSession(taskId);
    expect(controller.tasks.single.focusCount, 1);
    expect(controller.snapshot.tasks.single.focusCount, 1);
    controller.dispose();
  });

  test('pinned lists stay ordered and survive renaming', () {
    final controller = WorkspaceController(seedData: false);
    controller.toggleListPinned('个人');
    controller.updateListColor('个人', '#22AA66');
    expect(controller.orderedLists.first.name, '个人');
    expect(controller.orderedLists.first.color, '#22AA66');
    expect(controller.renameList('个人', '生活'), isTrue);
    expect(controller.orderedLists.first.name, '生活');
    expect(controller.orderedLists.first.pinned, isTrue);
    controller.dispose();
  });

  test(
      'DATE-007 QUICK-017 quick task creation preserves an explicit clock time',
      () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('预约',
        dueAt: DateTime(2099, 9, 15, 9, 30), hasTime: true);
    expect(controller.tasks.single.scheduledWithTime, isTrue);
    expect(controller.tasks.single.displayTimeLabel, contains('09:30'));
    controller.dispose();
  });

  test(
      'ARCH-004 DATE-013 recent and overdue smart lists project real due dates',
      () {
    final controller = WorkspaceController(seedData: false);
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    controller.addTask('已过期',
        dueAt: start.subtract(const Duration(days: 20)), hasTime: false);
    controller.addTask('今天', dueAt: start, hasTime: false);
    controller.addTask('本周内',
        dueAt: start.add(const Duration(days: 3)), hasTime: false);
    controller.addTask('更远的未来',
        dueAt: start.add(const Duration(days: 14)), hasTime: false);

    controller.selectView(WorkspaceView.recent);
    expect(controller.visibleTasks.map((task) => task.title),
        containsAll(<String>['已过期', '今天', '本周内']));
    expect(controller.visibleTasks.map((task) => task.title),
        isNot(contains('更远的未来')));
    expect(controller.countFor(WorkspaceView.recent), 3);

    controller.selectView(WorkspaceView.overdue);
    expect(controller.visibleTasks.map((task) => task.title), ['已过期']);
    expect(controller.viewTitle, '过期');
    controller.dispose();
  });

  test('ROW-004 task selection follows the visible list with arrow navigation',
      () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('第一件');
    controller.addTask('第二件');
    controller.addTask('第三件');
    controller.selectView(WorkspaceView.inbox);
    final first = controller.visibleTasks.first.id;
    controller.selectTask(first);
    controller.selectAdjacentTask(first, 1);
    expect(controller.selectedTask?.title, '第二件');
    controller.selectAdjacentTask(controller.selectedTask!.id, -1);
    expect(controller.selectedTask?.title, '第三件');
    controller.dispose();
  });
}
