import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../models/note_document.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';

class NoteDocumentEditor extends StatefulWidget {
  const NoteDocumentEditor(
      {super.key, required this.note, required this.controller});
  final NoteItem note;
  final WorkspaceController controller;
  @override
  State<NoteDocumentEditor> createState() => _NoteDocumentEditorState();
}

class _NoteDocumentEditorState extends State<NoteDocumentEditor> {
  late final quill.QuillController editor;
  final focus = FocusNode();
  final scroll = ScrollController();
  late String serialized;
  bool selectionPresent = false;

  @override
  void initState() {
    super.initState();
    editor = quill.QuillController(
        document: quill.Document.fromJson(noteDocumentDelta(widget.note)),
        selection: const TextSelection.collapsed(offset: 0),
        config: quill.QuillControllerConfig(
            clipboardConfig: quill.QuillClipboardConfig(
          onImagePaste: (bytes) async =>
              'data:image/png;base64,${base64Encode(bytes)}',
        )));
    serialized = jsonEncode(editor.document.toDelta().toJson());
    editor.addListener(_changed);
  }

  void _changed() {
    final selected = !editor.selection.isCollapsed;
    if (selected != selectionPresent && mounted)
      setState(() => selectionPresent = selected);
    final delta = editor.document.toDelta().toJson();
    final current = jsonEncode(delta);
    if (serialized == current) return;
    serialized = current;
    widget.controller.updateNoteRichContent(widget.note.id,
        noteContentFromDelta(delta), editor.document.toPlainText().trimRight());
  }

  @override
  void dispose() {
    editor.removeListener(_changed);
    editor.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final filename = await widget.controller.pickNoteAttachment();
    if (filename == null || !mounted) return;
    final node = {
      'type': 'attachment',
      'attrs': {'name': filename, 'localFile': filename}
    };
    final at = editor.selection.baseOffset.clamp(0, editor.document.length - 1);
    editor.replaceText(
        at,
        0,
        quill.BlockEmbed('workfollow-block', jsonEncode(node)),
        TextSelection.collapsed(offset: at + 1));
    focus.requestFocus();
  }

  void _taskFromSelection() {
    final text = editor.getPlainText().trim();
    if (text.isEmpty) return;
    final id = widget.controller.addTaskFromNote(widget.note.id, text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('已添加到收集箱'),
        action: SnackBarAction(
            label: '查看', onPressed: () => widget.controller.openTask(id))));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final textStyle = Theme.of(context)
        .textTheme
        .bodyLarge!
        .copyWith(fontSize: 15, height: 1.7, color: tokens.textPrimary);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: tokens.border),
                  bottom: BorderSide(color: tokens.border))),
          child: quill.QuillSimpleToolbar(
              controller: editor,
              config: quill.QuillSimpleToolbarConfig(
                multiRowsDisplay: false,
                toolbarSize: 34,
                color: tokens.content,
                showFontFamily: false,
                showFontSize: false,
                showUnderLineButton: false,
                showStrikeThrough: false,
                showInlineCode: false,
                showColorButton: false,
                showBackgroundColorButton: false,
                showClearFormat: false,
                showIndent: false,
                showUndo: false,
                showRedo: false,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
              ))),
      const SizedBox(height: 24),
      quill.QuillEditor(
          controller: editor,
          focusNode: focus,
          scrollController: scroll,
          key: const ValueKey('note-body-editor'),
          config: quill.QuillEditorConfig(
            scrollable: false,
            minHeight: 330,
            padding: const EdgeInsets.only(bottom: 24),
            placeholder: '写下你的想法、会议记录或下一步行动…',
            customStyles: quill.DefaultStyles(
              paragraph: quill.DefaultTextBlockStyle(
                  textStyle,
                  const quill.HorizontalSpacing(0, 0),
                  const quill.VerticalSpacing(0, 8),
                  const quill.VerticalSpacing(0, 0),
                  null),
              placeHolder: quill.DefaultTextBlockStyle(
                  textStyle.copyWith(color: tokens.textTertiary),
                  const quill.HorizontalSpacing(0, 0),
                  const quill.VerticalSpacing(0, 8),
                  const quill.VerticalSpacing(0, 0),
                  null),
            ),
            embedBuilders: [
              NoteBlockBuilder(controller: widget.controller),
              const NoteImageBuilder()
            ],
          )),
      Wrap(spacing: 12, children: [
        TextButton.icon(
            onPressed: _attach,
            icon: const Icon(Icons.attach_file, size: 16),
            label: const Text('添加附件', style: TextStyle(fontSize: 12))),
        TextButton.icon(
            key: const ValueKey('generate-task-from-selection'),
            onPressed: selectionPresent ? _taskFromSelection : null,
            icon: const Icon(Icons.playlist_add, size: 17),
            label: const Text('选中文字生成任务', style: TextStyle(fontSize: 12))),
      ]),
    ]);
  }
}

