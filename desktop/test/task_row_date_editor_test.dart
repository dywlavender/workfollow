import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_icons.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_row.dart';
import 'package:workfollow_personal/widgets/task_schedule_panel.dart';

void main() {
  testWidgets('task row dates use the editor schedule panel without row more',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('日期任务', dueAt: DateTime(2030, 9, 18));

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: controller,
                builder: (_, __) => TaskRow(
                    task: controller.tasks.single,
                    controller: controller,
                    selected: false)))));
    await tester.pumpAndSettle();

    final id = controller.tasks.single.id;
    expect(find.byKey(ValueKey('task-row-more-$id')), findsNothing);
    await tester.tap(find.byKey(ValueKey('task-row-date-$id')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskSchedulePanel), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-calendar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('date-shortcut-明天')));
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();
    expect(find.byType(TaskSchedulePanel), findsNothing);
    final due = localDateTimeFromStorage(controller.tasks.single.dueAt);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(due, isNotNull);
    expect(DateUtils.isSameDay(due, tomorrow), isTrue);
  });

  testWidgets('task row metadata shows absolute reminders', (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('提醒任务', dueAt: DateTime(2030, 9, 18, 10));
    final id = controller.tasks.single.id;
    controller.updateTaskReminder(id, DateTime.now().add(const Duration(hours: 2)));

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: controller,
                builder: (_, __) => TaskRow(
                    task: controller.tasks.single,
                    controller: controller,
                    selected: false)))));
    await tester.pumpAndSettle();

    expect(find.byIcon(WorkFollowIcons.reminder), findsOneWidget);
  });
}
