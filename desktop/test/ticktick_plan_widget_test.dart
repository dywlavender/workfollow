import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/quick_add.dart';

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

    await tester.ensureVisible(find.text('统计'));
    await tester.tap(find.text('统计').last);
    await tester.pumpAndSettle();
    expect(find.text('完成趋势'), findsOneWidget);
    expect(find.text('完成热力图'), findsOneWidget);
    expect(find.text('清单分布'), findsOneWidget);

    await tester.ensureVisible(find.text('四象限'));
    await tester.tap(find.text('四象限').last);
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

    await tester.ensureVisible(find.text('看板'));
    await tester.tap(find.text('看板').last);
    await tester.pumpAndSettle();
    expect(find.text('优先级'), findsOneWidget);
    expect(find.text('高优先级'), findsOneWidget);

    await tester.ensureVisible(find.text('习惯'));
    await tester.tap(find.text('习惯').last);
    await tester.pumpAndSettle();
    expect(find.text('晨间拉伸'), findsOneWidget);
    expect(find.text('连续'), findsNWidgets(2));

    await tester.ensureVisible(find.text('日历'));
    await tester.tap(find.text('日历').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    expect(find.textContaining('周一'), findsOneWidget);
    expect(find.textContaining('周日'), findsOneWidget);
  });

  testWidgets('dismissing a date chip keeps it as title text and unscheduled',
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

  testWidgets('unknown list chips stay in the quick-add title', (tester) async {
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

  testWidgets('task lists use the single-line add row and expose list actions',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
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

  testWidgets('wide task workspace keeps the inspector fixed by default',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();

    expect(find.text('选择一个任务开始编辑'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-title-editor')), findsNothing);
  });

  testWidgets('task inspector keeps secondary properties behind a clean toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
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

  testWidgets('task workspace exposes stable controls for atomic acceptance',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
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

  testWidgets('task property popovers expose their smallest option sets',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
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

  testWidgets('recent and overdue smart lists are reachable from the rail',
      (tester) async {
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近 7 天').first);
    await tester.pumpAndSettle();
    expect(find.text('最近 7 天'), findsWidgets);
    await tester.tap(find.text('过期').first);
    await tester.pumpAndSettle();
    expect(find.text('过期'), findsWidgets);
  });
}
