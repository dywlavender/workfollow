import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/features/editor/document_commands.dart';

/// Three lines, so a command that marks the line below shows up.
quill.Document threeLines() => quill.Document.fromJson([
      {'insert': '第一行'},
      {'insert': '\n'},
      {'insert': '第二行'},
      {'insert': '\n'},
      {'insert': '第三行'},
      {'insert': '\n'},
    ]);

/// The index of every line carrying a checklist marker, in document order.
///
/// Counting *which* lines took the attribute is the point: the marker is
/// resolved onto newlines, so a line command that spills over leaves a second,
/// empty box one line below the one the reader asked for. An index rather than
/// the line's text, because the line that went wrong is usually an empty one.
List<int> checklistLineIndexes(quill.Document doc) {
  final plain = doc.toPlainText();
  final marked = <int>[];
  var offset = 0;
  for (final op in doc.toDelta().toJson() as List) {
    final insert = op['insert'];
    if (insert is! String) {
      offset += 1;
      continue;
    }
    final attributes = op['attributes'];
    for (var i = 0; i < insert.length; i++) {
      if (insert[i] == '\n' &&
          attributes is Map &&
          attributes['list'] != null) {
        var line = 0;
        for (var at = 0; at < offset + i && at < plain.length; at++) {
          if (plain[at] == '\n') line++;
        }
        marked.add(line);
      }
    }
    offset += insert.length;
  }
  return marked;
}

void main() {
  test('a line command marks its own line and not the one below it', () {
    // The slash menu hands the command the line it captured, and the range has
    // to stop at that line's own newline. Quill resolves a block attribute onto
    // every newline inside the range and then onto the first newline beyond it,
    // so a range that ended past the newline marked the line below too — one
    // 检查项 drew two boxes, one under the other.
    for (final line in const [0, 1, 2]) {
      final controller = quill.QuillController(
          document: threeLines(),
          selection: TextSelection.collapsed(offset: line * 4));
      addTearDown(controller.dispose);

      DocumentCommands(editor: controller).toggleChecklist(lineStart: line * 4);

      expect(checklistLineIndexes(controller.document), [line],
          reason: 'line $line marked itself and no other line');
      expect(controller.document.toPlainText(), '第一行\n第二行\n第三行\n',
          reason: 'marking a line never rewrites the text around it');
    }
  });

  test('a line command marks an empty line as itself', () {
    // An empty line sits on its own newline, so the range is empty and the
    // trailing pass is the only thing that can mark it — and the line below it
    // must stay plain.
    final controller = quill.QuillController(
        document: quill.Document.fromJson([
          {'insert': '第一行'},
          {'insert': '\n'},
          {'insert': '\n'},
          {'insert': '第三行'},
          {'insert': '\n'},
        ]),
        selection: const TextSelection.collapsed(offset: 4));
    addTearDown(controller.dispose);

    DocumentCommands(editor: controller).toggleChecklist(lineStart: 4);

    expect(checklistLineIndexes(controller.document), [1],
        reason: 'the empty line is marked, the text line under it is not');
    expect(controller.document.toPlainText(), '第一行\n\n第三行\n');
  });

  test('the toolbar path still marks one line from the caret', () {
    final controller = quill.QuillController(
        document: threeLines(),
        selection: const TextSelection.collapsed(offset: 4));
    addTearDown(controller.dispose);

    DocumentCommands(editor: controller).toggleChecklist();

    expect(checklistLineIndexes(controller.document), [1]);
  });

  test('heading commands share semantic Delta attributes with slash callers',
      () {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(0, controller.document.length - 1, '彩色',
        const TextSelection.collapsed(offset: 2));
    controller.formatText(0, 2, const quill.ColorAttribute('#ff0000'));
    final commands = DocumentCommands(editor: controller);

    commands.setHeading1(lineStart: 0);

    final ops = controller.document.toDelta().toJson();
    final text = ops.firstWhere((op) => op['insert'] == '彩色');
    final textAttributes =
        Map<String, dynamic>.from((text['attributes'] as Map?) ?? const {});
    final line = ops.firstWhere(
        (op) => op['attributes'] is Map && op['attributes']['header'] == 1);

    expect(textAttributes['color'], '#ff0000');
    expect(textAttributes.containsKey('font'), isFalse);
    expect(textAttributes.containsKey('size'), isFalse);
    expect((line['attributes'] as Map).keys, contains('header'));
  });

  test('format commands toggle inline and block attributes from one service',
      () {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(0, controller.document.length - 1, '文本',
        const TextSelection.collapsed(offset: 2));
    controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
        quill.ChangeSource.local);
    final commands = DocumentCommands(editor: controller);

    commands.toggleBold();
    commands.toggleHighlight();
    expect(controller.getSelectionStyle().attributes['bold']?.value, isTrue);
    expect(controller.getSelectionStyle().attributes['background']?.value,
        DocumentCommands.highlightColor);

    controller.updateSelection(
        const TextSelection.collapsed(offset: 1), quill.ChangeSource.local);
    commands.toggleChecklist(lineStart: 0);
    expect(
        controller.document.toDelta().toJson().any((op) =>
            op['attributes'] is Map && op['attributes']['list'] == 'unchecked'),
        isTrue);
  });

  test('block insertion commands preserve order and use WorkFollow embeds', () {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(0, controller.document.length - 1, '前缀',
        const TextSelection.collapsed(offset: 2));
    final commands = DocumentCommands(editor: controller);

    commands.insertDivider(at: 2);
    commands.insertRelation('note-1', at: 3);

    final inserts = controller.document
        .toDelta()
        .toJson()
        .where((op) => op['insert'] is Map)
        .map((op) => (op['insert'] as Map)['workfollow-block'].toString())
        .toList();
    expect(inserts, hasLength(2));
    expect(inserts[0], contains('horizontalRule'));
    expect(inserts[1], contains('note-1'));
  });

  test('link insertion is applied by the command service', () {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(0, controller.document.length - 1, '链接',
        const TextSelection.collapsed(offset: 2));
    controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
        quill.ChangeSource.local);
    final commands = DocumentCommands(editor: controller);

    expect(commands.applyLink('https://example.com'), isTrue);
    expect(controller.getSelectionStyle().attributes['link']?.value,
        'https://example.com');
  });
}
