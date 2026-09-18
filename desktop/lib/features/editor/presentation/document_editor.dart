import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../../theme/workfollow_theme.dart';
import '../../../widgets/desktop_popover.dart';
import '../../../widgets/persistent_anchored_popover.dart';
import '../../../widgets/task_editor_popover.dart';
import '../document_commands.dart';
import '../document_keys.dart';
import '../document_editor_toolbar.dart';
import '../document_selection_toolbar.dart';
import '../document_slash_menu.dart';
import '../document_styles.dart';
import '../slash_command_session.dart';
import '../domain/document_selection_action.dart';
import '../domain/editor_capability.dart';
import '../domain/editor_profile.dart';

/// The one document editor behind every WorkFollow editing surface.
///
/// A task document and a note document differ in their Delta, their palette
/// vocabulary, their embeds, their under-prose panels and their selection
/// actions — not in how a slash invocation, a formatting strip or a save
/// handoff works. Those mechanics live here once, and [EditorProfile] says
/// which of them a document loads. The core never asks what kind of document it
/// holds.
class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.profile,
    this.onToolbarChanged,
    this.onEscape,
  });

  /// Adapter for the document being edited. Owners rebuild it on every build.
  final EditorProfile profile;

  /// Notified when the formatting strip opens or closes, so a shell that owns
  /// the trigger can reflect its state.
  final ValueChanged<bool>? onToolbarChanged;

  /// Last layer of the Escape chain, after the palette and the strip.
  final VoidCallback? onEscape;

  @override
  State<DocumentEditor> createState() => DocumentEditorState();
}

