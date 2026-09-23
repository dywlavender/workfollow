import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/document_slash_menu.dart';
import 'package:workfollow_personal/features/editor/domain/document_selection_action.dart';
import 'package:workfollow_personal/features/editor/domain/editor_capability.dart';
import 'package:workfollow_personal/features/editor/domain/editor_profile.dart';
import 'package:workfollow_personal/features/editor/presentation/document_editor.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';

class _CustomCommandProfile extends EditorProfile {
  bool invoked = false;

  @override
  String get documentId => 'custom-command-document';

  @override
  Object get documentHost => this;

  @override
  Set<EditorCapability> get capabilities =>
      const {EditorCapability.slashPalette};

  @override
  List<dynamic> get ownedDelta => const [
        <String, dynamic>{'insert': '\n'}
      ];

  @override
  void persist(List<dynamic> delta, String plainText) {}

  @override
  String get placeholder => '正文';

  @override
  TextCapitalization get textCapitalization => TextCapitalization.none;

  @override
  double get documentMinHeight => 240;

  @override
  bool get expandsToViewport => false;

  @override
  double get documentBottomPadding => 0;

  @override
  double get paragraphGap => 0;

  @override
  List<DocumentSlashCommand> get slashCommands => [
        DocumentSlashCommand(
          id: 'custom-command',
          label: '自定义命令',
          group: DocumentSlashGroup.insert,
          onInvoke: (_) => invoked = true,
        ),
      ];

  @override
  List<quill.EmbedBuilder> buildEmbeds(BuildContext context) => const [];

  @override
  List<Widget> buildTrailingPanels(BuildContext context) => const [];

  @override
  List<DocumentSelectionAction> get selectionActions => const [];

  @override
  Future<String?> pickAttachment() async => null;

  @override
  Key get bodyKey => const ValueKey('custom-command-editor');

  @override
  Key get surfaceKey => const ValueKey('custom-command-surface');
}

void main() {
  testWidgets('the editor executes an unknown profile command generically',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = _CustomCommandProfile();
    final editorKey = GlobalKey<DocumentEditorState>();
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: DocumentEditor(key: editorKey, profile: profile),
      ),
    ));
    await tester.pumpAndSettle();

    final editor = editorKey.currentState!;
    await tester.tap(find.byKey(profile.bodyKey));
    editor.editor.replaceText(
      0,
      editor.editor.document.length - 1,
      '/',
      const TextSelection.collapsed(offset: 1),
    );
    await tester.pumpAndSettle();

    final option =
        find.byKey(const ValueKey('document-slash-option-custom-command'));
    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);
    expect(option, findsOneWidget);

    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(profile.invoked, isTrue);
    expect(editor.editor.document.toPlainText(), '\n');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
    expect(editor.focus.hasFocus, isTrue);
  });
}
