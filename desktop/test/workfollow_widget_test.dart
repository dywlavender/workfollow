import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:workfollow_personal/app.dart';

void main() {
  testWidgets('renders the personal home workspace', (tester) async {
    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('今天'), findsWidgets);
    expect(find.text('准备季度产品评审演示文稿'), findsWidgets);
    expect(find.text('记下下一件事…'), findsOneWidget);
  });

  testWidgets('opens the notes view from the sidebar', (tester) async {
    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('笔记').first);
    await tester.pumpAndSettle();

    expect(find.text('季度评审 · 叙事结构'), findsWidgets);
    expect(find.text('把想法写下来，任务就有了可以回来的地方。'), findsOneWidget);
  });

  testWidgets('keeps the web-aligned task navigation as a separate pane',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();

    expect(find.text('任务视图'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('清单'), findsOneWidget);
    expect(find.text('所有'), findsOneWidget);
    expect(find.text('准备季度产品评审演示文稿'), findsWidgets);
  });

  testWidgets('notes keep folder, note list and editor panes', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('笔记').first);
    await tester.pumpAndSettle();

    expect(find.text('视图'), findsOneWidget);
    expect(find.text('文件夹'), findsOneWidget);
    expect(find.text('最近编辑'), findsOneWidget);
    expect(find.text('季度评审 · 叙事结构'), findsWidgets);
  });
}
