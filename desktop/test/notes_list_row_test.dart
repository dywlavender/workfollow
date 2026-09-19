import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/screens/notes_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

/// The note index is a list to scan, so a row is as tall as what it holds.
///
/// Every row used to carry an 88pt floor that was read off the reference list
/// without checking the content. A note row holds a title, a 4pt gap and one
/// preview line — 41pt — with a 10pt inset above and below, so the floor was
/// 27pt taller than the row. A minimum height above the content does not add
/// padding, it adds a gap: the row aligns its text to the top and the
/// difference piles up underneath it, which is what made every note look half
/// empty while the list scrolled at two thirds of the density it read as.
void main() {
  Future<String> pumpNotesList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    final id = controller.addNote(title: '季度评审 · 叙事结构');

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: NotesScreen(controller: controller)),
    ));
    await tester.pumpAndSettle();
    return id;
  }

  testWidgets('a note row is its content with no blank space under it',
      (tester) async {
    final id = await pumpNotesList(tester);
    final row = find.byKey(ValueKey('note-row-$id'));
    expect(row, findsOneWidget);

    // The title + preview stack, which the row aligns to its top. Measuring it
    // rather than asserting a number is the point: the contract is that the
    // row has no dead space, whatever the typography happens to be.
    final content =
        find.descendant(of: row, matching: find.byType(Column)).first;

    expect(
        tester.getRect(row).height,
        tester.getRect(content).height +
            NotesMetrics.rowVerticalPadding * 2,
        reason: 'a row taller than its content puts the difference under the '
            'text, which is the blank space a note was sitting above');
  });

  testWidgets('a note row holds four texts, so the height has a known basis',
      (tester) async {
    // What the height in the test above is the height *of*: title and preview
    // on the leading side, folder and timestamp on the trailing one. Adding a
    // line to a row means the floor has to be measured again, not assumed.
    final id = await pumpNotesList(tester);
    final row = find.byKey(ValueKey('note-row-$id'));

    expect(find.descendant(of: row, matching: find.byType(Text)),
        findsNWidgets(4),
        reason: 'a row was changed to hold something else, so its height is '
            'no longer the height that was measured');

    // The trailing column is shorter than the leading one, so it is the
    // title-and-preview stack that sets the row's height.
    final columns = find.descendant(of: row, matching: find.byType(Column));
    expect(tester.getRect(columns.first).height,
        greaterThanOrEqualTo(tester.getRect(columns.at(1)).height),
        reason: 'the trailing metadata column grew past the title and preview, '
            'so it is now what sizes the row');
  });
}
