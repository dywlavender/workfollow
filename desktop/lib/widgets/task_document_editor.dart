import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../models/rich_document.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'task_editor_toolbar.dart';
import 'task_slash_menu.dart';

/// A document-first editor for a task. Title editing remains a normal field;
/// everything below it is a Quill document whose Delta is persisted as the
/// task's structured content and projected back to plain text for lists/search.
class TaskDocumentEditor extends StatefulWidget {
  const TaskDocumentEditor({
    super.key,
    required this.task,
    required this.controller,
    this.onOpenTags,
    this.onOpenRelation,
    this.onToolbarChanged,
  });

  final TaskItem task;
  final WorkspaceController controller;
  final Future<void> Function(BuildContext anchor)? onOpenTags;
  final Future<void> Function(BuildContext anchor)? onOpenRelation;
  final ValueChanged<bool>? onToolbarChanged;

  @override
  TaskDocumentEditorState createState() => TaskDocumentEditorState();
}

class TaskDocumentEditorState extends State<TaskDocumentEditor> {
  late final quill.QuillController editor;
  late final FocusNode focus;
  late final ScrollController scroll;
  OverlayEntry? _slashOverlay;
  Offset _slashOffset = Offset.zero;
  late String serialized;
  bool selectionPresent = false;
  bool slashVisible = false;
  bool toolbarVisible = false;

  String get plainText => editor.document.toPlainText().trimRight();

  @override
  void initState() {
    super.initState();
    focus = FocusNode()..addListener(_focusChanged);
    scroll = ScrollController();
    editor = quill.QuillController(
      document: _documentFor(widget.task),
      selection: const TextSelection.collapsed(offset: 0),
      config: quill.QuillControllerConfig(
        clipboardConfig: quill.QuillClipboardConfig(
          onImagePaste: (bytes) async =>
              'data:image/png;base64,${base64Encode(bytes)}',
        ),
      ),
    );
    serialized = jsonEncode(editor.document.toDelta().toJson());
    editor.addListener(_changed);
  }

  quill.Document _documentFor(TaskItem task) {
    try {
      return quill.Document.fromJson(taskDocumentDelta(task));
    } on Object {
      return quill.Document();
    }
  }

  void _focusChanged() {
    if (!mounted) return;
    final nextToolbarVisible = focus.hasFocus || toolbarVisible;
    setState(() {
      if (focus.hasFocus) toolbarVisible = true;
      if (!focus.hasFocus) slashVisible = false;
    });
    if (nextToolbarVisible != toolbarVisible) {
      widget.onToolbarChanged?.call(toolbarVisible);
    } else if (focus.hasFocus) {
      widget.onToolbarChanged?.call(true);
    }
    if (!focus.hasFocus) _syncSlashOverlay();
  }

  void _changed() {
    final text = editor.document.toPlainText();
    final caret = editor.selection.baseOffset.clamp(0, text.length).toInt();
    final beforeCaret = text.substring(0, caret);
    final lineStart = beforeCaret.lastIndexOf('\n') + 1;
    final line = beforeCaret.substring(lineStart);
    final nextSlashVisible = focus.hasFocus &&
        (line.trim() == '/' ||
            (line.trimLeft().startsWith('/') && !line.contains('\n')));
    final nextSelectionPresent = !editor.selection.isCollapsed;
    if (mounted &&
        (nextSlashVisible != slashVisible ||
            nextSelectionPresent != selectionPresent)) {
      setState(() {
        slashVisible = nextSlashVisible;
        selectionPresent = nextSelectionPresent;
      });
      _syncSlashOverlay();
    }

    final delta = editor.document.toDelta().toJson();
    final current = jsonEncode(delta);
    if (serialized == current) return;
    serialized = current;
    // Do not show a SnackBar for each keystroke. The action result still
    // updates the global undo boundary and persistence queue.
    widget.controller.taskActions.setContent(
        widget.task.id, richContentFromDelta(delta), text.trimRight());
  }

  @override
  void didUpdateWidget(covariant TaskDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = jsonEncode(taskDocumentDelta(widget.task));
    if (incoming == serialized || focus.hasFocus) return;
    editor.document = _documentFor(widget.task);
    serialized = jsonEncode(editor.document.toDelta().toJson());
  }

