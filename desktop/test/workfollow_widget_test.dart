import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_color_tokens.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_row.dart';
import 'package:workfollow_personal/widgets/task_inspector.dart';

void main() {
  testWidgets('renders the personal home workspace', (tester) async {
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    // Home is reached from the icon rail; its own name no longer appears as a
    // second-column row (that column is gone).
    expect(find.byTooltip('首页'), findsOneWidget);
    expect(find.text('今天'), findsWidgets);
    expect(find.text('准备季度产品评审演示文稿'), findsWidgets);
    expect(find.text('记下下一件事…'), findsOneWidget);
  });

  testWidgets('home mini calendar shows every date at the normal window size',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;
    for (var day = 1; day <= days; day++) {
      expect(find.text('$day'), findsWidgets, reason: '日历应在首页显示本月 $day 日');
    }
  });

  testWidgets('opens the notes view from the sidebar', (tester) async {
    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    // Notes are a separate second-column context, selected from the native
    // icon rail instead of being mixed into task navigation.
    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部笔记'));
    await tester.pumpAndSettle();

    expect(find.text('季度评审 · 叙事结构'), findsWidgets);
    await tester.tap(find.text('季度评审 · 叙事结构').last);
    await tester.pumpAndSettle();
    expect(find.byType(quill.QuillEditor), findsOneWidget);
    expect(
        tester
            .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
            .controller
            .document
            .toPlainText()
            .trim(),
        isNotEmpty);
  });

  testWidgets('contextual rail separates task views from note folders',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划').first);
    await tester.pumpAndSettle();

    expect(find.text('清单'), findsOneWidget);
    expect(find.text('所有任务'), findsOneWidget);
    expect(find.text('全部笔记'), findsNothing);
    expect(find.text('阅读《设计心理学》第 4 章并做摘录'), findsWidgets);
    expect(find.byType(Tooltip), findsWidgets);

    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget);
    expect(find.text('清单'), findsNothing);
  });

  testWidgets('home and the module pages keep only the icon rail',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    // Home is a dashboard rather than a second navigation tree: its 首页 and
    // 快速录入 rows only repeated the icon rail, so the column is gone.
    expect(find.byKey(const ValueKey('rail-context-column')), findsNothing);
    expect(find.byTooltip('首页'), findsOneWidget);
    expect(find.text('清单'), findsNothing);
    expect(find.text('全部笔记'), findsNothing);

    // The task and note trees keep their column, and none of them drag the
    // global toolbar back: the shell has no such row any more, every page owns
    // its own header.
    expect(find.byKey(const ValueKey('app-toolbar')), findsNothing);

    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rail-context-column')), findsOneWidget);
    expect(find.text('清单'), findsOneWidget);
    expect(find.text('全部笔记'), findsNothing);
    expect(find.text('日历'), findsNothing);
    expect(find.byKey(const ValueKey('app-toolbar')), findsNothing);

    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget);
    expect(find.text('清单'), findsNothing);
    expect(find.byKey(const ValueKey('rail-context-column')), findsOneWidget);

    // Calendar and matrix are self-contained too: their page header already
    // owns the controls, so the shell keeps only the icon rail.
    for (final label in ['日历', '四象限']) {
      await tester.tap(find.byTooltip(label));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rail-context-column')), findsNothing,
          reason: '$label 不应再有第二栏');
      expect(find.byKey(const ValueKey('app-toolbar')), findsNothing,
          reason: '$label 不应再有全局顶栏');
      expect(find.byTooltip(label), findsOneWidget,
          reason: '$label 的图标栏入口必须保留');
      expect(find.text('清单'), findsNothing);
      expect(find.text('全部笔记'), findsNothing);
    }
  });

  testWidgets('switching the rail destination moves the highlight in one frame',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();

    Color? railFill(String label) {
      final box = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byKey(ValueKey('rail-button-$label')),
              matching: find.byType(DecoratedBox))
          .first);
      return (box.decoration as BoxDecoration).color;
    }

    expect(railFill('首页')!.a, greaterThan(0), reason: '首页应处于选中态');
    expect(railFill('任务')!.a, 0);

    await tester.tap(find.byTooltip('任务'));
    await tester.pump();
    expect(railFill('首页')!.a, 0, reason: '离开的入口必须当帧失去底色，不能淡出');
    expect(railFill('任务')!.a, greaterThan(0), reason: '进入的入口必须当帧就位');
  });

  testWidgets(
      'the navigation column states selection with a neutral fill, not ink',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    const tokens = WorkFollowTheme.light;

    TextStyle words(String rowKey) => tester
        .widget<Text>(find
            .descendant(
                of: find.byKey(ValueKey(rowKey)), matching: find.byType(Text))
            .first)
        .style!;

    Color? fill(String rowKey) {
      final box = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byKey(ValueKey(rowKey)), matching: find.byType(DecoratedBox))
          .first);
      return (box.decoration as BoxDecoration).color;
    }

    void expectNeutral(Color color, String what) {
      // A neutral fill is the product's own quiet grey, not a colour wash. The
      // column now shares the content surface with the panes beside it, so a
      // selected row cannot be a lighter-than-the-column white any more and
      // takes the same grey every other selected row wears; that grey carries
      // the theme's few steps of cool lean (238/241/243), so the rule is a
      // bound on the channel spread rather than three equal channels. An
      // accent tint is far outside the band.
      final channels = [color.r, color.g, color.b];
      final spread =
          channels.reduce((a, b) => a > b ? a : b) -
              channels.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThan(0.04),
          reason: '$what 的底色应是中性灰，不能带色相');
      expect(color, isNot(WorkFollowColorTokens.lightNavigationSelected),
          reason: '$what 不该再用主色淡洗来表达选中');
    }

    // Selected and unselected rows carry the same ink: the darkest text in the
    // column, one weight step above the body. Selection is the only thing that
    // may differ, and it belongs to the fill.
    for (final row in ['rail-navigation-item-今天', 'rail-navigation-item-计划']) {
      expect(words(row).color, tokens.textPrimary,
          reason: '$row 的文字是黑色主体，不随选中变色');
      expect(words(row).fontWeight, WorkFollowMacWeight.medium,
          reason: '$row 的文字是 medium，普通项不该细到看着发灰');
    }

    final selected = fill('rail-navigation-item-今天')!;
    expectNeutral(selected, '选中的导航项');

    // A list keeps its colour on the dot. Tinting the words instead made the
    // column read as a row of coloured labels rather than as navigation.
    await tester.tap(find.byKey(const ValueKey('rail-list-item-工作')));
    await tester.pumpAndSettle();
    expect(words('rail-list-item-工作').color, tokens.textPrimary);
    expect(words('rail-list-item-工作').fontWeight, WorkFollowMacWeight.medium);
    expectNeutral(fill('rail-list-item-工作')!, '选中的清单');
  });

  testWidgets('hovering a rail row lights only the row under the pointer',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    const lists = ['工作', '个人', '学习'];
    Finder row(String name) => find.byKey(ValueKey('rail-list-item-$name'));
    Color? fill(String name) {
      final box = tester.widget<DecoratedBox>(find
          .descendant(of: row(name), matching: find.byType(DecoratedBox))
          .first);
      return (box.decoration as BoxDecoration).color;
    }

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(1390, 890));
    await tester.pump();

    // A hand moving down the column: two frames per row, the pointer actually
    // resting on each one. With an eased fill every row already passed was still
    // carrying part of its tint (0.19 of it, measured 90ms after the pointer had
    // moved on), so three rows looked lit at once and the column read as if the
    // pointer had clicked its way down. The fill has to arrive and leave with
    // the pointer, in the same frame.
    for (final name in lists) {
      await gesture.moveTo(tester.getCenter(row(name)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      for (final other in lists) {
        if (other == name) {
          expect(fill(other)!.a, greaterThan(0),
              reason: '指针下的 $other 必须当帧亮起');
        } else {
          expect(fill(other)!.a, 0,
              reason: '$other 只是被指针路过，必须当帧恢复常态');
        }
      }
    }

    // And leaving the column clears them all at once.
    await gesture.moveTo(const Offset(1390, 890));
    await tester.pump();
    for (final name in lists) {
      expect(fill(name)!.a, 0, reason: '指针离开后 $name 不得残留底色');
    }
    await gesture.removePointer();
  });

  testWidgets('wide task view keeps a persistent list and inspector pane',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
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

    expect(find.byType(TaskInspector), findsNothing);
    await tester.tap(find.text('准备季度产品评审演示文稿').last);
    await tester.pumpAndSettle();

    expect(find.byType(TaskInspector), findsOneWidget);
    expect(find.byKey(const ValueKey('task-schedule')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-repeat')), findsNothing);
    expect(find.byKey(const ValueKey('task-priority')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes keep folder, note list and editor panes', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部笔记'));
    await tester.pumpAndSettle();

    expect(find.text('全部笔记'), findsOneWidget);
    // The index order toggle is an icon on the search line, so it is found by
    // its tooltip rather than by a visible "最近编辑" label.
    expect(find.byTooltip('按最近编辑'), findsOneWidget);
    expect(find.text('季度评审 · 叙事结构'), findsWidgets);
    // The note list pane carries its own 笔记 header, so the shell does not
    // repeat it in a global toolbar.
    expect(find.byKey(const ValueKey('app-toolbar')), findsNothing);

    // The navigation column opens at its first destination in every view. The
    // brand mark used to sit above the note tree only, so the column changed
    // height — and started with a logo — the moment the user switched to notes.
    expect(find.text('打勾'), findsNothing);

    // A note row carries its folder and timestamp in one trailing metadata
    // column, the arrangement the task rows already use for list name and date.
    final pane = find.byKey(const ValueKey('web-note-list-pane'));
    final paneRect = tester.getRect(pane);
    final folder = tester.getRect(find.descendant(
        of: pane, matching: find.text('工作笔记')));
    expect(folder.right, greaterThan(paneRect.center.dx));
    expect(paneRect.right - folder.right,
        lessThan(NotesMetrics.rowHorizontalPadding * 3));
  });

  testWidgets('narrow windows swap the list for a detail pane with a back path',
      (tester) async {
    tester.view.physicalSize = const Size(680, 600);
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

  testWidgets('narrow detail preserves the task list scroll position',
      (tester) async {
    tester.view.physicalSize = const Size(680, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController();
    controller.selectView(WorkspaceView.today);
    for (var index = 0; index < 80; index++) {
      controller.addTask('长列表任务 $index');
    }

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: TodayScreen(controller: controller)),
    ));
    await tester.pumpAndSettle();

    // TextFields have their own internal Scrollable; the task list is the
    // last one in this small standalone tree.
    final list = find.byType(Scrollable).last;
    await tester.drag(list, const Offset(0, -1200));
    await tester.pumpAndSettle();
    final visibleRow = find.byType(TaskRow).last;
    await tester.ensureVisible(visibleRow);
    // Let the scroll settle before resolving anything: the reveal schedules a
    // new frame, and a finder evaluated before it would read the pre-scroll
    // layout.
    await tester.pumpAndSettle();
    // Tap by title: the lazy list builds more rows during the scroll, so a
    // type-based ".last" finder would re-resolve to a different, off-screen
    // row between ensureVisible and tap.
    final rowTitle = tester.widget<TaskRow>(visibleRow).task.title;
    await tester.ensureVisible(find.text(rowTitle).last);
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(list).position.pixels;
    expect(before, greaterThan(0));
    await tester.tap(find.text(rowTitle).last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回列表'), findsOneWidget);
    await tester.tap(find.byTooltip('返回列表'));
    await tester.pumpAndSettle();

    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .pixels;
    expect(after, closeTo(before, 1));
  });

  testWidgets('edits a task from the detail inspector', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
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

    final title = find.byKey(const ValueKey('task-title-editor'));
    final document = find.byKey(const ValueKey('task-document-editor'));
    expect(title, findsOneWidget);
    expect(document, findsOneWidget);

    await tester.enterText(title, '本地编辑后的任务');
    final editor = tester.widget<quill.QuillEditor>(document).controller;
    editor.replaceText(0, editor.document.length - 1, '本地编辑后的描述',
        const TextSelection.collapsed(offset: 8));
    await tester.pump();

    expect(find.text('本地编辑后的任务'), findsWidgets);
    expect(editor.document.toPlainText().trimRight(), '本地编辑后的描述');
  });

  testWidgets('edits and favorites a note', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部笔记'));
    await tester.pumpAndSettle();

    final title = find.byKey(const ValueKey('note-title-editor'));
    final body = find.byKey(const ValueKey('note-body-editor'));
    expect(title, findsOneWidget);
    expect(body, findsOneWidget);
    await tester.enterText(title, '本地笔记标题');
    final editor = tester.widget<quill.QuillEditor>(body).controller;
    editor.replaceText(0, editor.document.length - 1, '本地笔记正文',
        const TextSelection.collapsed(offset: 6));
    await tester.pump();

    expect(find.text('本地笔记标题'), findsWidgets);
    expect(editor.document.toPlainText().trimRight(), '本地笔记正文');
    expect(find.byTooltip('收藏笔记'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏笔记'));
    await tester.pump();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
  });
}
