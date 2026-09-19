import 'package:flutter/material.dart';

import '../../../theme/workfollow_theme.dart';
import '../document_styles.dart';

/// The shared title input used by task and note document shells.
///
/// The host owns [controller] and [focusNode]. This widget only applies the
/// document-title interaction and visual contract, so a task switch or a note
/// switch cannot be hidden inside a reusable field.
class DocumentTitleEditor extends StatelessWidget {
  const DocumentTitleEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.fontSize,
    required this.onChanged,
    this.fieldKey,
    this.maxLines = 2,
    this.autofocus = false,
    this.muted = false,
    this.strikethrough = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final double fontSize;
  final ValueChanged<String> onChanged;

  /// Key for the underlying [TextField]. Keeping this separate from the
  /// component key preserves the existing task-title-editor and
  /// note-title-editor automation selectors.
  final Key? fieldKey;
  final int maxLines;
  final bool autofocus;
  final bool muted;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      minLines: 1,
      maxLines: maxLines,
      style: DocumentStyles.title(
        tokens,
        fontSize: fontSize,
        muted: muted,
        strikethrough: strikethrough,
      ),
      decoration: DocumentStyles.titleDecoration(placeholder,
          hintColor: WorkFollowTheme.of(context).textTertiary),
      onChanged: onChanged,
    );
  }
}
