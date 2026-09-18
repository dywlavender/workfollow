import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/feedback/feedback_controller.dart';
import 'package:workfollow_personal/features/feedback/feedback_event.dart';
import 'package:workfollow_personal/features/feedback/feedback_host.dart';
import 'package:workfollow_personal/features/feedback/feedback_scope.dart';
import 'package:workfollow_personal/features/feedback/feedback_sound_service.dart';
import 'package:workfollow_personal/features/tasks/application/task_actions.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/presentation/task_feedback_mapper.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_icons.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

/// FB-TEST — the single result channel.
///
/// What these cases protect is not "a toast appears" but the three properties
/// that made five coexisting channels worth collapsing into one: only one
/// surface ever shows, arbitration keeps the important item on screen, and a
/// repeat of the same completion is a count rather than a stack.

const _toastKey = ValueKey('feedback-toast');
const _actionKey = ValueKey('feedback-toast-action');

/// Mounts the host the way the shell does: the scope above the page, the HUD
/// as the last child of the page's stack.
Future<void> _pumpHarness(WidgetTester tester, FeedbackController feedback,
    {bool animate = true, ThemeData? theme, Widget? page}) async {
  _useDesktopWindow(tester);
  await tester.pumpWidget(MaterialApp(
      theme: theme ?? WorkFollowThemeData.light(),
      home: FeedbackScope(
          controller: feedback,
          child: Stack(fit: StackFit.expand, children: [
            page ?? const Scaffold(body: SizedBox.expand()),
            WorkFollowFeedbackHost(controller: feedback, animate: animate),
          ]))));
}

/// A page mounted with no host above it, which is how a row is exercised by a
/// widget test that has nothing to do with feedback.
Future<void> _pumpPageWithoutHost(WidgetTester tester, Widget page) async {
  _useDesktopWindow(tester);
  await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(), home: page));
}

void _useDesktopWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Lets every hold timer in flight expire before the test ends. A pending
/// timer fails the test on its own, and disposing the controller from a
/// tear-down happens after that check.
Future<void> _drainHolds(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

/// The page carries its own [Scaffold]: the screen is mounted without the app
/// shell, so it has to supply the Material ancestor the shell normally does.
Widget _todayPage(WorkspaceController controller) => Scaffold(
    body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) =>
            TodayScreen(controller: controller, persistentInspector: false)));

