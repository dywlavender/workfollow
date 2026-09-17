import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../models/note_document.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/feedback/feedback_event.dart';
import '../features/feedback/feedback_scope.dart';
import 'app_icon_button.dart';
import 'task_editor_toolbar.dart';
import 'desktop_popover.dart';
import 'task_slash_menu.dart';
import 'task_document_commands.dart';
import 'task_document_styles.dart';
import 'persistent_anchored_popover.dart';

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
  late final TaskDocumentCommands documentCommands;
  final focus = FocusNode();
  final scroll = ScrollController();
  final renderEditorKey = GlobalKey<quill.EditorState>();
  final _slashPopover = PersistentAnchoredPopoverController();
  final _formatToolbar = PersistentAnchoredPopoverController();
  final _slashMenuKey = GlobalKey<TaskSlashMenuState>();
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
    documentCommands = TaskDocumentCommands(
      editor: editor,
      pickAttachment: () => widget.controller.pickNoteAttachment(),
      canMutate: () => mounted,
      requestFocus: () {
        if (mounted) focus.requestFocus();
      },
    );
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
    _ancestorScrollPosition?.removeListener(_syncFormattingToolbarOverlay);
    _ancestorScrollPosition = next;
    _ancestorScrollPosition?.addListener(_syncSlashOverlay);
    _ancestorScrollPosition?.addListener(_syncFormattingToolbarOverlay);
  }

  @override
  void didChangeMetrics() {
    _syncSlashOverlay();
    _syncFormattingToolbarOverlay();
  }

  @override
  void didUpdateWidget(covariant NoteDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note.id != oldWidget.note.id) {
      _slashPopover.close();
      _formatToolbar.close();
      if (mounted) {
        setState(() {
          slashVisible = false;
          toolbarVisible = false;
        });
      }
    }
    final incoming = jsonEncode(noteDocumentDelta(widget.note));
    if (incoming == serialized || focus.hasFocus) return;
    editor.document = quill.Document.fromJson(noteDocumentDelta(widget.note));
    serialized = jsonEncode(editor.document.toDelta().toJson());
  }

  @override
  void dispose() {
    _slashPopover.close();
    _formatToolbar.close();
    _ancestorScrollPosition?.removeListener(_syncSlashOverlay);
    _ancestorScrollPosition?.removeListener(_syncFormattingToolbarOverlay);
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
    documentCommands.deleteRange(range.start, range.end - range.start);
    if (mounted) setState(() => slashVisible = false);
    _syncSlashOverlay();
  }

  bool _dismissSlash() {
    if (!slashVisible) return false;
    _slashPopover.close();
    setState(() => slashVisible = false);
    return true;
  }

  void _syncSlashOverlay() {
    if (!mounted) return;
    if (!slashVisible) {
      _slashPopover.close();
      return;
    }
    final screen = MediaQuery.sizeOf(context);
    final menuHeight = math.min(TaskSlashMenu.heightFor(_noteSlashActions),
        math.max(220.0, screen.height - 24));
    if (_slashPopover.isOpen) {
      _slashPopover.markNeedsBuild();
      return;
    }
    _slashPopover.open(
      context,
      width: TaskSlashMenuMetrics.width,
      height: menuHeight,
      placement: PopoverPlacement.bottomStart,
      policy: const DesktopOverlayPolicy(
        layer: DesktopOverlayLayer.menu,
        focusPolicy: PopoverFocusPolicy.none,
        restoreFocus: false,
      ),
      anchorRectResolver: _slashAnchorRect,
      onDismiss: () {
        if (!mounted) return;
        setState(() => slashVisible = false);
      },
      builder: (_) => Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: TaskSlashMenu(
          key: _slashMenuKey,
          actions: _noteSlashActions,
          maxHeight: menuHeight,
          onSelected: _applySlash,
        ),
      ),
    );
  }

  Rect? _slashAnchorRect() {
    final renderEditor = renderEditorKey.currentState?.renderEditor;
    if (renderEditor != null && editor.selection.isValid) {
      try {
        final caret = renderEditor.getLocalRectForCaret(
            TextPosition(offset: editor.selection.extentOffset));
        return renderEditor.localToGlobal(caret.topLeft) & caret.size;
      } on Object {
        // The first focus frame can be laid out before the caret is available.
      }
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  int _lineStartAtCaret() {
    final text = editor.document.toPlainText();
    final caret = editor.selection.baseOffset.clamp(0, text.length).toInt();
    return text.substring(0, caret).lastIndexOf('\n') + 1;
  }

  void _applySlash(TaskSlashAction action) {
    _removeSlash();
    final lineStart = _lineStartAtCaret();
    switch (action) {
      case TaskSlashAction.heading1:
        documentCommands.setHeading1(lineStart: lineStart);
      case TaskSlashAction.heading2:
        documentCommands.setHeading2(lineStart: lineStart);
      case TaskSlashAction.heading3:
        documentCommands.setHeading3(lineStart: lineStart);
      case TaskSlashAction.bullet:
        documentCommands.toggleBulletList(lineStart: lineStart);
      case TaskSlashAction.ordered:
        documentCommands.toggleOrderedList(lineStart: lineStart);
      case TaskSlashAction.checklist:
        documentCommands.toggleChecklist(lineStart: lineStart);
      case TaskSlashAction.quote:
        documentCommands.toggleQuote(lineStart: lineStart);
      case TaskSlashAction.divider:
        documentCommands.insertDivider();
      case TaskSlashAction.attachment:
        unawaited(documentCommands.insertAttachment());
      case TaskSlashAction.deadline:
      case TaskSlashAction.focus:
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
    await documentCommands.insertLink(
      pickUrl: () => showDialog<String>(
        context: context,
        builder: (context) => const _NoteLinkDialog(),
      ),
    );
  }

  Future<void> _toggleToolbar(BuildContext anchor) async {
    if (!mounted) return;
    if (toolbarVisible || _formatToolbar.isOpen) {
      _formatToolbar.close();
      setState(() => toolbarVisible = false);
      focus.requestFocus();
      return;
    }
    final opened = _formatToolbar.open(
      anchor,
      width: TaskEditorMetrics.toolbarPopoverWidth,
      height: TaskEditorMetrics.toolbarPopoverHeight,
      placement: const PopoverPlacement(
          preferredSide: PopoverSide.top,
          alignment: PopoverAlignment.center,
          gap: WorkFollowSpacing.space7),
      policy: const DesktopOverlayPolicy.toolbar(),
      anchorRectResolver: () => _toolbarAnchorRect(anchor),
      builder: (_) => TaskEditorToolbar(
        controller: editor,
        documentCommands: documentCommands,
        onAttach: () => unawaited(documentCommands.insertAttachment()),
        onLink: () => unawaited(_link()),
        onInsertSlash: documentCommands.insertSlash,
        onInsertDivider: documentCommands.insertDivider,
      ),
    );
    if (!opened || !mounted) return;
    setState(() => toolbarVisible = true);
    focus.requestFocus();
    _syncFormattingToolbarOverlay();
  }

  Rect? _toolbarAnchorRect(BuildContext anchor) {
    final bounds = context.findRenderObject() as RenderBox?;
    final trigger = anchor.findRenderObject() as RenderBox?;
    if (bounds == null ||
        trigger == null ||
        !bounds.attached ||
        !trigger.attached ||
        !bounds.hasSize ||
        !trigger.hasSize) {
      return null;
    }
    final center = bounds.localToGlobal(Offset(bounds.size.width / 2, 0));
    return Rect.fromLTWH(
        center.dx, trigger.localToGlobal(Offset.zero).dy, 0, 0);
  }

  void _syncFormattingToolbarOverlay() {
    if (!mounted || !toolbarVisible) return;
    _formatToolbar.markNeedsBuild();
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
    // The new task went to the inbox, so offer to follow it instead of an undo.
    showFeedback(
        context,
        WorkFollowFeedback(
            kind: WorkFollowFeedbackKind.success,
            message: '已添加到收集箱',
            actionLabel: '查看任务',
            actionIcon: WorkFollowIcons.next,
            onAction: () => widget.controller.openTask(id)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final textStyle = TaskDocumentStyles.body(tokens);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      quill.QuillEditor(
          controller: editor,
          focusNode: focus,
          scrollController: scroll,
          key: const ValueKey('note-body-editor'),
          config: quill.QuillEditorConfig(
            editorKey: renderEditorKey,
            customShortcuts: {
              LogicalKeySet(LogicalKeyboardKey.escape):
                  const _NoteEditorEscapeIntent(),
              if (slashVisible) ...{
                LogicalKeySet(LogicalKeyboardKey.arrowDown):
                    const _NoteSlashMoveIntent(1),
                LogicalKeySet(LogicalKeyboardKey.arrowUp):
                    const _NoteSlashMoveIntent(-1),
                LogicalKeySet(LogicalKeyboardKey.enter):
                    const _NoteSlashAcceptIntent(),
                LogicalKeySet(LogicalKeyboardKey.numpadEnter):
                    const _NoteSlashAcceptIntent(),
              },
            },
            customActions: {
              _NoteEditorEscapeIntent: CallbackAction<_NoteEditorEscapeIntent>(
                onInvoke: (_) {
                  if (_dismissSlash()) return null;
                  if (toolbarVisible) {
                    _formatToolbar.close();
                    setState(() => toolbarVisible = false);
                    focus.requestFocus();
                    return null;
                  }
                  focus.unfocus();
                  return null;
                },
              ),
              _NoteSlashMoveIntent: CallbackAction<_NoteSlashMoveIntent>(
                onInvoke: (intent) {
                  _slashMenuKey.currentState?.moveSelection(intent.delta);
                  return null;
                },
              ),
              _NoteSlashAcceptIntent: CallbackAction<_NoteSlashAcceptIntent>(
                onInvoke: (_) {
                  _slashMenuKey.currentState?.activateFocused();
                  return null;
                },
              ),
            },
            scrollable: false,
            minHeight: NotesMetrics.editorMinHeight,
            padding: const EdgeInsets.only(bottom: WorkFollowSpacing.space6),
            placeholder: '写下你的想法、会议记录或下一步行动…',
            customStyles: TaskDocumentStyles.build(
              tokens,
              base: textStyle,
              paragraphBottom: 8,
              placeholderBottom: 8,
            ),
            customStyleBuilder: TaskDocumentStyles.customStyleBuilder(tokens),
            embedBuilders: [
              NoteBlockBuilder(controller: widget.controller),
              const NoteImageBuilder()
            ],
          )),
      Row(children: [
        TextButton.icon(
            key: const ValueKey('generate-task-from-selection'),
            onPressed: selectionPresent ? _taskFromSelection : null,
            icon: AppIcon(WorkFollowIcons.playlistAdd,
                size: WorkFollowMetrics.compactFieldIcon,
                color: selectionPresent ? tokens.accent : tokens.textTertiary),
            label: const Text('选中文字生成任务',
                style: TextStyle(fontSize: WorkFollowMacTypography.control))),
        const Spacer(),
        Builder(
          builder: (anchor) => Tooltip(
            message: toolbarVisible ? '格式工具已打开' : '显示格式工具',
            child: IconButton(
              key: const ValueKey('note-format-toggle'),
              visualDensity: VisualDensity.compact,
              onPressed: () => unawaited(_toggleToolbar(anchor)),
              icon: AppIcon(
                toolbarVisible
                    ? WorkFollowIcons.expandLess
                    : WorkFollowIcons.format,
                size: WorkFollowMetrics.fieldIcon,
                color: toolbarVisible ? tokens.accent : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ]),
    ]);
  }
}

class _NoteEditorEscapeIntent extends Intent {
  const _NoteEditorEscapeIntent();
}

class _NoteSlashMoveIntent extends Intent {
  const _NoteSlashMoveIntent(this.delta);

  final int delta;
}

class _NoteSlashAcceptIntent extends Intent {
  const _NoteSlashAcceptIntent();
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
            padding: const EdgeInsets.all(WorkFollowSpacing.sectionGap),
            color: WorkFollowTheme.of(context).canvas,
            child: const Row(children: [
              AppIcon(WorkFollowIcons.brokenImage,
                  size: WorkFollowMetrics.navigationIcon),
              SizedBox(width: WorkFollowSpacing.xs),
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
        constraints:
            const BoxConstraints(maxHeight: NotesMetrics.imageMaxHeight),
        child: image);
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
              icon: const AppIcon(WorkFollowIcons.file,
                  size: WorkFollowMetrics.navigationIcon),
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
                                padding: const EdgeInsets.all(
                                    WorkFollowSpacing.cardInset),
                                child: SelectableText(
                                    i < (row['content'] as List).length
                                        ? notePlainTextFromContentJson(
                                                (row['content'] as List)[i])
                                            .trimRight()
                                        : '',
                                    style: TextStyle(
                                        fontSize:
                                            WorkFollowMacTypography.control,
                                        color: tokens.textPrimary))),
                        ]),
                    ])));
    }
    return Container(
        padding: const EdgeInsets.all(WorkFollowSpacing.space4),
        decoration: BoxDecoration(
            color: tokens.canvas,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(WorkFollowRadii.surface)),
        child: SelectableText(
            notePlainTextFromContentJson(node).trim().isEmpty
                ? '导入的内容块'
                : notePlainTextFromContentJson(node).trim(),
            style: TextStyle(
                fontSize: WorkFollowMacTypography.control,
                color: tokens.textSecondary)));
  }
}
