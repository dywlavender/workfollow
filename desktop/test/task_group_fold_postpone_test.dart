import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/feedback/feedback_controller.dart';
import 'package:workfollow_personal/features/feedback/feedback_host.dart';
import 'package:workfollow_personal/features/feedback/feedback_scope.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

/// LIST-F01 — group headings fold, and the overdue group can be postponed.
///
/// The screen is mounted on its own rather than through the app shell so these
/// cases exercise the list grammar only: no rail, no inspector, no demo seed
/// data deciding what happens to be overdue.

DateTime get _startOfToday {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// An overdue task with an all-day date (yesterday).
void _addOverdue(WorkspaceController controller, String title) {
  controller.createTask(TaskDraft(
      title: title,
      schedule: TaskScheduleDraft(
          dueAt: _startOfToday.subtract(const Duration(days: 1)),
          hasTime: false)));
}

/// An overdue task that carried a clock, to prove 顺延 does not drop it.
void _addOverdueTimed(WorkspaceController controller, String title) {
  controller.createTask(TaskDraft(
      title: title,
      schedule: TaskScheduleDraft(
          dueAt: _startOfToday
              .subtract(const Duration(days: 1))
              .add(const Duration(hours: 9, minutes: 30)),
          hasTime: true)));
}

void _addToday(WorkspaceController controller, String title) {
  controller.createTask(TaskDraft(
      title: title,
      schedule: TaskScheduleDraft(dueAt: _startOfToday, hasTime: false)));
}

Future<void> _pumpToday(WidgetTester tester, WorkspaceController controller) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // The app shell is what listens to the controller, so a test that mounts the
  // screen on its own has to supply that rebuild or nothing on screen follows a
  // date change. persistentInspector: false keeps it a single list column, so
  // the group headings are the only thing under test.
  //
  // The result HUD is mounted the way the shell mounts it — scope above the
  // page, host as the last child of the stack — because 顺延 reports through
  // that one channel and the test has to exercise it rather than bypass it.
  final feedback = FeedbackController();
  addTearDown(feedback.dispose);
  return tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: FeedbackScope(
          controller: feedback,
          child: Stack(fit: StackFit.expand, children: [
            Scaffold(
                body: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => TodayScreen(
                        controller: controller, persistentInspector: false))),
            WorkFollowFeedbackHost(controller: feedback),
          ]))));
}

Finder _chevron(String label) => find.byKey(ValueKey('group-chevron-$label'));

void main() {
  testWidgets('LIST-F01 folding a group hides its rows and keeps its heading',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    _addOverdue(controller, '逾期的报告');
    _addToday(controller, '今天要做');

    await _pumpToday(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('逾期的报告'), findsOneWidget);

    await tester.tap(_chevron('已过期'));
    await tester.pumpAndSettle();

    // The heading and its count survive the fold; only the row goes away.
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('逾期的报告'), findsNothing);
    // Folding one group must not touch its neighbour.
    expect(find.text('今天要做'), findsOneWidget);

    await tester.tap(_chevron('已过期'));
    await tester.pumpAndSettle();

    expect(find.text('逾期的报告'), findsOneWidget);
  });

  testWidgets('LIST-F01 the completed group starts open and folds on demand',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    controller.addTask('做完了的事');
    controller.taskActions.complete(controller.tasks.single.id);

    await _pumpToday(tester, controller);
    await tester.pumpAndSettle();

    // Open by default: the task finished a moment ago is the one being looked
    // at, and starting folded would hide it.
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('做完了的事'), findsOneWidget);

    await tester.tap(_chevron('已完成'));
    await tester.pumpAndSettle();

    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('做完了的事'), findsNothing);
  });

  testWidgets('LIST-F01 顺延 moves the whole overdue group to today',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    _addOverdue(controller, '逾期的报告');
    _addOverdue(controller, '逾期的对账');
    _addToday(controller, '今天要做');

    await _pumpToday(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('group-postpone-overdue')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-postpone-overdue')));
    await tester.pumpAndSettle();

    // Empty group disappears with its action.
    expect(find.text('已过期'), findsNothing);
    expect(find.byKey(const ValueKey('group-postpone-overdue')), findsNothing);

    for (final title in ['逾期的报告', '逾期的对账']) {
      final task = controller.tasks.firstWhere((t) => t.title == title);
      expect(localDateTimeFromStorage(task.dueAt), _startOfToday);
      expect(task.bucket, TaskBucket.today);
    }
    // The untouched group is still there.
    expect(find.text('今天要做'), findsOneWidget);

    // Drain the feedback snackbar's timer before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('LIST-F01 顺延 keeps the clock of a timed task', (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    _addOverdueTimed(controller, '昨天的站会纪要');

    await _pumpToday(tester, controller);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-postpone-overdue')));
    await tester.pumpAndSettle();

    final task = controller.tasks.single;
    // 昨天 09:30 → 今天 09:30. A bulk draft would have flattened this to
    // an all-day today and silently thrown the time away.
    expect(localDateTimeFromStorage(task.dueAt),
        _startOfToday.add(const Duration(hours: 9, minutes: 30)));
    expect(task.scheduledWithTime, isTrue);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('LIST-F01 顺延 is undoable in one step', (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    _addOverdue(controller, '逾期的报告');
    _addOverdueTimed(controller, '逾期的对账');

    await _pumpToday(tester, controller);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-postpone-overdue')));
    // Settle first: the HUD is still animating in right after the tap, and its
    // action is not hittable until it has arrived.
    await tester.pumpAndSettle();

    expect(find.text('已顺延 2 项到 今天'), findsOneWidget);
    final undo = find.byKey(const ValueKey('feedback-toast-action'));
    expect(undo, findsOneWidget);
    await tester.tap(undo);
    await tester.pumpAndSettle();

    // Both tasks come back, which is what makes the chained undo a single
    // command rather than only the last snapshot.
    expect(controller.tasks
            .firstWhere((t) => t.title == '逾期的报告')
            .bucket,
        TaskBucket.overdue);
    expect(controller.tasks
            .firstWhere((t) => t.title == '逾期的对账')
            .bucket,
        TaskBucket.overdue);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('LIST-F01 顺延 wears the ink a date wears', (tester) async {
    // 顺延 sat in `textTertiary`, the same grey as the count beside it, so a
    // control and a number read as the same kind of thing. It takes the ink a
    // row's date wears instead — and the point of the ask was that the two
    // *share* it, so this asserts the coupling and not just the value: a
    // palette move that took one and left the other would pass a value check
    // written against `accent` alone if `accent` had moved too, and fail here
    // the moment the two stop agreeing.
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    _addOverdue(controller, '逾期的报告');
    _addToday(controller, '今天要做');

    await _pumpToday(tester, controller);
    await tester.pumpAndSettle();

    const tokens = WorkFollowTheme.light;
    final postpone = tester.widget<TextButton>(
        find.byKey(const ValueKey('group-postpone-overdue')));
    final postponeInk = postpone.style?.foregroundColor?.resolve(<WidgetState>{});

    expect(postponeInk, tokens.accent,
        reason: '顺延 offers to move a task onto a day that is still ahead of '
            'the reader, so it wears that day\'s ink rather than the muted '
            'grey the group count wears');

    // The row beside it, drawn by the other file that has an opinion about
    // this date.
    final today = controller.tasks.firstWhere((t) => t.title == '今天要做');
    final date =
        tester.widget<Text>(find.byKey(ValueKey('task-row-date-${today.id}')));
    expect(date.style?.color, postponeInk,
        reason: 'the row says 今天 in one ink and the control offers to move '
            'the group there in another; the two have to be one token');
  });
}
