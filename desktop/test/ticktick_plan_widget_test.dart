import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/quick_add.dart';
import 'package:workfollow_personal/widgets/task_row.dart';

void main() {
  testWidgets('stats and matrix views are reachable from the native rail',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('统计'));
    await tester.pumpAndSettle();
    expect(find.text('完成趋势'), findsOneWidget);
    expect(find.text('完成热力图'), findsOneWidget);
    expect(find.text('清单分布'), findsOneWidget);

    await tester.tap(find.byTooltip('四象限'));
    await tester.pumpAndSettle();
    expect(find.text('立即做'), findsOneWidget);
    expect(find.text('安排做'), findsOneWidget);
    expect(find.text('缓一缓'), findsOneWidget);
  });

  testWidgets('board, habits and week calendar views are reachable',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('看板'));
    await tester.pumpAndSettle();
    expect(find.text('优先级'), findsOneWidget);
    expect(find.text('高优先级'), findsOneWidget);

    await tester.tap(find.byTooltip('习惯'));
    await tester.pumpAndSettle();
    expect(find.text('晨间拉伸'), findsOneWidget);
    expect(find.text('连续'), findsNWidgets(2));

    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    expect(find.textContaining('周一'), findsOneWidget);
    expect(find.textContaining('周日'), findsOneWidget);
  });

  testWidgets(
      'QUICK-010 dismissing a date chip keeps it as title text and unscheduled',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));
    await tester.enterText(
        find.byKey(const ValueKey('quick-add-title')), '周五理账');
    await tester.pump();
    expect(find.byType(InputChip), findsOneWidget);
    final field = find.byKey(const ValueKey('quick-add-title'));
    final rendered = tester.widget<TextField>(field).controller!.buildTextSpan(
        context: tester.element(field),
        style: const TextStyle(),
        withComposing: false);
    expect(rendered.children, isNotEmpty);
    expect((rendered.children!.first as TextSpan).style?.backgroundColor,
        isNotNull);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.tap(find.text('添加任务'));
    await tester.pump();
    expect(controller.tasks.single.title, '周五理账');
    expect(controller.tasks.single.dueAt, isNull);
    expect(controller.tasks.single.listName, '收集箱');
  });

  testWidgets('QUICK-008 unknown list chips stay in the quick-add title',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));
    await tester.enterText(
        find.byKey(const ValueKey('quick-add-title')), '整理资料 @不存在清单');
    await tester.pump();
    await tester.tap(find.text('添加任务'));
    await tester.pump();
    expect(controller.tasks.single.title, '整理资料 @不存在清单');
    expect(controller.lists, hasLength(4));
  });

  testWidgets('QUICK-020 Escape releases focus before clearing the draft',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));

    final field = find.byKey(const ValueKey('quick-add-title'));
    await tester.tap(field);
    await tester.enterText(field, '保留这条草稿');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '保留这条草稿');

    // Match TickTick: the first Escape only leaves the editor, keeping the
    // draft available for a later resume.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '保留这条草稿');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);

    // Re-entering the field and pressing Escape again is the explicit clear
    // gesture; it also verifies all smart-entry state is reset together.
    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
  });

  testWidgets(
      'QUICK-017 QUICK-021 quick add in Today keeps the view default in its Draft',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));
    await tester.enterText(
        find.byKey(const ValueKey('quick-add-title')), '今天要做');
    await tester.pump();
    await tester.tap(find.text('添加任务'));
    await tester.pump();
    final task = controller.tasks.single;
    final now = DateTime.now();
    expect(localDateTimeFromStorage(task.dueAt),
        DateTime(now.year, now.month, now.day));
    expect(task.bucket, TaskBucket.today);
  });

  testWidgets(
      'LIST-002 LIST-003 task lists use the single-line add row and expose list actions',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();

    final add = tester.widget<QuickAddField>(find.byType(QuickAddField).first);
    expect(add.listStyle, isTrue);
    expect(find.byTooltip('排序：手动'), findsOneWidget);
    await tester.tap(find.byTooltip('排序：手动'));
    await tester.pumpAndSettle();
    expect(find.text('按日期排序'), findsOneWidget);
    await tester.tap(find.text('按日期排序'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('排序：日期'), findsOneWidget);
  });

  testWidgets(
      'ROW-001 wide task workspace keeps the inspector fixed by default',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();

    expect(find.text('选择一个任务开始编辑'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-title-editor')), findsNothing);
  });

  testWidgets('KEY-004 Escape unwinds the fixed inspector selection',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备季度产品评审演示文稿').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsNothing);
    expect(find.text('选择一个任务开始编辑'), findsOneWidget);
  });

  testWidgets(
      'ARCH-008 task inspector keeps secondary properties behind a clean toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备季度产品评审演示文稿').last);
    await tester.pumpAndSettle();

    expect(find.byTooltip('显示更多属性'), findsOneWidget);
    expect(find.text('子任务'), findsNothing);
    expect(find.text('附件与关联'), findsNothing);

    await tester.tap(find.byTooltip('显示更多属性'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起更多属性'), findsOneWidget);
    expect(find.text('子任务'), findsOneWidget);
    expect(find.text('附件与关联'), findsOneWidget);
  });

  testWidgets(
      'DATE-001 DATE-002 MENU-001 task workspace exposes stable controls for atomic acceptance',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('list-view-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('list-sort')), findsOneWidget);
    expect(find.byKey(const ValueKey('list-actions')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-title')), findsOneWidget);

    await tester.tap(find.text('准备季度产品评审演示文稿').last);
    await tester.pumpAndSettle();
    for (final key in const [
      'task-complete',
      'task-schedule',
      'task-reminder',
      'task-repeat',
      'task-priority',
      'task-list-footer',
      'task-advanced-toggle',
      'task-more-actions',
      'save-status-indicator',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }

    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('date-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-shortcut-今天')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-shortcut-明天')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-prev-month')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-next-month')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-time-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('apply-date')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('date-cancel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-option-toggle-details')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-duplicate')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-delete')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-option-toggle-details')));
    await tester.pumpAndSettle();
    expect(find.text('附件与关联'), findsOneWidget);
  });

  testWidgets(
      'PRIORITY-001 LIST-001 TAG-001 REPEAT-001 task property popovers expose smallest option sets',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备季度产品评审演示文稿').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-priority')));
    await tester.pumpAndSettle();
    for (final label in ['无优先级', '低优先级', '中优先级', '高优先级']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester
        .tap(find.byKey(const ValueKey('menu-option-TaskPriority.none')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-repeat')));
    await tester.pumpAndSettle();
    expect(find.text('重复任务'), findsOneWidget);
    expect(find.text('频率'), findsOneWidget);
    expect(find.text('完成本次任务后，会自动生成下一次。'), findsOneWidget);
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-advanced-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-tags')));
    await tester.pumpAndSettle();
    expect(find.text('标签').last, findsOneWidget);
    expect(find.text('用逗号分隔，例如 工作，重要'), findsOneWidget);
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-list-footer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-option-收集箱')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-工作')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-option-工作')));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'ARCH-004 recent and overdue smart lists are reachable from the rail',
      (tester) async {
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近 7 天').first);
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天'), findsWidgets);
    await tester.tap(find.text('过期').first);
    await tester.pumpAndSettle();
    expect(find.text('过期'), findsWidgets);
  });

  testWidgets(
      'MENU-001 MENU-005 MENU-006 task row context menu exposes shared property actions',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('菜单任务', listName: '收集箱');
    final task = controller.tasks.single;
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body:
                TaskRow(task: task, controller: controller, selected: true))));

    await tester.tap(find.byKey(ValueKey('task-row-more-${task.id}')));
    await tester.pumpAndSettle();
    for (final label in [
      '移动到清单…',
      '编辑标签…',
      '设置提醒…',
      '设置重复…',
      '设置截止日期…',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.byKey(const ValueKey('menu-option-list')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-工作')));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.listName, '工作');
  });
}
