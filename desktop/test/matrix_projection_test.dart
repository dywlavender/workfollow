import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/matrix/matrix_projection.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/screens/matrix_screen.dart';

const captureMatrix = bool.fromEnvironment('MATRIX_CAPTURE');

TaskItem _task(
  String id, {
  bool completed = false,
  String listName = '收集箱',
  DateTime? dueAt,
  TaskPriority priority = TaskPriority.none,
}) {
  return TaskItem(
    id: id,
    title: id,
    listName: listName,
    bucket: taskBucketForDate(dueAt, completed: completed),
    dueAt: dueAt?.toIso8601String(),
    completed: completed,
    priority: priority,
  );
}

void main() {
  setUpAll(() async {
    if (!captureMatrix) return;
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    for (final family in [
      'Inter',
      'Noto Sans SC',
      'PingFang SC',
      'Roboto',
      'Ahem',
      '.SF Pro Text',
      '.SF Pro Display',
    ]) {
      await (FontLoader(family)
            ..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync()))))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  test('matrix projection keeps active list groups and one completed group',
      () {
    final now = DateTime(2026, 9, 16, 10);
    final active = _task('active', listName: '工作', dueAt: now);
    final done = _task('done',
        completed: true, dueAt: now.subtract(const Duration(days: 2)));
    final projected = MatrixProjection.project(
      tasks: [done, active],
      listOrder: const ['收集箱', '工作'],
      quadrantFor: (task) =>
          task.completed ? MatrixQuadrant.doNow : MatrixQuadrant.schedule,
      now: now,
    );

    final schedule = projected
        .firstWhere((item) => item.quadrant == MatrixQuadrant.schedule);
    expect(schedule.groups.single.title, '工作');
    expect(schedule.groups.single.completedGroup, isFalse);
    expect(schedule.groups.single.tasks.single.task.id, 'active');
    expect(schedule.groups.single.tasks.single.dateLabel, '今天');

    final doNow =
        projected.firstWhere((item) => item.quadrant == MatrixQuadrant.doNow);
    expect(doNow.groups.single.title, '已完成');
    expect(doNow.groups.single.completedGroup, isTrue);
    expect(doNow.groups.single.tasks.single.task.id, 'done');
  });

  test('matrix creation maps the four quadrants to real task fields', () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    controller.createTaskInMatrixQuadrant('do now', MatrixQuadrant.doNow);
    controller.createTaskInMatrixQuadrant('schedule', MatrixQuadrant.schedule);
    controller.createTaskInMatrixQuadrant('delegate', MatrixQuadrant.delegate);
    controller.createTaskInMatrixQuadrant('later', MatrixQuadrant.later);
    controller.createTaskInMatrixQuadrant(
      'implicit default date',
      MatrixQuadrant.doNow,
      schedule: const TaskScheduleDraft(),
    );

    final doNow = controller.tasks.firstWhere((task) => task.title == 'do now');
    final schedule =
        controller.tasks.firstWhere((task) => task.title == 'schedule');
    final delegate =
        controller.tasks.firstWhere((task) => task.title == 'delegate');
    final later = controller.tasks.firstWhere((task) => task.title == 'later');
    final implicit = controller.tasks
        .firstWhere((task) => task.title == 'implicit default date');
    expect(doNow.priority, TaskPriority.high);
    expect(localDateTimeFromStorage(doNow.dueAt), today);
    expect(schedule.priority, TaskPriority.high);
    expect(localDateTimeFromStorage(schedule.dueAt),
        today.add(const Duration(days: 7)));
    expect(delegate.priority, TaskPriority.low);
    expect(localDateTimeFromStorage(delegate.dueAt), today);
    expect(later.priority, TaskPriority.none);
    expect(later.dueAt, isNull);
    expect(localDateTimeFromStorage(implicit.dueAt), today);
  });

  test('moving a task between quadrants applies the matrix field semantics',
      () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final created =
        controller.createTaskInMatrixQuadrant('拖动任务', MatrixQuadrant.later);
    final taskId = created.taskId!;

    controller.moveTaskToMatrix(taskId, MatrixQuadrant.delegate);
    var task = controller.tasks.firstWhere((item) => item.id == taskId);
    expect(task.priority, TaskPriority.none);
    expect(localDateTimeFromStorage(task.dueAt), today);
    expect(controller.matrixQuadrantFor(task), MatrixQuadrant.delegate);

    controller.moveTaskToMatrix(taskId, MatrixQuadrant.doNow);
    task = controller.tasks.firstWhere((item) => item.id == taskId);
    expect(task.priority, TaskPriority.high);
    expect(localDateTimeFromStorage(task.dueAt), today);
    expect(controller.matrixQuadrantFor(task), MatrixQuadrant.doNow);

    controller.moveTaskToMatrix(taskId, MatrixQuadrant.schedule);
    task = controller.tasks.firstWhere((item) => item.id == taskId);
    expect(task.priority, TaskPriority.high);
    expect(localDateTimeFromStorage(task.dueAt),
        today.add(const Duration(days: 7)));
    expect(controller.matrixQuadrantFor(task), MatrixQuadrant.schedule);

    controller.moveTaskToMatrix(taskId, MatrixQuadrant.later);
    task = controller.tasks.firstWhere((item) => item.id == taskId);
    expect(task.priority, TaskPriority.none);
    expect(controller.matrixQuadrantFor(task), MatrixQuadrant.later);
  });

  testWidgets('matrix date metadata opens the full schedule panel',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final created =
        controller.createTaskInMatrixQuadrant('可编辑日期', MatrixQuadrant.doNow);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => MatrixScreen(controller: controller),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(ValueKey('matrix-task-date-${created.taskId}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-schedule-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-date-tab')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-reminder')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-repeat')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('date-shortcut-明天')));
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();

    final task =
        controller.tasks.firstWhere((item) => item.id == created.taskId);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    expect(localDateTimeFromStorage(task.dueAt), tomorrow);
    expect(find.text('明天'), findsOneWidget);
  });

  testWidgets('matrix plus opens a task editor with date and property controls',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: MatrixScreen(controller: controller)),
    ));
    await tester.pumpAndSettle();

    final quadrant = find.byKey(const ValueKey('matrix-quadrant-doNow'));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: tester.getCenter(quadrant));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('matrix-quadrant-add-doNow')));
    await tester.pumpAndSettle();

    // The composer is shared, so its keys are named after what it is rather
    // than after the page that happened to open it first.
    expect(find.byKey(const ValueKey('task-add-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-add-schedule')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-add-priority')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-add-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-add-more')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('task-add-title')), '面板新任务');
    await tester.tap(find.byKey(const ValueKey('task-add-schedule')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-schedule-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('date-shortcut-明天')));
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final task = controller.tasks.firstWhere((item) => item.title == '面板新任务');
    final now = DateTime.now();
    expect(localDateTimeFromStorage(task.dueAt),
        DateTime(now.year, now.month, now.day + 1));
    expect(task.priority, TaskPriority.high);
    await pointer.removePointer();
  });

  testWidgets('matrix task body opens the popup inspector in place',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final created = controller.createTaskInMatrixQuadrant(
        '矩阵浮层任务', MatrixQuadrant.schedule);
    final boundary = GlobalKey();

    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => MatrixScreen(controller: controller),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('矩阵浮层任务'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-inspector-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-inspector-footer')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-schedule')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-list-footer')), findsOneWidget);
    expect(controller.selectedTaskId, isNull);
    expect(find.byKey(ValueKey('matrix-task-${created.taskId}')), findsOneWidget);

    if (captureMatrix) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/private/tmp/matrix-task-editor-popup.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-schedule-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-date-tab')), findsOneWidget);

    if (captureMatrix) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/private/tmp/matrix-task-editor-date-panel.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('matrix renders a fixed 2x2 board and completed rows by default',
      (tester) async {
    tester.view.physicalSize = const Size(880, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.createTaskInMatrixQuadrant('未完成任务', MatrixQuadrant.doNow);
    final completed =
        controller.createTaskInMatrixQuadrant('已完成任务', MatrixQuadrant.schedule);
    controller.taskActions.complete(completed.taskId!);

    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: RepaintBoundary(
        key: boundary,
        child: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => MatrixScreen(controller: controller),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('四象限'), findsOneWidget);
    expect(find.text('重要且紧急'), findsOneWidget);
    expect(find.text('重要不紧急'), findsOneWidget);
    expect(find.text('不重要但紧急'), findsOneWidget);
    expect(find.text('不重要不紧急'), findsOneWidget);
    expect(find.byKey(const ValueKey('matrix-page-more')), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('已完成任务'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('matrix-quadrant-doNow'))),
        tester.getSize(find.byKey(const ValueKey('matrix-quadrant-schedule'))));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('matrix-quadrant-doNow')))
            .height,
        lessThan(360));

    if (captureMatrix) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/private/tmp/matrix-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('matrix rows complete in place and groups fold independently',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final active =
        controller.createTaskInMatrixQuadrant('待完成', MatrixQuadrant.doNow);
    controller.createTaskInMatrixQuadrant('另一件', MatrixQuadrant.delegate);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => MatrixScreen(controller: controller),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final checkbox =
        find.byKey(ValueKey('matrix-task-checkbox-${active.taskId}'));
    expect(checkbox, findsOneWidget);
    expect(tester.widget<IconButton>(checkbox).onPressed, isNotNull);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(
        controller.tasks
            .firstWhere((task) => task.id == active.taskId)
            .completed,
        isTrue);
    expect(find.text('待完成'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('matrix-group-chevron-delegate:list:收集箱')));
    await tester.pumpAndSettle();
    expect(find.text('另一件'), findsNothing);
    expect(find.text('待完成'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('matrix-page-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-show-completed')));
    await tester.pumpAndSettle();
    expect(find.text('待完成'), findsNothing);
  });
}
