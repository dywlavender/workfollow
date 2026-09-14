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
