import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

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

    await tester.ensureVisible(find.text('全部笔记'));
    await tester.tap(find.text('全部笔记'));
    await tester.pumpAndSettle();

    expect(find.text('季度评审 · 叙事结构'), findsWidgets);
    expect(find.text('写下你的想法、会议记录或下一步行动…'), findsOneWidget);
  });

  testWidgets('unified rail carries task views, lists and note folders',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划').first);
    await tester.pumpAndSettle();

    expect(find.text('清单'), findsOneWidget);
    expect(find.text('所有任务'), findsOneWidget);
    expect(find.text('阅读《设计心理学》第 4 章并做摘录'), findsWidgets);
    expect(find.byType(Tooltip), findsWidgets);
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
    await tester.ensureVisible(find.text('全部笔记'));
    await tester.tap(find.text('全部笔记'));
    await tester.pumpAndSettle();

    expect(find.text('全部笔记'), findsOneWidget);
    expect(find.text('最近编辑'), findsOneWidget);
    expect(find.text('季度评审 · 叙事结构'), findsWidgets);
  });

  testWidgets('narrow windows swap the list for a detail pane with a back path',
      (tester) async {
    tester.view.physicalSize = const Size(680, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();

    // Opening a row swaps the pane to the inspector with a back button.
    await tester.tap(find.text('给设计顾问发一封确认邮件').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-title-editor')), findsOneWidget);
    expect(find.byTooltip('返回列表'), findsOneWidget);

    // Going back restores the list.
    await tester.tap(find.byTooltip('返回列表'));
    await tester.pumpAndSettle();
    expect(find.text('给设计顾问发一封确认邮件'), findsOneWidget);
    expect(find.byTooltip('返回列表'), findsNothing);
  });

  testWidgets('edits a task from the detail inspector', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();

    final title = find.byKey(const ValueKey('task-title-editor'));
    final description = find.byKey(const ValueKey('task-description-editor'));
    expect(title, findsOneWidget);
    expect(description, findsOneWidget);

    await tester.enterText(title, '本地编辑后的任务');
    await tester.enterText(description, '本地编辑后的描述');
    await tester.pump();

    expect(find.text('本地编辑后的任务'), findsWidgets);
    expect(tester.widget<TextField>(description).controller?.text, '本地编辑后的描述');
  });

  testWidgets('edits and favorites a note', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('全部笔记'));
    await tester.tap(find.text('全部笔记'));
    await tester.pumpAndSettle();

    final title = find.byKey(const ValueKey('note-title-editor'));
    final body = find.byKey(const ValueKey('note-body-editor'));
    expect(title, findsOneWidget);
    expect(body, findsOneWidget);
    await tester.enterText(title, '本地笔记标题');
    await tester.enterText(body, '本地笔记正文');
    await tester.pump();

    expect(find.text('本地笔记标题'), findsWidgets);
    expect(tester.widget<TextField>(body).controller?.text, '本地笔记正文');
    expect(find.byTooltip('收藏笔记'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏笔记'));
    await tester.pump();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
  });
}
