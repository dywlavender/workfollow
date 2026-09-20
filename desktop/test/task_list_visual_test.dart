import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

/// Renders the task list to `docs/screenshots/` for visual review:
///
/// ```bash
/// flutter test test/task_list_visual_test.dart --dart-define=WORKFOLLOW_CAPTURE=true
/// ```
///
/// Two things are forced here, and both are needed for the picture to mean
/// anything. `debugDefaultTargetPlatformOverride` pins the macOS branch of
/// [WorkFollowThemeData], because the test host otherwise reports android and
/// the theme would render the Web type stack instead. A real CJK face is then
/// registered under the family names the theme asks for, because flutter_test's
/// placeholder font draws every glyph as a filled box — see the build skill's
/// note on test screenshots.
const capture = bool.fromEnvironment('WORKFOLLOW_CAPTURE');
final boundary = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!capture) return;
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    if (font.existsSync()) {
      final bytes = font.readAsBytesSync();
      // `fontFamily` is null on the macOS branch, so the face has to be
      // registered under the names the engine falls back through.
      for (final family in [
        'PingFang SC',
        'Hiragino Sans GB',
        '.SF Pro Text',
        '.SF Pro Display',
        'Roboto',
        'Ahem',
      ]) {
        await (FontLoader(family)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  Future<void> shoot(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.pumpAndSettle();
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../docs/screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  /// The list pane at its preferred width, with all three group kinds present
  /// so the heading grammar (chevron, label, count, 顺延) can be read off one
  /// picture.
  testWidgets('LIST-D01 capture the task list pane', (tester) async {
    tester.view.physicalSize = const Size(440, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    controller.createTask(TaskDraft(
        title: '整理上周的接口评审纪要',
        description: '把结论同步给测试与运维',
        listName: '工作',
        schedule: TaskScheduleDraft(
            dueAt: yesterday.add(const Duration(hours: 9, minutes: 30)),
            hasTime: true)));
    controller.createTask(TaskDraft(
        title: '补交上季度发票',
        listName: '个人',
        schedule: TaskScheduleDraft(dueAt: yesterday, hasTime: false),
        priority: TaskPriority.high));
    controller.createTask(TaskDraft(
        title: '和产品过一遍验收清单',
        schedule: TaskScheduleDraft(
            dueAt: today.add(const Duration(hours: 10)), hasTime: true)));
    controller.createTask(TaskDraft(
        title: '写周报',
        description: '本周进展与下周计划',
        schedule: TaskScheduleDraft(dueAt: today, hasTime: false),
        recurrence: const RecurrenceDraft(type: 'WEEKLY', config: {'weekday': 3})));
    controller.createTask(TaskDraft(
        title: '回复客户的邮件',
        schedule: TaskScheduleDraft(dueAt: today, hasTime: false)));
    controller.taskActions.complete(controller.tasks.last.id);

    // Pinned inside the body: flutter_test refuses to let a foundation debug
    // variable differ once a test returns, so it cannot be set in setUpAll.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      // The macOS branch leaves `fontFamily` null and lets the platform resolve
      // the face. The test engine has no such cascade, and its placeholder font
      // claims a glyph for part of the text while dropping the rest, which is
      // what turned counts and a few characters into filled boxes. Naming the
      // loaded face explicitly is the only way to get a legible picture; the
      // geometry is unchanged, the type resolution is approximated.
      final base = WorkFollowThemeData.light();
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Hiragino Sans GB'),
          // The date chips are TextButtons, and a button resolves its own
          // `textStyle` over the inherited one, which put the family back to a
          // face the engine cannot find — so `今天` and `10:00` drew as boxes
          // while the plain Text beside them was fine.
          textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: 'Hiragino Sans GB'))));
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: RepaintBoundary(
                  key: boundary,
                  child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => TodayScreen(
                          controller: controller,
                          persistentInspector: false))))));
      await tester.pumpAndSettle();

      await shoot(tester, 'task-list-groups');

      // Same list with 已过期 folded, so the fold is visible next to the open
      // state: heading and count stay, the row goes.
      await tester.tap(find.byKey(const ValueKey('group-chevron-已过期')));
      await tester.pumpAndSettle();
      await shoot(tester, 'task-list-groups-folded');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  /// Finished rows on their own, so the ink ladder can be *measured* instead of
  /// eyeballed: one title, one preview, one trailing column and one box, all on
  /// the same background, with nothing open beside them to compare against.
  testWidgets('LIST-D02 capture finished rows', (tester) async {
    tester.view.physicalSize = const Size(440, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.completed);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    controller.createTask(TaskDraft(
        title: '接口评审纪要',
        description: '把结论同步给测试与运维',
        listName: '工作',
        schedule: TaskScheduleDraft(
            dueAt: today.subtract(const Duration(days: 12)), hasTime: false)));
    controller.createTask(TaskDraft(
        title: '补交发票',
        description: '上季度',
        listName: '个人',
        schedule: TaskScheduleDraft(
            dueAt: today.add(const Duration(hours: 9)), hasTime: true)));
    for (final task in controller.tasks) {
      controller.taskActions.complete(task.id);
    }

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final base = WorkFollowThemeData.light();
      final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Hiragino Sans GB'),
          textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: 'Hiragino Sans GB'))));
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: RepaintBoundary(
                  key: boundary,
                  child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => TodayScreen(
                          controller: controller,
                          persistentInspector: false))))));
      await tester.pumpAndSettle();
      await shoot(tester, 'task-list-completed-rows');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
