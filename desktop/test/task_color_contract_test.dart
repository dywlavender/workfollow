import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:workfollow_personal/theme/workfollow_color_tokens.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/features/editor/document_styles.dart';

void main() {
  test('business widgets consume semantic colors instead of local hex values',
      () {
    final rawHex = <String>[];
    final directSemanticColors = <String>[];
    final allowedTokenFiles = {
      'theme/workfollow_theme.dart',
      'theme/workfollow_color_tokens.dart',
      'theme/workfollow_theme_parity.dart',
    };
    final forbidden = RegExp(
        r'\bColors\.(red|redAccent|green|greenAccent|grey|gray|orange|blue|blueAccent|purple|pink|indigo|teal|yellow|amber|deepOrange|lightBlue|cyan|lime|brown|blueGrey)\b');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path
          .replaceFirst('lib${Platform.pathSeparator}', '')
          .replaceAll(Platform.pathSeparator, '/');
      if (allowedTokenFiles.contains(relative)) continue;
      for (final line in entity.readAsStringSync().split('\n')) {
        if (RegExp(r'Color\s*\(\s*0x').hasMatch(line)) {
          rawHex.add('$relative: $line');
        }
        if (forbidden.hasMatch(line)) {
          directSemanticColors.add('$relative: $line');
        }
      }
    }

    expect(rawHex, isEmpty);
    expect(directSemanticColors, isEmpty);
  });

  test('D3 component palettes resolve through the shared theme', () {
    final tokens = WorkFollowTheme.light;
    expect(WorkFollowColorTokens.quickAddDate(tokens), tokens.accent);
    expect(WorkFollowColorTokens.quickAddTime(tokens), tokens.accentHover);
    expect(WorkFollowColorTokens.quickAddPriority(tokens), tokens.danger);
    expect(WorkFollowColorTokens.documentHighlightBackground(tokens),
        tokens.accentSoft);
    expect(WorkFollowColorTokens.documentHighlightForeground(tokens),
        tokens.textPrimary);
    final highlight = DocumentStyles.customStyleBuilder(tokens)(
      const quill.BackgroundAttribute('#d4ff00'),
    );
    expect(highlight.backgroundColor, tokens.accentSoft);
  });
}
