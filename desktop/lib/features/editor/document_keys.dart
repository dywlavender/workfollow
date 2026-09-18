import 'package:flutter/widgets.dart';

/// Keys of the widgets every document shares.
///
/// Each of these identifies one affordance — the formatting trigger, the link
/// dialog's field and its apply button — so it does not vary by document type.
/// A task inspector and a note page render the same trigger and the same
/// dialog, and a test that targets one of them should not have to know which
/// document is on screen.
///
/// Keys that address a document type's own surface — its body editor, its
/// surface, its blocks — stay on that type's profile instead.
const documentFormattingToggleKey = ValueKey('document-format-toggle');
const documentLinkInputKey = ValueKey('document-link-input');
const documentLinkApplyKey = ValueKey('document-link-apply');
