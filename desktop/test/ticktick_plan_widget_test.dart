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

  testWidgets('dismissing a date chip keeps it as title text and unscheduled',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(body: QuickAddField(controller: controller))));
    await tester.enterText(find.byKey(const ValueKey('quick-add-title')), '周五理账');
    await tester.pump();
    expect(find.byType(InputChip), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.tap(find.text('添加任务'));
    await tester.pump();
    expect(controller.tasks.single.title, '周五理账');
    expect(controller.tasks.single.dueAt, isNull);
    expect(controller.tasks.single.listName, '收集箱');
  });
}
