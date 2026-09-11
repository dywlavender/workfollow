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

  testWidgets('edits a task from the detail inspector', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('任务').first);
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
    await tester.tap(find.text('笔记').first);
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
