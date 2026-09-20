import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_icons.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/quick_add.dart';
import 'package:workfollow_personal/widgets/task_row.dart';
import 'package:workfollow_personal/widgets/task_list/task_metadata_trail.dart';

void main() {
  testWidgets('matrix view is reachable from the native rail', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('四象限'));
    await tester.pumpAndSettle();
    expect(find.text('重要且紧急'), findsOneWidget);
    expect(find.text('重要不紧急'), findsOneWidget);
    expect(find.text('不重要但紧急'), findsOneWidget);
    expect(find.text('不重要不紧急'), findsOneWidget);
  });

  testWidgets('week calendar view is reachable', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    // The view mode is a menu rather than a segmented control: the current
    // mode is the control's own label and the alternatives sit behind it.
    await tester.tap(find.byKey(const ValueKey('calendar-view-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-week')));
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

  testWidgets('task metadata keeps one right-aligned column across rows',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final date = DateTime(2030, 9, 18);
    final dateOnly = TaskItem(
      id: 'metadata-date-only',
      title: '只有日期',
      listName: '收集箱',
      bucket: TaskBucket.today,
      dueAt: date.toIso8601String(),
    );
    final listAndDate = TaskItem(
      id: 'metadata-list-and-date',
      title: '清单和日期',
      listName: '工作',
      bucket: TaskBucket.today,
      dueAt: date.toIso8601String(),
    );

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: SizedBox(
          width: 720,
          child: Column(
            children: [
              TaskRow(task: dateOnly, controller: controller, selected: false),
              TaskRow(
                  task: listAndDate, controller: controller, selected: false),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final metadata = find.byType(TaskMetadataTrail);
    expect(metadata, findsNWidgets(2));
    final dateOnlyRect = tester.getRect(metadata.at(0));
    final listAndDateRect = tester.getRect(metadata.at(1));
    expect(listAndDateRect.right, closeTo(dateOnlyRect.right, 0.01));
  });

  testWidgets('task metadata keeps primary fields and caps secondary noise',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final task = TaskItem(
      id: 'metadata-hierarchy',
      title: '一个足够长的任务标题，用来确认属性不会把标题挤成几个字',
      listName: '工作',
      bucket: TaskBucket.later,
      dueAt: DateTime(2030, 9, 18, 10).toIso8601String(),
      hasDueTime: true,
      reminderAt: DateTime(2030, 9, 18, 9).toIso8601String(),
      recurrenceType: 'WEEKLY',
      tags: const ['项目'],
      description: '这条描述只应该作为一个次要提示出现',
      attachments: const ['brief.pdf'],
      priority: TaskPriority.high,
    );
    // Two real child tasks back the hierarchy count in the metadata trail.
    controller.loadTasksForTest([
      task,
      TaskItem(
          id: 'child-1',
          title: '子任务一',
          listName: '工作',
          bucket: TaskBucket.unscheduled,
          parentTaskId: task.id,
          childOrder: 0),
      TaskItem(
          id: 'child-2',
          title: '子任务二',
          listName: '工作',
          bucket: TaskBucket.unscheduled,
          parentTaskId: task.id,
          childOrder: 1),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: SizedBox(
          width: TaskListMetrics.preferredPaneWidth,
          child: TaskRow(task: task, controller: controller, selected: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final title = find.text(task.title);
    final metadata = find.byType(TaskMetadataTrail);
    expect(title, findsOneWidget);
    expect(metadata, findsOneWidget);
    expect(tester.getSize(title).width, greaterThan(120));
    expect(tester.getSize(metadata).width,
        lessThanOrEqualTo(TaskListMetrics.metadataMaxWidth));

    // List, priority, subtask count and the date remain visible row-critical
    // information. Other secondary indicators are deliberately capped.
    expect(find.text('工作'), findsOneWidget);
    // The count reads the hierarchy: two children, none completed.
    expect(find.text('0/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-row-date-metadata-hierarchy')),
        findsOneWidget);
    final secondaryCount = [
      WorkFollowIcons.repeat,
      WorkFollowIcons.reminder,
      WorkFollowIcons.tag,
      WorkFollowIcons.article,
      WorkFollowIcons.attachment,
    ].fold<int>(
        0, (count, icon) => count + find.byIcon(icon).evaluate().length);
    expect(secondaryCount,
        lessThanOrEqualTo(TaskListMetrics.secondaryMetadataLimit));
  });

  testWidgets('task metadata exposes a tag indicator without rendering tags',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final task = TaskItem(
      id: 'metadata-tag',
      title: '标签任务',
      listName: '收集箱',
      bucket: TaskBucket.unscheduled,
      tags: const ['项目'],
    );

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: TaskRow(task: task, controller: controller, selected: false),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(WorkFollowIcons.tag), findsOneWidget);
    expect(find.text('项目'), findsNothing);
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

  testWidgets('ROW-003 moving the selection snaps instead of cross-fading',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('第一行');
    controller.addTask('第二行');
    final first = controller.tasks[0], second = controller.tasks[1];
    var selectedId = first.id;

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            TaskRow(
                task: first,
                controller: controller,
                selected: selectedId == first.id,
                onActivate: () => setState(() => selectedId = first.id)),
            TaskRow(
                task: second,
                controller: controller,
                selected: selectedId == second.id,
                onActivate: () => setState(() => selectedId = second.id)),
          ]),
        ),
      ),
    ));
    await tester.pump();

    Color? fill(String id) {
      final box = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byKey(ValueKey('task-row-surface-$id')),
              matching: find.byType(DecoratedBox))
          .first);
      return (box.decoration as BoxDecoration).color;
    }

    expect(fill(first.id), WorkFollowTheme.light.listRowSelected);
    expect(fill(second.id)?.a ?? 0, 0);

    await tester.tap(find.byType(TaskRow).at(1));
    // Exactly one frame: the row that just lost the selection has to be back to
    // normal immediately. Easing it leaves that row carrying 157/255 of its
    // selected fill 16ms later (measured), which reads as a second click.
    await tester.pump();
    expect(fill(first.id)?.a ?? 0, 0, reason: '刚取消选中的行必须当帧就恢复常态');
    expect(fill(second.id), WorkFollowTheme.light.listRowSelected,
        reason: '新选中的行必须当帧就位');
  });

  testWidgets('ROW-004 hovering a row never tints the rows passed over',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('第一行');
    controller.addTask('第二行');
    final first = controller.tasks[0], second = controller.tasks[1];

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Column(children: [
          TaskRow(task: first, controller: controller, selected: false),
          TaskRow(task: second, controller: controller, selected: false),
        ]),
      ),
    ));
    await tester.pump();

    Color? fill(String id) {
      final box = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byKey(ValueKey('task-row-surface-$id')),
              matching: find.byType(DecoratedBox))
          .first);
      return (box.decoration as BoxDecoration).color;
    }

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(5, 600));
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.byType(TaskRow).first));
    await tester.pump(const Duration(milliseconds: 16));
    expect(fill(first.id)!.a, greaterThan(0), reason: '指针下的行必须当帧亮起');
    expect(fill(second.id)!.a, 0);

    // Moving down to the second row has to clear the first one in the same
    // frame. An eased fill left it tinted for another 120ms, so both rows read
    // as hovered — and, on a list the pointer sweeps down, several at once.
    await gesture.moveTo(tester.getCenter(find.byType(TaskRow).last));
    await tester.pump(const Duration(milliseconds: 16));
    expect(fill(first.id)!.a, 0, reason: '被路过的行必须当帧清掉 hover 底色');
    expect(fill(second.id)!.a, greaterThan(0));

    await gesture.moveTo(const Offset(5, 600));
    await tester.pump(const Duration(milliseconds: 16));
    expect(fill(second.id)!.a, 0, reason: '指针离开后不得残留 hover 底色');
    await gesture.removePointer();
  });

  testWidgets('KEY-004 Escape keeps the fixed inspector selected',
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
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
    expect(find.text('选择一个任务开始编辑'), findsNothing);
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
    expect(find.byKey(const ValueKey('task-children-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-deadline')), findsNothing);
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
      'task-priority',
      'task-list-footer',
      'document-format-toggle',
      'task-more-actions',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }

    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-schedule-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-shortcut-今天')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-shortcut-明天')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-prev-month')), findsOneWidget);
    expect(find.byKey(const ValueKey('date-next-month')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('apply-date')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('menu-option-add-subtask')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-tags')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('menu-option-attachment')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-relation')), findsNothing);
    expect(find.byKey(const ValueKey('menu-option-copy')), findsNothing);
    expect(find.byKey(const ValueKey('menu-option-duplicate')), findsNothing);
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

    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-reminder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-offset-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-offset-30')), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-schedule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-repeat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('repeat-YEARLY')), findsOneWidget);
    expect(find.byKey(const ValueKey('repeat-workdays')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repeat-DAILY')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-date')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-tags')));
    await tester.pumpAndSettle();
    expect(find.text('标签').last, findsOneWidget);
    expect(find.byKey(const ValueKey('task-tag-search')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('task-tag-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task-list-footer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-option-收集箱')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-option-工作')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-option-工作')));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'ARCH-004 the recent list is reachable from the rail, and 过期 is not a destination',
      (tester) async {
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近 7 天').first);
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天'), findsWidgets);
    // Overdue work is now the leading group inside the dated views rather than
    // a page of its own, so the rail no longer offers 过期.
    expect(find.text('过期'), findsNothing);
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

    final menuGesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('task-row-surface-${task.id}'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await menuGesture.up();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('task-context-menu-panel')), findsOneWidget);
    for (final label in ['移动到', '标签', '置顶', '放弃', '转换为笔记', '删除']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('设置提醒…'), findsNothing);
    expect(find.text('设置重复…'), findsNothing);
    expect(find.text('设置截止日期…'), findsNothing);

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
    final firstMenuGesture = await tester.startGesture(
        tester.getCenter(find
            .byKey(ValueKey('task-row-surface-${controller.tasks.single.id}'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await firstMenuGesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-today')));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    final due = localDateTimeFromStorage(controller.tasks.single.dueAt);
    expect(due, isNotNull);
    expect(DateTime(due!.year, due.month, due.day),
        DateTime(today.year, today.month, today.day));

    await pumpRow();
    final secondMenuGesture = await tester.startGesture(
        tester.getCenter(find
            .byKey(ValueKey('task-row-surface-${controller.tasks.single.id}'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await secondMenuGesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-option-priority-high')));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.priority, TaskPriority.high);

    await pumpRow();
    final thirdMenuGesture = await tester.startGesture(
        tester.getCenter(find
            .byKey(ValueKey('task-row-surface-${controller.tasks.single.id}'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await thirdMenuGesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-option-complete')), findsNothing);
    controller.taskActions.complete(controller.tasks.single.id);
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
    await tester.enterText(
        find.byKey(const ValueKey('task-tag-search')), '项目，重要');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-tag-create')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('task-tag-confirm')));
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
    // Priority is a one-tap flag row inside the disclosure panel now, so the
    // old two-level menu (menu-option-priority → menu-option-TaskPriority.high)
    // is gone; tapping the high flag commits and closes the panel.
    await tester
        .tap(find.byKey(const ValueKey('quick-add-priority-flag-high')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-add-properties')), findsOneWidget);
  });

  testWidgets(
      'quick-add list and tag pickers stay beside their parent property rows',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 560,
            child: QuickAddField(controller: controller, listStyle: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The disclosure slots appear only while the row is selected (TickTick
    // rule: an unfocused add row shows just "+ placeholder"), so focus first.
    await tester.tap(find.byKey(const ValueKey('quick-add-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-add-properties')));
    await tester.pumpAndSettle();
    final parent = find.byKey(const ValueKey('quick-add-properties-panel'));
    expect(parent, findsOneWidget);

    final listRow = find.byKey(const ValueKey('menu-option-list'));
    final parentRect = tester.getRect(parent);
    final listRowRect = tester.getRect(listRow);
    await tester.tap(listRow);
    await tester.pumpAndSettle();
    expect(parent, findsOneWidget);
    final listPicker = find.byKey(const ValueKey('task-list-picker'));
    expect(listPicker, findsOneWidget);
    final listPickerRect = tester.getRect(listPicker);
    expect(listPickerRect.left, greaterThan(listRowRect.right));
    expect(listPickerRect.top, closeTo(listRowRect.top, 1));
    expect(parentRect.left, lessThan(listPickerRect.left));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(parent, findsOneWidget);
    expect(listPicker, findsNothing);

    final tagRow = find.byKey(const ValueKey('menu-option-tags'));
    final tagRowRect = tester.getRect(tagRow);
    await tester.tap(tagRow);
    await tester.pumpAndSettle();
    final tagPicker = find.byKey(const ValueKey('task-tag-picker'));
    expect(tagPicker, findsOneWidget);
    final tagPickerRect = tester.getRect(tagPicker);
    expect(tagPickerRect.left, greaterThan(tagRowRect.right));
    expect(tagPickerRect.top, closeTo(tagRowRect.top, 1));
    expect(parent, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('task navigation omits summary and trash keeps the task grammar',
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
    expect(find.text('摘要'), findsNothing);

    await tester.tap(find.text('垃圾桶').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('trash')), findsOneWidget);
    expect(find.text('打勾'), findsNothing);
    expect(find.text('摘要'), findsNothing);
  });
}
