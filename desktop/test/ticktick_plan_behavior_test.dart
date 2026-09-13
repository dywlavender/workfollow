import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';

void main() {
  test('smart capture applies title, date, list, tag and priority together', () {
    final controller = WorkspaceController(seedData: false);
    final now = DateTime.now();
    expect(
        controller.addTaskFromSmartInput('明早9点 #工作 @个人 !!!准备评审', now: now),
        isTrue);
    final task = controller.tasks.single;
    expect(task.title, '准备评审');
    expect(task.listName, '个人');
    expect(task.tags, ['工作']);
    expect(task.priority, TaskPriority.high);
    expect(task.scheduledWithTime, isTrue);
    expect(task.reminderAt, isNotNull);
    expect(localDateTimeFromStorage(task.dueAt)!.day,
        now.add(const Duration(days: 1)).day);
    controller.dispose();
  });

  test('tag filtering and list colors stay in the controller projection', () {
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
    expect(controller.snapshot.lists
        .firstWhere((list) => list.name == '工作')
        .color, '#22AA66');
    controller.dispose();
  });

  test('unknown smart-entry lists are kept in the title instead of created', () {
    final controller = WorkspaceController(seedData: false);
    expect(controller.addTaskFromSmartInput('整理资料 @不存在清单'), isTrue);
    expect(controller.tasks.single.title, '整理资料 @不存在清单');
    expect(controller.lists.any((list) => list.name == '不存在清单'), isFalse);
    controller.dispose();
  });

  test('unknown-only smart-entry markers remain a usable title', () {
    final controller = WorkspaceController(seedData: false);
    expect(controller.addTaskFromSmartInput('@稍后再分清单'), isTrue);
    expect(controller.tasks.single.title, '@稍后再分清单');
    expect(controller.tasks.single.listName, '收集箱');
    controller.dispose();
  });

  test('matrix projection classifies urgency and preserves priority on today drop', () {
    final controller = WorkspaceController(seedData: false);
    controller.addTask('季度计划', listName: '工作');
    final id = controller.tasks.single.id;
    controller.updateTaskPriority(id, TaskPriority.high);
    final later = DateTime.now().add(const Duration(days: 12));
    controller.updateTaskDue(id, later, hasTime: false);
    expect(controller.matrixQuadrantFor(controller.tasks.single), MatrixQuadrant.schedule);
    controller.moveTaskToMatrix(id, MatrixQuadrant.doNow);
    final task = controller.tasks.single;
    expect(task.priority, TaskPriority.high);
    expect(localDateTimeFromStorage(task.dueAt)!.day, DateTime.now().day);
    controller.dispose();
  });
}
