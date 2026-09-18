import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../features/editor/document_commands.dart';
import '../features/editor/presentation/document_editor.dart';
import '../features/editor/profiles/task_editor_profile.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';

export '../features/editor/document_commands.dart';
export '../features/editor/document_styles.dart';
export '../features/editor/profiles/task_editor_profile.dart';
export '../features/editor/slash_command_session.dart';

/// A document-first editor for a task.
///
/// Title editing remains a normal field; everything below it is a Quill
/// document whose Delta is persisted as the task's structured content and
/// projected back to plain text for lists and search. The editing mechanics
/// come from [DocumentEditor]; this widget adds the task's shell contract —
/// the block insertions the inspector's More menu asks for, and the inline
/// subtask input that the task profile renders.
class TaskDocumentEditor extends StatefulWidget {
  const TaskDocumentEditor({
    super.key,
    required this.task,
    required this.controller,
    this.onOpenTags,
    this.onOpenRelation,
    this.onOpenDeadline,
    this.onToolbarChanged,
    this.onEscape,
  });

  final TaskItem task;
  final WorkspaceController controller;
  final Future<void> Function(BuildContext anchor)? onOpenTags;
  final Future<void> Function(BuildContext anchor)? onOpenRelation;
  final Future<void> Function(BuildContext anchor)? onOpenDeadline;
  final ValueChanged<bool>? onToolbarChanged;
  final VoidCallback? onEscape;

  @override
  TaskDocumentEditorState createState() => TaskDocumentEditorState();
}

class TaskDocumentEditorState extends State<TaskDocumentEditor> {
  /// The shared editor. The inspector holds this widget's state, so every
  /// document command it issues is forwarded to the core from here.
  final _delegate = GlobalKey<DocumentEditorState>();

  /// Owned by this widget rather than by the profile so it survives the
  /// profile being rebuilt on every frame.
  final subtaskInputFocus = FocusNode(debugLabel: 'subtask-input');

  TaskEditorProfile _profile() => TaskEditorProfile(
        task: widget.task,
        controller: widget.controller,
        subtaskInputFocus: subtaskInputFocus,
        onOpenTags: widget.onOpenTags,
        onOpenRelation: widget.onOpenRelation,
        onOpenDeadline: widget.onOpenDeadline,
      );

  quill.QuillController get editor => _delegate.currentState!.editor;

  /// The document's focus node. The inspector's Escape chain and its tests ask
  /// whether the caret is still in the document.
  FocusNode get focus => _delegate.currentState!.focus;

  /// Shared document command surface used by inspector entry points.
  DocumentCommands get commands => _delegate.currentState!.documentCommands;

  String get plainText => _delegate.currentState?.plainText ?? '';

  bool get toolbarVisible => _delegate.currentState?.toolbarVisible ?? false;

  bool dismissSlashMenu() =>
      _delegate.currentState?.dismissSlashMenu() ?? false;

  bool dismissFormattingToolbar() =>
      _delegate.currentState?.dismissFormattingToolbar() ?? false;

  Future<void> toggleToolbar(BuildContext anchor) async =>
      _delegate.currentState?.toggleToolbar(anchor);

  /// Inserts the subtask block and puts the caret in its input.
  ///
  /// A task that already has subtask records does not get a second block: the
  /// panel below the prose is already showing those records, and two editors
  /// for one set of records is how a document starts contradicting itself.
  void insertSubtasksBlock() {
    final delegate = _delegate.currentState;
    if (delegate == null) return;
    final profile = _profile();
    if (!profile.hasSubtaskBlock) {
      delegate.documentCommands.insertSubtaskBlock();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      profile.focusSubtaskInput();
    });
  }

  void insertRelationBlock(String noteId) =>
      _delegate.currentState?.documentCommands.insertRelation(noteId);

  Future<void> attachFile() async =>
      _delegate.currentState?.documentCommands.insertAttachment();

  @override
  void dispose() {
    subtaskInputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DocumentEditor(
        key: _delegate,
        profile: _profile(),
        onToolbarChanged: widget.onToolbarChanged,
        onEscape: widget.onEscape,
      );
}
