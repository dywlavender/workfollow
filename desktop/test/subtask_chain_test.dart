import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule.dart';
import 'package:workfollow_personal/features/tasks/domain/task_schedule_settings.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/widgets/task_children_panel.dart';

/// S9 acceptance: the whole parent/child loop in one run — create, name,
/// list sync, complete, open child, edit body, set a date, crumb back,
/// fold/unfold — with every step read from the same TaskItem.
void main() {
  testWidgets('S9 the full parent/child chain stays in sync', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    // The rail groups navigation: open the 任务 tree first, then 今天.
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('所有任务').first);
    await tester.pumpAndSettle();
    final c = tester.widget<TodayScreen>(find.byType(TodayScreen)).controller;

    // Fresh parent on top of the demo data.
    c.addTask('主任务 2', forceUnscheduled: true);
    final parentId = c.tasks.first.id;
    c.openTask(parentId);
    await tester.pumpAndSettle();

    // 更多 → 添加子任务: an empty child appears and takes focus, no reload.
    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加子任务').last);
    await tester.pumpAndSettle();
    expect(c.childCount(parentId), 1);
    final childId = c.childrenOf(parentId).single.id;
    var lastOpened = parentId;
    expect(find.byKey(ValueKey('task-child-row-$childId')), findsOneWidget);
    expect(find.byKey(ValueKey('task-child-title-$childId')), findsOneWidget);

    // Naming inline writes straight through; the list grows the tree.
    await tester.enterText(
        find.byKey(ValueKey('task-child-title-$childId')), '问问');
    await tester.pumpAndSettle();
    expect(c.childrenOf(parentId).single.title, '问问');
    expect(find.text('问问'), findsWidgets);

    // The chevron opens the child inspector and keeps the parent expanded.
    await tester.tap(find.byKey(ValueKey('task-child-open-$childId')));
    await tester.pumpAndSettle();
    expect(c.selectedTaskId, childId);
    expect(
        find.byKey(const ValueKey('task-parent-breadcrumb')), findsOneWidget);
    expect(c.isTaskExpanded(parentId), isTrue);

    // Body edits flow through the normal document chain into the list row.
    c.taskActions.setContent(childId, const {
      'type': 'doc',
      'content': [
        {'type': 'paragraph', 'content': [
          {'type': 'text', 'text': '呜呜呜'}
        ]}
      ]
    }, '呜呜呜');
    await tester.pumpAndSettle();
    expect(find.text('呜呜呜'), findsOneWidget);

    // A date set in the child shows up in both parent panel and list row.
    final day = DateTime(2030, 9, 30);
    c.taskActions.setScheduleSettings(
        childId,
        TaskScheduleSettings(
            schedule: TaskScheduleDraft(dueAt: day, hasTime: false)));
    await tester.pumpAndSettle();
    expect(find.textContaining('9 月 30 日'), findsWidgets);

    // The crumb returns to the parent; the inline row already carries the date.
    await tester.tap(find.byKey(const ValueKey('task-parent-breadcrumb')));
    await tester.pumpAndSettle();
    expect(c.selectedTaskId, parentId);
    expect(find.byKey(ValueKey('task-child-date-$childId')), findsOneWidget);
    expect(find.textContaining('9 月 30 日'), findsWidgets);

    // Completing from the inline row syncs to the list and back again.
    await tester.tap(find.byKey(ValueKey('task-child-check-$childId')));
    await tester.pumpAndSettle();
    expect(c.childrenOf(parentId).single.completed, isTrue);

    // Folding hides the list rows but touches neither data nor selection.
    await tester.tap(find.byKey(const ValueKey('task-expander-open')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(childId)).evaluate(), isEmpty,
        reason: 'folded: the list row disappears');
    expect(find.byKey(ValueKey('task-child-row-$childId')), findsOneWidget,
        reason: 'the inspector panel keeps showing the child');
    expect(c.selectedTaskId, parentId);
    expect(c.childCount(parentId), 1);
    await tester.tap(find.byKey(const ValueKey('task-expander-closed')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(childId)), findsOneWidget);
    expect(find.byKey(ValueKey('task-child-check-$childId')), findsOneWidget);
    expect(find.textContaining('9 月 30 日'), findsWidgets);
  });
}
