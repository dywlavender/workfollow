import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/trash_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/app_icon_button.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_divider.dart';
import 'package:workfollow_personal/widgets/task_list/task_group_header.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_header.dart';
import 'package:workfollow_personal/widgets/task_list/task_list_row.dart';
import 'package:workfollow_personal/widgets/task_completion_box.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';
import 'package:workfollow_personal/widgets/task_list_inspector_split.dart';

/// TRASH-001 … TRASH-010 — the trash page.
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

Future<void> pumpTrash(
    WidgetTester tester, WorkspaceController controller) async {
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
    expect(find.byType(TaskGroupHeader), findsNothing);
    expect(find.byKey(const ValueKey('web-task-list-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('web-task-detail-pane')), findsOneWidget);
    expect(find.byType(EmptyTaskInspector), findsOneWidget);

    // One row frame per removed task, and the rows are separated the way the
    // lists separate theirs rather than by a per-page rule.
    expect(find.byType(TaskListRowFrame), findsNWidgets(2));
    expect(find.byType(TaskListDivider), findsOneWidget);
    expect(surface('a'), findsOneWidget);
    expect(surface('b'), findsOneWidget);

    // The marker is the task's own box in the state it was thrown away in —
    // reported, not offered. Nothing on this page ticks a task off.
    expect(
        tester
            .widget<TaskCompletionBox>(find.byType(TaskCompletionBox).first)
            .completed,
        isFalse);
    expect(
        tester
            .widget<TaskCompletionBox>(find.byType(TaskCompletionBox).last)
            .completed,
        isTrue);
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

  testWidgets('TRASH-003 selecting a trashed task opens the shared inspector',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('gone', title: '点得开吗')]);
    await pumpTrash(tester, controller);

    await tester.tap(surface('gone'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskInspector), findsOneWidget);
    expect(find.byKey(const ValueKey('wide-detail-gone')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('floating-task-editor-gone')), findsNothing);
    // Selecting a task does not navigate away from the page it was selected on.
    expect(find.byType(TrashScreen), findsOneWidget);
  });

  testWidgets('TRASH-004 restoring a selected task clears the inspector',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('gone', title: '别自己关掉')]);
    await pumpTrash(tester, controller);

    await tester.tap(surface('gone'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskInspector), findsOneWidget);

    // A restored task leaves the trash immediately, replacing its editor with
    // the shared empty inspector.
    controller.restoreTask('gone');
    await tester.pumpAndSettle();
    expect(find.byType(TaskInspector), findsNothing);
    expect(find.byType(EmptyTaskInspector), findsOneWidget);

    controller.purgeTask('gone');
    await tester.pumpAndSettle();
    expect(find.byType(TaskInspector), findsNothing);
  });

  testWidgets('TRASH-005 the task trash does not contain deleted notes',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('task-only', title: '仍然只显示任务')]);
    final noteId = controller.addNote(title: '扔掉的笔记');
    controller.removeNote(noteId);
    await pumpTrash(tester, controller);

    expect(surface('task-only'), findsOneWidget);
    expect(find.text('仍然只显示任务'), findsOneWidget);
    expect(find.text('扔掉的笔记'), findsNothing);
    expect(surface(noteId), findsNothing);
    expect(find.byType(TaskCompletionBox), findsOneWidget);
  });

  testWidgets('TRASH-006 恢复 puts a row back without also opening it',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('kept', title: '还给我')]);
    await pumpTrash(tester, controller);

    // The row's own actions sit inside the row's tap target. Tapping one has to
    // mean the action and nothing else.
    await tester.tap(
        find.descendant(of: surface('kept'), matching: find.byTooltip('恢复')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('floating-task-editor-kept')), findsNothing);
    expect(surface('kept'), findsNothing);
    expect(controller.tasks.firstWhere((task) => task.id == 'kept').deletedAt,
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
    final noteId = controller.addNote(title: '只能在笔记垃圾桶出现');
    controller.removeNote(noteId);
    await pumpTrash(tester, controller);

    expect(find.text('垃圾桶是空的'), findsOneWidget);
    expect(find.byType(TaskListRowFrame), findsNothing);
    expect(find.text('只能在笔记垃圾桶出现'), findsNothing);
    expect(controller.deletedNotes, hasLength(1));
    expect(
        tester
            .widget<AppIconButton>(
                find.byKey(const ValueKey('empty-trash-button')))
            .onPressed,
        isNull);
  });

  testWidgets('TRASH-009 the task deletion order ignores deleted notes',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([
      removed('older-task', title: '更早删除的任务', at: DateTime(2020, 6, 10)),
      removed('newer-task', title: '较新删除的任务', at: DateTime(2021, 6, 10)),
    ]);
    final noteId = controller.addNote(title: '较晚删除的笔记');
    controller.removeNote(noteId);
    await pumpTrash(tester, controller);

    expect(find.text('较晚删除的笔记'), findsNothing);
    expect(tester.getTopLeft(surface('newer-task')).dy,
        lessThan(tester.getTopLeft(surface('older-task')).dy));
  });

  testWidgets('TRASH-010 the shared pane divider stays within its limits',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([removed('resizable')]);
    await pumpTrash(tester, controller);

    final divider = find.byKey(const ValueKey('task-pane-divider'));
    expect(divider, findsOneWidget);
    await tester.drag(divider, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(controller.taskListPaneWidth, TaskListMetrics.maxPaneWidth);

    await tester.drag(divider, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(controller.taskListPaneWidth, TaskListMetrics.minPaneWidth);
  });

  testWidgets('TRASH-011 clearing purges tasks but leaves notes alone',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.loadTasksForTest([
      removed('deleted-parent', title: '删除的父任务'),
      removed('deleted-child', title: '删除的子任务', parent: 'deleted-parent'),
      TaskItem(
        id: 'active-child',
        title: '仍然有效的子任务',
        listName: '工作',
        bucket: taskBucketForDate(null, now: anchor),
        parentTaskId: 'deleted-parent',
      ),
    ]);
    final deletedNoteId = controller.addNote(title: '删除的笔记');
    controller.removeNote(deletedNoteId);
    final activeNoteId = controller.addNote(title: '保留的笔记');
    await pumpTrash(tester, controller);

    await tester.tap(find.byTooltip('清空垃圾桶'));
    await tester.pumpAndSettle();
    expect(find.text('清空垃圾桶'), findsOneWidget);
    expect(find.text('垃圾桶中的任务将被永久删除，确定清空垃圾桶吗？'), findsOneWidget);
    final dialogSize =
        tester.getSize(find.byKey(const ValueKey('clear-trash-dialog')));
    expect(dialogSize.width, lessThanOrEqualTo(440));
    expect(dialogSize.height, lessThanOrEqualTo(240));

    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    expect(controller.deletedTasks, hasLength(2));
    expect(controller.deletedNotes, hasLength(1));

    await tester.tap(find.byTooltip('清空垃圾桶'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(controller.deletedTasks, isEmpty);
    expect(controller.deletedNotes, hasLength(1));
    expect(controller.deletedNotes.single.id, deletedNoteId);
    expect(controller.tasks.map((task) => task.id), ['active-child']);
    expect(controller.tasks.single.parentTaskId, isNull);
    expect(controller.notes.map((note) => note.id),
        containsAll([deletedNoteId, activeNoteId]));
  });
}
