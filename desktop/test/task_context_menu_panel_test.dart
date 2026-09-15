import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_context_menu_panel.dart';

TaskItem _task({String recurrenceType = 'NONE'}) => TaskItem(
      id: 'menu-task',
      title: '菜单任务',
      listName: '收集箱',
      bucket: TaskBucket.today,
      dueAt: DateTime(2030, 1, 10, 9).toIso8601String(),
      recurrenceType: recurrenceType,
      recurrenceConfig: recurrenceType == 'NONE' ? null : const {'weekday': 4},
    );

void main() {
  testWidgets('TASK-CTX normal date grid has exactly five actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: SizedBox(
          width: 264,
          child: TaskContextMenuPanel(task: _task()),
        ),
      ),
    ));

    for (final value in const [
      'today',
      'tomorrow',
      'next-7',
      'date',
      'clear-date',
    ]) {
      expect(find.byKey(ValueKey('menu-option-$value')), findsOneWidget,
          reason: value);
    }
    expect(find.byKey(const ValueKey('menu-option-skip-occurrence')),
        findsNothing);
    expect(find.byKey(const ValueKey('task-context-date-section')),
        findsOneWidget);
  });

  testWidgets('TASK-CTX recurring date grid inserts skip without a blank slot',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: SizedBox(
          width: 264,
          child: TaskContextMenuPanel(task: _task(recurrenceType: 'DAILY')),
        ),
      ),
    ));

    for (final value in const [
      'today',
      'tomorrow',
      'next-7',
      'skip-occurrence',
      'date',
      'clear-date',
    ]) {
      expect(find.byKey(ValueKey('menu-option-$value')), findsOneWidget,
          reason: value);
    }
    final dateButtons = [
      for (final value in const [
        'today',
        'tomorrow',
        'next-7',
        'skip-occurrence',
        'date',
        'clear-date',
      ])
        tester.getSize(find.byKey(ValueKey('menu-option-$value'))),
    ];
    expect(dateButtons.map((size) => size.width).toSet(), hasLength(1));
  });
}
