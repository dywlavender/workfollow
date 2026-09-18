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
      {super.key, required this.note, required this.controller});

  final NoteItem note;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => DocumentEditor(
        profile: NoteEditorProfile(note: note, controller: controller),
      );
}
