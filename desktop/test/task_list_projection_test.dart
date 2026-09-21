import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/features/tasks/application/task_list_projection.dart';
import 'package:workfollow_personal/features/tasks/application/task_projection.dart';
import 'package:workfollow_personal/features/tasks/domain/task_draft.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_date_picker.dart';

/// LIST-001 … LIST-015 — where a row goes.
///
/// Grouping is a business rule, so it is tested as one: these cases read the
/// projection directly and never pump a widget. A heading that only exists
/// because a screen decided to draw it is exactly what this file exists to
/// catch.
///
/// The clock is fixed so "today" cannot drift under the assertions.
final DateTime anchor = DateTime(2030, 6, 10, 9);

DateTime day(int offset) => DateTime(2030, 6, 10 + offset);

final TaskListProjection lists =
    TaskListProjection(projection: TaskProjection(clock: () => anchor));

TaskItem item(String id,
    {String? title,
    DateTime? due,
    bool completed = false,
    DateTime? completedAt,
    DateTime? abandonedAt,
    DateTime? deletedAt,
    bool pinned = false,
    String list = '收集箱',
    String? parent}) {
  return TaskItem(
    id: id,
    title: title ?? id,
    listName: list,
    bucket: taskBucketForDate(due, now: anchor),
    dueAt: due?.toIso8601String(),
    completed: completed,
    completedAt: completedAt?.toIso8601String(),
    abandonedAt: abandonedAt?.toIso8601String(),
    deletedAt: deletedAt?.toIso8601String(),
    isPinned: pinned,
    parentTaskId: parent,
  );
}

List<TaskListGroup> groups(String view, List<TaskItem> tasks,
        {String? listName, String? tagName}) =>
    lists.groupsFor(
        view: view,
        tasks: tasks,
        selectedListName: listName,
        selectedTagName: tagName,
        reference: anchor);

TaskListGroup groupOf(List<TaskListGroup> groups, String id) =>
    groups.firstWhere((group) => group.id == id,
        orElse: () => fail('no group $id in ${groups.map((g) => g.id)}'));

List<String> ids(List<TaskListGroup> groups) => [
      for (final group in groups) ...group.tasks.map((task) => task.id),
    ];

/// Every row of the second navigation column that is on screen, by label.
///
/// The rows are private widgets inside the sidebar, so there is no type a test
/// can name; they are found by the key each one carries. Read as a set rather
/// than as a list of expected names so that a row added later cannot slip in
/// without the ordering contract below noticing.
List<String> railLabels(WidgetTester tester) {
  const prefix = 'rail-navigation-item-';
  final labels = <String>[];
  for (final element in find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith(prefix);
      })
      .evaluate()) {
    labels.add((element.widget.key! as ValueKey<String>)
        .value
        .substring(prefix.length));
  }
  return labels;
}

