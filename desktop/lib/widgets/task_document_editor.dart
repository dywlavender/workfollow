import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../models/rich_document.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'task_editor_toolbar.dart';
import 'task_editor_popover.dart';
import 'desktop_popover.dart';
import 'task_slash_menu.dart';
import 'task_document_commands.dart';
import 'task_document_styles.dart';
import 'persistent_anchored_popover.dart';

export 'task_document_commands.dart';
export 'task_document_styles.dart';

/// The immutable state captured when a slash command starts.
///
/// A command is anchored to the slash itself, rather than to the current
/// caret line. The editor can lose focus while the palette is being clicked,
/// and the text before the slash can contain ordinary prose (for example
/// `文字/`). Keeping these offsets makes both cases deterministic.
class SlashCommandSession {
  const SlashCommandSession({
    required this.slashOffset,
    required this.lineStart,
    required this.originalSelection,
  });

  final int slashOffset;
  final int lineStart;
  final TextSelection originalSelection;
}

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
    this.onOpenDeadline,
    this.onOpenFocus,
    this.onToolbarChanged,
    this.onEscape,
  });

  final TaskItem task;
  final WorkspaceController controller;
  final Future<void> Function(BuildContext anchor)? onOpenTags;
  final Future<void> Function(BuildContext anchor)? onOpenRelation;
  final Future<void> Function(BuildContext anchor)? onOpenDeadline;
  final VoidCallback? onOpenFocus;
  final ValueChanged<bool>? onToolbarChanged;
  final VoidCallback? onEscape;

  @override
  TaskDocumentEditorState createState() => TaskDocumentEditorState();
}

