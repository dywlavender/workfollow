import 'package:flutter/material.dart';

import '../features/editor/presentation/document_editor.dart';
import '../features/editor/profiles/note_editor_profile.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';

export '../features/editor/presentation/document_editor.dart' show DocumentEditorState;
export '../features/editor/profiles/note_editor_profile.dart';

/// A note body.
///
/// Notes and tasks edit the same document with the same commands; what differs
/// is the profile. A note carries images and a footer action that turns a
/// highlighted paragraph into a task, and it carries none of the task blocks —
/// a note is where work is described, not where it is tracked.
class NoteDocumentEditor extends StatelessWidget {
  const NoteDocumentEditor(
      {super.key,
      required this.note,
      required this.controller,
      this.editorKey,
      this.onToolbarChanged});

  final NoteItem note;
  final WorkspaceController controller;

  /// Handle on the shared editor, for chrome that lives outside the prose.
  ///
  /// The note page owns the formatting trigger — it sits in the bottom status
  /// row rather than under the document — so the page needs a way to open the
  /// toolbar popover and to read back whether it is currently up.
  final GlobalKey<DocumentEditorState>? editorKey;

  /// Fires when the formatting toolbar opens or closes, so the page can repaint
  /// the trigger's active state.
  final ValueChanged<bool>? onToolbarChanged;

  @override
  Widget build(BuildContext context) => DocumentEditor(
        key: editorKey,
        profile: NoteEditorProfile(note: note, controller: controller),
        onToolbarChanged: onToolbarChanged,
      );
}