void main() {
  test('LIST-001 今天 reads 已过期 / 今天 / 已完成', () {
    final result = groups('today', [
      item('overdue', due: day(-1)),
      item('today', due: day(0)),
      item('done', due: day(0), completed: true, completedAt: day(0)),
    ]);
    expect(result.map((group) => group.id),
        ['overdue', 'today', 'closed']);
    expect(ids(result), ['overdue', 'today', 'done']);
    expect(groupOf(result, 'overdue').label, '已过期');
    expect(groupOf(result, 'closed').label, '已完成');
    // The day group is named by its day, and the screen writes that name.
    expect(groupOf(result, 'today').day, day(0));
    expect(groupOf(result, 'today').label, isNull);
  });

  test('LIST-002 最近 7 天 walks the week day by day, earliest first', () {
    final result = groups('recent', [
      item('overdue', due: day(-3)),
      item('today', due: day(0)),
      item('later', due: day(3)),
      item('sooner', due: day(1)),
      item('done', due: day(1), completed: true, completedAt: day(0)),
    ]);
    expect([for (final group in result) group.id],
        ['overdue', 'today', 'day:2030-06-11', 'day:2030-06-13', 'closed']);
    expect(groupOf(result, 'day:2030-06-11').tasks.single.id, 'sooner');
    expect(groupOf(result, 'day:2030-06-13').tasks.single.id, 'later');
  });

  test('LIST-002 a day past the window is not in 最近 7 天 at all', () {
    final result = groups('recent', [item('far', due: day(9))]);
    expect(ids(result), isEmpty);
    expect(result, isEmpty);
  });

  test('LIST-003 所有任务 reads 已过期 / 今天 / 最近 7 天 / 更远 / 无日期 / 已完成',
      () {
    final result = groups('all', [
      item('overdue', due: day(-3)),
      item('today', due: day(0)),
      item('soon', due: day(3)),
      item('beyond', due: day(30)),
      item('undated'),
      item('done', due: day(0), completed: true, completedAt: day(0)),
    ]);
    expect([for (final group in result) group.id],
        ['overdue', 'today', 'upcoming', 'later', 'undated', 'closed']);
    expect(groupOf(result, 'upcoming').label, '最近 7 天');
    expect(groupOf(result, 'later').label, '更远');
    expect(groupOf(result, 'undated').label, '无日期');
    expect(groupOf(result, 'upcoming').tasks.map((task) => task.id), ['soon']);
    expect(groupOf(result, 'later').tasks.map((task) => task.id), ['beyond']);
  });

  test('LIST-003 最近 7 天 and 更远 split where the recent window ends', () {
    final result = groups('all', [
      item('sixDays', due: day(6)),
      item('sevenDays', due: day(7)),
    ]);
    expect(groupOf(result, 'upcoming').tasks.map((task) => task.id),
        ['sixDays']);
    expect(groupOf(result, 'later').tasks.map((task) => task.id), ['sevenDays']);
  });

  test('LIST-004 已完成 groups by closing day, newest first', () {
    final result = groups('completed', [
      item('older', completed: true, completedAt: DateTime(2030, 6, 8, 10)),
      item('newerMorning',
          completed: true, completedAt: DateTime(2030, 6, 10, 8)),
      item('newerNoon', completed: true, completedAt: DateTime(2030, 6, 10, 12)),
    ]);
    expect([for (final group in result) group.id],
        ['closed:2030-06-10', 'closed:2030-06-08']);
    expect(groupOf(result, 'closed:2030-06-10').day, DateTime(2030, 6, 10));
    // Inside one day the most recent closing leads.
    expect(groupOf(result, 'closed:2030-06-10').tasks.map((task) => task.id),
        ['newerNoon', 'newerMorning']);
  });

  test('LIST-004 an abandoned task is filed under the day it was given up on',
      () {
    final result = groups('completed', [
      item('done', completed: true, completedAt: DateTime(2030, 6, 9, 10)),
      item('gaveUp', abandonedAt: DateTime(2030, 6, 10, 10)),
    ]);
    expect([for (final group in result) group.id],
        ['closed:2030-06-10', 'closed:2030-06-09']);
    expect(groupOf(result, 'closed:2030-06-10').tasks.single.id, 'gaveUp');
  });

  test('LIST-005 the closing heading follows what the group holds', () {
    final done = item('done', due: day(0), completed: true, completedAt: day(0));
    final gaveUp = item('gaveUp', due: day(0), abandonedAt: day(0));
    expect(groupOf(groups('today', [done]), 'closed').label, '已完成');
    expect(groupOf(groups('all', [gaveUp]), 'closed').label, '已放弃');
    expect(groupOf(groups('all', [done, gaveUp]), 'closed').label,
        '已完成&已放弃');
  });

  test('LIST-005 已完成 itself keeps the dates: the day is the heading', () {
    final result = groups('completed', [
      item('done', completed: true, completedAt: day(0)),
      item('gaveUp', abandonedAt: day(0)),
    ]);
    expect(result, hasLength(1));
    expect(result.single.label, isNull);
    expect(result.single.day, day(0));
  });

  test('LIST-006 the closing group holds what the view is about', () {
    final tasks = [
      item('doneToday', due: day(0), completed: true, completedAt: day(0)),
      item('doneNextMonth', due: day(45), completed: true, completedAt: day(0)),
      item('doneUndated', completed: true, completedAt: day(0)),
    ];
    // 今天 claims the finished task its own day is about, and nothing else.
    expect(groupOf(groups('today', tasks), 'closed').tasks.map((t) => t.id),
        ['doneToday']);
    // 所有任务 is about everything, so it holds all three.
    expect(groupOf(groups('all', tasks), 'closed').tasks.length, 3);
  });

  test('LIST-006 a child of a listed parent is not also a row of its own', () {
    final result = groups('today', [
      item('parent', due: day(0)),
      item('child', due: day(0), parent: 'parent'),
    ]);
    expect(ids(result), ['parent']);
  });

  test('LIST-012 a pinned task leads the list, whatever day it falls on', () {
    final result = groups('today', [
      item('overdue', due: day(-1)),
      item('pinned', due: day(-1), pinned: true),
    ]);
    expect(result.first.id, 'pinned');
    expect(result.first.label, '置顶');
    expect(groupOf(result, 'overdue').tasks.single.id, 'overdue');
  });

  test('LIST-003 a named list stays one plain list with its closing group', () {
    final result = groups('all', [
      item('open', due: day(-3), list: '工作'),
      item('done', list: '工作', completed: true, completedAt: day(0)),
      item('other', due: day(0), list: '个人'),
    ], listName: '工作');
    expect([for (final group in result) group.id], ['plain', 'closed']);
    expect(groupOf(result, 'plain').label, '');
    expect(groupOf(result, 'plain').tasks.single.id, 'open');
  });

  test('LIST-011 the trash is one flat list, closed or not', () {
    final result = groups('trash', [
      item('removed', deletedAt: day(-1)),
      item('removedDone',
          deletedAt: day(-1), completed: true, completedAt: day(-1)),
    ]);
    expect([for (final group in result) group.id], ['plain']);
    expect(result.single.tasks.length, 2);
  });

  test('LIST-011 所有任务 and 垃圾桶 are the names the pages carry', () {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.all);
    expect(controller.viewTitle, '所有任务');
    controller.selectView(WorkspaceView.trash);
    expect(controller.viewTitle, '垃圾桶');
  });

  test('LIST-013 the trash reads newest deletion first', () {
    // Deliberately out of order, and out of the order the store would hold
    // them in: the page is a timeline of removals, so the stamps decide.
    final result = groups('trash', [
      item('oldest', deletedAt: day(-3)),
      item('newest', deletedAt: day(-1)),
      item('middle', deletedAt: day(-2)),
    ]);
    expect([for (final group in result) group.id], ['plain']);
    expect(result.single.tasks.map((task) => task.id),
        ['newest', 'middle', 'oldest']);
  });

  test('LIST-013 the trash orders within one day too, not just between days',
      () {
    // 已完成 groups by day and then sorts inside the day. The trash does not
    // group, but the ordering still has to be the stamp rather than the day, or
    // two things thrown away an hour apart would swap places between runs.
    final result = groups('trash', [
      item('thisMorning', deletedAt: DateTime(2030, 6, 9, 9)),
      item('thisEvening', deletedAt: DateTime(2030, 6, 9, 21)),
    ]);
    expect(result.single.tasks.map((task) => task.id),
        ['thisEvening', 'thisMorning']);
  });

  testWidgets('LIST-014 已完成 sits directly above 垃圾桶, past a break',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    final done = find.byKey(const ValueKey('rail-navigation-item-已完成'));
    final trash = find.byKey(const ValueKey('rail-navigation-item-垃圾桶'));
    final breakRow = find.byKey(const ValueKey('rail-group-break'));
    expect(done, findsOneWidget);
    expect(trash, findsOneWidget);
    expect(breakRow, findsOneWidget);
    expect(tester.getTopLeft(done).dy, lessThan(tester.getTopLeft(trash).dy));

    // Nothing sits between them: no other row of the column starts in the gap
    // the two share. Read off every rail row rather than off a list of names,
    // so a row added later cannot slip in unnoticed.
    final rows = <String, double>{};
    for (final label in railLabels(tester)) {
      rows[label] =
          tester.getTopLeft(find.byKey(ValueKey('rail-navigation-item-$label')))
              .dy;
    }
    final ordered = rows.keys.toList()
      ..sort((a, b) => rows[a]!.compareTo(rows[b]!));
    expect(ordered.sublist(ordered.length - 2), ['已完成', '垃圾桶']);

    // The break is what makes them a group: the pair starts further below the
    // row above it than any two plain rows sit apart.
    final above = find.byKey(ValueKey('rail-navigation-item-${ordered[ordered.length - 3]}'));
    final plainGap = tester.getTopLeft(trash).dy -
        tester.getBottomLeft(done).dy;
    final groupGap =
        tester.getTopLeft(done).dy - tester.getBottomLeft(above).dy;
    expect(groupGap, greaterThan(plainGap));
    expect(tester.getBottomLeft(breakRow).dy,
        lessThanOrEqualTo(tester.getTopLeft(done).dy));
  });

  testWidgets('LIST-015 the rule that opens 清单 is the one above 已完成',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    // 任务 holds views and 清单 holds lists. With a header alone the two sat no
    // further apart than two ordinary rows, so the lists read as one more view
    // of the group above instead of the start of a new group. The boundary now
    // carries the same hairline the closing pair opens with — and both are
    // asserted here, because "like the one above 已完成" is the whole rule: a
    // second, slightly different line would be worse than none.
    final listsBreak = find.byKey(const ValueKey('rail-lists-group-break'));
    final closingBreak = find.byKey(const ValueKey('rail-group-break'));
    expect(listsBreak, findsOneWidget);
    expect(closingBreak, findsOneWidget);

    /// `_RailGroupBreak` is a Padding around the line, so the line's own box is
    /// the Container inside it.
    Finder lineOf(Finder breakFinder) =>
        find.descendant(of: breakFinder, matching: find.byType(Container));

    expect(tester.getSize(lineOf(listsBreak)).height,
        WorkFollowMetrics.dividerThickness);
    expect(tester.getSize(lineOf(listsBreak)).height,
        tester.getSize(lineOf(closingBreak)).height,
        reason: '两条分组横线同一厚度');
    expect(tester.widget<Container>(lineOf(listsBreak)).color,
        tester.widget<Container>(lineOf(closingBreak)).color,
        reason: '两条分组横线同一支颜色（tokens.border），不是各自调出来的');

    final views = find.byKey(const ValueKey('rail-navigation-item-所有任务'));
    final listsHeader = find.text('清单');
    final line = lineOf(listsBreak);
    expect(listsHeader, findsOneWidget);
    expect(tester.getSize(line).width, tester.getSize(lineOf(closingBreak)).width,
        reason: '两条分组横线画出同一段宽度');

    // Strictly between them, and set off from the group above: the rule carries
    // the group's top spacing, it does not sit against the last view's edge.
    // (A row's own box already includes its margin, so two plain rows measure
    // as touching — the distance has to be read off the line, not off a row.)
    expect(tester.getTopLeft(line).dy,
        greaterThan(tester.getBottomLeft(views).dy),
        reason: '横线在 所有任务 之下，并与它留出组间距');
    expect(tester.getBottomLeft(line).dy,
        lessThan(tester.getTopLeft(listsHeader).dy),
        reason: '横线在 清单 标题之上');
  });

  testWidgets('LIST-007 LIST-008 the rail offers no 过期 or 计划 destination',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    // Keyed, not matched by text: 过期 and 计划 are ordinary words that a task
    // title may well contain.
    expect(find.byKey(const ValueKey('rail-navigation-item-过期')), findsNothing);
    expect(find.byKey(const ValueKey('rail-navigation-item-计划')), findsNothing);
    expect(find.byKey(const ValueKey('rail-navigation-item-垃圾桶')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('rail-navigation-item-废纸篓')),
        findsNothing);
    expect(find.byKey(const ValueKey('rail-navigation-item-所有任务')),
        findsOneWidget);
  });

  test('LIST-001 a heading the screen writes comes from the group, not a copy',
      () {
    // The projection hands the screen a day; the screen spells it. Asserting
    // the two agree keeps a second date formatter from growing in either half.
    final result = groups('all', [item('soon', due: day(1))]);
    final upcoming = groupOf(result, 'upcoming');
    expect(upcoming.day, isNull);
    expect(upcoming.label, '最近 7 天');
    final recent = groups('recent', [item('soon', due: day(1))]);
    expect(calendarGroupLabel(groupOf(recent, 'day:2030-06-11').day),
        calendarGroupLabel(day(1)));
  });

  testWidgets('LIST-003 所有任务 draws every heading its groups ask for',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.all);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    void schedule(String title, DateTime due) => controller.createTask(TaskDraft(
        title: title,
        schedule: TaskScheduleDraft(dueAt: due, hasTime: false)));
    schedule('逾期的报告', start.subtract(const Duration(days: 1)));
    schedule('今天要做', start);
    schedule('周末再说', start.add(const Duration(days: 3)));
    schedule('下个月', start.add(const Duration(days: 30)));
    controller.addTask('想到再说', forceUnscheduled: true);

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: controller,
                builder: (_, __) =>
                    TodayScreen(controller: controller, persistentInspector: false)))));
    await tester.pumpAndSettle();

    expect(find.text('已过期'), findsOneWidget);
    expect(find.text(calendarGroupLabel(start)), findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);
    expect(find.text('更远'), findsOneWidget);
    expect(find.text('无日期'), findsOneWidget);

    // The order is the rule, not just the presence: 已过期 / 今天 / 最近 7 天 /
    // 更远 / 无日期, top to bottom.
    final tops = [
      for (final heading in [
        '已过期',
        calendarGroupLabel(start),
        '最近 7 天',
        '更远',
        '无日期',
      ])
        tester.getTopLeft(find.text(heading)).dy,
    ];
    expect(tops, orderedEquals(<double>[...tops]..sort()));
  });

  testWidgets('LIST-004 已完成 draws its days newest first', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    controller.loadTasksForTest([
      item('newer',
          title: '刚做完的',
          completed: true,
          completedAt: start.add(const Duration(hours: 12))),
      item('older',
          title: '前两天做完的',
          completed: true,
          completedAt: start.subtract(const Duration(days: 2))),
    ]);
    controller.selectView(WorkspaceView.completed);

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: controller,
                builder: (_, __) => TodayScreen(
                    controller: controller, persistentInspector: false)))));
    await tester.pumpAndSettle();

    final newer = calendarGroupLabel(start);
    final older = calendarGroupLabel(start.subtract(const Duration(days: 2)));
    expect(find.text(newer), findsOneWidget);
    expect(find.text(older), findsOneWidget);
    expect(tester.getTopLeft(find.text(newer)).dy,
        lessThan(tester.getTopLeft(find.text(older)).dy));
  });
}
