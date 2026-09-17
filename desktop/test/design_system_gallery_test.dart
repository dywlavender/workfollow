import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/theme/design_system_gallery.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  testWidgets('gallery exposes the shared component states in both themes',
      (tester) async {
    for (final theme in [
      WorkFollowThemeData.light(),
      WorkFollowThemeData.dark(),
    ]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const WorkFollowDesignSystemGallery(),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('design-gallery-title')), findsOneWidget);
      for (final section in [
        'typography',
        'colors',
        'icons',
        'controls',
        'task-row',
        'overlays',
        'feedback',
      ]) {
        expect(
          find.byKey(ValueKey('design-gallery-section-$section')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });
}