class NoteImageBuilder extends quill.EmbedBuilder {
  const NoteImageBuilder();
  @override
  String get key => 'image';
  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final source = embedContext.node.value.data.toString();
    Widget fallback(BuildContext _, Object error, StackTrace? stack) =>
        Container(
            padding: const EdgeInsets.all(18),
            color: WorkFollowTheme.of(context).canvas,
            child: const Row(children: [
              Icon(Icons.broken_image_outlined, size: 20),
              SizedBox(width: 8),
              Text('图片暂时无法显示')
            ]));
    final image = source.startsWith('http://') || source.startsWith('https://')
        ? Image.network(source, fit: BoxFit.contain, errorBuilder: fallback)
        : source.startsWith('data:')
            ? Image.memory(UriData.parse(source).contentAsBytes(),
                errorBuilder: fallback)
            : Image.file(
                File(source.startsWith('file:')
                    ? Uri.parse(source).toFilePath()
                    : source),
                fit: BoxFit.contain,
                errorBuilder: fallback);
    return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420), child: image);
  }
}

class NoteBlockBuilder extends quill.EmbedBuilder {
  const NoteBlockBuilder({required this.controller});
  final WorkspaceController controller;
  @override
  String get key => 'workfollow-block';
  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = jsonDecode(embedContext.node.value.data.toString()) as Map;
    final tokens = WorkFollowTheme.of(context);
    if (node['type'] == 'horizontalRule')
      return Divider(color: tokens.borderStrong, height: 24);
    if (node['type'] == 'attachment') {
      final attrs = node['attrs'] as Map;
      final filename = attrs['localFile']?.toString();
      return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
              icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
              label: Text(attrs['name']?.toString() ?? '附件'),
              onPressed: filename == null
                  ? null
                  : () => controller.revealWorkspaceAttachment(filename)));
    }
    if (node['type'] == 'table') {
      final rows = (node['content'] as List? ?? []).whereType<Map>().toList();
      final columns = rows.fold<int>(
          0,
          (max, row) => (row['content'] as List? ?? []).length > max
              ? (row['content'] as List).length
              : max);
      if (columns > 0)
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: columns * 170,
                child: Table(
                    border: TableBorder.all(color: tokens.border),
                    children: [
                      for (final row in rows)
                        TableRow(children: [
                          for (var i = 0; i < columns; i++)
                            Padding(
                                padding: const EdgeInsets.all(10),
                                child: SelectableText(
                                    i < (row['content'] as List).length
                                        ? notePlainTextFromContentJson(
                                                (row['content'] as List)[i])
                                            .trimRight()
                                        : '',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: tokens.textPrimary))),
                        ]),
                    ])));
    }
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: tokens.canvas,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(8)),
        child: SelectableText(
            notePlainTextFromContentJson(node).trim().isEmpty
                ? '导入的内容块'
                : notePlainTextFromContentJson(node).trim(),
            style: TextStyle(fontSize: 13, color: tokens.textSecondary)));
  }
}
