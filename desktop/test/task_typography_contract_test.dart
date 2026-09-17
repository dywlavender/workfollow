import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop typography consumers use semantic macOS roles', () {
    final lib = Directory('lib');
    final rawFontSizes = <String>[];
    final rawTracking = <String>[];
    final materialTextThemes = <String>[];
    final webTypographyConsumers = <String>[];

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceFirst('lib${Platform.pathSeparator}', '');
      final source = entity.readAsStringSync();
      if (relative == 'theme/workfollow_theme.dart') continue;
      for (final line in source.split('\n')) {
        if (RegExp(r'fontSize\s*:\s*(?:const\s+)?(?:\d+(?:\.\d+)?|\.\d+)')
            .hasMatch(line)) {
          rawFontSizes.add('$relative: $line');
        }
        if (RegExp(r'letterSpacing\s*:\s*-?(?:\d+(?:\.\d+)?|\.\d+)')
            .hasMatch(line)) {
          rawTracking.add('$relative: $line');
        }
        if (line.contains('textTheme')) {
          materialTextThemes.add('$relative: $line');
        }
        if (line.contains('WorkFollowTypography')) {
          webTypographyConsumers.add('$relative: $line');
        }
      }
    }

    expect(rawFontSizes, isEmpty);
    expect(rawTracking, isEmpty);
    expect(materialTextThemes, isEmpty);
    expect(webTypographyConsumers, isEmpty);

    final documentStyles =
        File('lib/widgets/task_document_styles.dart').readAsStringSync();
    expect(documentStyles, contains('fontFamily: WorkFollowMacTypeFamily.ui'));
    expect(documentStyles,
        contains('fontFamilyFallback: WorkFollowMacTypeFamily.fallback'));
  });
}
