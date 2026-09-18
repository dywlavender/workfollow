import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/document_keys.dart';
import 'package:workfollow_personal/features/editor/presentation/document_editor_footer.dart';
import 'package:workfollow_personal/features/editor/presentation/document_formatting_toggle.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  testWidgets('footer composes leading, status, and action slots',
      (tester) async {
    const leadingKey = ValueKey('footer-leading');
    const statusKey = ValueKey('footer-status');
    const actionKey = ValueKey('footer-action');

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: DocumentEditorFooter(
          leading: const SizedBox(key: leadingKey, width: 20),
          status: const SizedBox(key: statusKey, width: 20),
          actions: const [SizedBox(key: actionKey, width: 20)],
        ),
      ),
    ));

    expect(find.byKey(leadingKey), findsOneWidget);
    expect(find.byKey(statusKey), findsOneWidget);
    expect(find.byKey(actionKey), findsOneWidget);
  });

  testWidgets('formatting toggle keeps the shared key and anchor callback',
      (tester) async {
    BuildContext? callbackAnchor;

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: DocumentFormattingToggle(
          active: false,
          onPressed: (anchor) => callbackAnchor = anchor,
        ),
      ),
    ));

    expect(find.byKey(documentFormattingToggleKey), findsOneWidget);
    await tester.tap(find.byKey(documentFormattingToggleKey));
    expect(callbackAnchor, isNotNull);
  });
}
