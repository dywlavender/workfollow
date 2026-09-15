import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../models/note_document.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'task_editor_toolbar.dart';
import 'desktop_popover.dart';
import 'task_slash_menu.dart';

const _noteSlashActions = <TaskSlashAction>[
  TaskSlashAction.heading1,
  TaskSlashAction.heading2,
  TaskSlashAction.heading3,
  TaskSlashAction.bullet,
  TaskSlashAction.ordered,
  TaskSlashAction.checklist,
  TaskSlashAction.quote,
  TaskSlashAction.divider,
  TaskSlashAction.attachment,
];

class NoteDocumentEditor extends StatefulWidget {
  const NoteDocumentEditor(
      {super.key, required this.note, required this.controller});
  final NoteItem note;
  final WorkspaceController controller;
  @override
  State<NoteDocumentEditor> createState() => _NoteDocumentEditorState();
}

class _NoteDocumentEditorState extends State<NoteDocumentEditor>
    with WidgetsBindingObserver {
  late final quill.QuillController editor;
  final focus = FocusNode();
  final scroll = ScrollController();
  final renderEditorKey = GlobalKey<quill.EditorState>();
  OverlayEntry? slashOverlay;
  Offset slashOffset = Offset.zero;
  late String serialized;
  bool selectionPresent = false;
  bool slashVisible = false;
  bool toolbarVisible = false;
  ScrollPosition? _ancestorScrollPosition;

  String get plainText => editor.document.toPlainText().trimRight();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    focus.addListener(_focusChanged);
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

  void _focusChanged() {
    if (!mounted) return;
    setState(() {
      if (!focus.hasFocus) slashVisible = false;
    });
    _syncSlashOverlay();
  }

  void _changed() {
    final selected = !editor.selection.isCollapsed;
    final text = editor.document.toPlainText();
    final caret = editor.selection.baseOffset.clamp(0, text.length).toInt();
    final beforeCaret = text.substring(0, caret);
    final lineStart = beforeCaret.lastIndexOf('\n') + 1;
    final line = beforeCaret.substring(lineStart);
    final nextSlashVisible = focus.hasFocus &&
        (line.trim() == '/' ||
            (line.trimLeft().startsWith('/') && !line.contains('\n')));
    if (mounted &&
        (selected != selectionPresent || nextSlashVisible != slashVisible)) {
      setState(() {
        selectionPresent = selected;
        slashVisible = nextSlashVisible;
      });
      _syncSlashOverlay();
    }
    final delta = editor.document.toDelta().toJson();
    final current = jsonEncode(delta);
    if (serialized == current) return;
    serialized = current;
    widget.controller.updateNoteRichContent(
        widget.note.id, noteContentFromDelta(delta), text.trimRight());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _ancestorScrollPosition)) return;
    _ancestorScrollPosition?.removeListener(_syncSlashOverlay);
    _ancestorScrollPosition = next;
    _ancestorScrollPosition?.addListener(_syncSlashOverlay);
  }

  @override
  void didChangeMetrics() {
    _syncSlashOverlay();
  }

  @override
  void didUpdateWidget(covariant NoteDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = jsonEncode(noteDocumentDelta(widget.note));
    if (incoming == serialized || focus.hasFocus) return;
    editor.document = quill.Document.fromJson(noteDocumentDelta(widget.note));
    serialized = jsonEncode(editor.document.toDelta().toJson());
  }

  @override
  void dispose() {
    slashOverlay?.remove();
    slashOverlay = null;
    _ancestorScrollPosition?.removeListener(_syncSlashOverlay);
    WidgetsBinding.instance.removeObserver(this);
    editor.removeListener(_changed);
    editor.dispose();
    focus
      ..removeListener(_focusChanged)
      ..dispose();
    scroll.dispose();
    super.dispose();
  }

  TextRange? _slashRange() {
    final text = editor.document.toPlainText();
    final caret = editor.selection.baseOffset.clamp(0, text.length).toInt();
    final before = text.substring(0, caret);
    final start = before.lastIndexOf('\n') + 1;
    if (start >= caret || text.substring(start, caret).trim() != '/') {
      return null;
    }
    return TextRange(start: caret - 1, end: caret);
  }

  void _removeSlash() {
    final range = _slashRange();
    if (range == null) return;
    editor.replaceText(range.start, range.end - range.start, '',
        TextSelection.collapsed(offset: range.start));
    if (mounted) setState(() => slashVisible = false);
    _syncSlashOverlay();
  }

  void _syncSlashOverlay() {
    if (!mounted) return;
    if (!slashVisible) {
      slashOverlay?.remove();
      slashOverlay = null;
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final screen = MediaQuery.sizeOf(context);
    final menuHeight = math.min(390.0, math.max(220.0, screen.height - 24));
    Offset? caretOrigin;
    double caretHeight = 20;
    final renderEditor = renderEditorKey.currentState?.renderEditor;
    if (renderEditor != null && editor.selection.isValid) {
      try {
        final caret = renderEditor.getLocalRectForCaret(
            TextPosition(offset: editor.selection.extentOffset));
        caretOrigin = renderEditor.localToGlobal(caret.topLeft);
        caretHeight = caret.height;
      } on Object {
        // The first focus frame can be laid out before the caret is available.
      }
    }
    final box = context.findRenderObject() as RenderBox?;
    final fallbackOrigin = box?.localToGlobal(Offset.zero);
    final origin = caretOrigin ?? fallbackOrigin;
    if (origin != null) {
      final geometry = calculatePopoverGeometry(
        anchor: Rect.fromLTWH(origin.dx, origin.dy, 1, caretHeight),
        viewport: screen,
        desiredSize: Size(270, menuHeight),
        placement: PopoverPlacement.bottomStart,
        safeArea: const EdgeInsets.all(12),
      );
      slashOffset = geometry.rect.topLeft;
    }
    if (slashOverlay != null) {
      slashOverlay!.markNeedsBuild();
      return;
    }
    slashOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: slashOffset.dx,
        top: slashOffset.dy,
        child: TaskSlashMenu(
          actions: _noteSlashActions,
          onSelected: _applySlash,
        ),
      ),
    );
    overlay.insert(slashOverlay!);
  }

  void _formatLine(quill.Attribute attribute) {
    final text = editor.document.toPlainText();
    final caret = editor.selection.baseOffset.clamp(0, text.length).toInt();
    final start = text.substring(0, caret).lastIndexOf('\n') + 1;
    final endIndex = text.indexOf('\n', caret);
    final end = endIndex < 0 ? text.length : endIndex + 1;
    editor.formatText(
        start, (end - start).clamp(1, text.length - start), attribute);
  }

  void _insertBlock(Map<String, dynamic> node) {
    final at = editor.selection.baseOffset
        .clamp(0, editor.document.length - 1)
        .toInt();
    editor.replaceText(
        at,
        0,
        quill.BlockEmbed('workfollow-block', jsonEncode(node)),
        TextSelection.collapsed(offset: at + 1));
  }

  void _applySlash(TaskSlashAction action) {
    _removeSlash();
    switch (action) {
      case TaskSlashAction.heading1:
        _formatLine(quill.Attribute.h1);
      case TaskSlashAction.heading2:
        _formatLine(quill.Attribute.h2);
      case TaskSlashAction.heading3:
        _formatLine(quill.Attribute.h3);
      case TaskSlashAction.bullet:
        _formatLine(quill.Attribute.ul);
      case TaskSlashAction.ordered:
        _formatLine(quill.Attribute.ol);
      case TaskSlashAction.checklist:
        _formatLine(quill.Attribute.checked);
      case TaskSlashAction.quote:
        _formatLine(quill.Attribute.blockQuote);
      case TaskSlashAction.divider:
        _insertBlock({'type': 'horizontalRule'});
      case TaskSlashAction.attachment:
        unawaited(_attach());
      case TaskSlashAction.subtask:
      case TaskSlashAction.tag:
      case TaskSlashAction.relation:
        // These actions are intentionally not exposed in a note's palette.
        break;
    }
    focus.requestFocus();
  }

  Future<void> _link() async {
    if (editor.selection.isCollapsed) return;
    final url = await showDialog<String>(
      context: context,
      builder: (context) => const _NoteLinkDialog(),
    );
    if (!mounted || url == null || url.isEmpty) return;
    editor.formatSelection(quill.LinkAttribute(url));
    focus.requestFocus();
  }

  Future<void> _toggleToolbar(BuildContext anchor) async {
    if (!mounted || toolbarVisible) return;
    setState(() => toolbarVisible = true);
    // The toggle lives outside Quill's editor; explicitly reclaim focus before
    // presenting the floating strip so a selected range remains formatable.
    focus.requestFocus();
    await showAnchoredPopover<void>(
      anchor,
      width: 740,
      maxHeight: 58,
      placement: PopoverPlacement.topEnd,
      focusPolicy: PopoverFocusPolicy.preserveEditor,
      builder: (_) => TaskEditorToolbar(
        controller: editor,
        onAttach: _attach,
        onLink: _link,
        onInsertSlash: () {
          final at = editor.selection.baseOffset
              .clamp(0, editor.document.length - 1)
              .toInt();
          editor.replaceText(
              at, 0, '/', TextSelection.collapsed(offset: at + 1));
          focus.requestFocus();
        },
        onInsertDivider: () {
          _insertBlock({'type': 'horizontalRule'});
          focus.requestFocus();
        },
      ),
    );
    if (!mounted) return;
    setState(() => toolbarVisible = false);
    focus.requestFocus();
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
    if (editor.selection.isCollapsed) return;
    final body = editor.document.toPlainText();
    final start =
        math.min(editor.selection.baseOffset, editor.selection.extentOffset);
    final end =
        math.max(editor.selection.baseOffset, editor.selection.extentOffset);
    final text = body.substring(start, end).trim();
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
      quill.QuillEditor(
          controller: editor,
          focusNode: focus,
          scrollController: scroll,
          key: const ValueKey('note-body-editor'),
          config: quill.QuillEditorConfig(
            editorKey: renderEditorKey,
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
      Row(children: [
        TextButton.icon(
            key: const ValueKey('generate-task-from-selection'),
            onPressed: selectionPresent ? _taskFromSelection : null,
            icon: const Icon(Icons.playlist_add, size: 17),
            label: const Text('选中文字生成任务', style: TextStyle(fontSize: 12))),
        const Spacer(),
        Builder(
          builder: (anchor) => Tooltip(
            message: toolbarVisible ? '格式工具已打开' : '显示格式工具',
            child: IconButton(
              key: const ValueKey('note-format-toggle'),
              visualDensity: VisualDensity.compact,
              onPressed: () => unawaited(_toggleToolbar(anchor)),
              icon: Icon(
                toolbarVisible
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.text_format_rounded,
                size: 18,
              ),
            ),
          ),
        ),
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

class _NoteLinkDialog extends StatefulWidget {
  const _NoteLinkDialog();

  @override
  State<_NoteLinkDialog> createState() => _NoteLinkDialogState();
}

class _NoteLinkDialogState extends State<_NoteLinkDialog> {
  late final TextEditingController input;

  @override
  void initState() {
    super.initState();
    input = TextEditingController();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('插入链接'),
        content: TextField(
          key: const ValueKey('note-link-input'),
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消')),
          FilledButton(
              key: const ValueKey('note-link-apply'),
              onPressed: () => Navigator.of(context).pop(input.text.trim()),
              child: const Text('应用')),
        ],
      );
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
              key: ValueKey('note-attachment-${filename ?? 'file'}'),
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