  @override
  void dispose() {
    _slashOverlay?.remove();
    _slashOverlay = null;
    editor.removeListener(_changed);
    editor.dispose();
    focus
      ..removeListener(_focusChanged)
      ..dispose();
    scroll.dispose();
    super.dispose();
  }

  void toggleToolbar() {
    if (!mounted) return;
    setState(() => toolbarVisible = !toolbarVisible);
    widget.onToolbarChanged?.call(toolbarVisible);
    if (toolbarVisible) focus.requestFocus();
  }

  void showToolbar() {
    if (!mounted) return;
    setState(() => toolbarVisible = true);
    widget.onToolbarChanged?.call(true);
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
      _slashOverlay?.remove();
      _slashOverlay = null;
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final origin = box.localToGlobal(Offset.zero);
      final screen = MediaQuery.sizeOf(context);
      final menuHeight = math.min(390.0, math.max(220.0, screen.height - 24));
      final availableBelow = screen.height - (origin.dy + box.size.height);
      final rawTop = availableBelow >= menuHeight + 6
          ? origin.dy + box.size.height + 6
          : origin.dy - menuHeight - 6;
      _slashOffset = Offset(
        origin.dx.clamp(12.0, math.max(12.0, screen.width - 282.0)),
        rawTop.clamp(12.0, math.max(12.0, screen.height - menuHeight - 12)),
      );
    }
    if (_slashOverlay != null) {
      _slashOverlay!.markNeedsBuild();
      return;
    }
    _slashOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: _slashOffset.dx,
        top: _slashOffset.dy,
        child: TaskSlashMenu(onSelected: _applySlash),
      ),
    );
    overlay.insert(_slashOverlay!);
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
        final at = editor.selection.baseOffset;
        editor.replaceText(
            at,
            0,
            quill.BlockEmbed(
                'workfollow-block', jsonEncode({'type': 'horizontalRule'})),
            TextSelection.collapsed(offset: at + 1));
      case TaskSlashAction.subtask:
        _insertBlock({'type': 'taskSubtasks'});
      case TaskSlashAction.tag:
        final callback = widget.onOpenTags;
        if (callback != null) unawaited(callback(context));
      case TaskSlashAction.relation:
        final callback = widget.onOpenRelation;
        if (callback != null) unawaited(callback(context));
      case TaskSlashAction.attachment:
        unawaited(_attach());
    }
    focus.requestFocus();
  }

  void _insertBlock(Map<String, dynamic> node) {
    final at = editor.selection.baseOffset;
    editor.replaceText(
        at,
        0,
        quill.BlockEmbed('workfollow-block', jsonEncode(node)),
        TextSelection.collapsed(offset: at + 1));
  }

  Future<void> _attach() async {
    final filename = await widget.controller.pickTaskAttachment(widget.task.id);
    if (!mounted || filename == null) return;
    _insertBlock({
      'type': 'attachment',
      'attrs': {'name': filename, 'localFile': filename},
    });
  }

  Future<void> _link() async {
    if (editor.selection.isCollapsed) return;
    final input = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('插入链接'),
        content: TextField(
          key: const ValueKey('task-link-input'),
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
              key: const ValueKey('task-link-apply'),
              onPressed: () => Navigator.of(context).pop(input.text.trim()),
              child: const Text('应用')),
        ],
      ),
    );
    input.dispose();
    if (!mounted || url == null || url.isEmpty) return;
    editor.formatSelection(quill.LinkAttribute(url));
    focus.requestFocus();
  }

  /// Public commands used by the inspector More menu and relation picker.
  void insertSubtasksBlock() => _insertBlock({'type': 'taskSubtasks'});

  void insertRelationBlock(String noteId) => _insertBlock({
        'type': 'relation',
        'attrs': {'noteId': noteId}
      });

  Future<void> attachFile() => _attach();

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final textStyle = Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: 14.5,
          height: 1.7,
          color: tokens.textPrimary,
        );
    final hasSubtaskBlock = _hasBlock(widget.task, 'taskSubtasks');
    final hasAttachmentBlock = _hasBlock(widget.task, 'attachment');
    return Column(
      key: const ValueKey('task-document-surface'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        quill.QuillEditor(
          key: const ValueKey('task-document-editor'),
          controller: editor,
          focusNode: focus,
          scrollController: scroll,
          config: quill.QuillEditorConfig(
            scrollable: false,
            minHeight: 235,
            padding: const EdgeInsets.only(bottom: 20),
            placeholder: '输入内容，或使用 / 快速插入',
            textCapitalization: TextCapitalization.sentences,
            customStyles: quill.DefaultStyles(
              paragraph: quill.DefaultTextBlockStyle(
                textStyle,
                const quill.HorizontalSpacing(0, 0),
                const quill.VerticalSpacing(0, 7),
                const quill.VerticalSpacing(0, 0),
                null,
              ),
              placeHolder: quill.DefaultTextBlockStyle(
                textStyle.copyWith(color: tokens.textTertiary),
                const quill.HorizontalSpacing(0, 0),
                const quill.VerticalSpacing(0, 7),
                const quill.VerticalSpacing(0, 0),
                null,
              ),
            ),
            embedBuilders: [
              TaskDocumentBlockBuilder(
                task: widget.task,
                controller: widget.controller,
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: toolbarVisible
              ? TaskEditorToolbar(
                  controller: editor,
                  onAttach: _attach,
                  onLink: _link,
                  onInsertSlash: () {
                    editor.replaceText(
                        editor.selection.baseOffset,
                        0,
                        '/',
                        TextSelection.collapsed(
                            offset: editor.selection.baseOffset + 1));
                    focus.requestFocus();
                  },
                )
              : const SizedBox.shrink(),
        ),
        if (widget.task.subtasks.isNotEmpty && !hasSubtaskBlock)
          TaskSubtasksPanel(task: widget.task, controller: widget.controller),
        if (widget.task.attachments.isNotEmpty && !hasAttachmentBlock)
          TaskAttachmentsPanel(
              task: widget.task,
              controller: widget.controller,
              onAttach: () => _attach()),
        if (widget.controller.sourceNoteFor(widget.task.id) != null &&
            !_hasBlock(widget.task, 'relation'))
          TaskSourceNotePanel(task: widget.task, controller: widget.controller),
      ],
    );
  }
}

bool _hasBlock(TaskItem task, String type) {
  final content = task.contentJson?['content'];
  if (content is! List) return false;
  for (final block in content.whereType<Map>()) {
    if (block['type'] == type) return true;
    final nested = block['content'];
    if (nested is List &&
        nested.whereType<Map>().any((item) => item['type'] == type)) {
      return true;
    }
  }
  return false;
}

/// Renders WorkFollow-specific blocks inside a Quill document.
class TaskDocumentBlockBuilder extends quill.EmbedBuilder {
  const TaskDocumentBlockBuilder(
      {required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  String get key => 'workfollow-block';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final raw = embedContext.node.value.data.toString();
    Map<String, dynamic> node;
    try {
      node = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on Object {
      return const SizedBox.shrink();
    }
    return switch (node['type']) {
      'horizontalRule' => Divider(
          key: const ValueKey('task-horizontal-rule'),
          color: WorkFollowTheme.of(context).borderStrong,
          height: 26),
      'taskSubtasks' => TaskSubtasksPanel(
          key: const ValueKey('task-subtasks-block'),
          task: task,
          controller: controller),
      'attachment' =>
        _TaskAttachmentBlock(node: node, task: task, controller: controller),
      'relation' => TaskSourceNotePanel(task: task, controller: controller),
      _ => const SizedBox.shrink(),
    };
  }
}

class TaskSubtasksPanel extends StatefulWidget {
  const TaskSubtasksPanel(
      {super.key, required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  State<TaskSubtasksPanel> createState() => _TaskSubtasksPanelState();
}

class _TaskSubtasksPanelState extends State<TaskSubtasksPanel> {
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

  void _add() {
    if (widget.controller.addSubtask(widget.task.id, input.text)) {
      input.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final task = widget.controller.tasks
                .where((item) => item.id == widget.task.id)
                .firstOrNull ??
            widget.task;
        final progress = task.subtaskTotal == 0
            ? 0.0
            : task.subtaskCompleted / task.subtaskTotal;
        return Container(
          key: const ValueKey('task-subtasks-panel'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: tokens.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.playlist_add_check_rounded,
                    size: 16, color: tokens.textSecondary),
                const SizedBox(width: 7),
                Text('子任务',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: tokens.textSecondary)),
                const Spacer(),
                if (task.subtaskTotal > 0)
                  Text('${task.subtaskCompleted}/${task.subtaskTotal}',
                      style:
                          TextStyle(fontSize: 11, color: tokens.textTertiary)),
              ]),
              if (task.subtaskTotal > 0) ...[
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: tokens.border,
                      color: progress == 1 ? tokens.success : tokens.accent),
                ),
              ],
              for (final item in task.subtasks)
                Row(key: ValueKey('task-subtask-${item.id}'), children: [
                  Checkbox(
                    value: item.completed,
                    onChanged: (_) =>
                        widget.controller.toggleSubtask(task.id, item.id),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: tokens.borderStrong),
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: item.title,
                      onChanged: (value) => widget.controller
                          .renameSubtask(task.id, item.id, value),
                      decoration: const InputDecoration(
                          border: InputBorder.none, isDense: true),
                      style: TextStyle(
                          fontSize: 12.5,
                          color: item.completed
                              ? tokens.textTertiary
                              : tokens.textPrimary,
                          decoration: item.completed
                              ? TextDecoration.lineThrough
                              : null),
                    ),
                  ),
                  IconButton(
                    tooltip: '删除子任务',
                    visualDensity: VisualDensity.compact,
                    icon:
                        Icon(Icons.close, size: 14, color: tokens.textTertiary),
                    onPressed: () =>
                        widget.controller.removeSubtask(task.id, item.id),
                  ),
                ]),
              Row(children: [
                Icon(Icons.add_rounded, size: 16, color: tokens.textTertiary),
                const SizedBox(width: 5),
                Expanded(
                  child: TextField(
                    key: const ValueKey('task-subtask-input'),
                    controller: input,
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(
                        hintText: '添加子任务，按 Return 确认',
                        border: InputBorder.none,
                        isDense: true),
                    style: TextStyle(fontSize: 12.5, color: tokens.textPrimary),
                  ),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class TaskAttachmentsPanel extends StatelessWidget {
  const TaskAttachmentsPanel(
      {super.key, required this.task, required this.controller, this.onAttach});

  final TaskItem task;
  final WorkspaceController controller;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      key: const ValueKey('task-attachments-block'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 5),
      decoration: BoxDecoration(
          color: tokens.canvas,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: tokens.border)),
      child: Wrap(
        spacing: 7,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final file in task.attachments)
            InputChip(
              label: Text(file, style: const TextStyle(fontSize: 11.5)),
              avatar: const Icon(Icons.insert_drive_file_outlined, size: 15),
              onPressed: () => controller.revealAttachment(task.id, file),
              onDeleted: () => controller.removeAttachment(task.id, file),
            ),
          TextButton.icon(
              key: const ValueKey('task-attach-file'),
              onPressed: onAttach ?? () => controller.attachFileToTask(task.id),
              icon: const Icon(Icons.attach_file_rounded, size: 15),
              label: const Text('添加附件', style: TextStyle(fontSize: 11.5))),
        ],
      ),
    );
  }
}

