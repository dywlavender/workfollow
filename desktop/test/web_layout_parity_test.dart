import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/app.dart';
import 'package:workfollow_personal/screens/notes_screen.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/sidebar.dart';

void main() {
  test('native workspace keeps the Web contract and compact macOS profile', () {
    expect(AppRail.width, 52 + 1 + WorkFollowLayout.compactTaskNavigationWidth);
    expect(WorkFollowLayout.taskNavigationWidth, 218);
    expect(WorkFollowLayout.taskListMinWidth, 360);
    expect(WorkFollowLayout.taskListWidth, 430);
    expect(WorkFollowLayout.compactTaskNavigationWidth, 196);
    // The native list pane is now driven by TaskListMetrics: 440 wide, never
    // below 380. The old 380/320 pair was a navigation-column width, and it
    // ellipsised task titles before their metadata.
    expect(WorkFollowLayout.compactTaskListMinWidth, 380);
    expect(WorkFollowLayout.compactTaskListWidth, 440);
    expect(WorkFollowMetrics.compactNavigationRowHeight, 34);
    expect(WorkFollowMetrics.compactNavigationSectionTop, 14);
    expect(WorkFollowLayout.taskListDividerWidth, 1);
    expect(WorkFollowLayout.taskDetailMinWidth, 320);
    expect(WorkFollowLayout.taskRowComfortableHeight, 48);
  });

  testWidgets('task workspace uses a compact list and readable detail column',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.inbox);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body:
                SizedBox.expand(child: TodayScreen(controller: controller)))));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('web-task-list-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('web-task-detail-pane')), findsOneWidget);
    expect(
        tester.getSize(find.byKey(const ValueKey('web-task-list-pane'))).width,
        WorkFollowLayout.compactTaskListWidth);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('web-task-detail-pane')))
            .width,
        1000 -
            WorkFollowLayout.compactTaskListWidth -
            WorkFollowLayout.taskListDividerWidth);
  });

  testWidgets('task list pane width survives task-view changes', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (_, __) => SizedBox.expand(
            child: TodayScreen(controller: controller),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final divider = find.byKey(const ValueKey('task-pane-divider'));
    await tester.drag(divider, const Offset(30, 0));
    await tester.pumpAndSettle();
    final listPane = find.byKey(const ValueKey('web-task-list-pane'));
    expect(tester.getSize(listPane).width, TaskListMetrics.maxPaneWidth);
    expect(controller.taskListPaneWidth, TaskListMetrics.maxPaneWidth);

    for (final view in [WorkspaceView.inbox, WorkspaceView.recent]) {
      controller.selectView(view);
      await tester.pumpAndSettle();
      expect(tester.getSize(listPane).width, TaskListMetrics.maxPaneWidth,
          reason: '${view.name} should reuse the workspace pane width');
    }
  });

  testWidgets('full shell locks the 949/950 and 1280 workspace geometry',
      (tester) async {
    tester.view.physicalSize = const Size(950, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const WorkFollowApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    final listPane = find.byKey(const ValueKey('web-task-list-pane'));
    final detailPane = find.byKey(const ValueKey('web-task-detail-pane'));
    expect(tester.getSize(listPane).width, TaskListMetrics.minPaneWidth);
    expect(tester.getSize(detailPane).width,
        WorkFollowLayout.taskDetailMinWidth);

    tester.view.physicalSize = const Size(949, 800);
    await tester.pumpAndSettle();
    expect(detailPane, findsNothing,
        reason: '949 total window pixels leaves a 700px task workspace');

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(tester.getSize(listPane).width, TaskListMetrics.preferredPaneWidth);
    expect(
        tester.getSize(detailPane).width,
        1280 -
            AppRail.width -
            TaskListMetrics.preferredPaneWidth -
            WorkFollowLayout.taskListDividerWidth);
  });

  testWidgets('workspace keeps the detail fallback until both panes fit',
      (tester) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: true);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.inbox);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body:
                SizedBox.expand(child: TodayScreen(controller: controller)))));
    await tester.pumpAndSettle();

    // The list still owns the whole surface while the inspector contract does
    // not fit. Selecting a task must use the stacked detail fallback rather
    // than leaving the selection without an editor.
    expect(find.byKey(const ValueKey('web-task-detail-pane')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task-03')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-task-03')), findsOneWidget);

    // At the first width where list minimum + divider + detail minimum fit,
    // the same selection becomes the persistent two-pane workspace.
    tester.view.physicalSize = const Size(701, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('web-task-detail-pane')), findsOneWidget);
    expect(
        tester.getSize(find.byKey(const ValueKey('web-task-list-pane'))).width,
        greaterThanOrEqualTo(TaskListMetrics.minPaneWidth));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('web-task-detail-pane')))
            .width,
        greaterThanOrEqualTo(WorkFollowLayout.taskDetailMinWidth));

    // Grouped rows hold the same one-line title contract as every other list
    // entry: a wrapped title would make grouping change the row's height.
    final title = tester.widget<Text>(find.text('给设计顾问发一封确认邮件').first);
    expect(title.maxLines, 1);
  });

  testWidgets('task list divider keeps its width inside the readable range',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.inbox);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body:
                SizedBox.expand(child: TodayScreen(controller: controller)))));
    await tester.pumpAndSettle();

    final listPane = find.byKey(const ValueKey('web-task-list-pane'));
    final divider = find.byKey(const ValueKey('task-pane-divider'));
    expect(tester.getSize(listPane).width, TaskListMetrics.preferredPaneWidth);

    await tester.drag(divider, const Offset(1000, 0));
    await tester.pump();
    expect(tester.getSize(listPane).width, TaskListMetrics.maxPaneWidth);

    await tester.drag(divider, const Offset(-1000, 0));
    await tester.pump();
    expect(tester.getSize(listPane).width, TaskListMetrics.minPaneWidth);
  });

  testWidgets('task navigation and list rows use the compact native rhythm',
      (tester) async {
    final controller = WorkspaceController(seedData: true);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.today);
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: SizedBox(
          width: AppRail.width,
          height: 720,
          child: AppRail(
            controller: controller,
            isDark: false,
            onToggleTheme: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('rail-navigation-item-今天')))
          .height,
      WorkFollowMetrics.compactNavigationRowHeight + 2,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('rail-list-item-工作'))).height,
      WorkFollowMetrics.compactNavigationRowHeight + 2,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('rail-list-item-工作'))).width,
      WorkFollowMetrics.listItemMaxWidth,
    );
  });

  testWidgets('notes index resolves the wide and compact pane widths',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
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
            body:
                SizedBox.expand(child: NotesScreen(controller: controller)))));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('web-note-list-pane')), findsOneWidget);
    // 330 wide / 300 compact. The index is a third of a three-column
    // workspace, so it follows the reference proportion rather than the Web
    // client's 300/270 index widths.
    expect(NotesMetrics.listWidth, 330);
    expect(NotesMetrics.compactListWidth, 300);
    expect(
        tester.getSize(find.byKey(const ValueKey('web-note-list-pane'))).width,
        NotesMetrics.listWidth);
  });
}
