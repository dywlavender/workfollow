import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// An action offered next to a non-collapsed document selection.
///
/// Selection actions belong to an editor profile, but the editor core owns
/// where they are rendered and when they disappear. This keeps a note-only
/// action such as “创建任务” out of the document's permanent footer.
class DocumentSelectionAction {
  const DocumentSelectionAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onInvoke,
  });

  final String id;
  final String label;
  final IconData icon;
  final void Function(BuildContext context, quill.QuillController editor)
      onInvoke;
}
