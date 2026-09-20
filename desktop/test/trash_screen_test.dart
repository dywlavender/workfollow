import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/trash_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_divider.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_header.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_row.dart';
import 'package:workfollow_personal/widgets/task_completion_box.dart';

/// TRASH-001 … TRASH-008 — the trash page.
///
/// 已完成 sits directly above 垃圾桶 in the rail, so the two pages are read in
/// the same breath and have to be the same kind of page: the same header, the
/// same row frame, the same divider. These cases mount the page and read what
/// it drew, because "it looks like the list" is not something a projection test
/// can answer.
///
/// The clock is fixed and the rows are seeded with explicit stamps: the page's
/// order is by deletion time, and `removeTask` writes `DateTime.now()`, which
/// two calls in one test can share.
final DateTime anchor = DateTime(2030, 6, 10, 9);

DateTime day(int offset) => DateTime(2030, 6, 10 + offset);

TaskItem removed(String id,
    {String? title,
    DateTime? at,
    bool completed = false,
    String list = '收集箱',
    String? parent}) {
  return TaskItem(
    id: id,
    title: title ?? id,
    listName: list,
    bucket: taskBucketForDate(null, now: anchor),
    completed: completed,
    deletedAt: (at ?? day(-1)).toIso8601String(),
    parentTaskId: parent,
  );
}

Future<void> pumpTrash(WidgetTester tester, WorkspaceController controller) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  controller.selectView(WorkspaceView.trash);
  await tester.pumpWidget(MaterialApp(
    theme: WorkFollowThemeData.light(),
    home: Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TrashScreen(controller: controller),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder surface(String id) => find.byKey(ValueKey('trash-row-surface-$id'));

void main() {
  testWidgets('TRASH-001 the page is a task list, not a report about one',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([
      removed('a', title: '扔掉的任务', at: day(-1)),
      removed('b', title: '另一个', at: day(-2), completed: true),
    ]);
    await pumpTrash(tester, controller);

    // The header every list page opens with, carrying this page's own name.
    expect(find.byType(TaskListHeader), findsOneWidget);
    expect(find.text('垃圾桶'), findsOneWidget);

    // One row frame per removed task, and the rows are separated the way the
    // lists separate theirs rather than by a per-page rule.
    expect(find.byType(TaskListRowFrame), findsNWidgets(2));
    expect(find.byType(TaskListDivider), findsOneWidget);
    expect(surface('a'), findsOneWidget);
    expect(surface('b'), findsOneWidget);

    // The marker is the task's own box in the state it was thrown away in —
    // reported, not offered. Nothing on this page ticks a task off.
    expect(tester.widget<TaskCompletionBox>(find.byType(TaskCompletionBox).first)
        .completed, isFalse);
    expect(tester.widget<TaskCompletionBox>(find.byType(TaskCompletionBox).last)
        .completed, isTrue);
  });

  testWidgets('TRASH-002 the rows run newest deletion first', (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    // Seeded out of order on purpose: the row order has to come from the
    // stamps, not from the order the store happens to hold them in.
    controller.loadTasksForTest([
      removed('oldest', title: '三天前扔的', at: day(-3)),
      removed('newest', title: '刚扔的', at: day(-1)),
      removed('middle', title: '昨天扔的', at: day(-2)),
    ]);
    await pumpTrash(tester, controller);

    final tops = <String, double>{
      for (final id in ['oldest', 'middle', 'newest'])
        id: tester.getTopLeft(surface(id)).dy,
    };
    expect(tops['newest']!, lessThan(tops['middle']!));
    expect(tops['middle']!, lessThan(tops['oldest']!));
  });

  testWidgets('TRASH-003 clicking a trashed task opens it over the page',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('gone', title: '点得开吗')]);
    await pumpTrash(tester, controller);

    await tester.tap(surface('gone'));
    await tester.pumpAndSettle();

    // The floating editor is the same surface the board and the calendar open.
    // A row a user can see but not read is the failure this guards.
    expect(find.byKey(const ValueKey('floating-task-editor-gone')),
        findsOneWidget);
    // Opening a task does not navigate away from the page it was opened on.
    expect(find.byType(TrashScreen), findsOneWidget);
  });

  testWidgets('TRASH-004 the editor on a trashed task still holds it',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('gone', title: '别自己关掉')]);
    await pumpTrash(tester, controller);

    await tester.tap(surface('gone'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('floating-task-editor-gone')),
        findsOneWidget);

    // Everywhere else a deleted task closes the editor — that is how removing
    // it from inside takes the editor with it. Here the deleted state is what
    // the user clicked, so the surface has to survive the controller rebuilding
    // under it. A purge is different: the task is gone, so the surface goes.
    controller.restoreTask('gone');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('floating-task-editor-gone')),
        findsOneWidget);

    controller.purgeTask('gone');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('floating-task-editor-gone')), findsNothing);
  });

  testWidgets('TRASH-005 a deleted note has no page to open', (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final noteId = controller.addNote(title: '扔掉的笔记');
    controller.removeNote(noteId);
    await pumpTrash(tester, controller);

    // The note is in the trash and wears the same frame — but not a task's box,
    // because it has no completion state to report.
    expect(surface(noteId), findsOneWidget);
    expect(find.byType(TaskCompletionBox), findsNothing);
    expect(find.text('扔掉的笔记'), findsOneWidget);
    expect(find.textContaining('删除'), findsOneWidget);

    // Tapping it opens nothing: the notes tree shows live notes only, so there
    // is no page that could draw a deleted one. Acting on it means 恢复.
    await tester.tap(surface(noteId));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('floating-task-editor-$noteId')), findsNothing);
  });

  testWidgets('TRASH-006 恢复 puts a row back without also opening it',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('kept', title: '还给我')]);
    await pumpTrash(tester, controller);

    // The row's own actions sit inside the row's tap target. Tapping one has to
    // mean the action and nothing else.
    await tester.tap(find.descendant(
        of: surface('kept'), matching: find.byTooltip('恢复')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('floating-task-editor-kept')), findsNothing);
    expect(surface('kept'), findsNothing);
    expect(
        controller.tasks.firstWhere((task) => task.id == 'kept').deletedAt,
        isNull);
  });

  testWidgets('TRASH-007 永久删除 asks first, and only then removes the row',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('doomed', title: '真的删掉')]);
    await pumpTrash(tester, controller);

    await tester.tap(find.descendant(
        of: surface('doomed'), matching: find.byTooltip('永久删除')));
    await tester.pumpAndSettle();
    expect(find.text('永久删除这个任务？'), findsOneWidget);
    expect(find.byKey(const ValueKey('floating-task-editor-doomed')),
        findsNothing);

    // Backing out of the dialog leaves the row where it was.
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(surface('doomed'), findsOneWidget);
    expect(controller.tasks.any((task) => task.id == 'doomed'), isTrue);

    await tester.tap(find.descendant(
        of: surface('doomed'), matching: find.byTooltip('永久删除')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(surface('doomed'), findsNothing);
    expect(controller.tasks.any((task) => task.id == 'doomed'), isFalse);
  });

  testWidgets('TRASH-008 an empty trash says so', (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await pumpTrash(tester, controller);

    expect(find.text('垃圾桶是空的'), findsOneWidget);
    expect(find.byType(TaskListRowFrame), findsNothing);
  });
}
