import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workfollow_personal/theme/workfollow_icons.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  test('desktop icon consumers use the semantic icon vocabulary', () {
    final directMaterialIcons = <String>[];
    final directCupertinoIcons = <String>[];
    final literalIconSizes = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceFirst(
          'lib${Platform.pathSeparator}', '');
      if (relative == 'theme/workfollow_icons.dart') continue;
      for (final line in entity.readAsStringSync().split('\n')) {
        if (RegExp(r'\bIcons\.[A-Za-z0-9_]+').hasMatch(line)) {
          directMaterialIcons.add('$relative: $line');
        }
        if (RegExp(r'\bCupertinoIcons\.[A-Za-z0-9_]+').hasMatch(line)) {
          directCupertinoIcons.add('$relative: $line');
        }
        if (RegExp(r'\biconSize\s*:\s*(?:\d+(?:\.\d+)?|\.\d+)')
            .hasMatch(line)) {
          literalIconSizes.add('$relative: $line');
        }
      }
    }

    expect(directMaterialIcons, isEmpty);
    expect(directCupertinoIcons, isEmpty);
    expect(literalIconSizes, isEmpty);
  });

  test('task menu actions resolve to one semantic icon source', () {
    expect(WorkFollowIcons.taskAction('add-subtask'),
        WorkFollowIcons.subtask);
    expect(WorkFollowIcons.taskAction('attachment'),
        WorkFollowIcons.attachment);
    expect(WorkFollowIcons.taskAction('abandon'), WorkFollowIcons.abandon);
    expect(WorkFollowIcons.taskAction('abandon', restored: true),
        WorkFollowIcons.restore);
    expect(WorkFollowIcons.taskAction('delete'), WorkFollowIcons.delete);
    expect(WorkFollowIcons.taskAction('deadline'), WorkFollowIcons.deadline);
  });

  test('icon roles remain tied to the shared desktop metrics', () {
    expect(WorkFollowMetrics.railIcon, 22);
    expect(WorkFollowMetrics.navigationIcon, 20);
    expect(WorkFollowMetrics.headerIcon, 20);
    expect(WorkFollowMetrics.toolbarIcon, 18);
    expect(WorkFollowMetrics.fieldIcon, 20);
    expect(WorkFollowMetrics.compactFieldIcon, 17);
    expect(WorkFollowMetrics.metadataIcon, 15);
  });
}
