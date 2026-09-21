import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/calendar_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/theme/workfollow_theme_parity.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_day_cell.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_month_view.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_task_bar.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_week_view.dart';
import 'package:workfollow_personal/widgets/task_completion_box.dart';

const _tokens = WorkFollowTheme.light;

/// The month grid on its own, with today pinned so the circled day is not a
/// function of the machine clock.
///
/// Wrapped in an [AnimatedBuilder] because the grid only reads the controller:
/// the shell is what listens, so a test that mounts the grid directly has to
/// supply the listening itself.
Future<void> _pumpGrid(
  WidgetTester tester,
  WorkspaceController controller, {
  required DateTime month,
  DateTime? selectedDay,
  DateTime? today,
  bool showCompleted = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: WorkFollowThemeData.light(),
    home: Scaffold(
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CalendarMonthView(
          month: month,
          controller: controller,
          selectedDay: selectedDay,
          showCompleted: showCompleted,
          today: today,
          onSelectDay: (_) {},
          onOpenTask: (_, __) {},
          onCreateTask: (_, __) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
    WidgetTester tester, WorkspaceController controller) async {
  await tester.pumpWidget(MaterialApp(
    theme: WorkFollowThemeData.light(),
    home: Scaffold(
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CalendarScreen(controller: controller),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Creates a task on [day] through the same entry point the calendar uses, and
/// hands back its id. A task is all-day unless [at] gives it a time.
///
/// A task that runs over several days is not a different kind of task, it is a
/// schedule with an end — so [until] goes through the same settings action the
/// schedule panel pops with, and the range is whatever the two dates say.
String _taskOn(WorkspaceController controller, DateTime day, String title,
    {String listName = '收集箱', DateTime? at, DateTime? until}) {
  final timed = at != null;
  final ranged = until != null;
  final start = at ?? day;
  final result = controller.createTaskFromComposer(
    title: title,
    listName: listName,
    scheduleOverridden: timed || ranged,
    schedule: timed || ranged
        ? TaskScheduleDraft(dueAt: start, hasTime: timed)
        : const TaskScheduleDraft(),
    fallbackSchedule: TaskScheduleDraft.forDay(day),
  );
  final id = result.taskId!;
  if (ranged) {
    controller.taskActions.setScheduleSettings(
      id,
      TaskScheduleSettings(
        schedule: TaskScheduleDraft(dueAt: start, hasTime: timed),
        endAt: until,
      ),
    );
  }
  return id;
}

Finder _dayCell(DateTime date) =>
    find.byKey(ValueKey('calendar-day-${calendarDayKey(date)}'));

Finder _taskBar(String id) => find.byKey(ValueKey('calendar-task-$id'));

/// One week row's piece of a multi-day task, addressed by the row it belongs
/// to and the column it starts at.
Finder _band(String id, int fromColumn) =>
    find.byKey(ValueKey('calendar-span-$id-$fromColumn'));

/// The colour a bar's own surface is painted with — the bar's, not the wash
/// today lays over the row it sits in.
Color _barFill(WidgetTester tester, Finder bar) => tester
    .widget<Material>(
        find.descendant(of: bar, matching: find.byType(Material)).first)
    .color!;

Finder _row(int rowIndex) => find.byKey(ValueKey('calendar-week-row-$rowIndex'));

/// The paper a day is drawn on.
///
/// The cell owns nothing that has to cross between cells, so this is its
/// background and nothing else: no border, no wash, no radius. Today's wash
/// and the hairlines are the week row's.
Color? _cellFill(WidgetTester tester, DateTime date) =>
    tester.widget<Container>(_dayCell(date)).color;

/// One line of the grid, which is painted by the row and by no day.
BoxDecoration _hairline(WidgetTester tester,
        {required int row, required int column}) =>
    tester
        .widget<DecoratedBox>(
            find.byKey(ValueKey('calendar-hairline-$row-$column')))
        .decoration as BoxDecoration;

/// The style of a day's number, addressed by the words the cell actually
/// draws — so a first of the month is looked up as "9月1日" and the test does
/// not restate a rule the cell owns.
TextStyle _numberStyle(WidgetTester tester, DateTime date) =>
    tester.widget<Text>(find.descendant(
        of: _dayCell(date),
        matching: find.text(calendarDayLabel(date)))).style!;

/// The holiday a day is labelled with, or null when it carries none.
String? _festival(WidgetTester tester, DateTime date) {
  final finder = find.byKey(
      ValueKey('calendar-day-festival-${calendarDayKey(date)}'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

/// The corner rounding of a bar or a band's piece.
BorderRadius _radiusOf(WidgetTester tester, Finder finder) => tester
    .widget<Material>(
        find.descendant(of: finder, matching: find.byType(Material)).first)
    .borderRadius! as BorderRadius;

/// The `HH:mm` labels inside a bar, which is how a test tells a clock from a
/// title without depending on the widget that draws it.
List<String> _clocksIn(WidgetTester tester, Finder finder) => tester
    .widgetList<Text>(find.descendant(of: finder, matching: find.byType(Text)))
    .map((text) => text.data ?? '')
    .where((data) => RegExp(r'^\d{2}:\d{2}$').hasMatch(data))
    .toList();

/// The completion box a bar or a week item leads with.
TaskCompletionBox _boxIn(WidgetTester tester, Finder finder) =>
    tester.widget<TaskCompletionBox>(
        find.descendant(of: finder, matching: find.byType(TaskCompletionBox)));

/// What a completion box actually paints — a fill when the task is done, an
/// outline when it is not. Read off the render objects rather than off the
/// widget's arguments, so an assertion about colour holds however the box is
/// drawn.
BoxDecoration _boxPaint(WidgetTester tester, Finder finder) => tester
    .widget<DecoratedBox>(
        find.descendant(of: finder, matching: find.byType(DecoratedBox)).first)
    .decoration as BoxDecoration;

/// Where one of a row's layers sits in that row's stack.
///
/// The row is a stack of cells, bands, today's wash and lines, and the order
/// is the design rather than an accident of the code — a band has to cover the
/// cells, the wash has to land on a band that crosses today, and the lines
/// have to cross both. Nothing about the painted result can be asserted
/// directly, so the order itself is what is pinned.
int _layerIndex(WidgetTester tester,
    {required int row, required Finder layer}) {
  final stack = tester.widget<Stack>(_row(row));
  return stack.children.indexOf(tester.widget(layer));
}

void main() {
  group('month grid skeleton', () {
    testWidgets('opens on Sunday and keeps the previous month\'s closing days',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      // The header and the leading offset have to agree. A Sunday-first header
      // over a Monday-first grid shifts every date in the month by a column.
      expect(CalendarWeekHeader.labels.first, '周日');
      expect(CalendarWeekHeader.labels.last, '周六');

      // September 2026 opens on a Tuesday, so the grid opens two days earlier.
      final sunday = _dayCell(DateTime(2026, 8, 30));
      final monday = _dayCell(DateTime(2026, 8, 31));
      final tuesday = _dayCell(DateTime(2026, 9, 1));
      expect(sunday, findsOneWidget);
      expect(monday, findsOneWidget);
      expect(tuesday, findsOneWidget);

      final sundayRect = tester.getRect(sunday);
      final mondayRect = tester.getRect(monday);
      final tuesdayRect = tester.getRect(tuesday);
      expect(sundayRect.top, mondayRect.top);
      expect(mondayRect.top, tuesdayRect.top);
      expect(sundayRect.left, lessThan(mondayRect.left));
      expect(mondayRect.left, lessThan(tuesdayRect.left));

      // Neighbours share an edge: the grid is continuous, so there is no
      // gutter between one day and the next.
      expect(mondayRect.left, sundayRect.right);
      expect(tuesdayRect.left, mondayRect.right);
    });

    testWidgets('draws the neighbouring months\' dates, one step back in ink',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      // The cell keeps its number rather than being blanked out.
      final leading = _dayCell(DateTime(2026, 8, 30));
      expect(find.descendant(of: leading, matching: find.text('30')),
          findsOneWidget);
      expect(_numberStyle(tester, DateTime(2026, 8, 30)).color,
          _tokens.textTertiary);
      expect(_numberStyle(tester, DateTime(2026, 9, 1)).color,
          _tokens.textPrimary);

      // The cell steps back with it: the page's own background rather than the
      // sheet's, which says "not this month" without looking switched off.
      expect(_cellFill(tester, DateTime(2026, 8, 30)), _tokens.canvas);
      expect(_cellFill(tester, DateTime(2026, 9, 1)), _tokens.content);
    });

    testWidgets('a first of the month says which month it belongs to',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 1));

      // The grid opens with August's closing days and closes with October's
      // opening ones, so a bare "1" at either end does not say which of the
      // three months on screen it belongs to. Both ends spell the month out.
      expect(
          find.descendant(
              of: _dayCell(DateTime(2026, 9, 1)), matching: find.text('9月1日')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _dayCell(DateTime(2026, 10, 1)),
              matching: find.text('10月1日')),
          findsOneWidget);
      // And only a first: every other day of a month is unambiguous.
      expect(
          find.descendant(
              of: _dayCell(DateTime(2026, 8, 31)), matching: find.text('31')),
          findsOneWidget);

      // Naming the month does not move the day into the month on screen:
      // October's first is still drawn a step back in ink. September's is not,
      // because it is the month being shown.
      expect(_numberStyle(tester, DateTime(2026, 10, 1)).color,
          _tokens.textTertiary);

      // The marker grows to hold the words rather than clipping them, and stays
      // one capsule instead of a 24pt circle painted behind a wider label.
      final marker = find.byKey(ValueKey(
          'calendar-day-marker-${calendarDayKey(DateTime(2026, 9, 1))}'));
      expect(tester.getSize(marker).height, CalendarMetrics.dayCellSize);
      expect(tester.getSize(marker).width,
          greaterThan(CalendarMetrics.dayCellSize));
      final fill = tester.widget<Container>(marker).decoration! as BoxDecoration;
      expect(fill.color, _tokens.accent);
      expect(fill.borderRadius,
          BorderRadius.circular(CalendarMetrics.dayCellSize / 2));
    });

    testWidgets('a holiday is named in the corner of its day', (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      // 教师节 9/10 and 中秋节 9/25 fall in the month on screen; 国庆节 10/1 is
      // drawn as one of the days October lends the grid. All three come from the
      // same table the schedule panel's picker reads, so the two cannot disagree
      // about what a date is.
      expect(_festival(tester, DateTime(2026, 9, 10)), '教师节');
      expect(_festival(tester, DateTime(2026, 9, 25)), '中秋节');
      expect(_festival(tester, DateTime(2026, 10, 1)), '国庆节');

      // It is the page's own green, and it is set to the day's trailing edge
      // rather than crowding the number.
      final label = tester.widget<Text>(find.byKey(ValueKey(
          'calendar-day-festival-${calendarDayKey(DateTime(2026, 9, 10))}')));
      expect(label.style!.color, _tokens.success);
      expect(label.style!.fontSize, WorkFollowMacTypography.caption);
      expect(label.textAlign, TextAlign.end);

      // A day that is not one says nothing.
      expect(_festival(tester, DateTime(2026, 9, 15)), isNull);
    });

    testWidgets('is a hairline grid, not a card per day', (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      // The cell is paper: no border of its own, no radius, no card. A card
      // grid would have each day carry its own outline, which is what the
      // lines between days used to be.
      final cell = tester.widget<Container>(_dayCell(DateTime(2026, 9, 15)));
      expect(cell.decoration, isNull);
      expect(cell.foregroundDecoration, isNull);

      // The lines belong to the week row instead. A middle day owns its right
      // and bottom edge and nothing else, so the line between two days is
      // painted once — and it is painted by the row, which is above the cells'
      // and therefore able to cross the bands they hold.
      // 9/15 is a Tuesday, so column 2 of the row that opens on 9/13.
      final middle = _hairline(tester, row: 2, column: 2);
      final border = middle.border! as Border;
      expect(middle.borderRadius, isNull);
      expect(border.top.width, 0);
      expect(border.left.width, 0);
      expect(border.right.width, WorkFollowMetrics.dividerThickness);
      expect(border.bottom.width, WorkFollowMetrics.dividerThickness);

      // And the box the border is painted into actually fills its share of the
      // row: one column wide and the row's full height. A box with a border
      // and no child asks for its smallest size, which in a row with a loose
      // cross axis is zero — the right border then draws as a line of length
      // zero, which is a grid with no vertical rules in it, and the row
      // centres what is left so the bottom border lands through the middle of
      // the week. Asserting the border alone would not notice either.
      final rowRect = tester.getRect(_row(2));
      final lineRect = tester.getRect(
          find.byKey(const ValueKey('calendar-hairline-2-2')));
      expect(lineRect.height, rowRect.height);
      expect(lineRect.bottom, rowRect.bottom);
      expect(lineRect.width, closeTo(rowRect.width / 7, .001));
      expect(lineRect.left, closeTo(rowRect.left + 2 * rowRect.width / 7, .001));

      // The grid's outer edge is one line, not two: the last column draws no
      // right edge, and the last row draws no bottom.
      final lastColumn = _hairline(tester, row: 2, column: 6).border! as Border;
      expect(lastColumn.right.width, 0);
      final lastRow = _hairline(tester, row: 4, column: 2).border! as Border;
      expect(lastRow.bottom.width, 0);
    });

    testWidgets('marks today on its number without filling the cell',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final today = DateTime(2026, 9, 18);
      final selected = DateTime(2026, 9, 22);
      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), selectedDay: selected, today: today);

      // Today: a filled circle behind the number, and a wash over the cell.
      expect(_numberStyle(tester, today).color,
          WorkFollowThemeContrast.foregroundOn(_tokens.accent));

      // The wash is the row's, not the cell's. A cell can only tint itself,
      // and the wash has to land on top of a band that crosses today — so it
      // is a layer of the row, at today's column and spanning the row's full
      // height.
      final wash =
          find.byKey(ValueKey('calendar-today-wash-${calendarDayKey(today)}'));
      final fill = tester.widget<ColoredBox>(
          find.descendant(of: wash, matching: find.byType(ColoredBox)));
      expect(fill.color.r, closeTo(_tokens.accent.r, .001));
      expect(fill.color.a, closeTo(CalendarMetrics.todayCellAlpha, .001));

      final washRect = tester.getRect(wash);
      final rowRect = tester.getRect(_row(2));
      expect(washRect.top, rowRect.top);
      expect(washRect.bottom, rowRect.bottom);
      expect(washRect.width, closeTo(rowRect.width / 7, .001));
      // 9/13 opens the row, so 9/18 is its sixth column.
      expect(washRect.left, closeTo(rowRect.left + 5 * rowRect.width / 7, .001));

      // The day's own paint stays the page's paper, and so does the day the
      // page has selected: selecting a day is not a second highlight
      // competing with today.
      expect(_cellFill(tester, today), _tokens.content);
      expect(_cellFill(tester, selected), _tokens.content);
      expect(_numberStyle(tester, selected).color, _tokens.accent);

      // A wash in the row is only there when today is in the row: a month
      // grid that showed September has no use for a tint on a day it is not
      // drawing.
      expect(find.byKey(ValueKey('calendar-today-wash-2026-09-19')),
          findsNothing);
    });
  });

  group('tasks in the grid', () {
    testWidgets('a day\'s tasks render as bars inside its own cell',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final day = DateTime(2026, 9, 15);
      final openId = _taskOn(controller, day, '整理周报');
      final doneId = _taskOn(controller, day, '交报销');
      final timedId =
          _taskOn(controller, day, '联调', at: DateTime(2026, 9, 15, 9, 30));
      controller.toggleTask(doneId);

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      final cell = _dayCell(day);
      expect(
          find.descendant(of: cell, matching: _taskBar(openId)), findsOneWidget);
      expect(
          find.descendant(of: cell, matching: _taskBar(doneId)), findsOneWidget);
      expect(find.descendant(of: cell, matching: find.text('整理周报')),
          findsOneWidget);

      // A bar carries the clock and nothing else, and only when the task has a
      // time of day. The cell already says which day it is, so repeating the
      // date on the bar would spend the title's room on what the grid says.
      expect(_clocksIn(tester, _taskBar(timedId)), ['09:30']);
      expect(_clocksIn(tester, _taskBar(openId)), isEmpty);

      // Every bar leads with the task's completion box, and the box says which
      // state the task is in. This is the month grid's half of the rule the
      // week's items share — and it is the drawn box, the one a task row and
      // the editor's header use, not a glyph of the calendar's own.
      expect(_boxIn(tester, _taskBar(openId)).completed, isFalse);
      expect(_boxIn(tester, _taskBar(doneId)).completed, isTrue);
      expect(_boxIn(tester, _taskBar(openId)).size,
          CalendarMetrics.taskBarCheckboxSize);

      // A bar spends the cell's whole content width. It is the cell that
      // insets, not the bar: a bar narrower than its cell would leave the day
      // looking half empty and waste the title's room.
      final cellRect = tester.getRect(cell);
      final barRect = tester.getRect(_taskBar(openId));
      expect(
          barRect.left, cellRect.left + CalendarMetrics.cellHorizontalPadding);
      expect(
          barRect.right, cellRect.right - CalendarMetrics.cellHorizontalPadding);

      // Completion is carried by ink: the title steps back to grey and keeps
      // its words. A rule struck through it said the same thing a second time,
      // and at this size took more off the title than the colour already did.
      final completed = tester
          .widget<Text>(find.descendant(of: cell, matching: find.text('交报销')))
          .style!;
      expect(completed.color, _tokens.textTertiary);
      expect(completed.decoration, isNot(TextDecoration.lineThrough));

      // The bar's own tint is the other half of that rule, and the half a
      // reader gets before reading anything. Both bars carry the task's list
      // colour, so the two states can only differ in how far that colour is
      // laid down — and with the titles the same size, a month where they are
      // laid down alike answers "what is left today" with nothing at all.
      final openFill = _barFill(tester, _taskBar(openId));
      final doneFill = _barFill(tester, _taskBar(doneId));
      expect(openFill.withValues(alpha: 1), doneFill.withValues(alpha: 1),
          reason: 'the two states share the task\'s list colour');
      expect(openFill.a, greaterThan(doneFill.a * 2),
          reason: 'an open bar is the dense one, not a shade off the finished');
    });

    testWidgets('a full cell counts the bars it left out', (tester) async {
      tester.view.physicalSize = const Size(1100, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final day = DateTime(2026, 9, 15);
      for (var index = 0; index < 8; index++) {
        _taskOn(controller, day, '任务 $index');
      }
      expect(controller.tasksForDay(day).length, 8);

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      final cell = _dayCell(day);
      final overflow = find.byKey(
          ValueKey('calendar-day-overflow-${calendarDayKey(day)}'));
      expect(find.descendant(of: cell, matching: overflow), findsOneWidget);

      final shown = tester
          .widgetList(
              find.descendant(of: cell, matching: find.byType(CalendarTaskBar)))
          .length;
      expect(shown, lessThan(8));
      final label = tester.widget<Text>(
          find.descendant(of: overflow, matching: find.byType(Text)));
      // The count is what is actually missing, not the day's total.
      expect(label.data, '+${8 - shown}');
    });

    testWidgets('hiding completed work hides the bar, not the day',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final day = DateTime(2026, 9, 15);
      controller.toggleTask(_taskOn(controller, day, '已完成的事'));

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9),
          today: DateTime(2026, 9, 18),
          showCompleted: false);

      expect(find.text('已完成的事'), findsNothing);
      expect(_dayCell(day), findsOneWidget);
    });

    testWidgets('a row paints cells, then bands, then today, then its lines',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      // A run that crosses today, so all four layers of the row are in play.
      _taskOn(controller, DateTime(2026, 9, 14), '搬工位',
          until: DateTime(2026, 9, 18));

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      // Each step is above the one before it, and each is there for a reason.
      // The cells go down first as the paper. The bands follow, because a band
      // has to cover the paint of the cells it crosses or it would read as six
      // separate strips. Today's wash follows the bands — a day tinted by its
      // own column has to tint what is in it. The lines go last, so they run
      // across everything the row holds instead of stopping at it.
      final bands = _layerIndex(tester,
          row: 2,
          layer: find.byKey(const ValueKey('calendar-span-layer-2')));
      final wash = _layerIndex(tester,
          row: 2,
          layer: find.byKey(const ValueKey('calendar-today-wash-2026-09-18')));
      final lines = _layerIndex(tester,
          row: 2,
          layer: find.byKey(const ValueKey('calendar-row-hairlines-2')));

      expect(bands, greaterThan(0));
      expect(wash, greaterThan(bands));
      expect(lines, greaterThan(wash));
    });
  });

  /// A task that runs over several days is not a second kind of task. It is a
  /// schedule with an end, and the grid's job is to draw the run as what it
  /// looks like — one thing — while keeping each day's own work in its own
  /// cell.
  group('multi-day runs', () {
    testWidgets('a run of days is one band, not a bar in every cell',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      // Monday to Friday of the row that opens on 9/13.
      final id = _taskOn(controller, DateTime(2026, 9, 14), '搬工位',
          until: DateTime(2026, 9, 18));

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      final band = _band(id, 1);
      expect(band, findsOneWidget);
      // One piece, not five neighbours that happen to share a colour.
      expect(find.byType(CalendarTaskSpan), findsOneWidget);
      // And no cell draws it a second time.
      expect(find.byKey(ValueKey('calendar-task-$id')), findsNothing);

      // The piece covers the columns the run actually occupies: 9/14 is the
      // row's second column and 9/18 its sixth, and the box runs between them
      // as one width rather than as five cell-wide strips.
      final rowRect = tester.getRect(_row(2));
      final columnWidth = rowRect.width / 7;
      final bandRect = tester.getRect(band);
      expect(
          bandRect.left,
          closeTo(
              rowRect.left +
                  columnWidth +
                  CalendarMetrics.cellHorizontalPadding,
              .001));
      expect(
          bandRect.width,
          closeTo(
              5 * columnWidth - 2 * CalendarMetrics.cellHorizontalPadding,
              .001));
      expect(bandRect.height, CalendarMetrics.taskBarHeight);

      // The run begins and ends inside this row, so both corners are the
      // task's own ends and neither side says "continues".
      final radius = _radiusOf(tester, band);
      expect(
          radius.topLeft, const Radius.circular(CalendarMetrics.taskBarRadius));
      expect(
          radius.topRight, const Radius.circular(CalendarMetrics.taskBarRadius));

      // A piece is nameable wherever it is, and an all-day run prints no
      // clock: its end is stored as that day's midnight, so printing the end
      // unconditionally would label every all-day band "00:00".
      expect(find.descendant(of: band, matching: find.text('搬工位')),
          findsOneWidget);
      expect(_clocksIn(tester, band), isEmpty);
    });

    testWidgets(
        'a run that leaves the row is cut flat and picks up on the other side',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      // Friday 9/18 at 09:00 through the following Tuesday at 18:00. The row
      // that opens on 9/13 sees the task's first two days, the next row sees
      // the last three.
      final id = _taskOn(controller, DateTime(2026, 9, 18), '外出拍摄',
          at: DateTime(2026, 9, 18, 9), until: DateTime(2026, 9, 22, 18));

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      final head = _band(id, 5);
      final tail = _band(id, 0);
      expect(head, findsOneWidget);
      expect(tail, findsOneWidget);

      final headRow = tester.getRect(_row(2));
      final tailRow = tester.getRect(_row(3));

      // The cut is at the row's edge and nowhere else: the piece runs flush to
      // the right of one row and flush to the left of the next, so the two
      // meet as one run rather than as a box that stops short of the edge.
      expect(tester.getRect(head).right, headRow.right);
      expect(tester.getRect(tail).left, tailRow.left);
      expect(
          tester.getRect(tail).right,
          closeTo(tailRow.left + 3 * tailRow.width / 7 -
              CalendarMetrics.cellHorizontalPadding, .001));

      // The corners say which ends are the task's own. The first piece is
      // rounded on the left and square on the right, the second the other way
      // round, so the join reads as a continuation rather than as two tasks.
      final headRadius = _radiusOf(tester, head);
      expect(headRadius.topLeft,
          const Radius.circular(CalendarMetrics.taskBarRadius));
      expect(headRadius.topRight, Radius.zero);
      final tailRadius = _radiusOf(tester, tail);
      expect(tailRadius.topLeft, Radius.zero);
      expect(tailRadius.topRight,
          const Radius.circular(CalendarMetrics.taskBarRadius));

      // Both pieces are nameable, so a band that resumes three days later is
      // not a coloured bar nobody could identify.
      expect(find.descendant(of: head, matching: find.text('外出拍摄')),
          findsOneWidget);
      expect(find.descendant(of: tail, matching: find.text('外出拍摄')),
          findsOneWidget);

      // What a piece carries follows the same rule as its corners. The
      // completion box marks where the task begins, so only the first piece
      // has one. The clock belongs to the end of the run, and the run ends
      // once, so only the last piece prints it.
      expect(
          find.descendant(of: head, matching: find.byType(TaskCompletionBox)),
          findsOneWidget);
      expect(
          find.descendant(of: tail, matching: find.byType(TaskCompletionBox)),
          findsNothing);
      expect(_clocksIn(tester, head), isEmpty);
      expect(_clocksIn(tester, tail), ['18:00']);
    });

    testWidgets('overlapping runs stack, and a cell steps below all of them',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final long = _taskOn(controller, DateTime(2026, 9, 14), '长跑',
          until: DateTime(2026, 9, 18));
      final short = _taskOn(controller, DateTime(2026, 9, 16), '短跑',
          until: DateTime(2026, 9, 17));
      final single = _taskOn(controller, DateTime(2026, 9, 16), '单日的事');

      await _pumpGrid(tester, controller,
          month: DateTime(2026, 9), today: DateTime(2026, 9, 18));

      const slack =
          CalendarMetrics.taskBarHeight + CalendarMetrics.taskBarGap;
      // 9/14 opens the long run at the row's second column; 9/16 opens the
      // short one at its fourth.
      final longRect = tester.getRect(_band(long, 1));
      final shortRect = tester.getRect(_band(short, 3));
      expect(shortRect.top, longRect.bottom + CalendarMetrics.taskBarGap);

      // The cell a band crosses cannot use the band's slot, so 9/16's own task
      // starts below both of them. Without that the day's first bar would land
      // on top of the run passing through it.
      final singleRect = tester.getRect(_taskBar(single));
      expect(singleRect.top, closeTo(shortRect.bottom + CalendarMetrics.taskBarGap, .001));
      expect(singleRect.top,
          closeTo(longRect.top + 2 * slack, .001));
      // And it is the day's own task that moved, not the day: the cell is
      // still where it was.
      expect(find.descendant(of: _dayCell(DateTime(2026, 9, 16)), matching: _taskBar(single)),
          findsOneWidget);
    });
  });

  group('calendar interactions', () {
    testWidgets('the toolbar names the month and steps through it',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpScreen(tester, controller);

      final now = DateTime.now();
      final title = find.byKey(const ValueKey('calendar-month-title'));
      expect(tester.widget<Text>(title).data, '${now.year}年${now.month}月');

      await tester.tap(find.byKey(const ValueKey('calendar-previous')));
      await tester.pumpAndSettle();
      final previous = DateTime(now.year, now.month - 1);
      expect(tester.widget<Text>(title).data,
          '${previous.year}年${previous.month}月');

      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-today')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(title).data, '${now.year}年${now.month}月');
    });

    testWidgets('week mode also starts on Sunday', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpScreen(tester, controller);
      await tester.tap(find.byKey(const ValueKey('calendar-view-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-option-week')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarWeekView), findsOneWidget);

      // The columns read left to right, so the first one has to be the week's
      // start. The toolbar's own "周" chip is a one-character label, not a
      // column, so it is skipped.
      final columns = find.textContaining('周');
      final ordered = <(double, String)>[];
      for (var index = 0; index < columns.evaluate().length; index++) {
        final column = columns.at(index);
        final data = tester.widget<Text>(column).data!;
        if (data.length < 2) continue;
        ordered.add((tester.getTopLeft(column).dx, data));
      }
      ordered.sort((a, b) => a.$1.compareTo(b.$1));
      expect(ordered.length, 7);
      expect(ordered.first.$2, startsWith('周日'));
      expect(ordered.last.$2, startsWith('周六'));
    });

    testWidgets('a week column marks each task open or done', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final openId = _taskOn(controller, today, '还没做');
      final doneId = _taskOn(controller, today, '已经做完');
      controller.toggleTask(doneId);

      await _pumpScreen(tester, controller);
      await tester.tap(find.byKey(const ValueKey('calendar-view-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-option-week')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarWeekView), findsOneWidget);

      // A week item leads with the same completion box a month cell's bar does.
      // One page, two views, one way of saying whether a task is done: the box
      // is not something the month grid invented for its own narrow strip.
      // Addressed through the task each box belongs to rather than by the order
      // the column happens to list them in.
      final open = find.byKey(ValueKey('calendar-week-box-$openId'));
      final done = find.byKey(ValueKey('calendar-week-box-$doneId'));
      expect(tester.widget<TaskCompletionBox>(open).completed, isFalse);
      expect(tester.widget<TaskCompletionBox>(done).completed, isTrue);
      expect(tester.widget<TaskCompletionBox>(open).size,
          CalendarMetrics.taskBarCheckboxSize);
      expect(tester.widget<TaskCompletionBox>(done).size,
          CalendarMetrics.taskBarCheckboxSize);

      // An open box takes the task's list colour; a finished one is grey along
      // with the words beside it. Read off what is painted rather than off the
      // arguments, so the assertion survives the box being drawn differently.
      expect((_boxPaint(tester, open).border! as Border).top.color,
          Color(controller.colorValueForList('收集箱')));
      expect(_boxPaint(tester, done).color, taskCompletionFill(_tokens));

      // It leads the title, on its first line rather than centred on a block
      // that is free to wrap to two.
      final mark = tester.getRect(open);
      final title = tester.getRect(find.text('还没做'));
      expect(mark.right, lessThanOrEqualTo(title.left));
      expect(mark.top, closeTo(title.top, 1));
    });

    testWidgets('clicking a task opens the floating editor over the grid',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final now = DateTime.now();
      final id = _taskOn(
          controller, DateTime(now.year, now.month, 8), '给日历开个浮层');

      await _pumpScreen(tester, controller);
      await tester.tap(_taskBar(id));
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('floating-task-editor-$id')), findsOneWidget);
      // The page stays where it was: editing a task does not navigate.
      expect(find.byType(CalendarMonthView), findsOneWidget);

      // The floating editor is the compact card the reference popup is —
      // 400 × 356, a title and a few lines — not a page dropped over the grid.
      // Longer documents scroll inside it rather than growing it.
      final card =
          tester.getRect(find.byKey(ValueKey('floating-task-editor-$id')));
      expect(card.width, TaskSurfaceMetrics.editorWidth);
      expect(card.height, TaskSurfaceMetrics.editorMinHeight);
    });

    testWidgets('dragging a task onto another day moves its date',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final now = DateTime.now();
      final from = DateTime(now.year, now.month, 1);
      final to = DateTime(now.year, now.month, 8);
      final id = _taskOn(controller, from, '拖到下周');

      await _pumpScreen(tester, controller);

      final gesture = await tester.startGesture(tester.getCenter(_taskBar(id)),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(_dayCell(to)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final moved =
          controller.tasks.firstWhere((task) => task.id == id);
      expect(localDateTimeFromStorage(moved.dueAt), to);
      expect(find.descendant(of: _dayCell(to), matching: _taskBar(id)),
          findsOneWidget);
    });

    testWidgets('double-clicking a day opens the composer on that day',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final now = DateTime.now();
      // Any day of the month except today: the composer dates a new task from
      // the day that was clicked, and the assertion has to tell the two apart.
      final day = DateTime(now.year, now.month, now.day == 8 ? 9 : 8);

      await _pumpScreen(tester, controller);
      final cell = _dayCell(day);
      await tester.tap(cell);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('task-add-title')), findsOneWidget);
      // The clicked day arrives as the composer's date rather than as an
      // untouched "设置日期".
      expect(find.text('设置日期'), findsNothing);

      await tester.enterText(
          find.byKey(const ValueKey('task-add-title')), '从格子里新建');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final created =
          controller.tasks.firstWhere((task) => task.title == '从格子里新建');
      expect(localDateTimeFromStorage(created.dueAt), day);
    });

    testWidgets('a click on a day selects it and creates nothing',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      await _pumpScreen(tester, controller);
      await tester.tap(_dayCell(DateTime.now()));
      await tester.pumpAndSettle();

      expect(controller.tasks, isEmpty);
      expect(find.byKey(const ValueKey('task-add-title')), findsNothing);
      expect(find.byType(CalendarMonthView), findsOneWidget);
    });

    testWidgets('the selected day is the day the toolbar\'s plus button dates',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final now = DateTime.now();
      await _pumpScreen(tester, controller);

      // The composer's date chip as it stands after selecting [day]. Compared
      // against itself for a second day rather than against a literal, so the
      // assertion is about selection reaching the composer and not about how a
      // date happens to be spelled.
      Future<Set<String?>> chipFor(int dayOfMonth) async {
        await tester.tap(_dayCell(DateTime(now.year, now.month, dayOfMonth)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('calendar-add-task')));
        await tester.pumpAndSettle();
        final rendered = tester
            .widgetList<Text>(find.descendant(
                of: find.byKey(const ValueKey('task-add-schedule')),
                matching: find.byType(Text)))
            .map((text) => text.data)
            .toSet();
        // Dismiss the composer without submitting.
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        return rendered;
      }

      final first = await chipFor(8);
      final second = await chipFor(20);
      expect(first, isNot(second));
    });

    testWidgets('double-clicking a task opens it instead of creating a task',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = WorkspaceController(seedData: false);
      addTearDown(controller.dispose);

      final now = DateTime.now();
      final day = DateTime(now.year, now.month, 8);
      final id = _taskOn(controller, day, '别在任务上新建');

      await _pumpScreen(tester, controller);
      // Both clicks land on the bar, not on the day: the bar is its own hit
      // target, so the day's double-click never sees the press and no second
      // task is created on top of the one that was double-clicked.
      final onBar = tester.getCenter(_taskBar(id));
      await tester.tapAt(onBar);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(onBar);
      await tester.pumpAndSettle();

      expect(controller.tasksForDay(day).length, 1);
      expect(find.byKey(const ValueKey('task-add-title')), findsNothing);
    });
  });
}
