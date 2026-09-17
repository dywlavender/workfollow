import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D11 source guard. The existing dimension contracts check individual token
/// families; this test is the final gate that stops a new business widget from
/// bypassing those families with a local primitive.
void main() {
  test('business Dart sources stay behind the design-system token boundary',
      () {
    final violations = <String>[];
    final root = Directory('lib');
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path
          .replaceFirst('lib${Platform.pathSeparator}', '')
          .replaceAll(Platform.pathSeparator, '/');
      if (_isDeferred(relative)) continue;

      final tokenSource = relative.startsWith('theme/');
      for (final entry in entity.readAsStringSync().split('\n').indexed) {
        final lineNumber = entry.$1 + 1;
        // Comments describe the rule or a reference implementation and are not
        // source usage. Keeping the scan line-based makes failures actionable.
        final line = entry.$2.replaceFirst(RegExp(r'//.*$'), '').trim();
        if (line.isEmpty) continue;
        void reject(String rule) =>
            violations.add('$relative:$lineNumber [$rule] $line');

        if (!tokenSource && RegExp(r'\b(?:Icons|CupertinoIcons)\.')
            .hasMatch(line)) {
          reject('use WorkFollowIcons');
        }
        if (!tokenSource && RegExp(r'Color\s*\(\s*0x')
            .hasMatch(line)) {
          reject('use a semantic color token');
        }
        if (!tokenSource && RegExp(
                r'\bColors\.(?:red|redAccent|green|greenAccent|grey|gray|orange|blue|blueAccent|purple|pink|indigo|teal|yellow|amber|deepOrange|lightBlue|cyan|lime|brown|blueGrey)\b')
            .hasMatch(line)) {
          reject('use a semantic status token');
        }
        if (!tokenSource && RegExp(r'\bColors\.white\b').hasMatch(line)) {
          reject('use foregroundOn or a theme role');
        }
        if (!tokenSource &&
            RegExp(r'\bColors\.black\.withValues\(alpha:').hasMatch(line) &&
            relative != 'widgets/command_palette.dart' &&
            relative != 'widgets/settings_panel.dart') {
          reject('use an overlay semantic role');
        }
        if (!tokenSource && line.contains('WorkFollowTypography')) {
          reject('use WorkFollowMacTypography');
        }
        if (!tokenSource && line.contains('textTheme')) {
          reject('use a WorkFollowMacTypography role');
        }
        if (!tokenSource &&
            RegExp(r'''fontFamily\s*:\s*['"](?:Inter|Noto Sans SC)''')
                .hasMatch(line)) {
          reject('use the macOS system family');
        }
        if (!tokenSource && RegExp(
                r'fontSize\s*:\s*(?:const\s+)?(?:\d+(?:\.\d+)?|\.\d+)')
            .hasMatch(line)) {
          reject('use a typography role');
        }
        if (!tokenSource && RegExp(
                r'letterSpacing\s*:\s*-?(?:\d+(?:\.\d+)?|\.\d+)')
            .hasMatch(line)) {
          reject('use a tracking role');
        }
        if (!tokenSource &&
            relative != 'widgets/note_document_editor.dart' &&
            RegExp(r'\bheight\s*:\s*(?:const\s+)?(?:\d+(?:\.\d+)?|\.\d+)')
                .hasMatch(line)) {
          reject('use a line-height role or geometry metric');
        }
        if (!tokenSource && RegExp(r'FontWeight\.w\d+').hasMatch(line)) {
          reject('use WorkFollowMacWeight');
        }
        if (!tokenSource && RegExp(
                r'BorderRadius\.(?:circular|only)\(\s*(?:const\s+)?(?:\d+(?:\.\d+)?|\.\d+)')
            .hasMatch(line)) {
          reject('use a radius role');
        }
        if (!tokenSource && RegExp(
                r'(?:BoxShadow\(|elevation\s*:\s*(?:\d+(?:\.\d+)?|\.\d+))')
            .hasMatch(line)) {
          reject('use a surface shadow role');
        }
        if (!tokenSource && RegExp(
                r'Duration\(\s*(?:const\s+)?milliseconds\s*:\s*\d+')
            .hasMatch(line)) {
          reject('use a WorkFollowMotion role');
        }
        if (!tokenSource && RegExp(r'\bCurves\.[A-Za-z0-9_]+').hasMatch(line)) {
          reject('use a WorkFollowMotion curve');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'D11 design-system violations:\n${violations.join('\n')}',
    );
  });
}

/// These files are an explicit boundary for another in-flight task. They are
/// recorded in `docs/design-system/exceptions.md`; the allowlist names files,
/// rather than whole directories, so newly added business files still fail the
/// guard immediately.
bool _isDeferred(String relative) {
  const exact = {
    'screens/today_screen.dart',
    'screens/matrix_screen.dart',
    'widgets/quick_add.dart',
    'widgets/task_document_styles.dart',
    'widgets/task_inspector.dart',
    'widgets/task_row.dart',
    'widgets/task_schedule_options.dart',
    'widgets/task_schedule_panel.dart',
    'features/feedback/feedback_controller.dart',
    'features/feedback/feedback_event.dart',
    'features/feedback/feedback_host.dart',
    'features/feedback/feedback_scope.dart',
    'features/feedback/feedback_sound_service.dart',
    'features/feedback/feedback_toast.dart',
    'features/matrix/matrix_models.dart',
    'features/matrix/matrix_projection.dart',
    'features/tasks/domain/chinese_work_calendar.dart',
    'features/tasks/presentation/task_feedback_mapper.dart',
    'widgets/matrix/matrix_add_surface.dart',
    'widgets/matrix/matrix_board.dart',
    'widgets/matrix/matrix_group.dart',
    'widgets/matrix/matrix_quadrant.dart',
    'widgets/matrix/matrix_task_editor_popover.dart',
    'widgets/matrix/matrix_task_row.dart',
    'widgets/task_list/task_group_header.dart',
    'widgets/task_list/task_list_divider.dart',
    'widgets/task_list/task_list_header.dart',
    'widgets/task_list/task_list_row.dart',
    'widgets/task_list/task_list_row_transition.dart',
    'widgets/task_list/task_metadata_trail.dart',
  };
  return exact.contains(relative);
}
