import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/models/task.dart';
import 'package:workfollow_personal/screens/notes_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_interaction_states.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/calendar/calendar_task_bar.dart';

/// Controls that sit on a surface which already carries a hue must deepen that
/// hue under the pointer.
///
/// The shared hover is an opaque neutral (`listRowHover`), which is correct for
/// a row on the canvas and wrong for anything else: laid over the round accent
/// "new note" button it replaced the blue with a grey block, so the icon looked
/// washed out the moment the pointer arrived. These contracts hold the resolved
/// overlay of each tinted control, not a source scan, so a control that
/// silently falls back to the theme default fails here.
void main() {
  final tokens = WorkFollowTheme.light;

  Color? hoverOverlay(WidgetTester tester, Finder control) => tester
      .widget<InkWell>(
          find.descendant(of: control, matching: find.byType(InkWell)))
      .overlayColor
      ?.resolve({WidgetState.hovered});

  test('a tinted overlay deepens on hover and press and stays quiet otherwise',
      () {
    final overlay = WorkFollowInteractionStyles.tintedOverlay(tokens.accent);

    expect(overlay.resolve({WidgetState.hovered}),
        tokens.accent.withValues(alpha: .10));
    expect(overlay.resolve({WidgetState.pressed}),
        tokens.accent.withValues(alpha: .18));
    expect(overlay.resolve(const <WidgetState>{}), isNull);
    expect(overlay.resolve({WidgetState.disabled}), isNull);
    // The point of the contract: it is never the shared neutral.
    expect(overlay.resolve({WidgetState.hovered}), isNot(tokens.listRowHover));
  });

  testWidgets('the new-note button deepens its accent instead of going grey',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.selectView(WorkspaceView.notes);
    controller.addNoteInCurrentFolder();
    await tester.pump();

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: NotesScreen(controller: controller))));
    await tester.pumpAndSettle();

    final button = find.descendant(
        of: find.byType(NotesScreen),
        matching: find.byTooltip('新建笔记'));
    expect(button, findsOneWidget);

    final hover = hoverOverlay(tester, button);
    expect(hover, tokens.accentHover,
        reason: '实心 accent 按钮 hover 要走它自己的加深档，不能落在中性灰上');
    expect(hover, isNot(tokens.listRowHover));
  });

  testWidgets('the month bar keeps its list colour under the pointer',
      (tester) async {
    const listColor = Color(0xFF7C3AED);
    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: CalendarTaskBar(
                task: TaskItem(
                    id: 'bar',
                    title: '日历里的任务',
                    listName: '工作',
                    bucket: taskBucketForDate(null, now: DateTime.now())),
                listColor: listColor))));
    await tester.pumpAndSettle();

    final hover = hoverOverlay(tester, find.byType(CalendarTaskBar));
    expect(hover, listColor.withValues(alpha: .10),
        reason: '任务条本身就带清单色，hover 只能加深它，不能被中性灰盖掉');
    expect(hover, isNot(tokens.listRowHover));
  });

  test('the tinted controls without a widget harness still opt out', () {
    // The week pill and the source-note card are private or need a populated
    // controller, so they cannot be mounted as cheaply as the two above. A
    // scan is weaker than reading a resolved value, but it still fails the
    // day someone drops the line and re-inherits the opaque neutral.
    for (final path in const [
      'lib/widgets/calendar/calendar_week_view.dart',
      'lib/features/editor/profiles/task_editor_profile.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('tintedOverlay'),
          reason: '$path 里的有色表面控件必须显式声明 overlay，'
              '否则又回到吃全局不透明 hover 的老样子');
    }
  });
}
