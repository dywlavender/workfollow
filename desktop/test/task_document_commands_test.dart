import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';

import 'package:workfollow_personal/widgets/task_document_commands.dart';

void main() {
  test('heading commands share semantic Delta attributes with slash callers',
      () {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(0, controller.document.length - 1, '彩色',
        const TextSelection.collapsed(offset: 2));
    controller.formatText(0, 2, const quill.ColorAttribute('#ff0000'));
    final commands = TaskDocumentCommands(editor: controller);

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
    final commands = TaskDocumentCommands(editor: controller);

    commands.toggleBold();
    commands.toggleHighlight();
    expect(controller.getSelectionStyle().attributes['bold']?.value, isTrue);
    expect(controller.getSelectionStyle().attributes['background']?.value,
        TaskDocumentCommands.highlightColor);

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
    final commands = TaskDocumentCommands(editor: controller);

    commands.insertDivider(at: 2);
    commands.insertSubtaskBlock(at: 3);
    commands.insertRelation('note-1', at: 4);

    final inserts = controller.document
        .toDelta()
        .toJson()
        .where((op) => op['insert'] is Map)
        .map((op) => (op['insert'] as Map)['workfollow-block'].toString())
        .toList();
    expect(inserts, hasLength(3));
    expect(inserts[0], contains('horizontalRule'));
    expect(inserts[1], contains('taskSubtasks'));
    expect(inserts[2], contains('note-1'));
  });

  test('link insertion is applied by the command service', () {
    final controller = quill.QuillController.basic();
    addTearDown(controller.dispose);
    controller.replaceText(0, controller.document.length - 1, '链接',
        const TextSelection.collapsed(offset: 2));
    controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 2),
        quill.ChangeSource.local);
    final commands = TaskDocumentCommands(editor: controller);

    expect(commands.applyLink('https://example.com'), isTrue);
    expect(controller.getSelectionStyle().attributes['link']?.value,
        'https://example.com');
  });
}
