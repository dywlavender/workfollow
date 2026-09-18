import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/models/migration.dart';
import 'package:workfollow_personal/models/rich_document.dart';
import 'package:workfollow_personal/services/local_workspace_store.dart';
import 'package:workfollow_personal/services/notification_service.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/widgets/task_context_menu.dart';
import 'package:workfollow_personal/widgets/task_menu_actions.dart';
import 'package:workfollow_personal/widgets/task_row.dart';

class _Store extends LocalWorkspaceStore {
  MigrationBundle? bundle;
  @override
  Future<void> save(MigrationBundle value) async {
    bundle = MigrationBundle.fromJson(jsonDecode(jsonEncode(value.toJson())));
  }

  @override
  Future<WorkspaceSnapshotLoad> load() async =>
      WorkspaceSnapshotLoad(bundle: bundle);
}

class _Reminders extends NotificationService {
  final cancelled = <String>[];
  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
  }
}

void main() {
  test(
      'pinned and abandoned states survive save/reopen and restore independently',
      () async {
    final store = _Store();
    final reminders = _Reminders();
    final c = WorkspaceController(
        seedData: false, store: store, reminderScheduler: reminders);
    addTearDown(c.dispose);
    final created = c.createTask(TaskDraft(
        title: '每周整理',
        schedule: TaskScheduleDraft(dueAt: DateTime.now()),
        recurrence: const RecurrenceDraft(type: 'WEEKLY'),
        reminderAt: DateTime.now().add(const Duration(hours: 2))));
    final id = created.taskId!;
    c.taskActions.setPinned(id, true);
    final abandoned = c.taskActions.abandon(id);
    expect(abandoned.success, isTrue);
    expect(c.tasks.single.isAbandoned, isTrue);
    expect(c.tasks.single.completed, isFalse);
    expect(c.activeTasks, isEmpty);
    expect(reminders.cancelled, contains(id));
    expect(c.tasks, hasLength(1), reason: '放弃不会生成下一周期');
    c.selectView(WorkspaceView.completed);
    expect(c.visibleTasks.single.id, id);
    await c.waitForPendingSaves();
    final reopened = WorkspaceController(seedData: false, store: store);
    addTearDown(reopened.dispose);
    await reopened.restoreFromDisk();
    expect(reopened.tasks.single.isPinned, isTrue);
    expect(reopened.tasks.single.isAbandoned, isTrue);
    expect(reopened.tasks.single.toMigrationRecord().status, 'ABANDONED');
    expect(reopened.taskActions.restore(id).success, isTrue);
    expect(reopened.tasks.single.isAbandoned, isFalse);
    expect(reopened.activeTasks.single.isPinned, isTrue);
    expect(reopened.taskActions.setPinned(id, false).success, isTrue);
    expect(reopened.taskActions.undo().success, isTrue);
    expect(reopened.tasks.single.isPinned, isTrue);
  });

  test('conversion keeps formatted content, checklist, attachments and undo',
      () async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('资料整理', forceUnscheduled: true);
    final id = c.tasks.single.id;
    c.addSubtask(id, '检查资料');
    c.toggleSubtask(id, c.tasks.single.subtasks.single.id);
    c.taskActions.setTags(id, ['工作']);
    final content = richContentFromDelta([
      {
        'insert': '重要资料',
        'attributes': {'bold': true, 'link': 'https://example.com'}
      },
      {'insert': '\n'},
      {
        'insert': {
          'workfollow-block': jsonEncode({'type': 'taskSubtasks'})
        }
      },
      {'insert': '\n'},
      {
        'insert': {
          'workfollow-block': jsonEncode({
            'type': 'attachment',
            'attrs': {'localFile': '资料.pdf', 'name': '资料.pdf'}
          })
        }
      },
      {'insert': '\n'},
    ]);
    c.taskActions.setContent(id, content, '重要资料');
    final result = c.taskActions.convertToNote(id);
    expect(result.success, isTrue);
    expect(c.view, WorkspaceView.notes);
    expect(c.activeTasks, isEmpty);
    final note = c.notes.single;
    expect(note.title, '资料整理');
    final delta = note.contentJson!['quillDelta'] as List;
    expect(delta.any((op) => op['attributes']?['bold'] == true), isTrue);
    expect(delta.any((op) => op['attributes']?['list'] == 'checked'), isTrue);
    expect(jsonEncode(delta), contains('资料.pdf'));
    expect(jsonEncode(delta), isNot(contains('taskSubtasks')));
    expect(note.plainText, contains('检查资料'));
    expect(note.plainText, contains('#工作'));
    expect(c.tasks.single.convertedNoteId, note.id);
    final reopened = TaskItem.fromMigration(MigrationTaskRecord.fromJson(
        c.tasks.single.toMigrationRecord().toJson()));
    expect(reopened.isConverted, isTrue);
    expect(await result.undo!.execute(), isTrue);
    expect(c.notes, isEmpty);
    expect(c.activeTasks.single.contentJson, content);
    expect(c.activeTasks.single.subtasks.single.completed, isTrue);
  });

  testWidgets(
      'tags search, create, cancel, confirm and move share menu actions',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('菜单任务', forceUnscheduled: true);
    final id = c.tasks.single.id;
    c.taskActions.setTags(id, ['已有标签']);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      final result = await TaskContextMenu.show(context,
                          task: c.tasks.single, controller: c);
                      if (result != null && context.mounted)
                        await runTaskMenuAction(
                            context, c, c.tasks.single, result);
                    },
                    child: const Text('打开菜单'))))));
    Future<void> openTags() async {
      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-option-tags')));
      await tester.pumpAndSettle();
    }

    await openTags();
    await tester.tap(find.byKey(const ValueKey('task-tag-已有标签')));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.tasks.single.tags, ['已有标签']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await openTags();
    await tester.enterText(find.byKey(const ValueKey('task-tag-search')), '项目');
    await tester.pump();
    expect(find.byKey(const ValueKey('task-tag-已有标签')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task-tag-create')));
    await tester.pump();
    expect(c.tasks.single.tags, ['已有标签']);
    await tester.tap(find.byKey(const ValueKey('task-tag-confirm')));
    await tester.pumpAndSettle();
    expect(c.tasks.single.tags, ['已有标签', '项目']);
    c.addList('工作');
    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-list')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-工作')));
    await tester.pumpAndSettle();
    expect(c.tasks.single.listName, '工作');
  });

  testWidgets('row add-subtask opens and focuses one reusable input', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.selectView(WorkspaceView.inbox);
    c.addTask('增加子任务', forceUnscheduled: true);
    final id = c.tasks.single.id;
    await tester.pumpWidget(MaterialApp(theme: WorkFollowThemeData.light(), home: Scaffold(body: ListenableBuilder(listenable: c, builder: (_, __) => TodayScreen(controller: c, persistentInspector: true)))));
    await tester.pumpAndSettle();
    Future<void> addFromMenu() async {
      c.selectTask(id);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey('task-row-surface-$id'))),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-option-add-subtask')));
      await tester.pumpAndSettle();
    }
    await addFromMenu();
    final input = find.byKey(const ValueKey('task-subtask-input'));
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    await tester.enterText(input, '子步骤');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.tasks.single.subtasks.single.title, '子步骤');
    await addFromMenu();
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    expect(c.view, WorkspaceView.inbox);
  });

  testWidgets('submenus flip within the minimum desktop window', (tester) async {
    tester.view.physicalSize = const Size(880, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('靠边菜单', forceUnscheduled: true);
    await tester.pumpWidget(MaterialApp(theme: WorkFollowThemeData.dark(), home: Scaffold(body: Builder(builder: (context) => TextButton(
      child: const Text('打开'), onPressed: () => TaskContextMenu.show(context, task: c.tasks.single, controller: c, globalPosition: const Offset(860, 570)),
    )))));
    await tester.tap(find.text('打开')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-tags'))); await tester.pumpAndSettle();
    final parent = tester.getRect(find.byKey(const ValueKey('task-context-menu-panel')));
    final child = tester.getRect(find.byKey(const ValueKey('task-tag-picker')));
    expect(child.right, lessThan(parent.left));
    expect(child.top, greaterThanOrEqualTo(12));
    expect(child.bottom, lessThanOrEqualTo(588));
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-context-menu-panel')), findsOneWidget);
  });

  testWidgets(
      'pin stays before other date groups and abandoned task can be restored',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.selectView(WorkspaceView.inbox);
    c.addTask('置顶任务', forceUnscheduled: true);
    final pinnedId = c.tasks.single.id;
    c.addTask('普通任务', forceUnscheduled: true);
    c.taskActions.setPinned(pinnedId, true);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: c,
                builder: (_, __) => TodayScreen(controller: c)))));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<TaskRow>(find.byType(TaskRow)).toList();
    expect(rows.first.task.id, pinnedId);
    expect(find.text('置顶'), findsOneWidget);
    c.taskActions.abandon(pinnedId);
    c.selectView(WorkspaceView.completed);
    await tester.pumpAndSettle();
    expect(find.text('已放弃'), findsWidgets);
    c.taskActions.restore(pinnedId);
    c.selectView(WorkspaceView.inbox);
    await tester.pumpAndSettle();
    expect(tester.widgetList<TaskRow>(find.byType(TaskRow)).first.task.id,
        pinnedId);
  });
}