class TaskDocumentEditorState extends State<TaskDocumentEditor>
    with WidgetsBindingObserver {
  late final quill.QuillController editor;
  late final TaskDocumentCommands documentCommands;
  late final FocusNode focus;
  late final ScrollController scroll;
  final renderEditorKey = GlobalKey<quill.EditorState>();
  final subtaskInputFocus = FocusNode(debugLabel: 'subtask-input');

  /// The palette keeps its own selection model but never takes focus, so the
  /// editor reaches it through this key and the caret stays in the document.
  final _slashMenuKey = GlobalKey<TaskSlashMenuState>();
  OverlayEntry? _slashOverlay;
  final _formatToolbar = PersistentAnchoredPopoverController();
  Offset _slashOffset = Offset.zero;
  late String serialized;
  late String _lastEditorText;
  SlashCommandSession? _slashSession;
  bool _applyingSlash = false;
  bool selectionPresent = false;
  bool slashVisible = false;
  bool toolbarVisible = false;
  bool _toolbarSyncScheduled = false;
  ScrollPosition? _ancestorScrollPosition;

  String get plainText => editor.document.toPlainText().trimRight();

  bool dismissSlashMenu() {
    if (_slashSession == null && !slashVisible) return false;
    _closeSlashSession();
    return true;
  }

  /// Closes the persistent formatting strip without releasing editor focus.
  /// Slash and nested pickers are handled before this layer in the Escape
  /// hierarchy.
  bool dismissFormattingToolbar() {
    if (!toolbarVisible && !_formatToolbar.isOpen) return false;
    _closeFormattingToolbar();
    return true;
  }

  void _focusDocumentEnd() {
    _closeSlashSession();
    editor.updateSelection(
        TextSelection.collapsed(offset: editor.document.length - 1),
        quill.ChangeSource.local);
    focus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    documentCommands = TaskDocumentCommands(
      editor: editor,
      pickAttachment: () =>
          widget.controller.pickTaskAttachment(widget.task.id),
      canMutate: () => mounted,
      requestFocus: () {
        if (mounted) focus.requestFocus();
      },
    );
    serialized = jsonEncode(editor.document.toDelta().toJson());
    _lastEditorText = editor.document.toPlainText();
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
    // A palette click can transiently move focus away from Quill. Focus is
    // therefore not a slash-session lifecycle event. The session is closed by
    // an explicit command, Escape, outside click, deletion, task switch, or
    // disposal instead.
    if (focus.hasFocus && _slashSession != null) _syncSlashOverlay();
  }

  void _changed() {
    final text = editor.document.toPlainText();
    final selection = editor.selection;
    if (!_applyingSlash) {
      final active = _slashSession;
      if (active == null) {
        final opened = _sessionForSlashInsertion(text, selection);
        if (opened != null) _openSlashSession(opened);
      } else if (!_sessionStillValid(active, text, selection)) {
        // Typing after the slash, moving the caret, selecting text, or
        // deleting the slash ends this invocation. There is intentionally no
        // query/filter mode in this first implementation.
        _closeSlashSession();
      }
    }

    final nextSelectionPresent = !selection.isCollapsed;
    if (mounted && nextSelectionPresent != selectionPresent) {
      setState(() => selectionPresent = nextSelectionPresent);
    }

    _lastEditorText = text;

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
  void didUpdateWidget(covariant TaskDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final taskChanged = widget.task.id != oldWidget.task.id ||
        !identical(widget.controller, oldWidget.controller);
    if (taskChanged) {
      _closeFormattingToolbar(notify: false, requestFocus: false);
      _closeSlashSession();
      final wasApplying = _applyingSlash;
      _applyingSlash = true;
      editor.document = _documentFor(widget.task);
      _applyingSlash = wasApplying;
      serialized = jsonEncode(editor.document.toDelta().toJson());
      _lastEditorText = editor.document.toPlainText();
      return;
    }
    final incoming = jsonEncode(taskDocumentDelta(widget.task));
    if (incoming == serialized ||
        incoming == jsonEncode(taskDocumentDelta(oldWidget.task)) ||
        focus.hasFocus) return;
    final wasApplying = _applyingSlash;
    _applyingSlash = true;
    editor.document = _documentFor(widget.task);
    _applyingSlash = wasApplying;
    serialized = jsonEncode(editor.document.toDelta().toJson());
    _lastEditorText = editor.document.toPlainText();
  }

  @override
  void dispose() {
    _formatToolbar.close();
    _slashOverlay?.remove();
    _slashOverlay = null;
    _slashSession = null;
    _ancestorScrollPosition?.removeListener(_syncSlashOverlay);
    _ancestorScrollPosition?.removeListener(_syncFormattingToolbarOverlay);
    WidgetsBinding.instance.removeObserver(this);
    editor.removeListener(_changed);
    editor.dispose();
    subtaskInputFocus.dispose();
    focus
      ..removeListener(_focusChanged)
      ..dispose();
    scroll.dispose();
    super.dispose();
  }

  /// Toggles the persistent formatting strip anchored to the footer's `A`
  /// button. It intentionally does not use [showTaskEditorPopover]: that API
  /// creates a modal route whose lifetime is tied to one action.
  Future<void> toggleToolbar(BuildContext anchor) async {
    if (!mounted) return;
    if (toolbarVisible || _formatToolbar.isOpen) {
      _closeFormattingToolbar();
      focus.requestFocus();
      return;
    }

    final opened = _formatToolbar.open(
      anchor,
      width: TaskEditorPopoverStyle.toolbarWidth,
      height: TaskEditorPopoverStyle.toolbarHeight,
      placement: const PopoverPlacement(
          preferredSide: PopoverSide.top,
          alignment: PopoverAlignment.center,
          gap: 28),
      popoverTheme: TaskEditorPopoverStyle.theme(anchor),
      surfaceDecoration: taskFormattingToolbarDecoration(),
      anchorRectResolver: () => _formatToolbarAnchorRect(anchor),
      builder: (_) => TaskEditorToolbar(
        controller: editor,
        documentCommands: documentCommands,
        onAttach: () => unawaited(documentCommands.insertAttachment()),
        onLink: () => unawaited(_link()),
        onInsertSlash: documentCommands.insertSlash,
        onInsertDivider: documentCommands.insertDivider,
      ),
    );
    if (!opened || !mounted) {
      _formatToolbar.close();
      return;
    }
    setState(() => toolbarVisible = true);
    widget.onToolbarChanged?.call(true);
    // The footer trigger lives outside Quill; reclaim focus without changing
    // the controller's existing range so multiple commands can be composed.
    focus.requestFocus();
    _syncFormattingToolbarOverlay();
  }

  Rect? _formatToolbarAnchorRect(BuildContext trigger) {
    final bounds = context.findRenderObject() as RenderBox?;
    final triggerBox = trigger.findRenderObject() as RenderBox?;
    if (bounds == null ||
        triggerBox == null ||
        !bounds.attached ||
        !triggerBox.attached ||
        !bounds.hasSize ||
        !triggerBox.hasSize) {
      return null;
    }
    final center = bounds.localToGlobal(Offset(bounds.size.width / 2, 0));
    final triggerOrigin = triggerBox.localToGlobal(Offset.zero);
    return Rect.fromLTWH(center.dx, triggerOrigin.dy, 0, 0);
  }

  void _closeFormattingToolbar(
      {bool notify = true, bool requestFocus = false}) {
    final wasOpen = toolbarVisible || _formatToolbar.isOpen;
    _formatToolbar.close();
    if (!wasOpen) return;
    if (mounted && toolbarVisible) setState(() => toolbarVisible = false);
    if (notify) widget.onToolbarChanged?.call(false);
    if (requestFocus) focus.requestFocus();
  }

  void _syncFormattingToolbarOverlay() {
    if (!mounted || !toolbarVisible) return;
    _formatToolbar.markNeedsBuild();
  }

  void _scheduleFormattingToolbarSync() {
    if (!toolbarVisible || _toolbarSyncScheduled) return;
    _toolbarSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toolbarSyncScheduled = false;
      if (mounted) _syncFormattingToolbarOverlay();
    });
  }

  SlashCommandSession? _sessionForSlashInsertion(
      String text, TextSelection selection) {
    if (!selection.isCollapsed || text.isEmpty) return null;
    final slashOffset = selection.extentOffset - 1;
    if (slashOffset < 0 ||
        slashOffset >= text.length ||
        text[slashOffset] != '/') {
      return null;
    }

    // Compare the old/new documents as an edit. The changed part must be one
    // slash at this exact offset; this handles both an ordinary insertion and
    // replacing selected text while avoiding a false trigger when a caret is
    // merely moved into an existing `foo/`.
    var prefix = 0;
    final common = math.min(_lastEditorText.length, text.length);
    while (prefix < common && _lastEditorText[prefix] == text[prefix]) {
      prefix++;
    }
    var oldEnd = _lastEditorText.length - 1;
    var newEnd = text.length - 1;
    while (oldEnd >= prefix &&
        newEnd >= prefix &&
        _lastEditorText[oldEnd] == text[newEnd]) {
      oldEnd--;
      newEnd--;
    }
    final inserted = newEnd < prefix ? '' : text.substring(prefix, newEnd + 1);
    if (inserted != '/' || prefix != slashOffset) return null;

    final lineStart =
        slashOffset == 0 ? 0 : text.lastIndexOf('\n', slashOffset - 1) + 1;
    return SlashCommandSession(
      slashOffset: slashOffset,
      lineStart: lineStart,
      originalSelection: selection,
    );
  }

  bool _sessionStillValid(
      SlashCommandSession session, String text, TextSelection selection) {
    return session.slashOffset >= 0 &&
        session.slashOffset < text.length &&
        text[session.slashOffset] == '/' &&
        selection.isCollapsed &&
        selection.extentOffset == session.slashOffset + 1;
  }

  void _openSlashSession(SlashCommandSession session) {
    _slashSession = session;
    if (!mounted) return;
    if (!slashVisible) setState(() => slashVisible = true);
    _syncSlashOverlay();
  }

  void _closeSlashSession() {
    _slashSession = null;
    if (mounted && slashVisible) setState(() => slashVisible = false);
    _slashOverlay?.remove();
    _slashOverlay = null;
  }

  TextRange? _slashRange([SlashCommandSession? requested]) {
    final session = requested ?? _slashSession;
    if (session == null) return null;
    final text = editor.document.toPlainText();
    if (session.slashOffset < 0 ||
        session.slashOffset >= text.length ||
        text[session.slashOffset] != '/') {
      return null;
    }
    return TextRange(start: session.slashOffset, end: session.slashOffset + 1);
  }

  bool _removeSlash(SlashCommandSession session) {
    final range = _slashRange(session);
    if (range == null) return false;
    documentCommands.deleteRange(range.start, range.end - range.start);
    return true;
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
    final screen = MediaQuery.sizeOf(context);
    // The full command set is 425pt tall. A window that cannot hold it gets a
    // shorter card that scrolls, instead of one that spills past the edge.
    final menuHeight = math.min(
        TaskSlashMenu.heightFor(null), math.max(220.0, screen.height - 24));
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
        // Layout can be between frames while the editor is first gaining
        // focus. The editor surface fallback below still keeps the menu
        // visible and clamped instead of dropping the command palette.
      }
    }
    final box = context.findRenderObject() as RenderBox?;
    final fallbackOrigin = box?.localToGlobal(Offset.zero);
    final origin = caretOrigin ?? fallbackOrigin;
    if (origin != null) {
      final geometry = calculatePopoverGeometry(
        anchor: Rect.fromLTWH(origin.dx, origin.dy, 1, caretHeight),
        viewport: screen,
        desiredSize: Size(TaskSlashMenuMetrics.width, menuHeight),
        placement: PopoverPlacement.bottomStart,
        safeArea: const EdgeInsets.all(12),
      );
      _slashOffset = geometry.rect.topLeft;
    }
    if (_slashOverlay != null) {
      _slashOverlay!.markNeedsBuild();
      return;
    }
    _slashOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: _slashOffset.dx,
          top: _slashOffset.dy,
          child: TapRegion(
            onTapOutside: (_) => _closeSlashSession(),
            child: Focus(
              canRequestFocus: false,
              descendantsAreFocusable: false,
              child: TaskSlashMenu(
                key: _slashMenuKey,
                maxHeight: menuHeight,
                onSelected: _applySlash,
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_slashOverlay!);
  }

  void _applySlash(TaskSlashAction action) {
    final session = _slashSession;
    if (session == null || _applyingSlash) return;
    final range = _slashRange(session);
    if (range == null) {
      _closeSlashSession();
      return;
    }
    final at = session.slashOffset;
    Future<void> Function(BuildContext)? openPicker;
    var attach = false;
    VoidCallback? openFocus;
    _applyingSlash = true;
    try {
      if (!_removeSlash(session)) {
        _closeSlashSession();
        return;
      }
      switch (action) {
        case TaskSlashAction.heading1:
          documentCommands.setHeading1(lineStart: session.lineStart);
        case TaskSlashAction.heading2:
          documentCommands.setHeading2(lineStart: session.lineStart);
        case TaskSlashAction.heading3:
          documentCommands.setHeading3(lineStart: session.lineStart);
        case TaskSlashAction.bullet:
          documentCommands.toggleBulletList(lineStart: session.lineStart);
        case TaskSlashAction.ordered:
          documentCommands.toggleOrderedList(lineStart: session.lineStart);
        case TaskSlashAction.checklist:
          documentCommands.toggleChecklist(lineStart: session.lineStart);
        case TaskSlashAction.quote:
          documentCommands.toggleQuote(lineStart: session.lineStart);
        case TaskSlashAction.divider:
          documentCommands.insertDivider(at: at);
        case TaskSlashAction.subtask:
          documentCommands.insertSubtaskBlock(at: at);
        case TaskSlashAction.tag:
          openPicker = widget.onOpenTags;
        case TaskSlashAction.relation:
          openPicker = widget.onOpenRelation;
        case TaskSlashAction.attachment:
          attach = true;
        case TaskSlashAction.deadline:
          openPicker = widget.onOpenDeadline;
        case TaskSlashAction.focus:
          openFocus = widget.onOpenFocus;
      }
      final insertedBlock = action == TaskSlashAction.divider ||
          action == TaskSlashAction.subtask;
      final desiredCaret = insertedBlock ? at + 1 : at;
      final maxCaret = math.max(0, editor.document.length - 1);
      editor.updateSelection(
          TextSelection.collapsed(
              offset: desiredCaret.clamp(0, maxCaret).toInt()),
          quill.ChangeSource.local);
    } finally {
      _applyingSlash = false;
    }
    _closeSlashSession();
    focus.requestFocus();
    if (attach) unawaited(documentCommands.insertAttachment(at: at));
    if (openPicker != null) unawaited(openPicker(context));
    openFocus?.call();
  }

  Future<void> _link() async {
    final input = TextEditingController();
    await documentCommands.insertLink(
      pickUrl: () async {
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
        return url;
      },
    );
  }

  /// Public commands used by the inspector More menu and relation picker.
  void insertSubtasksBlock() {
    if (!_hasBlock(widget.task, 'taskSubtasks') &&
        widget.task.subtasks.isEmpty) {
      documentCommands.insertSubtaskBlock();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      subtaskInputFocus.requestFocus();
      final inputContext = subtaskInputFocus.context;
      if (inputContext != null)
        Scrollable.ensureVisible(inputContext, alignment: .5);
    });
  }

  void insertRelationBlock(String noteId) =>
      documentCommands.insertRelation(noteId);

  Future<void> attachFile() async {
    await documentCommands.insertAttachment();
  }

  /// Shared document command surface used by inspector entry points.
  TaskDocumentCommands get commands => documentCommands;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    _scheduleFormattingToolbarSync();
    final textStyle = Theme.of(context).textTheme.bodyLarge!;
    final hasSubtaskBlock = _hasBlock(widget.task, 'taskSubtasks');
    final hasAttachmentBlock = _hasBlock(widget.task, 'attachment');
    final hasTrailingPanels =
        (widget.task.subtasks.isNotEmpty && !hasSubtaskBlock) ||
            (widget.task.attachments.isNotEmpty && !hasAttachmentBlock) ||
            (widget.controller.sourceNoteFor(widget.task.id) != null &&
                !_hasBlock(widget.task, 'relation'));
    return LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _focusDocumentEnd,
            child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.minHeight),
                child: Column(
                  key: const ValueKey('task-document-surface'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    quill.QuillEditor(
                      key: const ValueKey('task-document-editor'),
                      controller: editor,
                      focusNode: focus,
                      scrollController: scroll,
                      config: quill.QuillEditorConfig(
                        editorKey: renderEditorKey,
                        // A key set keeps this binding ahead of Quill's
                        // default single-activator Escape binding when merged.
                        //
                        // ↑/↓/Enter are only claimed while the palette is open.
                        // Quill sends plain Enter to the text input, and the
                        // framework's own Enter and Space bindings exist to
                        // hand those keys to the IME — an inner binding is the
                        // only place where Enter can mean "run the highlighted
                        // command" instead of "insert a newline".
                        customShortcuts: {
                          LogicalKeySet(LogicalKeyboardKey.escape):
                              const _TaskEditorEscapeIntent(),
                          if (slashVisible) ...{
                            LogicalKeySet(LogicalKeyboardKey.arrowDown):
                                const _SlashMoveIntent(1),
                            LogicalKeySet(LogicalKeyboardKey.arrowUp):
                                const _SlashMoveIntent(-1),
                            LogicalKeySet(LogicalKeyboardKey.enter):
                                const _SlashAcceptIntent(),
                            LogicalKeySet(LogicalKeyboardKey.numpadEnter):
                                const _SlashAcceptIntent(),
                          },
                        },
                        customActions: {
                          _TaskEditorEscapeIntent:
                              CallbackAction<_TaskEditorEscapeIntent>(
                            onInvoke: (_) {
                              if (dismissSlashMenu()) return null;
                              if (dismissFormattingToolbar()) return null;
                              if (widget.onEscape != null) {
                                widget.onEscape!();
                              } else {
                                focus.unfocus();
                              }
                              return null;
                            },
                          ),
                          _SlashMoveIntent: CallbackAction<_SlashMoveIntent>(
                            onInvoke: (intent) {
                              _slashMenuKey.currentState
                                  ?.moveSelection(intent.delta);
                              return null;
                            },
                          ),
                          _SlashAcceptIntent:
                              CallbackAction<_SlashAcceptIntent>(
                            onInvoke: (_) {
                              _slashMenuKey.currentState?.activateFocused();
                              return null;
                            },
                          ),
                        },
                        scrollable: false,
                        // Legacy panels stay near the prose; the surrounding surface
                        // accepts clicks in the remaining blank space below them.
                        minHeight: hasTrailingPanels
                            ? 150
                            : math.max(150, constraints.minHeight),
                        padding: const EdgeInsets.only(bottom: 20),
                        placeholder: '添加描述，输入 / 插入内容',
                        textCapitalization: TextCapitalization.sentences,
                        customStyles: TaskDocumentStyles.build(
                          tokens,
                          base: textStyle,
                        ),
                        customStyleBuilder:
                            TaskDocumentStyles.customStyleBuilder(tokens),
                        embedBuilders: [
                          TaskDocumentBlockBuilder(
                            subtaskFocus: subtaskInputFocus,
                            task: widget.task,
                            controller: widget.controller,
                          ),
                        ],
                      ),
                    ),
                    if (widget.task.subtasks.isNotEmpty && !hasSubtaskBlock)
                      TaskSubtasksPanel(
                          focusNode: subtaskInputFocus,
                          task: widget.task,
                          controller: widget.controller),
                    if (widget.task.attachments.isNotEmpty &&
                        !hasAttachmentBlock)
                      TaskAttachmentsPanel(
                          task: widget.task,
                          controller: widget.controller,
                          onAttach: () => unawaited(attachFile())),
                    if (widget.controller.sourceNoteFor(widget.task.id) !=
                            null &&
                        !_hasBlock(widget.task, 'relation'))
                      TaskSourceNotePanel(
                          task: widget.task, controller: widget.controller),
                  ],
                ))));
  }
}

