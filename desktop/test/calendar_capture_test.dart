import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/screens/calendar_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_task_bar.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_week_view.dart';

/// Writes a PNG of the month grid to /private/tmp when the run is asked for one:
///
/// ```bash
/// flutter test test/calendar_capture_test.dart --dart-define=CALENDAR_CAPTURE=true
/// ```
///
/// The assertions run either way, so this is a test first and a screenshot
/// second.
const capture = bool.fromEnvironment('CALENDAR_CAPTURE');

/// The theme the desktop build resolves at runtime, spelled out.
///
/// macOS gets its faces from the system cascade, and the test engine has none:
/// without pinning the family here every glyph renders as a placeholder box.
/// The button theme is separate because a button's own text style overrides
/// what it would otherwise inherit, which shows up as one readable label and
/// one row of boxes.
ThemeData _captureTheme() {
  final base = WorkFollowThemeData.light();
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Hiragino Sans GB'),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            textStyle: const TextStyle(fontFamily: 'Hiragino Sans GB'))),
  );
}

/// The calendar as the shell mounts it: the page owns its own surface, so this
/// is the whole window apart from the navigation rail.
Widget _page(GlobalKey boundary, WorkspaceController controller) => MaterialApp(
      theme: _captureTheme(),
      home: RepaintBoundary(
        key: boundary,
        child: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => CalendarScreen(controller: controller),
          ),
        ),
      ),
    );

Future<void> _write(WidgetTester tester, GlobalKey boundary, String name) async {
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/private/tmp/$name').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!capture) return;
    // The test engine has no system font cascade, so the faces the desktop
    // build resolves at runtime have to be registered by hand or every glyph
    // comes out as a placeholder box.
    final font = File('/System/Library/Fonts/Hiragino Sans GB.ttc');
    for (final family in [
      'Inter',
      'Noto Sans SC',
      'PingFang SC',
      'Hiragino Sans GB',
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

  testWidgets('the month grid renders a month of work', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);

    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    DateTime day(int dayOfMonth, [int hour = 0, int minute = 0]) =>
        DateTime(month.year, month.month, dayOfMonth, hour, minute);

    void schedule(String title, String list, DateTime at,
        {bool timed = false}) {
      controller.createTaskFromComposer(
        title: title,
        listName: list,
        scheduleOverridden: timed,
        schedule: timed
            ? TaskScheduleDraft(dueAt: at, hasTime: true)
            : const TaskScheduleDraft(),
        fallbackSchedule: TaskScheduleDraft.forDay(at),
      );
    }

    /// A run of days, written the way the schedule panel writes one: a start
    /// and an end, with the end's date deciding how far the run reaches.
    String range(String title, String list, DateTime from, DateTime to,
        {bool timed = false}) {
      final result = controller.createTaskFromComposer(
        title: title,
        listName: list,
        scheduleOverridden: true,
        schedule: TaskScheduleDraft(dueAt: from, hasTime: timed),
        fallbackSchedule: TaskScheduleDraft.forDay(from),
      );
      controller.taskActions.setScheduleSettings(
        result.taskId!,
        TaskScheduleSettings(
          schedule: TaskScheduleDraft(dueAt: from, hasTime: timed),
          endAt: to,
        ),
      );
      return result.taskId!;
    }

    // A working month: some days busy, one day over capacity, a couple of
    // finished items, and work spilling into the neighbouring months so the
    // leading and trailing cells are exercised too.
    schedule('阅读《设计心理学》第 4 章并做摘录', '学习', day(2));
    schedule('季度评审材料初稿', '工作', day(3));
    schedule('站会同步接口联调进度', '工作', day(7, 9, 30), timed: true);
    schedule('整理用户反馈：移动端适配问题清单', '工作', day(7, 14));
    schedule('回访三位试用用户', '工作', day(7, 16));
    schedule('把任务列表同步到日历格子', '工作', day(7));
    schedule('补充周报数据口径说明', '工作', day(7));
    schedule('评审埋点方案', '工作', day(7, 11));
    schedule('给日历加拖拽改期', '工作', day(7));
    schedule('写本周复盘', '个人', day(11));
    schedule('理发', '个人', day(14));
    schedule('月度账单核对', '个人', day(18));
    schedule('给日历工具补回归用例', '工作', day(21));
    schedule('和小李对一下排期', '工作', day(21, 15), timed: true);
    schedule('读《重构》第 6 章', '学习', day(24));
    schedule('准备下周评审', '工作', day(28));
    schedule('提前一天的事', '工作', day(0));
    schedule('下月初的第一件事', '工作', day(32));

    // Runs that last more than a day. One sits inside a single week row, one
    // crosses the row boundary and today, and one is a timed range whose end
    // is what the band's clock prints.
    range('出差：客户现场', '工作', day(8), day(12));
    final reviewWeek = range('设计评审周', '工作', day(16), day(20));
    range('季度培训', '学习', day(23, 9), day(25, 18), timed: true);

    final done = controller.tasks
        .where((task) => task.title == '读《重构》第 6 章')
        .first;
    controller.toggleTask(done.id);
    final alsoDone = controller.tasks
        .where((task) => task.title == '月度账单核对')
        .first;
    controller.toggleTask(alsoDone.id);

    final boundary = GlobalKey();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(_page(boundary, controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('calendar-month-title')), findsOneWidget);
      expect(controller.tasksForDay(day(7)).length, 7);
      // 9/16 to 9/20 leaves the row that opens on 9/13, so it is drawn twice:
      // once running off the right edge of that row and once picking up at the
      // left edge of the next.
      expect(controller.spansMultipleDays(controller.tasks
          .firstWhere((task) => task.id == reviewWeek)), isTrue);
      expect(find.byType(CalendarTaskSpan), findsNWidgets(4));

      if (capture) await _write(tester, boundary, 'calendar-month.png');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  /// The week view shares the page and therefore the page's edges. It is worth
  /// its own frame because the two views carry their own structure — the month
  /// grid draws its own lines to the edge, the week draws cards — and only one
  /// of them is visible at a time.
  testWidgets('the week view fills the page the same way', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);

    final now = DateTime.now();
    // Anchor the seven tasks to the week's own first day rather than to today.
    // The window used to start two days back, which lands in the previous week
    // whenever today is Sunday or Monday — the view reads the current week, so
    // a task seeded at `now - 2` was simply not on the page and this test went
    // red on two days out of seven. `weekday % 7` is the Sunday-first index the
    // month grid uses.
    final weekStart =
        DateTime(now.year, now.month, now.day - now.weekday % 7);
    for (var offset = 0; offset < 7; offset++) {
      final at = weekStart.add(Duration(days: offset));
      controller.createTaskFromComposer(
        title: '第 ${offset + 1} 件事',
        listName: offset.isEven ? '工作' : '个人',
        scheduleOverridden: false,
        schedule: const TaskScheduleDraft(),
        fallbackSchedule: TaskScheduleDraft.forDay(at),
      );
    }

    final boundary = GlobalKey();
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(_page(boundary, controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-view-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-option-week')));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarWeekView), findsOneWidget);
      expect(find.text('第 1 件事'), findsOneWidget);

      if (capture) await _write(tester, boundary, 'calendar-week.png');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
