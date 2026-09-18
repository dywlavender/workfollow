import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../document_slash_menu.dart';
import 'document_selection_action.dart';
import 'editor_capability.dart';

/// Everything the document editor core needs from the document it is editing.
///
/// The core owns the editor state machine: the Quill controller, the slash
/// invocation, the formatting strip, the link dialog, the escape chain and the
/// persistence handoff. A profile supplies the parts that belong to a document
/// type — its Delta, its palette vocabulary, its embeds, its under-prose
/// panels and its selection actions — and the core renders them without ever asking
/// which type it is holding.
///
/// Implementations are rebuilt on every editor build, so they must be cheap
/// value objects over data the data layer already owns. They must not create
/// controllers or focus nodes in a getter; anything stateful belongs to the
/// owning widget, which then hands it in.
abstract class EditorProfile {
  /// Identity of the document. A change replaces the live Quill document after
  /// the current frame, which is how a task switch or a note switch drops the
  /// previous document without the core knowing what a task or a note is.
  String get documentId;

  /// The object that owns the data layer behind this document. The core only
  /// compares it for identity, to notice that the whole store was replaced.
  Object get documentHost;

  /// Which entry points the core loads. See [EditorCapability].
  Set<EditorCapability> get capabilities;

  /// The Delta the data layer currently owns for [documentId].
  List<dynamic> get ownedDelta;

  /// Writes an editor change back to the data layer. The core calls this for
  /// every structural change and never for a keystroke that produced the same
  /// Delta, so implementations can forward it to their normal action boundary.
  void persist(List<dynamic> delta, String plainText);

  /// Builds the live Quill document. A malformed Delta degrades to an empty
  /// document instead of taking the editor down.
  quill.Document buildDocument() {
    try {
      return quill.Document.fromJson(ownedDelta);
    } on Object {
      return quill.Document();
    }
  }

  /// Placeholder shown while the document has no content.
  String get placeholder;

  /// Autocapitalisation policy for the document's text input.
  TextCapitalization get textCapitalization;

  /// Height the document reserves when no trailing panel follows it.
  double get documentMinHeight;

  /// Whether the document's canvas grows to the height it was handed, so the
  /// blank space under the last line belongs to the editor.
  ///
  /// A task's detail pane *is* its document: the pane has one height, the area
  /// below the prose is the same canvas, and a click there puts the caret back
  /// in the task. A note lives inside a scrolling page — its prose is
  /// content-height and the page owns everything under it, so the sections that
  /// follow the prose have to follow the text rather than a fixed position in
  /// the pane. That difference is the whole reason this is a profile decision
  /// and not a constant: `documentMinHeight` is the *document's* floor, and
  /// stretching it to the viewport is a property of the host, not of prose.
  bool get expandsToViewport;

  /// Padding below the last line, before a trailing panel or the shell.
  double get documentBottomPadding;

  /// Vertical rhythm between paragraphs, placeholders and list lines.
  double get paragraphGap;

  /// Palette entries for `/`, or null for the full shared palette.
  List<DocumentSlashAction>? get slashActions;

  /// Block and image embeds this document can render.
  List<quill.EmbedBuilder> buildEmbeds(BuildContext context);

  /// Panels rendered between the prose and the end of the document. Empty when
  /// the document type keeps everything inside the Quill document itself.
  List<Widget> buildTrailingPanels(BuildContext context);

  /// Actions shown beside a non-collapsed selection. The editor core owns the
  /// floating surface and its lifecycle; a profile only supplies the semantic
  /// actions valid for its document type.
  List<DocumentSelectionAction> get selectionActions;

  /// Requests a file for an attachment block. A null result is a cancelled
  /// picker and leaves the document untouched.
  /// Creates a child task for this document's owner. Only task documents
  /// provide it; other profiles leave it null and the palette entry no-ops.
  void Function()? get onAddChildTask => null;

  Future<String?> pickAttachment();

  /// Picker entry points for the palette commands the core does not implement
  /// itself. A null callback means the document type does not offer that
  /// command, which its [slashActions] already reflects.
  Future<void> Function(BuildContext anchor)? get onOpenTags;
  Future<void> Function(BuildContext anchor)? get onOpenRelation;
  Future<void> Function(BuildContext anchor)? get onOpenDeadline;

  /// Keys that address this document type's own surfaces: its body editor and
  /// the surface that accepts clicks below the last line.
  ///
  /// Keys of shared widgets — the formatting trigger, the link dialog — are
  /// not here: those identify one affordance across every document type and
  /// live in `document_keys.dart`.
  Key get bodyKey;
  Key get surfaceKey;
}