class _TaskEditorEscapeIntent extends Intent {
  const _TaskEditorEscapeIntent();
}

/// ↑ / ↓ while the slash palette is open.
class _SlashMoveIntent extends Intent {
  const _SlashMoveIntent(this.delta);

  final int delta;
}

/// Enter while the slash palette is open.
class _SlashAcceptIntent extends Intent {
  const _SlashAcceptIntent();
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
      {required this.task, required this.controller, this.subtaskFocus});

  final TaskItem task;
  final WorkspaceController controller;
  final FocusNode? subtaskFocus;

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
          focusNode: subtaskFocus,
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
      {super.key,
      required this.task,
      required this.controller,
      this.focusNode});

  final TaskItem task;
  final WorkspaceController controller;
  final FocusNode? focusNode;

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
        return Padding(
          key: const ValueKey('task-subtasks-panel'),
          padding: const EdgeInsets.only(top: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('子任务',
                    style: TextStyle(
                        fontSize: WorkFollowMacTypography.sectionTitle,
                        height: WorkFollowMacTypography.lineControl,
                        fontWeight: WorkFollowMacWeight.semibold,
                        color: tokens.textPrimary)),
                const Spacer(),
                if (task.subtaskTotal > 0)
                  Text('${task.subtaskCompleted}/${task.subtaskTotal}',
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.listMeta,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.regular,
                          color: tokens.textTertiary)),
              ]),
              if (task.subtaskTotal > 0) ...[
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
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
                          fontSize: WorkFollowMacTypography.listTitle,
                          height: WorkFollowMacTypography.lineList,
                          fontWeight: WorkFollowMacWeight.medium,
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
                    icon: AppIcon(WorkFollowIcons.close,
                        size: WorkFollowMetrics.metadataIcon,
                        color: tokens.textTertiary),
                    onPressed: () =>
                        widget.controller.removeSubtask(task.id, item.id),
                  ),
                ]),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  AppIcon(WorkFollowIcons.add,
                      size: WorkFollowMetrics.toolbarIcon,
                      color: tokens.textTertiary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('task-subtask-input'),
                      focusNode: widget.focusNode,
                      controller: input,
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(
                          hintText: '添加子任务，按 Return 确认',
                          border: InputBorder.none,
                          isDense: true),
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.listTitle,
                          height: WorkFollowMacTypography.lineList,
                          fontWeight: WorkFollowMacWeight.regular,
                          color: tokens.textPrimary),
                    ),
                  ),
                ]),
              ),
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
    return Padding(
      key: const ValueKey('task-attachments-block'),
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('附件与关联',
              style: TextStyle(
                  fontSize: WorkFollowMacTypography.sectionTitle,
                  height: WorkFollowMacTypography.lineControl,
                  fontWeight: WorkFollowMacWeight.semibold,
                  color: tokens.textPrimary)),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final file in task.attachments)
                InputChip(
                  label: Text(file,
                      style: const TextStyle(
                          fontSize: WorkFollowMacTypography.control,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.regular)),
                  avatar: const AppIcon(WorkFollowIcons.file,
                      size: WorkFollowMetrics.metadataIcon),
                  onPressed: () => controller.revealAttachment(task.id, file),
                  onDeleted: () => controller.removeAttachment(task.id, file),
                ),
              TextButton.icon(
                  key: const ValueKey('task-attach-file'),
                  onPressed:
                      onAttach ?? () => controller.attachFileToTask(task.id),
                  icon: AppIcon(WorkFollowIcons.attachment,
                      size: WorkFollowMetrics.compactFieldIcon,
                      color: tokens.accent),
                  label: const Text('添加附件',
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.control,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.medium))),
            ],
          ),
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
    return Padding(
      key: const ValueKey('task-source-note'),
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        color: tokens.accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
        child: InkWell(
          borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
          onTap: () => controller.openNote(source.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              AppIcon(WorkFollowIcons.article,
                  size: WorkFollowMetrics.navigationIcon, color: tokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.listTitle,
                              height: WorkFollowMacTypography.lineList,
                              fontWeight: WorkFollowMacWeight.medium,
                              color: tokens.textPrimary)),
                      Text('来自笔记 · ${source.folder}',
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.listMeta,
                              height: WorkFollowMacTypography.lineControl,
                              fontWeight: WorkFollowMacWeight.regular,
                              color: tokens.textTertiary)),
                    ]),
              ),
              AppIcon(WorkFollowIcons.chevronNext,
                  size: WorkFollowMetrics.navigationIcon,
                  color: tokens.textTertiary),
            ]),
          ),
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
        icon: AppIcon(WorkFollowIcons.file,
            size: WorkFollowMetrics.navigationIcon, color: tokens.accent),
        label: Text(attrs['name']?.toString() ?? '附件',
            style: const TextStyle(
                fontSize: WorkFollowMacTypography.control,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.regular)),
      ),
    );
  }
}
