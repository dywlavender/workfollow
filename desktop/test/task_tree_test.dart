import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
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
    expect(c.parentOf(children.first)!.id, parent.id);
    expect(c.hasChildren(parent.id), isTrue);
    expect(c.taskUiState.pendingChildFocusTaskId, second);
    // The parent keeps the selection so the panel shows the new row.
    expect(c.selectedTaskId, parent.id);
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
    c.expandLegacyForTest([parent]);

    final children = c.childrenOf('task-legacy');
    expect(children, hasLength(2));
    expect(children.first.title, '整理数据');
    expect(children.first.completed, isTrue);
    expect(children.first.parentTaskId, 'task-legacy');
    expect(children.last.title, '核对清单');
    expect(
        c.tasks.firstWhere((task) => task.id == 'task-legacy').subtasks,
        isEmpty);
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
                    task: c.tasks.firstWhere(
                        (task) => task.id == c.selectedTaskId),
                    controller: c)))));
    await tester.pumpAndSettle();

    // The panel lists the child with an editable title field.
    expect(find.byKey(const ValueKey('task-children-panel')), findsOneWidget);
    expect(find.byKey(titleKey), findsOneWidget);
    await tester.enterText(find.byKey(titleKey), '改好的标题');
    await tester.pumpAndSettle();
    expect(c.childrenOf(parentId).single.title, '改好的标题');

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
    final parentRect = tester
        .getRect(find.byKey(ValueKey('task-row-surface-$parentId')));
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
