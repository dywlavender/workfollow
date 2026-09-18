import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

void main() {
  test('SUB-001/003 creating a child allows an empty title and orders siblings',
      () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parent = c.tasks.single;
    final first = c.createChildTask(parent.id)!;
    final second = c.createChildTask(parent.id, title: '  ')!;

    final children = c.childrenOf(parent.id);
    expect(children.map((task) => task.id), [first, second]);
    expect(children.first.childOrder, 0);
    expect(children.last.childOrder, 1);
    expect(children.every((task) => task.title.isEmpty), isTrue);
    expect(children.every((task) => task.listName == parent.listName), isTrue);
    expect(c.parentOf(children.first.id)!.id, parent.id);
    expect(c.hasChildren(parent.id), isTrue);
    expect(c.taskUiState.pendingChildFocusTaskId, second);
    // The parent keeps the selection so the panel shows the new row.
    expect(c.selectedTaskId, parent.id);
  });

  test('S1 a plain task has no parent and three children order 0/1/2', () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parent = c.tasks.single;
    expect(parent.parentTaskId, isNull);
    expect(parent.childOrder, 0);
    expect(parent.isChildTask, isFalse);

    final a = c.createChildTask(parent.id, title: '什么')!;
    final b = c.createChildTask(parent.id, title: '问问')!;
    final empty = c.createChildTask(parent.id)!;
    expect(c.childrenOf(parent.id).map((task) => task.id), [a, b, empty]);
    expect(c.childrenOf(parent.id).map((task) => task.childOrder), [0, 1, 2]);
    expect(c.childCount(parent.id), 3);
    expect(c.completedChildCount(parent.id), 0);
  });

  test('S1 childrenOf stays stable when child orders tie', () {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    // Two children with the same childOrder: the createdAt/id tie-break
    // must keep the listing deterministic instead of depending on the
    // internal _tasks order.
    c.normalizeHierarchyForTest(const [
      TaskItem(
          id: 'parent-2',
          title: '2',
          listName: '收集箱',
          bucket: TaskBucket.unscheduled),
      TaskItem(
          id: 'child-b',
          title: '问问',
          listName: '收集箱',
          bucket: TaskBucket.unscheduled,
          parentTaskId: 'parent-2',
          childOrder: 1,
          createdAt: '2026-09-19T09:00:00.000'),
      TaskItem(
          id: 'child-a',
          title: '什么',
          listName: '收集箱',
          bucket: TaskBucket.unscheduled,
          parentTaskId: 'parent-2',
          childOrder: 1,
          createdAt: '2026-09-19T08:00:00.000'),
    ]);
    // Earlier createdAt wins the tie: 什么 before 问问, on every call.
    expect(c.childrenOf('parent-2').map((task) => task.id),
        ['child-a', 'child-b']);
    expect(c.childrenOf('parent-2').map((task) => task.id),
        c.childrenOf('parent-2').map((task) => task.id).toList());
  });

  test('S1 child edits run through the normal Task actions', () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId)!;
    c.taskActions.setTitle(childId, '改名后的子任务');
    c.taskActions.complete(childId);

    final child = c.tasks.firstWhere((task) => task.id == childId);
    expect(child.title, '改名后的子任务');
    expect(child.completed, isTrue);
    expect(child.completedAt, isNotNull);
    expect(c.completedChildCount(parentId), 1);
  });

  test('SUB-005 completing a child leaves the parent and siblings untouched',
      () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parent = c.tasks.single;
    final childId = c.createChildTask(parent.id)!;
    c.taskActions.complete(childId);

    expect(c.tasks.firstWhere((task) => task.id == childId).completed, isTrue);
    expect(
        c.tasks.firstWhere((task) => task.id == parent.id).completed, isFalse);
  });

  test('SUB-010/011 child dates live on the child and stay out of flat lists',
      () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parent = c.tasks.single;
    final childId = c.createChildTask(parent.id)!;
    c.taskActions.setSchedule(childId,
        TaskScheduleDraft(dueAt: DateTime(2030, 9, 4), hasTime: false));

    final child = c.tasks.firstWhere((task) => task.id == childId);
    expect(localDateTimeFromStorage(child.dueAt), DateTime(2030, 9, 4));
    // Children render nested only: the flat list shows just the parent.
    expect(c.visibleTasks.map((task) => task.id), [parent.id]);
  });

  test('SUB-017 legacy subtask records expand into real child tasks', () {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final parent = TaskItem(
      id: 'task-legacy',
      title: '旧结构任务',
      listName: '收集箱',
      bucket: TaskBucket.unscheduled,
      subtasks: const [
        TaskSubtask(id: 'sub-1', title: '整理数据', completed: true),
        TaskSubtask(id: 'sub-2', title: '核对清单'),
      ],
    );
    // The same helper the load and seed paths run.
    c.normalizeHierarchyForTest([parent]);

    final children = c.childrenOf('task-legacy');
    expect(children, hasLength(2));
    expect(children.first.title, '整理数据');
    expect(children.first.completed, isTrue);
    expect(children.first.parentTaskId, 'task-legacy');
    expect(children.last.title, '核对清单');
    expect(c.tasks.firstWhere((task) => task.id == 'task-legacy').subtasks,
        isEmpty);
  });

  test('SUB-020/021/022 createChild via TaskActions inherits only the list', () {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('父任务');
    final parentId = c.tasks.single.id;
    c.taskActions
        .setSchedule(parentId, TaskScheduleDraft(dueAt: DateTime(2030, 8, 22), hasTime: false));
    c.taskActions.setPriority(parentId, TaskPriority.high);
    c.taskActions.setReminder(parentId, DateTime(2030, 8, 21, 9));

    final result = c.taskActions.createChild(parentId);
    expect(result.success, isTrue);
    final child = c.tasks.firstWhere((task) => task.id == result.taskId);
    expect(child.title, '');
    expect(child.parentTaskId, parentId);
    expect(child.childOrder, 0);
    expect(child.listName, c.tasks.firstWhere((task) => task.id == parentId).listName);
    // Nothing else is inherited: dates, priority and reminders start clean.
    expect(child.dueAt, isNull);
    expect(child.deadlineAt, isNull);
    expect(child.priority, TaskPriority.none);
    expect(child.reminderAt, isNull);
    expect(child.recurrenceType, 'NONE');
  });

  test('SUB-024 an empty child title saves and stays empty', () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId)!;
    // Name it, then clear it: an empty value is a real save, not a rejection.
    c.taskActions.setTitle(childId, '问问');
    final result = c.taskActions.setTitle(childId, '   ');
    expect(result.success, isTrue);
    expect(c.tasks.firstWhere((task) => task.id == childId).title, '');
    // Top-level tasks keep the non-empty guard.
    final topLevel = c.taskActions.setTitle(parentId, '');
    expect(topLevel.success, isFalse);
  });

  test('SUB-026 completing a child is undoable', () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final childId = c.createChildTask(c.tasks.single.id, title: '问问')!;
    c.taskActions.complete(childId);
    expect(c.tasks.firstWhere((task) => task.id == childId).completed, isTrue);
    c.undoLastAction();
    expect(c.tasks.firstWhere((task) => task.id == childId).completed, isFalse);
  });

  test('SUB-027/028 the child schedule is the single source for every view',
      () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId)!;
    c.taskActions.setScheduleSettings(
        childId,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(
                dueAt: DateTime(2030, 9, 4), hasTime: false)));
    final child = c.tasks.firstWhere((task) => task.id == childId);
    expect(localDateTimeFromStorage(child.dueAt), DateTime(2030, 9, 4));
    // The parent carries no copy of the child's date.
    expect(c.tasks.firstWhere((task) => task.id == parentId).dueAt, isNull);
  });

  test('SUB-030/031 deleting a child shrinks the hierarchy and orders stay stable', () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '什么')!;
    final b = c.createChildTask(parentId, title: '问问')!;
    c.taskActions.delete(b);
    expect(c.childrenOf(parentId).map((task) => task.id), [a]);
    expect(c.childCount(parentId), 1);
    expect(c.childrenOf(parentId).first.childOrder, 0);
  });

  test('SUB-031 reorderChildren is the only sibling-order entry point', () {
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final a = c.createChildTask(parentId, title: '什么')!;
    final b = c.createChildTask(parentId, title: '问问')!;
    final d = c.createChildTask(parentId, title: '无标题')!;
    c.reorderChildren(parentId, [b, d, a]);
    expect(c.childrenOf(parentId).map((task) => task.id), [b, d, a]);
    expect(c.childrenOf(parentId).map((task) => task.childOrder), [0, 1, 2]);
  });

  testWidgets(
      'SUB-004/006/007/008 the panel edits inline and the crumb navigates',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    c.createChildTask(parentId, title: '问问');
    final childId = c.childrenOf(parentId).single.id;
    final titleKey = ValueKey('task-child-title-$childId');

    // Follow the controller selection, like the real detail pane does.
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: AnimatedBuilder(
                animation: c,
                builder: (context, _) => TaskInspector(
                    task: c.tasks
                        .firstWhere((task) => task.id == c.selectedTaskId),
                    controller: c)))));
    await tester.pumpAndSettle();

    // The panel lists the child with an editable title field.
    expect(find.byKey(const ValueKey('task-children-panel')), findsOneWidget);
    expect(find.byKey(titleKey), findsOneWidget);
    await tester.enterText(find.byKey(titleKey), '改好的标题');
    await tester.pumpAndSettle();
    expect(c.childrenOf(parentId).single.title, '改好的标题');

    // S4 geometry: 48pt rows, accent add-row, hairline divider between rows.
    final rowRect =
        tester.getRect(find.byKey(ValueKey('task-child-row-$childId')));
    expect(rowRect.height, greaterThanOrEqualTo(48));
    expect(find.byKey(const ValueKey('task-add-child')), findsOneWidget);
    final addText = tester.widget<Text>(find.text('添加子任务'));
    expect(addText.style?.color, WorkFollowTheme.light.accent);

    // Following the chevron opens the child inspector with a crumb.
    await tester.tap(find.byKey(ValueKey('task-child-open-$childId')));
    await tester.pumpAndSettle();
    expect(c.selectedTaskId, childId);
    expect(
        find.byKey(const ValueKey('task-parent-breadcrumb')), findsOneWidget);

    // The crumb returns to the parent and restores its selection.
    await tester.tap(find.byKey(const ValueKey('task-parent-breadcrumb')));
    await tester.pumpAndSettle();
    expect(c.selectedTaskId, parentId);
  });

  testWidgets('SUB-012/013/016 the list tree indents children and folds',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId, title: '问问')!;

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: TodayScreen(controller: c))));
    await tester.pumpAndSettle();

    // Parent row carries the fold chevron; the child row sits indented below.
    expect(find.byKey(const ValueKey('task-expander-open')), findsOneWidget);
    expect(find.byKey(ValueKey(childId)), findsOneWidget);
    final parentRect =
        tester.getRect(find.byKey(ValueKey('task-row-surface-$parentId')));
    final childRect =
        tester.getRect(find.byKey(ValueKey('task-row-surface-$childId')));
    expect(childRect.left, greaterThan(parentRect.left));

    // Folding hides the child rows without touching the data.
    await tester.tap(find.byKey(const ValueKey('task-expander-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(childId)), findsNothing);
    expect(c.childrenOf(parentId), hasLength(1));
    expect(c.isTaskExpanded(parentId), isFalse);
  });
}
