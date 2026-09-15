import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/screens/notes_screen.dart';
import 'package:workfollow_personal/screens/today_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/sidebar.dart';

void main() {
  test('native workspace columns expose the Web layout contract', () {
    expect(AppRail.width, 52 + 1 + WorkFollowLayout.taskNavigationWidth);
    expect(WorkFollowLayout.taskNavigationWidth, 218);
    expect(WorkFollowLayout.taskListMinWidth, 360);
    expect(WorkFollowLayout.taskListWidth, 430);
    expect(WorkFollowLayout.taskListDividerWidth, 1);
    expect(WorkFollowLayout.taskDetailMinWidth, 320);
    expect(WorkFollowLayout.taskRowComfortableHeight, 48);
  });

  testWidgets('task workspace keeps the Web list and detail columns readable',
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
        WorkFollowLayout.taskListWidth);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('web-task-detail-pane')))
            .width,
        1000 -
            WorkFollowLayout.taskListWidth -
            WorkFollowLayout.taskListDividerWidth);
  });

  testWidgets('notes index follows the Web 300/270 desktop widths',
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
    expect(
        tester.getSize(find.byKey(const ValueKey('web-note-list-pane'))).width,
        300);
  });
}