DateTime get _startOfToday {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

WorkFollowFeedback _completion({VoidCallback? onAction, String? message}) =>
    WorkFollowFeedback(
        kind: WorkFollowFeedbackKind.completion,
        message: message ?? '任务已完成',
        actionLabel: '撤销',
        actionIcon: WorkFollowIcons.undo,
        onAction: onAction,
        sound: WorkFollowFeedbackSound.completion);

TaskActionResult _completedSingle(String id) => TaskActionResult.success(
    taskId: id,
    message: '任务已完成',
    undo: UndoCommand(label: '撤销完成', execute: () => true),
    feedback: TaskFeedbackIntent.completion);

void main() {
  group('FB-HUD01 one surface', () {
    testWidgets('a completion draws the dark HUD in both themes',
        (tester) async {
      for (final theme in [
        WorkFollowThemeData.light(),
        WorkFollowThemeData.dark()
      ]) {
        final feedback = FeedbackController();
        addTearDown(feedback.dispose);
        await _pumpHarness(tester, feedback, theme: theme);
        feedback.show(_completion());
        await tester.pumpAndSettle();

        expect(find.byKey(_toastKey), findsOneWidget);
        expect(find.text('任务已完成'), findsOneWidget);

        final tokens =
            WorkFollowTheme.of(tester.element(find.byKey(_toastKey)));
        final container = tester.widget<Container>(find.byKey(_toastKey));
        final decoration = container.decoration! as BoxDecoration;
        // One dark surface in both themes: the single place the app is
        // deliberately not theme-following, and it must not drift.
        expect(decoration.color, tokens.feedbackSurface);
        expect(decoration.color, const Color(0xFF2C2C2E));
        // No outline: a border on a dark field reads as a focus ring.
        expect(decoration.border, isNull);

        feedback.dismiss();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the HUD sits horizontally centred above the window bottom',
        (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);
      feedback.show(_completion(onAction: () {}));
      await tester.pumpAndSettle();

      final window = tester.getRect(find.byType(MaterialApp));
      final toast = tester.getRect(find.byKey(_toastKey));
      expect(toast.center.dx, closeTo(window.center.dx, 1));
      expect(window.bottom - toast.bottom, closeTo(26, 1));
      expect(toast.width, greaterThanOrEqualTo(220));
      expect(toast.width, lessThanOrEqualTo(360));
      expect(toast.height, closeTo(60, 1));

      await _drainHolds(tester);
    });

    testWidgets('the action fires once and takes the HUD with it',
        (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      var undone = 0;
      await _pumpHarness(tester, feedback);
      feedback.show(_completion(onAction: () => undone++));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_actionKey));
      await tester.pumpAndSettle();

      expect(undone, 1);
      // Leaving it up would invite a second tap on an action already taken.
      expect(find.byKey(_toastKey), findsNothing);

      await _drainHolds(tester);
    });
  });

  group('FB-HUD02 motion', () {
    testWidgets('the entrance rises into place rather than appearing',
        (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);
      feedback.show(_completion());
      await tester.pump();

      final start = tester.getRect(find.byKey(_toastKey)).top;
      await tester.pumpAndSettle();
      final settled = tester.getRect(find.byKey(_toastKey)).top;

      // Rises 44pt and overshoots slightly on the way in; the extra ~1pt is the
      // 0.96 start scale showing up in the painted rect.
      expect(start - settled, greaterThan(40));
      expect(start - settled, lessThan(50));

      await _drainHolds(tester);
    });

    testWidgets('dynamic feedback off keeps the HUD and drops the rise',
        (tester) async {
      final feedback = FeedbackController(animatedFeedback: false);
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback, animate: false);
      feedback.show(_completion());
      await tester.pump();

      final start = tester.getRect(find.byKey(_toastKey)).top;
      await tester.pumpAndSettle();
      final settled = tester.getRect(find.byKey(_toastKey)).top;

      expect(find.byKey(_toastKey), findsOneWidget);
      expect(start, closeTo(settled, .5));

      await _drainHolds(tester);
    });

    testWidgets('a completion holds 2.6s and one with an undo holds 4s',
        (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);

      // Timed by hand rather than with pumpAndSettle: the hold is a timer, and
      // what matters is where its boundaries are.
      feedback.show(_completion());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1500)); // t≈2.0s
      expect(find.byKey(_toastKey), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900)); // t≈2.9s
      await tester.pumpAndSettle();
      expect(find.byKey(_toastKey), findsNothing);

      // An undo affordance that leaves while the user is still reaching for it
      // is worse than none, so it gets 4s.
      feedback.show(_completion(onAction: () {}));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3500));
      expect(find.byKey(_toastKey), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900)); // t≈4.4s
      await tester.pumpAndSettle();
      expect(find.byKey(_toastKey), findsNothing);

      await _drainHolds(tester);
    });

    testWidgets('a replacement swaps in place instead of replaying',
        (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);
      feedback.show(_completion());
      await tester.pumpAndSettle();
      final resting = tester.getRect(find.byKey(_toastKey)).top;

      // A different completion of the same weight replaces the one on screen.
      // Replaying the entrance here would make the HUD look like it restarted
      // rather than like the message changed.
      feedback.show(_completion(message: '已完成另一项'));
      await tester.pump();

      expect(find.text('已完成另一项'), findsOneWidget);
      expect(find.text('任务已完成'), findsNothing);
      expect(tester.getRect(find.byKey(_toastKey)).top, closeTo(resting, .5));

      await _drainHolds(tester);
    });
  });

  group('FB-CTRL01 arbitration', () {
    testWidgets('two completions fold into one count', (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);

      for (var i = 0; i < 3; i++) {
        presentTaskResult(feedback, _completedSingle('task-$i'));
      }
      await tester.pumpAndSettle();

      expect(find.byKey(_toastKey), findsOneWidget);
      expect(find.text('已完成 3 个任务'), findsOneWidget);
      expect(find.text('任务已完成'), findsNothing);

      await _drainHolds(tester);
    });

    testWidgets('a batch total is not re-counted by a later single completion',
        (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);

      presentTaskResult(
          feedback,
          TaskActionResult.success(
              message: '已完成 3 个任务',
              feedback: TaskFeedbackIntent.completion));
      await tester.pumpAndSettle();
      expect(find.text('已完成 3 个任务'), findsOneWidget);

      presentTaskResult(feedback, _completedSingle('task-9'));
      await tester.pumpAndSettle();

      // The batch carries no coalesce key on purpose: folding a single
      // completion into it would recount three as two.
      expect(find.text('任务已完成'), findsOneWidget);
      expect(find.text('已完成 3 个任务'), findsNothing);

      await _drainHolds(tester);
    });

    testWidgets('a failure outranks everything', (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);

      presentTaskResult(feedback, TaskActionResult.failure('save', '保存失败'));
      await tester.pumpAndSettle();
      expect(find.text('保存失败'), findsOneWidget);

      // A completion must not push a failure off screen.
      presentTaskResult(feedback, _completedSingle('task-1'));
      await tester.pumpAndSettle();
      expect(find.text('保存失败'), findsOneWidget);

      // A later failure does replace a completion, and outranks an undo.
      feedback.dismiss();
      presentTaskResult(feedback, _completedSingle('task-1'));
      await tester.pumpAndSettle();
      presentTaskResult(feedback, TaskActionResult.failure('save', '保存失败'));
      await tester.pumpAndSettle();
      expect(find.text('保存失败'), findsOneWidget);

      await _drainHolds(tester);
    });

    testWidgets('an undo already on screen is not replaced by a completion',
        (tester) async {
      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback);

      presentTaskResult(
          feedback,
          TaskActionResult.success(
              taskId: 'task-1',
              message: '任务已移到废纸篓',
              undo: UndoCommand(label: '撤销删除', execute: () => true),
              feedback: TaskFeedbackIntent.undoable));
      await tester.pumpAndSettle();

      presentTaskResult(feedback, _completedSingle('task-2'));
      await tester.pumpAndSettle();

      expect(find.text('任务已移到废纸篓'), findsOneWidget);
      expect(find.byKey(_actionKey), findsOneWidget);

      await _drainHolds(tester);
    });
  });

  group('FB-TEST02 mapper', () {
    test('a batch completion cannot be aggregated', () {
      final batch = feedbackForTaskResult(TaskActionResult.success(
          message: '已完成 2 个任务',
          feedback: TaskFeedbackIntent.completion))!;
      expect(batch.kind, WorkFollowFeedbackKind.completion);
      expect(batch.sound, WorkFollowFeedbackSound.completion);
      expect(batch.coalesceKey, isNull);
      expect(batch.actionLabel, '撤销');
      // Nothing to undo, so no action is offered.
      expect(batch.onAction, isNull);

      final single = feedbackForTaskResult(_completedSingle('task-1'))!;
      expect(single.coalesceKey, 'task-completed');
      expect(single.coalescedMessage!(2), '已完成 2 个任务');
      expect(single.onAction, isNotNull);
    });

    test('failures never borrow the completion treatment', () {
      final failure =
          feedbackForTaskResult(TaskActionResult.failure('save', '保存失败'))!;
      expect(failure.kind, WorkFollowFeedbackKind.error);
      expect(failure.sound, WorkFollowFeedbackSound.none);
      expect(failure.hold, const Duration(milliseconds: 5000));
    });

    test('an unmigrated result reports, without inventing an undo', () {
      final plain = feedbackForTaskResult(TaskActionResult.success(
          taskId: 'task-1',
          message: '已复制',
          undo: UndoCommand(label: '撤销修改', execute: () => true)))!;
      expect(plain.kind, WorkFollowFeedbackKind.undoable);
      expect(plain.sound, WorkFollowFeedbackSound.none);

      final silent = feedbackForTaskResult(
          TaskActionResult.success(taskId: 'task-1', message: null));
      // A property edit the row already shows needs no HUD.
      expect(silent, isNull);
    });

    test('movedAwayFeedback offers to follow the task', () {
      final moved = movedAwayFeedback(
          TaskActionResult.success(taskId: 'task-1', message: '已添加到收集箱'),
          onOpen: () {});
      expect(moved.kind, WorkFollowFeedbackKind.success);
      expect(moved.actionLabel, '查看任务');
      expect(moved.actionIcon, WorkFollowIcons.next);
      expect(moved.onAction, isNotNull);
    });
  });

  group('FB-TEST03 sound', () {
    MethodChannel channelWith(List<String> calls) {
      const channel = MethodChannel('workfollow/feedback');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add('${call.method}:${call.arguments}');
        return null;
      });
      return channel;
    }

    testWidgets('the tone is throttled to one per second', (tester) async {
      final calls = <String>[];
      final channel = channelWith(calls);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final sound = FeedbackSoundService(channel: channel);
      expect(await sound.play(WorkFollowFeedbackSound.completion), isTrue);
      expect(calls, ['playFeedbackSound:completion']);

      // Ticking off a list must not mean one chime per row.
      expect(await sound.play(WorkFollowFeedbackSound.completion), isFalse);
      expect(calls, hasLength(1));

      // Silence is not a sound and must not consume the throttle window.
      expect(await sound.play(WorkFollowFeedbackSound.none), isFalse);
      expect(calls, hasLength(1));

      sound.resetThrottle();
      expect(await sound.play(WorkFollowFeedbackSound.focus), isTrue);
      expect(calls.last, 'playFeedbackSound:focus');
    });

    testWidgets('the setting gates the tone, not the HUD', (tester) async {
      final calls = <String>[];
      final channel = channelWith(calls);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final muted = FeedbackController(
          soundService: FeedbackSoundService(channel: channel),
          completionSoundEnabled: false);
      addTearDown(muted.dispose);
      await _pumpHarness(tester, muted);
      muted.show(_completion());
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.byKey(_toastKey), findsOneWidget);

      final audible = FeedbackController(
          soundService: FeedbackSoundService(channel: channel));
      addTearDown(audible.dispose);
      audible.show(_completion());
      await tester.pumpAndSettle();
      expect(calls, ['playFeedbackSound:completion']);

      await _drainHolds(tester);
    });
  });

  group('FB-MIG02 list row', () {
    testWidgets('ticking a task reports once, and the undo un-ticks it',
        (tester) async {
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);
      controller.selectView(WorkspaceView.today);
      controller.createTask(TaskDraft(
          title: '写完周报',
          schedule: TaskScheduleDraft(dueAt: _startOfToday, hasTime: false)));
      final id = controller.tasks.single.id;

      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback, page: _todayPage(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('task-row-checkbox-$id')));
      // The row reports as part of the same synchronous turn, so the HUD has to
      // be up on the next frame — and there must be exactly one of it.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(_toastKey), findsOneWidget);
      expect(find.text('任务已完成'), findsOneWidget);
      expect(controller.tasks.single.completed, isTrue);

      // Let the entrance settle before aiming at the action: it starts 44pt
      // lower than it rests.
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_actionKey));
      await tester.pumpAndSettle();

      expect(controller.tasks.single.completed, isFalse);
      expect(find.byKey(_toastKey), findsNothing);

      await _drainHolds(tester);
    });

    testWidgets('a row without a host reports nothing instead of throwing',
        (tester) async {
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);
      controller.selectView(WorkspaceView.today);
      controller.createTask(TaskDraft(
          title: '无宿主',
          schedule: TaskScheduleDraft(dueAt: _startOfToday, hasTime: false)));
      final id = controller.tasks.single.id;

      await _pumpPageWithoutHost(tester, _todayPage(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('task-row-checkbox-$id')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(controller.tasks.single.completed, isTrue);
    });

    testWidgets('顺延 reports one undoable HUD for the whole group',
        (tester) async {
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);
      controller.selectView(WorkspaceView.today);
      for (final title in ['逾期的报告', '逾期的对账']) {
        controller.createTask(TaskDraft(
            title: title,
            schedule: TaskScheduleDraft(
                dueAt: _startOfToday.subtract(const Duration(days: 1)),
                hasTime: false)));
      }

      final feedback = FeedbackController();
      addTearDown(feedback.dispose);
      await _pumpHarness(tester, feedback, page: _todayPage(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('group-postpone-overdue')));
      await tester.pumpAndSettle();

      expect(find.byKey(_toastKey), findsOneWidget);
      expect(find.text('已顺延 2 项到 今天'), findsOneWidget);

      await tester.tap(find.byKey(_actionKey));
      await tester.pumpAndSettle();

      // Both come back: the group move is one undo, not just the last snapshot.
      for (final task in controller.tasks) {
        expect(task.bucket, TaskBucket.overdue);
      }

      await _drainHolds(tester);
    });
  });
}
