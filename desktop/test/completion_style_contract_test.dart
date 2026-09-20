import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Completion is a step back in ink, never a rule through the words.
///
/// The product carries one reading of "done" wherever it shows a task title —
/// the task rows, the calendar's bars and bands, the board's cards, and the
/// linked tasks beside a note all grey the title out and leave it legible. At
/// 12–14pt a strike costs more of the words than the colour already does, and
/// it says the same thing a second time.
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
}