class TaskSourceNotePanel extends StatelessWidget {
  const TaskSourceNotePanel(
      {super.key, required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final source = controller.sourceNoteFor(task.id);
    if (source == null) return const SizedBox.shrink();
    final tokens = WorkFollowTheme.of(context);
    return Material(
      key: const ValueKey('task-source-note'),
      color: tokens.accent.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => controller.openNote(source.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            Icon(Icons.article_outlined, size: 17, color: tokens.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary)),
                    Text('来自笔记 · ${source.folder}',
                        style: TextStyle(
                            fontSize: 10.5, color: tokens.textTertiary)),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: tokens.textTertiary),
          ]),
        ),
      ),
    );
  }
}

class _TaskAttachmentBlock extends StatelessWidget {
  const _TaskAttachmentBlock(
      {required this.node, required this.task, required this.controller});

  final Map<String, dynamic> node;
  final TaskItem task;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final attrs = node['attrs'] is Map
        ? Map<String, dynamic>.from(node['attrs'] as Map)
        : const <String, dynamic>{};
    final filename =
        attrs['localFile']?.toString() ?? attrs['name']?.toString();
    final tokens = WorkFollowTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: ValueKey('task-attachment-${filename ?? 'file'}'),
        onPressed: filename == null
            ? null
            : () => controller.revealAttachment(task.id, filename),
        icon: Icon(Icons.insert_drive_file_outlined,
            size: 17, color: tokens.accent),
        label: Text(attrs['name']?.toString() ?? '附件'),
      ),
    );
  }
}
