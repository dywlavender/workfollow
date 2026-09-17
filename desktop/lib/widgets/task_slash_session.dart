import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Immutable state for one slash invocation.
///
/// A session belongs to the inserted `/`, not to whatever line happens to be
/// under the caret later. Keeping the detection here makes the editor's
/// lifecycle explicit and gives tests a pure boundary for the offset rules.
class SlashCommandSession {
  const SlashCommandSession({
    required this.slashOffset,
    required this.lineStart,
    required this.originalSelection,
  });

  final int slashOffset;
  final int lineStart;
  final TextSelection originalSelection;

  /// Detects a single `/` insertion at the current collapsed caret.
  ///
  /// Comparing the previous and current plain text avoids opening a palette
  /// when the caret is merely moved into an existing `foo/`. It also handles
  /// replacing a selected range with `/`, which is a normal editor edit rather
  /// than a special case in the widget.
  static SlashCommandSession? fromInsertion({
    required String previousText,
    required String text,
    required TextSelection selection,
  }) {
    if (!selection.isCollapsed) return null;
    final slashOffset = selection.extentOffset - 1;
    if (slashOffset < 0 || slashOffset >= text.length) return null;
    if (text[slashOffset] != '/') return null;

    var prefix = 0;
    final common = math.min(previousText.length, text.length);
    while (prefix < common && previousText[prefix] == text[prefix]) {
      prefix++;
    }
    var oldEnd = previousText.length - 1;
    var newEnd = text.length - 1;
    while (oldEnd >= prefix &&
        newEnd >= prefix &&
        previousText[oldEnd] == text[newEnd]) {
      oldEnd--;
      newEnd--;
    }
    final inserted = newEnd < prefix ? '' : text.substring(prefix, newEnd + 1);
    if (inserted != '/' || prefix != slashOffset) return null;

    final lineStart = slashOffset == 0
        ? 0
        : text.lastIndexOf('\n', slashOffset - 1) + 1;
    return SlashCommandSession(
      slashOffset: slashOffset,
      lineStart: lineStart,
      originalSelection: selection,
    );
  }
}
