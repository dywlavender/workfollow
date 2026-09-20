import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/theme/workfollow_theme_parity.dart';
import 'package:workfollow_personal/widgets/task_row.dart';

/// Completion is a step back in ink, never a rule through the words.
///
/// The product carries one reading of "done" wherever it shows a task title
/// inside a list — the task rows, the calendar's bars and bands, the board's
/// cards, and the linked tasks beside a note all grey the title out and leave
/// it legible. At 12–14pt a strike costs more of the words than the colour
/// already does, and it says the same thing a second time.
///
/// The editor is not on that list. A task list is a column of rows and reads
/// better when its settled items recede; the inspector shows one task as
/// itself, so a finished task's title and date keep the ink they had before
/// the box was ticked. That half of the rule is a widget assertion —
/// `task_inspector_layout_test.dart`, "a finished task keeps its title and
/// date at full ink" — because it is about the ink a built field resolves to
/// rather than about where a decoration may appear.
///
/// A line through the text is a different statement, and the two places that
/// make it are not task titles in a task surface:
///
///  * `document_styles` styles the checklist lines
///    *inside a document*, where a strike through a ticked line is the
///    convention the editor is imitating;
///  * the trash strikes every title unconditionally, because there the line
///    means "deleted" rather than "done".
///
/// This is a source scan rather than a widget test on purpose. The surfaces
/// that must not strike a title are private widgets inside four different
/// screens, and mounting each of them to read one `TextStyle` would be a lot of
/// harness for a rule that is really about where the decoration is allowed to
/// appear at all.
///
/// *How much* a finished row steps back is a different question and is answered
/// the other way round: the product now has one row widget, so the ink a
/// finished task actually wears is read off a mounted [TaskRow] at the bottom of
/// this file rather than inferred from the palette above it.
void main() {
  const allowed = <String>[
    'lib/features/editor/document_styles.dart',
    'lib/screens/trash_screen.dart',
  ];

  test('a completed task is greyed out and never struck through', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (allowed.contains(entity.path)) continue;
      if (entity.readAsStringSync().contains('TextDecoration.lineThrough')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'a finished task title keeps its words and steps back to '
            'textTertiary; a new surface that genuinely needs a rule through '
            'the text has to argue for it above rather than widen this list');
  });

  test('every surface on the exception list still strikes something', () {
    // Otherwise the exception above outlives the reason it was written for, and
    // the next reader has to re-derive whether it is still true.
    for (final path in allowed) {
      expect(File(path).readAsStringSync(),
          contains('TextDecoration.lineThrough'),
          reason: '$path no longer strikes anything — drop it from the list');
    }
  });

  test('no title field can ask for a rule through the words', () {
    // The scan above looks for the decoration itself, and the decoration lives
    // in the document stylesheet — which is on the exception list because it
    // strikes a ticked checklist line. So a title field could reach the very
    // same decoration through a boolean flag and the scan would still pass.
    //
    // That is not hypothetical. The inspector passed
    // `strikethrough: task.completed`, so a finished task's own title wore a
    // line through it while every row, card and bar in the product greyed out —
    // and this file happily reported none. The flag is gone; this keeps it from
    // coming back, and it is written against the word rather than the
    // decoration for exactly that reason.
    for (final path in const [
      'lib/features/editor/document_styles.dart',
      'lib/features/editor/presentation/document_title_editor.dart',
      'lib/widgets/task_inspector.dart',
    ]) {
      expect(File(path).readAsStringSync().toLowerCase(),
          isNot(contains('strikethrough')),
          reason: '$path is on the title pipeline, so it can hand a task title '
              'a rule through the words');
    }
  });

  test('a finished list row reads as a ladder rather than as one grey', () {
    // Every piece of a closed row used to take `textTertiary` — title, preview,
    // list name, date, the little state icons — so the row had no internal
    // order and the only way to lighten it was to lighten `textTertiary`, which
    // navigation, breadcrumbs, placeholders and menu hints all share. The
    // finished row has its own four rungs now.
    //
    // The rows are asserted in contrast against the surface rather than as
    // literals, so the rule survives a palette move and reads the same way in
    // both themes: light ink on a light surface and dim ink on a dark one are
    // the same statement about which line matters most.
    for (final tokens in [WorkFollowTheme.light, WorkFollowTheme.dark]) {
      final ladder = <String, double>{
        'title': WorkFollowThemeContrast.ratio(
            tokens.taskCompletedTitle, tokens.content),
        'body': WorkFollowThemeContrast.ratio(
            tokens.taskCompletedBody, tokens.content),
        'meta': WorkFollowThemeContrast.ratio(
            tokens.taskCompletedMeta, tokens.content),
        'checkbox': WorkFollowThemeContrast.ratio(
            tokens.taskCompletedCheckbox, tokens.content),
      };
      expect(ladder['title'], greaterThan(ladder['body']!),
          reason: 'the title is the darkest thing left on a finished row');
      expect(ladder['body'], greaterThan(ladder['meta']!),
          reason: 'the preview steps down from the title');
      expect(ladder['meta'], greaterThan(ladder['checkbox']!),
          reason: 'the trailing column is the faintest, and the box is the '
              'palest chip on the row');
      expect(
          ladder['title'],
          lessThan(WorkFollowThemeContrast.ratio(
              tokens.textTertiary, tokens.content)),
          reason: 'the whole ladder sits past tertiary, which the product '
              'still needs for navigation and placeholders');

      // Every rung is still *there*: a row that fades into its own background
      // has stopped being a row.
      for (final entry in ladder.entries) {
        expect(entry.value, greaterThan(1.3),
            reason: '${entry.key} is no longer visible on the surface');
      }
    }
  });

  testWidgets('a finished row wears that ladder in the list', (tester) async {
    // The palette is only a promise until a row collects on it. One row widget
    // draws every task list in the product now, so reading the ink back off a
    // real row costs one mount — and it is the assertion that fails when a row
    // quietly keeps reaching for `textTertiary` while the tokens are correct.
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addTask('完成的行', dueAt: DateTime(2030, 9, 18));
    final id = controller.tasks.single.id;
    controller.updateTaskDescription(id, '正文预览');
    controller.taskActions.complete(id);

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: ListenableBuilder(
                listenable: controller,
                builder: (_, __) => TaskRow(
                    task: controller.tasks.single,
                    controller: controller,
                    selected: false)))));
    await tester.pumpAndSettle();

    const tokens = WorkFollowTheme.light;
    expect(tester.widget<Text>(find.text('完成的行')).style?.color,
        tokens.taskCompletedTitle,
        reason: 'the title is the row\'s head, not another grey line');
    expect(
        tester
            .widget<Text>(find.byKey(ValueKey('task-row-preview-$id')))
            .style
            ?.color,
        tokens.taskCompletedBody,
        reason: 'the preview steps down from the title');
    expect(
        tester
            .widget<Text>(find.byKey(ValueKey('task-row-date-$id')))
            .style
            ?.color,
        tokens.taskCompletedMeta,
        reason: 'the date is trailing metadata, and a finished task is not '
            'overdue — it is done');
  });
}
