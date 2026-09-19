import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/features/tasks/application/task_actions.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

/// S5: the child inspector is the standard TaskInspector with a parent
/// breadcrumb — no SubtaskEditor, no second navigation stack.
void main() {
  Future<WorkspaceController> pumpInspector(WidgetTester tester,
      {required WorkspaceController c, required String taskId}) async {
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
    return c;
  }

  testWidgets('SUB-045/046/048 the crumb shows the parent and navigates back',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = WorkspaceController(seedData: false)..addTask('父任务二');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId, title: '问问')!;
    c.openTask(childId);
    await pumpInspector(tester, c: c, taskId: childId);

    expect(
        find.byKey(const ValueKey('task-parent-breadcrumb')), findsOneWidget);
    expect(find.text('父任务二'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-parent-breadcrumb')));
    await tester.pumpAndSettle();
    expect(c.selectedTaskId, parentId);
  });

  testWidgets('SUB-047 an unnamed parent shows 无标题 in the crumb',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    // Whitespace-titled parents cannot come from addTask; build one the way
    // a legacy load would.
    c.loadTasksForTest(const [
      TaskItem(
          id: 'parent-empty',
          title: '   ',
          listName: '收集箱',
          bucket: TaskBucket.unscheduled),
    ]);
    final parentId = 'parent-empty';
    final childId = c.createChildTask(parentId)!;
    c.openTask(childId);
    await pumpInspector(tester, c: c, taskId: childId);

    // The crumb renders the placeholder name; the child's own empty field
    // shows the same hint, so match within the breadcrumb.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('task-parent-breadcrumb')),
            matching: find.text('无标题')),
        findsOneWidget);
    // The placeholder value never reaches the data.
    expect(c.tasks.firstWhere((task) => task.id == parentId).title, '   ');
  });

  testWidgets('SUB-050 deleting a child lands back on its parent',
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
    final childId = c.createChildTask(parentId, title: '问问')!;
    c.openTask(childId);
    await pumpInspector(tester, c: c, taskId: childId);

    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(c.activeTasks.any((task) => task.id == childId), isFalse);
    expect(c.selectedTaskId, parentId);
  });

  testWidgets('SUB-051 an orphaned child opens as a plain task',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    // Orphans only arise from old data or import errors now that deleting a
    // parent cascades — build one directly the way a legacy load would.
    c.loadTasksForTest(const [
      TaskItem(
          id: 'orphan-child',
          title: '问问',
          listName: '收集箱',
          bucket: TaskBucket.unscheduled,
          parentTaskId: 'gone-parent'),
    ]);
    final childId = 'orphan-child';
    c.openTask(childId);
    await pumpInspector(tester, c: c, taskId: childId);

    // No parent to point at: the inspector stays a normal task page.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('task-parent-breadcrumb')), findsNothing);
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
  });

  testWidgets('SUB-052 a child offers no 添加子任务 entries', (tester) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = WorkspaceController(seedData: false)..addTask('父任务');
    addTearDown(c.dispose);
    final parentId = c.tasks.single.id;
    final childId = c.createChildTask(parentId, title: '问问')!;
    c.createChildTask(childId, title: '不该存在');

    // The more menu hides the entry for children.
    c.openTask(childId);
    await pumpInspector(tester, c: c, taskId: childId);
    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    expect(find.text('添加子任务'), findsNothing);

    // The data layer refuses grandchildren even if a caller bypasses the UI.
    expect(c.createChildTask(childId), isNull);
    expect(c.childrenOf(childId), isEmpty);
    final viaActions = c.taskActions.createChild(childId);
    expect(viaActions.success, isFalse);
    expect(viaActions.error?.code, 'nested-child-not-supported');
  });
}
