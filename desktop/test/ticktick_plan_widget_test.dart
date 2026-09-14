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

  testWidgets(
      'QUICK-010 dismissing one scheduling token preserves the other token',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));

    final field = find.byKey(const ValueKey('quick-add-title'));
    // The comma keeps the date and clock as two independent smart tokens,
    // which lets this test exercise one-token dismissal rather than the
    // parser's single combined “明天 下午3点” span.
    await tester.enterText(field, '明天，下午3点 面试');
    await tester.pump();
    expect(find.byKey(const ValueKey('smart-chip-date-明天')), findsOneWidget);
    expect(find.byKey(const ValueKey('smart-chip-time-下午3点')), findsOneWidget);

    // Dismissing only the date must not make the remaining clock token
    // unscheduled. The dismissed date stays ordinary title text.
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('smart-chip-date-明天')),
        matching: find.byIcon(Icons.close)));
    await tester.pump();
    await tester.tap(find.text('添加任务'));
    await tester.pump();

    final created = controller.tasks.single;
    final now = DateTime.now();
    final expectedDay = DateTime(now.year, now.month, now.day, 15).isAfter(now)
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, now.day + 1);
    final due = localDateTimeFromStorage(created.dueAt);
    expect(created.title, contains('明天'));
    expect(created.title, contains('面试'));
    expect(created.scheduledWithTime, isTrue);
    expect(due, isNotNull);
    expect(DateTime(due!.year, due.month, due.day), expectedDay);
    expect(due.hour, 15);
    expect(due.minute, 0);
  });

  testWidgets(
      'QUICK-010 dismissing one duplicate token keeps the other token active',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));

    final field = find.byKey(const ValueKey('quick-add-title'));
    await tester.enterText(field, '#工作 #工作 记录');
    await tester.pump();
    expect(find.byType(InputChip), findsNWidgets(2));

    // Dismiss by position: the second identical marker must remain parsed as
    // a tag and only the first marker should stay in the title.
    await tester.tap(find.descendant(
        of: find.byType(InputChip).first, matching: find.byIcon(Icons.close)));
    await tester.pump();
    await tester.tap(find.text('添加任务'));
    await tester.pump();

    final task = controller.tasks.single;
    expect(task.title, '#工作 记录');
    expect(task.tags, ['工作']);
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

  testWidgets('QUICK-013 explicit list override keeps later @markers in title',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));

    final field = find.byKey(const ValueKey('quick-add-title'));
    await tester.enterText(field, '整理 @工作');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-add-list')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-工作')));
    await tester.pumpAndSettle();

    // The chosen list is authoritative, but a different marker typed later
    // is ordinary title text and must not disappear from the created task.
    await tester.enterText(field, '整理 @工作 @个人');
    await tester.pump();
    await tester.tap(find.text('添加任务'));
    await tester.pump();
    expect(controller.tasks.single.listName, '工作');
    expect(controller.tasks.single.title, '整理 @个人');
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

  testWidgets(
      'ROW-007 ROW-008 ROW-009 ROW-010 multi-selection keeps completion state separate',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('多选未完成');
    final task = controller.tasks.single;

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: TaskRow(
                task: task,
                controller: controller,
                selected: false,
                multiSelected: true))));
    await tester.pump();

    final checkbox = find.byKey(ValueKey('task-row-checkbox-${task.id}'));
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.tap(checkbox);
    await tester.pump();
    expect(controller.tasks.single.completed, isTrue);
  });

  testWidgets('KEY-001 KEY-002 Enter selects and Space completes a task row',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.inbox);
    controller.addTask('键盘任务');
    final task = controller.tasks.single;

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body:
                TaskRow(task: task, controller: controller, selected: false))));
    await tester.pump();

    await tester.tap(find.byType(TaskRow));
    await tester.pump();
    expect(controller.selectedTaskId, task.id);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.tasks.single.completed, isTrue);
  });

  testWidgets('ROW-002 repeated task-row tap preserves the current selection',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('重复点击任务');
    final task = controller.tasks.single;

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body:
                TaskRow(task: task, controller: controller, selected: false))));
    await tester.pump();

    await tester.tap(find.byType(TaskRow));
    await tester.pump();
    expect(controller.selectedTaskId, task.id);
    expect(controller.multiSelectedTaskIds, isEmpty);
    final openVersion = controller.taskOpenVersion;

    await tester.tap(find.byType(TaskRow));
    await tester.pump();
    expect(controller.selectedTaskId, task.id);
    expect(controller.multiSelectedTaskIds, isEmpty);
    expect(controller.taskOpenVersion, openVersion);
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
      'ARCH-008 task inspector keeps task capabilities in the document workbench',
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

    expect(find.byKey(const ValueKey('task-advanced-toggle')), findsNothing);
    expect(find.text('显示更多属性'), findsNothing);
    expect(find.byKey(const ValueKey('task-document-editor')), findsOneWidget);
    expect(find.text('子任务'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-deadline')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('list-view-icon')), findsOneWidget);
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
      'task-deadline',
      'task-list-footer',
      'task-format-toggle',
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
    expect(
        find.byKey(const ValueKey('menu-option-add-subtask')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-tags')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('menu-option-attachment')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-relation')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-duplicate')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-delete')), findsOneWidget);
  });

  testWidgets(
      'PRIORITY-001 LIST-001 TAG-001 REM-001 REPEAT-001 task property popovers expose smallest option sets',
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

    await tester.tap(find.byKey(const ValueKey('task-reminder')));
    await tester.pumpAndSettle();
    expect(find.text('提醒我'), findsOneWidget);
    expect(find.byKey(const ValueKey('date-input')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('date-cancel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-repeat')));
    await tester.pumpAndSettle();
    expect(find.text('重复任务'), findsOneWidget);
    expect(find.text('频率'), findsOneWidget);
    expect(find.text('完成本次任务后，会自动生成下一次。'), findsOneWidget);
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-tags')));
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

  testWidgets(
      'DATE-004 DATE-005 MENU-002 MENU-003 MENU-004 PRIORITY-002 context menu routes date, completion and priority through Actions',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    controller.addTask('原子菜单任务', dueAt: yesterday, hasTime: false);

    Future<void> pumpRow() async {
      await tester.pumpWidget(MaterialApp(
          theme: WorkFollowThemeData.light(),
          home: Scaffold(
              body: TaskRow(
                  task: controller.tasks.single,
                  controller: controller,
                  selected: true))));
      await tester.pumpAndSettle();
    }

    await pumpRow();
    await tester.tap(
        find.byKey(ValueKey('task-row-more-${controller.tasks.single.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-today')));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    final due = localDateTimeFromStorage(controller.tasks.single.dueAt);
    expect(due, isNotNull);
    expect(DateTime(due!.year, due.month, due.day),
        DateTime(today.year, today.month, today.day));

    await pumpRow();
    await tester.tap(
        find.byKey(ValueKey('task-row-more-${controller.tasks.single.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-priority-high')));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.priority, TaskPriority.high);

    await pumpRow();
    await tester.tap(
        find.byKey(ValueKey('task-row-more-${controller.tasks.single.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-complete')));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.completed, isTrue);
  });

  testWidgets(
      'DATE-003 QUICK-001 QUICK-003 QUICK-011 QUICK-012 QUICK-013 QUICK-014 QUICK-015 QUICK-016 QUICK-018 QUICK-019 PRIORITY-003 TAG-002 REM-006 REPEAT-006 manual Draft properties commit once',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));

    final field = find.byKey(const ValueKey('quick-add-title'));
    await tester.tap(field);
    await tester.enterText(field, '一次完成的手动任务');
    await tester.pump();

    // Every property is changed in the Draft while the task list remains
    // untouched until the single Return/submit boundary.
    await tester.tap(find.byKey(const ValueKey('quick-add-schedule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('date-shortcut-明天')));
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-add-priority')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('menu-option-TaskPriority.high')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-add-list')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-工作')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-add-tags')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '项目，重要');
    await tester.tap(find.text('完成').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-add-reminder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('date-shortcut-明天')));
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-add-repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每天').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();

    expect(controller.tasks, isEmpty);
    await tester.tap(find.text('添加任务'));
    await tester.pumpAndSettle();

    expect(controller.tasks, hasLength(1));
    final task = controller.tasks.single;
    expect(task.title, '一次完成的手动任务');
    expect(task.listName, '工作');
    expect(task.priority, TaskPriority.high);
    expect(task.tags, ['项目', '重要']);
    expect(task.reminderAt, isNotNull);
    expect(task.recurrenceType, 'DAILY');
    final due = localDateTimeFromStorage(task.dueAt);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(due, isNotNull);
    expect(DateTime(due!.year, due.month, due.day),
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
  });

  testWidgets(
      'L-05 QUICK-012 QUICK-013 list QuickAdd keeps secondary properties behind one clean menu',
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

    final field = find.byKey(const ValueKey('quick-add-title'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-add-properties')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-add-priority')), findsNothing);
    expect(find.byKey(const ValueKey('quick-add-list')), findsNothing);
    expect(find.byKey(const ValueKey('quick-add-tags')), findsNothing);
    expect(find.byKey(const ValueKey('quick-add-reminder')), findsNothing);
    expect(find.byKey(const ValueKey('quick-add-repeat')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('quick-add-properties')));
    await tester.pumpAndSettle();
    for (final label in ['优先级', '清单', '标签', '提醒', '重复']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.byKey(const ValueKey('menu-option-priority')));
    await tester.pumpAndSettle();
    expect(find.text('高优先级'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('menu-option-TaskPriority.high')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-add-properties')), findsOneWidget);
  });
}
