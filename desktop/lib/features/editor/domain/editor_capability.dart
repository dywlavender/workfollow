/// The entry points a document editor can load for one document type.
///
/// The editor core never asks what kind of document it is editing. It asks its
/// [EditorProfile] which capabilities are available and loads only those, so a
/// new document type is a new profile rather than a new branch inside the
/// editor.
///
/// The enum only carries capabilities the core itself has to decide on. The
/// vocabulary a document adds *inside* those entry points — its block palette
/// entries, its embeds, its under-prose panels — travels as profile data, since
/// the core renders whatever the profile hands it without inspecting it.
enum EditorCapability {
  /// `/` opens the block command palette.
  slashPalette,

  /// The core owns the floating formatting strip and its overlay lifecycle.
  formattingToolbar,

  /// The profile renders panels between the prose and the end of the document.
  trailingPanels,
}
