import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
