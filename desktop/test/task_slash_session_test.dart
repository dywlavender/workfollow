import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/state/workspace_controller.dart';
import 'package:workfollow_personal/theme/workfollow_theme.dart';
import 'package:workfollow_personal/widgets/task_document_editor.dart';

class _AttachmentController extends WorkspaceController {
  _AttachmentController() : super(seedData: false);

  @override
  Future<String?> pickTaskAttachment(String taskId) async => '资料.txt';
}

void main() {
  test('slash session records an exact offset for a prose insertion', () {
    final session = SlashCommandSession.fromInsertion(
      previousText: '文字\n',
      text: '文字/\n',
      selection: const TextSelection.collapsed(offset: 3),
    );

    expect(session, isNotNull);
    expect(session!.slashOffset, 2);
    expect(session.lineStart, 0);
  });

  test('slash session does not trigger when the caret moves into old text', () {
    final session = SlashCommandSession.fromInsertion(
      previousText: '文字/\n',
      text: '文字/\n',
      selection: const TextSelection.collapsed(offset: 3),
    );

    expect(session, isNull);
  });

  Future<TaskDocumentEditorState> mountEditor(
    WidgetTester tester,
    WorkspaceController controller, {
    required String taskId,
    Future<void> Function(BuildContext)? onTags,
  }) async {
    final key = GlobalKey<TaskDocumentEditorState>();
    await tester.pumpWidget(MaterialApp(
      theme: WorkFollowThemeData.light(),
      home: Scaffold(
        body: TaskDocumentEditor(
          key: key,
          task: controller.tasks.firstWhere((task) => task.id == taskId),
          controller: controller,
          onOpenTags: onTags,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  Future<TaskDocumentEditorState> freshEditor(
      WidgetTester tester, WorkspaceController controller,
      {Future<void> Function(BuildContext)? onTags}) async {
    controller.addTask('Slash 测试');
    return mountEditor(tester, controller,
        taskId: controller.tasks.single.id, onTags: onTags);
  }

  Future<void> typeSlash(
      WidgetTester tester, TaskDocumentEditorState state, String value) async {
    await tester.tap(find.byKey(const ValueKey('task-document-editor')));
    final slashOffset = value.lastIndexOf('/');
    final beforeSlash = value.substring(0, slashOffset);
    state.editor.replaceText(0, state.editor.document.length - 1, beforeSlash,
        TextSelection.collapsed(offset: beforeSlash.length));
    await tester.pump();
    state.editor.replaceText(beforeSlash.length, 0, '/',
        TextSelection.collapsed(offset: slashOffset + 1));
    await tester.pump();
  }

  Finder option(String name) => find.byKey(ValueKey('document-slash-option-$name'));

  testWidgets('SLASH-B01/B02/B03 opens after an empty line or prose slash',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);

    await typeSlash(tester, editor, '/');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);

    // A fresh editor state is used for each input shape so the trigger is a
    // new insertion, rather than a caret move inside an existing slash.
    final c2 = WorkspaceController(seedData: false);
    addTearDown(c2.dispose);
    final editor2 = await freshEditor(tester, c2);
    await typeSlash(tester, editor2, '文字/');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);

    final c3 = WorkspaceController(seedData: false);
    addTearDown(c3.dispose);
    final editor3 = await freshEditor(tester, c3);
    await typeSlash(tester, editor3, 'abc/');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);
  });

  testWidgets('SLASH-B04/B05 executes H1 at the recorded slash offset',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '文字/');
    await tester.tap(option('heading-1'));
    await tester.pump();

    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
    expect(editor.editor.document.toPlainText().trimRight(), '文字');
    expect(
        editor.editor.document.toDelta().toJson().any(
            (op) => op['attributes'] is Map && op['attributes']['header'] == 1),
        isTrue);
    expect(editor.focus.hasFocus, isTrue);
    expect(editor.editor.selection.extentOffset, 2);
  });

  testWidgets('SLASH-B06 applies checklist to a prose line', (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '检查/');
    await tester.tap(option('checklist'));
    await tester.pump();
    expect(editor.editor.document.toPlainText().trimRight(), '检查');
    expect(
        editor.editor.document.toDelta().toJson().any((op) =>
            op['attributes'] is Map && op['attributes']['list'] == 'unchecked'),
        isTrue);
  });

  testWidgets('slash block commands keep semantic Delta attributes only',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '彩色/');
    editor.editor.formatText(0, 2, quill.ColorAttribute('#ff0000'));
    await tester.tap(option('heading-1'));
    await tester.pump();

    final ops = editor.editor.document.toDelta().toJson();
    final textOp = ops.firstWhere((op) => op['insert'] == '彩色');
    final textAttributes = Map<String, dynamic>.from(
        (textOp['attributes'] as Map?) ?? const <String, dynamic>{});
    final lineOp = ops.firstWhere((op) {
      final attributes = op['attributes'];
      return attributes is Map && attributes['header'] == 1;
    });
    final lineAttributes =
        Map<String, dynamic>.from(lineOp['attributes'] as Map);

    expect(textAttributes['color'], '#ff0000');
    expect(textAttributes.containsKey('font'), isFalse);
    expect(textAttributes.containsKey('size'), isFalse);
    expect(lineAttributes.keys, contains('header'));
    expect(lineAttributes.containsKey('color'), isFalse);
    expect(lineAttributes.containsKey('font'), isFalse);
    expect(lineAttributes.containsKey('size'), isFalse);
  });

  testWidgets('SLASH-B07 inserts a block at the slash position',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '前缀/');
    await tester.tap(option('divider'));
    await tester.pump();

    final ops = editor.editor.document.toDelta().toJson();
    final textIndex = ops.indexWhere((op) => op['insert'] == '前缀');
    final blockIndex = ops.indexWhere((op) {
      final insert = op['insert'];
      return insert is Map && insert.containsKey('workfollow-block');
    });
    expect(textIndex, greaterThanOrEqualTo(0));
    expect(blockIndex, textIndex + 1);
    expect(editor.editor.document.toPlainText(), contains('前缀'));
  });

  testWidgets('SLASH-B07 attachment uses the recorded insertion position',
      (tester) async {
    final c = _AttachmentController();
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '前缀/');
    await tester.tap(option('attachment'));
    await tester.pump();

    final ops = editor.editor.document.toDelta().toJson();
    final textIndex = ops.indexWhere((op) => op['insert'] == '前缀');
    final blockIndex = ops.indexWhere((op) {
      final insert = op['insert'];
      return insert is Map && insert.containsKey('workfollow-block');
    });
    expect(textIndex, greaterThanOrEqualTo(0));
    expect(blockIndex, textIndex + 1);
    expect(ops[blockIndex]['insert']['workfollow-block'], contains('资料.txt'));
  });

  testWidgets('SLASH tag removes the slash before opening its picker',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    var opened = false;
    final editor = await freshEditor(tester, c, onTags: (_) async {
      opened = true;
    });
    await typeSlash(tester, editor, '任务/');
    await tester.tap(option('tag'));
    await tester.pump();
    expect(opened, isTrue);
    expect(editor.editor.document.toPlainText(), '任务\n');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
  });

  testWidgets('SLASH-B08/B09 menu clicks preserve and restore editor focus',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, 'abc/');
    expect(editor.focus.hasFocus, isTrue);
    await tester.tap(option('heading-2'));
    await tester.pump();
    expect(editor.focus.hasFocus, isTrue);
    expect(editor.editor.selection.isCollapsed, isTrue);
  });

  testWidgets('SLASH-B10/B11 Esc and deleting the slash close the session',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '/');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
    expect(editor.editor.document.toPlainText(), '/\n');

    editor.editor.replaceText(0, editor.editor.document.length - 1, '',
        const TextSelection.collapsed(offset: 0));
    await typeSlash(tester, editor, '/');
    editor.editor
        .replaceText(0, 1, '', const TextSelection.collapsed(offset: 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
  });

  testWidgets('SLASH-B12 ordinary text after slash ends the session',
      (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '/');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);
    editor.editor
        .replaceText(1, 0, 'a', const TextSelection.collapsed(offset: 2));
    await tester.pump();
    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
    expect(editor.editor.document.toPlainText(), '/a\n');
  });

  testWidgets('SLASH-B13 outside click closes the palette', (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    final editor = await freshEditor(tester, c);
    await typeSlash(tester, editor, '/');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);
    await tester.tapAt(const Offset(760, 560));
    await tester.pump();
    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
  });

  testWidgets('SLASH-B14 task switch removes a stale palette', (tester) async {
    final c = WorkspaceController(seedData: false);
    addTearDown(c.dispose);
    c.addTask('第一个');
    c.addTask('第二个');
    final key = GlobalKey<TaskDocumentEditorState>();
    Future<void> pumpTask(String id) async {
      await tester.pumpWidget(MaterialApp(
        theme: WorkFollowThemeData.light(),
        home: Scaffold(
          body: TaskDocumentEditor(
            key: key,
            task: c.tasks.firstWhere((task) => task.id == id),
            controller: c,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await pumpTask(c.tasks[0].id);
    final editor = key.currentState!;
    await typeSlash(tester, editor, '/');
    expect(find.byKey(const ValueKey('document-slash-menu')), findsOneWidget);
    await pumpTask(c.tasks[1].id);
    expect(find.byKey(const ValueKey('document-slash-menu')), findsNothing);
  });
}
