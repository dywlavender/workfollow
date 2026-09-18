import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/presentation/document_editor.dart'
    show DocumentEditor;
import 'package:workfollow_personal/screens/notes_screen.dart';
import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/note_document_editor.dart';

/// The bare editor. Enough for whatever the document itself owns — the slash
/// palette and the selected-text task action.
Widget _surface(WorkspaceController controller) {
  final note = controller.notes.single;
  return MaterialApp(
    theme: WorkFollowThemeData.light(),
    home: Scaffold(
      body: NoteDocumentEditor(note: note, controller: controller),
    ),
  );
}

/// The whole note page.
///
/// The formatting trigger is page chrome — it rides the bottom status row
/// rather than trailing the prose — so the trigger and the toolbar only ever
/// coexist once the page is mounted. A test holding the bare editor cannot
/// reach the trigger at all, which is the point of the split.
Future<void> _pumpPage(
    WidgetTester tester, WorkspaceController controller) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  controller.selectView(WorkspaceView.notes);
  controller.openNote(controller.notes.single.id);
  await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(body: NotesScreen(controller: controller))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('note editor opens the shared toolbar as a floating popover',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addNote(title: '编辑笔记');

    await _pumpPage(tester, controller);

    expect(find.byKey(const ValueKey('note-body-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('document-format-toggle')), findsOneWidget);
    expect(find.byType(quill.QuillSimpleToolbar), findsNothing);
    expect(find.byKey(const ValueKey('document-editor-toolbar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('note-body-editor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-editor-toolbar')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('document-format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-editor-toolbar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-body-editor')));
    await tester.pumpAndSettle();
    // The note toolbar is persistent like the task toolbar: clicking back in
    // the document must not destroy the formatting surface or its selection.
    expect(find.byKey(const ValueKey('document-editor-toolbar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('document-format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-editor-toolbar')), findsNothing);
  });

  testWidgets('note slash menu only exposes note-safe document actions',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addNote(title: '斜杠笔记');

    await tester.pumpWidget(_surface(controller));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('note-body-editor')))
        .controller;
    await tester.tap(find.byKey(const ValueKey('note-body-editor')));
    editor.replaceText(0, editor.document.length - 1, '/',
        const TextSelection.collapsed(offset: 1));
    await tester.pump();

    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('document-slash-option-heading-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('document-slash-option-checklist')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('document-slash-option-attachment')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('document-slash-option-subtask')), findsNothing);
    expect(
        find.byKey(const ValueKey('document-slash-option-relation')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('document-slash-option-heading-1')));
    await tester.pump();
    final delta = editor.document.toDelta().toJson();
    expect(
        delta.any(
            (op) => op['attributes'] is Map && op['attributes']['header'] == 1),
        isTrue);
    expect(controller.notes.single.contentJson?['quillDelta'], isNotNull);
  });

  testWidgets('shared note toolbar formats text and inserts links',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addNote(title: '格式笔记');

    await _pumpPage(tester, controller);
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('note-body-editor')))
        .controller;
    editor.replaceText(0, editor.document.length - 1, '加粗文字',
        const TextSelection.collapsed(offset: 4));
    editor.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 4),
        quill.ChangeSource.local);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('document-format-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-editor-toolbar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('document-format-bold')));
    await tester.pump();
    expect(
        editor.document.toDelta().toJson().any((op) =>
            op['attributes'] is Map && op['attributes']['bold'] == true),
        isTrue);

    await tester.tap(find.byKey(const ValueKey('document-format-link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-link-input')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('document-link-input')), 'https://example.com');
    await tester.tap(find.byKey(const ValueKey('document-link-apply')));
    await tester.pumpAndSettle();
    expect(
        editor.document.toDelta().toJson().any((op) =>
            op['attributes'] is Map &&
            op['attributes']['link'] == 'https://example.com'),
        isTrue);
  });

  testWidgets('note document blocks and selected text task creation persist',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addNote(title: '行动笔记');

    await tester.pumpWidget(_surface(controller));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('note-body-editor')))
        .controller;
    editor.replaceText(
      0,
      editor.document.length - 1,
      quill.BlockEmbed(
          'workfollow-block',
          jsonEncode({
            'type': 'attachment',
            'attrs': {'name': '设计稿.pdf', 'localFile': '设计稿.pdf'},
          })),
      const TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    expect(
        find.byKey(const ValueKey('note-attachment-设计稿.pdf')), findsOneWidget);
    expect(controller.notes.single.contentJson?['quillDelta'], isNotNull);

    editor.replaceText(0, editor.document.length - 1, '整理会议纪要',
        const TextSelection.collapsed(offset: 6));
    editor.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 6),
        quill.ChangeSource.local);
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('generate-task-from-selection')));
    await tester.pump();
    expect(controller.tasks.single.title, '整理会议纪要');
    expect(controller.tasks.single.sourceNoteId, controller.notes.single.id);
  });

  testWidgets(
      'related tasks follow the prose and the blank page focuses the document',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addNote(title: '行动笔记');
    final note = controller.notes.single;
    controller.addTaskFromNote(note.id, '测试');

    await _pumpPage(tester, controller);

    final page =
        tester.getRect(find.byKey(const ValueKey('web-note-editor-pane')));
    final editor = tester.widget<quill.QuillEditor>(
        find.byKey(const ValueKey('note-body-editor')));
    final doc = tester.getRect(find.byKey(const ValueKey('note-body-editor')));
    final linked = tester.getRect(
        find.byKey(ValueKey('note-linked-task-${controller.tasks.single.id}')));

    // The document's canvas is its content, not the pane it happens to sit in.
    // Reserving the pane here is what put "关联任务" — and the formatting
    // trigger that used to trail the prose — in the middle of a one-line note.
    expect(doc.height, NotesMetrics.editorContentMinHeight);

    // The list follows the prose: it starts one section rhythm under the last
    // line rather than wherever an empty document happened to end.
    expect(linked.top - doc.bottom, lessThan(NotesMetrics.editorContentMinHeight));

    // Everything below the prose is blank page, and it is still a way into the
    // document. This is the mechanism that lets the canvas stay content-height.
    expect(linked.bottom, lessThan(page.bottom - 300));
    expect(editor.focusNode.hasFocus, isFalse);
    await tester.tapAt(Offset(linked.center.dx, linked.bottom + 200));
    await tester.pump();
    expect(editor.focusNode.hasFocus, isTrue);
  });

  testWidgets('creating a task from a selection is a selection action',
      (tester) async {
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addNote(title: '行动笔记');

    await tester.pumpWidget(_surface(controller));
    await tester.pumpAndSettle();
    // With nothing highlighted there is no action to take, so the page does not
    // spend a row of the prose on a button that cannot do anything.
    expect(
        find.byKey(const ValueKey('generate-task-from-selection')), findsNothing);

    final editor = tester
        .widget<quill.QuillEditor>(
            find.byKey(const ValueKey('note-body-editor')))
        .controller;
    editor.replaceText(0, editor.document.length - 1, '测试',
        const TextSelection.collapsed(offset: 2));
    editor.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 2),
        quill.ChangeSource.local);
    await tester.pump();
    expect(
        find.byKey(const ValueKey('generate-task-from-selection')), findsOneWidget);

    // Leaving the selection takes the action away with it.
    editor.updateSelection(const TextSelection.collapsed(offset: 2),
        quill.ChangeSource.local);
    await tester.pump();
    expect(
        find.byKey(const ValueKey('generate-task-from-selection')), findsNothing);
  });

  testWidgets('a note canvas refuses the height its host offers it',
      (tester) async {
    // The task inspector hands its editor the height of the pane, because there
    // the pane *is* the canvas — see `DocumentEditorViewport`. A note refuses
    // the same offer: the page under the prose owns that space, and a document
    // that grew to fill it would push the related-task list down the page with
    // it. This is the one place the two document types disagree about layout,
    // so it is stated in the profile rather than inferred from the host.
    final controller = WorkspaceController(seedData: false);
    addTearDown(controller.dispose);
    controller.addNote(title: '行动笔记');

    await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
            body: SizedBox(
                height: 800,
                child: DocumentEditor(
                    profile: NoteEditorProfile(
                        note: controller.notes.single,
                        controller: controller))))));
    await tester.pumpAndSettle();

    expect(
        tester.getRect(find.byKey(const ValueKey('note-body-editor'))).height,
        NotesMetrics.editorContentMinHeight);
  });
}
