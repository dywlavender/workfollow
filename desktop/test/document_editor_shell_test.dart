import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/presentation/document_editor_shell.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

void main() {
  testWidgets('shell keeps header, body and footer as independent slots',
      (tester) async {
    const headerKey = ValueKey('shell-header');
    const bodyKey = ValueKey('shell-body');
    const footerKey = ValueKey('shell-footer');

    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: DocumentEditorShell(
          backgroundColor: Colors.amber,
          header: const SizedBox(key: headerKey, height: 20),
          body: const SizedBox(key: bodyKey, height: 40),
          footer: const SizedBox(key: footerKey, height: 20),
        ),
      ),
    ));

    expect(find.byKey(headerKey), findsOneWidget);
    expect(find.byKey(bodyKey), findsOneWidget);
    expect(find.byKey(footerKey), findsOneWidget);

    final shell = tester.widget<DocumentEditorShell>(
        find.byType(DocumentEditorShell));
    expect(shell.backgroundColor, Colors.amber);
    expect(shell.mainAxisSize, MainAxisSize.max);
  });
}