class DocumentEditorState extends State<DocumentEditor>
    with WidgetsBindingObserver {
  late final quill.QuillController editor;
  late final DocumentCommands documentCommands;
  late final FocusNode focus;
  late final ScrollController scroll;
  final renderEditorKey = GlobalKey<quill.EditorState>();

  /// The palette keeps its own selection model but never takes focus, so the
  /// editor reaches it through this key and the caret stays in the document.
  final _slashMenuKey = GlobalKey<DocumentSlashMenuState>();
  final _slashPopover = PersistentAnchoredPopoverController();
  final _formatToolbar = PersistentAnchoredPopoverController();
  final _selectionPopover = PersistentAnchoredPopoverController();
  late String serialized;
  late String _lastEditorText;
  SlashCommandSession? _slashSession;
  bool _applyingSlash = false;
  bool selectionPresent = false;
  bool slashVisible = false;
  bool toolbarVisible = false;
  bool selectionToolbarVisible = false;
  bool _selectionOverlaySuppressed = false;
  TextSelection? _lastSelectionForOverlay;
  bool _toolbarSyncScheduled = false;
  int _documentLoadGeneration = 0;
  ScrollPosition? _ancestorScrollPosition;

  /// Shared command surface used by a shell's own entry points, such as the
  /// inspector's block insertions.
  DocumentCommands get commands => documentCommands;

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

  /// Closes the selection action strip while leaving the editor selection
  /// intact. The next non-collapsed selection opens it again.
  bool dismissSelectionToolbar() {
    if (!selectionToolbarVisible && !_selectionPopover.isOpen) return false;
    _selectionOverlaySuppressed = true;
    _closeSelectionToolbar();
    return true;
  }

  /// Puts the caret at the end of the document and takes focus.
  ///
  /// Page chrome calls this so the blank area under the prose is a way into the
  /// document. That is the alternative to stretching the document to reach the
  /// bottom of the pane, which is what used to drag everything after it down.
  void focusEnd() => _focusDocumentEnd();

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
      document: widget.profile.buildDocument(),
      selection: const TextSelection.collapsed(offset: 0),
      config: quill.QuillControllerConfig(
        clipboardConfig: quill.QuillClipboardConfig(
          onImagePaste: (bytes) async =>
              'data:image/png;base64,${base64Encode(bytes)}',
        ),
      ),
    );
    documentCommands = DocumentCommands(
      editor: editor,
      pickAttachment: widget.profile.pickAttachment,
      canMutate: () => mounted,
      requestFocus: () {
        if (mounted) focus.requestFocus();
      },
    );
    serialized = jsonEncode(editor.document.toDelta().toJson());
    _lastEditorText = editor.document.toPlainText();
    editor.addListener(_changed);
  }

  void _focusChanged() {
    if (!mounted) return;
    // A palette click can transiently move focus away from Quill. Focus is
    // therefore not a slash-session lifecycle event. The session is closed by
    // an explicit command, Escape, outside click, deletion, document switch, or
    // disposal instead.
    if (focus.hasFocus && _slashSession != null) _syncSlashOverlay();
  }

  void _changed() {
    final text = editor.document.toPlainText();
    final selection = editor.selection;
    final selectionChanged = _lastSelectionForOverlay == null ||
        selection != _lastSelectionForOverlay;
    if (selectionChanged) _selectionOverlaySuppressed = false;
    _lastSelectionForOverlay = selection;
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
    if (nextSelectionPresent) {
      _syncSelectionToolbar(selectionPresentOverride: nextSelectionPresent);
    } else {
      _selectionOverlaySuppressed = false;
      _closeSelectionToolbar();
    }

    _lastEditorText = text;

    final delta = editor.document.toDelta().toJson();
    final current = jsonEncode(delta);
    if (serialized == current) return;
    serialized = current;
    // Do not show a SnackBar for each keystroke. The action result still
    // updates the global undo boundary and persistence queue.
    widget.profile.persist(delta, text.trimRight());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (identical(next, _ancestorScrollPosition)) return;
    _ancestorScrollPosition?.removeListener(_syncSlashOverlay);
    _ancestorScrollPosition?.removeListener(_syncFormattingToolbarOverlay);
    _ancestorScrollPosition?.removeListener(_syncSelectionToolbar);
    _ancestorScrollPosition = next;
    _ancestorScrollPosition?.addListener(_syncSlashOverlay);
    _ancestorScrollPosition?.addListener(_syncFormattingToolbarOverlay);
    _ancestorScrollPosition?.addListener(_syncSelectionToolbar);
  }

  @override
  void didChangeMetrics() {
    _syncSlashOverlay();
    _syncFormattingToolbarOverlay();
    _syncSelectionToolbar();
  }

  @override
  void didUpdateWidget(covariant DocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final documentChanged = widget.profile.documentId !=
            oldWidget.profile.documentId ||
        !identical(widget.profile.documentHost, oldWidget.profile.documentHost);
    if (documentChanged) {
      _closeFormattingToolbar(notify: false, requestFocus: false);
      _closeSlashSession();
      // A Quill document replacement can briefly retain the old non-collapsed
      // selection. Keep the old action strip closed until the user makes a
      // fresh selection in the new document.
      _selectionOverlaySuppressed = true;
      _closeSelectionToolbar();
      _scheduleDocumentReplacement(widget.profile.documentId);
      return;
    }
    final incoming = jsonEncode(widget.profile.ownedDelta);
    if (incoming == serialized ||
        incoming == jsonEncode(oldWidget.profile.ownedDelta) ||
        focus.hasFocus) return;
    _selectionOverlaySuppressed = true;
    _closeSelectionToolbar();
    _scheduleDocumentReplacement(widget.profile.documentId);
  }

  /// Quill notifies its listeners when [QuillController.document] changes.
  /// Doing that synchronously from [didUpdateWidget] can notify the toolbar's
  /// AnimatedBuilder while Flutter is still rebuilding the old overlay. Queue
  /// the replacement after the frame so a document switch closes every overlay
  /// before the controller emits its document notification.
  void _scheduleDocumentReplacement(String documentId) {
    final generation = ++_documentLoadGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _documentLoadGeneration) return;
      if (widget.profile.documentId != documentId) return;
      final wasApplying = _applyingSlash;
      _applyingSlash = true;
      editor.document = widget.profile.buildDocument();
      _applyingSlash = wasApplying;
      _selectionOverlaySuppressed = true;
      _lastSelectionForOverlay = editor.selection;
      serialized = jsonEncode(editor.document.toDelta().toJson());
      _lastEditorText = editor.document.toPlainText();
    });
  }

  @override
  void dispose() {
    _formatToolbar.close();
    _slashPopover.close();
    _selectionPopover.close();
    _slashSession = null;
    _ancestorScrollPosition?.removeListener(_syncSlashOverlay);
    _ancestorScrollPosition?.removeListener(_syncFormattingToolbarOverlay);
    _ancestorScrollPosition?.removeListener(_syncSelectionToolbar);
    WidgetsBinding.instance.removeObserver(this);
    editor.removeListener(_changed);
    editor.dispose();
    focus
      ..removeListener(_focusChanged)
      ..dispose();
    scroll.dispose();
    super.dispose();
  }

  /// Toggles the persistent formatting strip anchored to its trigger.
  ///
  /// It intentionally does not use [showTaskEditorPopover]: that API creates a
  /// modal route whose lifetime is tied to one action, and the strip has to
  /// survive several commands in a row.
  Future<void> toggleToolbar(BuildContext anchor) async {
    if (!mounted) return;
    if (toolbarVisible || _formatToolbar.isOpen) {
      _closeFormattingToolbar();
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
      popoverTheme: TaskEditorPopoverStyle.theme(anchor),
      surfaceDecoration:
          taskFormattingToolbarDecoration(WorkFollowTheme.of(anchor)),
      anchorRectResolver: () => _formatToolbarAnchorRect(anchor),
      builder: (_) => DocumentEditorToolbar(
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
    // The trigger lives outside Quill; reclaim focus without changing the
    // controller's existing range so multiple commands can be composed.
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

  void _closeSelectionToolbar() {
    final wasOpen = selectionToolbarVisible || _selectionPopover.isOpen;
    _selectionPopover.close();
    if (!wasOpen) return;
    if (mounted && selectionToolbarVisible) {
      setState(() => selectionToolbarVisible = false);
    }
  }

  void _dismissSelectionToolbarFromOutside() {
    _selectionOverlaySuppressed = true;
    _closeSelectionToolbar();
  }

  void _syncSelectionToolbar({bool? selectionPresentOverride}) {
    if (!mounted) return;
    final actions = widget.profile.selectionActions;
    final hasSelection = selectionPresentOverride ?? selectionPresent;
    if (_selectionOverlaySuppressed ||
        !hasSelection ||
        editor.selection.isCollapsed ||
        actions.isEmpty) {
      _closeSelectionToolbar();
      return;
    }
    if (_selectionPopover.isOpen) {
      _selectionPopover.markNeedsBuild();
      return;
    }
    final opened = _selectionPopover.open(
      context,
      width: TaskEditorMetrics.selectionToolbarWidth,
      height: TaskEditorMetrics.selectionToolbarHeight,
      placement: PopoverPlacement.topCenter,
      policy: const DesktopOverlayPolicy(
        layer: DesktopOverlayLayer.toolbar,
        focusPolicy: PopoverFocusPolicy.none,
        dismissOnTapOutside: true,
        restoreFocus: false,
      ),
      popoverTheme: TaskEditorPopoverStyle.theme(context),
      surfaceDecoration:
          taskFormattingToolbarDecoration(WorkFollowTheme.of(context)),
      anchorRectResolver: _selectionAnchorRect,
      onDismiss: _dismissSelectionToolbarFromOutside,
      builder: (_) => DocumentSelectionToolbar(
        actions: actions,
        onInvoke: _invokeSelectionAction,
      ),
    );
    if (opened && mounted) {
      setState(() => selectionToolbarVisible = true);
    }
  }

  void _invokeSelectionAction(DocumentSelectionAction action) {
    if (!mounted || editor.selection.isCollapsed) return;
    _selectionOverlaySuppressed = true;
    action.onInvoke(context, editor);
    _closeSelectionToolbar();
    focus.requestFocus();
  }

  Rect? _selectionAnchorRect() {
    final renderEditor = renderEditorKey.currentState?.renderEditor;
    final selection = editor.selection;
    if (renderEditor == null || !selection.isValid || selection.isCollapsed) {
      return null;
    }
    try {
      final maxOffset = math.max(0, editor.document.length - 1);
      final extent = selection.extentOffset.clamp(0, maxOffset).toInt();
      final caret =
          renderEditor.getLocalRectForCaret(TextPosition(offset: extent));
      final global = renderEditor.localToGlobal(caret.topLeft);
      return Rect.fromLTWH(
          global.dx, global.dy, math.max(1, caret.width), caret.height);
    } on Object {
      // The selection can change before Quill has laid out its new line. Keep
      // the last popover geometry until the next scroll/layout notification.
      return null;
    }
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
    return SlashCommandSession.fromInsertion(
      previousText: _lastEditorText,
      text: text,
      selection: selection,
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
    _slashPopover.close();
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
      _slashPopover.close();
      return;
    }
    final screen = MediaQuery.sizeOf(context);
    // The full command set is 425pt tall. A window that cannot hold it gets a
    // shorter card that scrolls, instead of one that spills past the edge.
    final menuHeight = math.min(
        DocumentSlashMenu.heightFor(widget.profile.slashActions),
        math.max(220.0, screen.height - 24));
    if (_slashPopover.isOpen) {
      _slashPopover.markNeedsBuild();
      return;
    }
    _slashPopover.open(
      context,
      width: DocumentSlashMenuMetrics.width,
      height: menuHeight,
      placement: PopoverPlacement.bottomStart,
      policy: const DesktopOverlayPolicy(
        layer: DesktopOverlayLayer.menu,
        focusPolicy: PopoverFocusPolicy.none,
        restoreFocus: false,
      ),
      anchorRectResolver: _slashAnchorRect,
      onDismiss: _closeSlashSession,
      builder: (_) => Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: DocumentSlashMenu(
          key: _slashMenuKey,
          actions: widget.profile.slashActions,
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

  void _applySlash(DocumentSlashAction action) {
    final session = _slashSession;
    if (session == null || _applyingSlash) return;
    final range = _slashRange(session);
    if (range == null) {
      _closeSlashSession();
      return;
    }
    final at = session.slashOffset;
    final profile = widget.profile;
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
        case DocumentSlashAction.heading1:
          documentCommands.setHeading1(lineStart: session.lineStart);
        case DocumentSlashAction.heading2:
          documentCommands.setHeading2(lineStart: session.lineStart);
        case DocumentSlashAction.heading3:
          documentCommands.setHeading3(lineStart: session.lineStart);
        case DocumentSlashAction.bullet:
          documentCommands.toggleBulletList(lineStart: session.lineStart);
        case DocumentSlashAction.ordered:
          documentCommands.toggleOrderedList(lineStart: session.lineStart);
        case DocumentSlashAction.checklist:
          documentCommands.toggleChecklist(lineStart: session.lineStart);
        case DocumentSlashAction.quote:
          documentCommands.toggleQuote(lineStart: session.lineStart);
        case DocumentSlashAction.divider:
          documentCommands.insertDivider(at: at);
        case DocumentSlashAction.subtask:
          documentCommands.insertSubtaskBlock(at: at);
        case DocumentSlashAction.tag:
          openPicker = profile.onOpenTags;
        case DocumentSlashAction.relation:
          openPicker = profile.onOpenRelation;
        case DocumentSlashAction.attachment:
          attach = true;
        case DocumentSlashAction.deadline:
          openPicker = profile.onOpenDeadline;
        case DocumentSlashAction.focus:
          openFocus = profile.onOpenFocus;
      }
      final insertedBlock = action == DocumentSlashAction.divider ||
          action == DocumentSlashAction.subtask;
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
    await documentCommands.insertLink(
      pickUrl: () => showDialog<String>(
        context: context,
        builder: (context) => const _DocumentLinkDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final profile = widget.profile;
    final capabilities = profile.capabilities;
    _scheduleFormattingToolbarSync();
    final textStyle = DocumentStyles.body(tokens);
    final panels = capabilities.contains(EditorCapability.trailingPanels)
        ? profile.buildTrailingPanels(context)
        : const <Widget>[];
    return LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _focusDocumentEnd,
            child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.minHeight),
                child: Column(
                  key: profile.surfaceKey,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    quill.QuillEditor(
                      key: profile.bodyKey,
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
                              const _EditorEscapeIntent(),
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
                          _EditorEscapeIntent:
                              CallbackAction<_EditorEscapeIntent>(
                            onInvoke: (_) {
                              if (dismissSlashMenu()) return null;
                              if (dismissSelectionToolbar()) return null;
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
                        // A profile that owns its pane fills it, so the blank
                        // area under the last line is part of the canvas — that
                        // is how a click below a task's prose lands in the task.
                        // A document inside a scrolling page stays at its floor
                        // instead, and the page routes clicks in the blank space
                        // back here: filling the pane would drag everything that
                        // follows the prose — panels, related tasks — down with
                        // it. See [EditorProfile.expandsToViewport].
                        minHeight: profile.expandsToViewport && panels.isEmpty
                            ? math.max(profile.documentMinHeight,
                                constraints.minHeight)
                            : profile.documentMinHeight,
                        padding: EdgeInsets.only(
                            bottom: profile.documentBottomPadding),
                        placeholder: profile.placeholder,
                        textCapitalization: profile.textCapitalization,
                        customStyles: DocumentStyles.build(
                          tokens,
                          base: textStyle,
                          paragraphBottom: profile.paragraphGap,
                          placeholderBottom: profile.paragraphGap,
                        ),
                        customStyleBuilder:
                            DocumentStyles.customStyleBuilder(tokens),
                        embedBuilders: profile.buildEmbeds(context),
                      ),
                    ),
                    ...panels,
                  ],
                ))));
  }
}

class _EditorEscapeIntent extends Intent {
  const _EditorEscapeIntent();
}

/// Asks for a URL and returns it, or null when the user cancels.
///
/// The dialog owns its text controller: the modal route outlives the `await`
/// on its result by one transition, so a controller disposed by the caller
/// would be read by the closing frame. The field keys come from the profile so
/// each document type stays addressable in tests.
class _DocumentLinkDialog extends StatefulWidget {
  const _DocumentLinkDialog();

  @override
  State<_DocumentLinkDialog> createState() => _DocumentLinkDialogState();
}

class _DocumentLinkDialogState extends State<_DocumentLinkDialog> {
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
          key: documentLinkInputKey,
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
              key: documentLinkApplyKey,
              onPressed: () => Navigator.of(context).pop(input.text.trim()),
              child: const Text('应用')),
        ],
      );
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
