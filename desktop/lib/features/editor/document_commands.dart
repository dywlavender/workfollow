import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../theme/workfollow_color_tokens.dart';

/// Supplies a file path for a document attachment command.
typedef DocumentAttachmentPicker = Future<String?> Function();

/// Lets an editor owner restore focus after a document command.
typedef DocumentFocusRequester = void Function();

/// Prevents an asynchronous picker from mutating a disposed document owner.
typedef DocumentMutationGuard = bool Function();

/// The single mutation boundary for a Quill task (or note) document.
///
/// Menus and toolbars decide which command the user selected. They do not
/// format a controller or construct embeds themselves. Keeping that work in
/// one object means a heading selected from `/` has the same Delta and the
/// same insertion/focus behaviour as a heading selected from the toolbar.
class DocumentCommands {
  DocumentCommands({
    required this.editor,
    this.pickAttachment,
    this.requestFocus,
    this.canMutate,
  });

  /// Stored in existing Deltas for compatibility. Rendering resolves the
  /// attribute to the current semantic document highlight surface.
  static const highlightColor =
      WorkFollowColorTokens.documentHighlightAttribute;

  final quill.QuillController editor;
  final DocumentAttachmentPicker? pickAttachment;
  final DocumentFocusRequester? requestFocus;
  final DocumentMutationGuard? canMutate;

  /// The header level shared by the heading picker and its active state.
  int? get headingLevel {
    final value = editor
        .getSelectionStyle()
        .attributes[quill.Attribute.header.key]
        ?.value;
    return value is num
        ? value.toInt()
        : value is int
            ? value
            : null;
  }

  /// Returns whether [attribute] is active at the current selection.
  ///
  /// Quill represents both checked and unchecked checklists with the `list`
  /// attribute. The unchecked toolbar control therefore treats either value
  /// as active, matching Quill's own checklist button semantics.
  bool isActive(quill.Attribute attribute) {
    final value = editor.getSelectionStyle().attributes[attribute.key]?.value;
    return value == attribute.value ||
        (attribute == quill.Attribute.unchecked &&
            value == quill.Attribute.checked.value);
  }

  void setParagraph({int? lineStart}) =>
      _setBlock(quill.Attribute.clone(quill.Attribute.header, null), lineStart);

  void setHeading1({int? lineStart}) =>
      _setBlock(quill.Attribute.h1, lineStart);

  void setHeading2({int? lineStart}) =>
      _setBlock(quill.Attribute.h2, lineStart);

  void setHeading3({int? lineStart}) =>
      _setBlock(quill.Attribute.h3, lineStart);

  /// Sets a heading level, where null means a normal paragraph.
  void setHeading(int? level, {int? lineStart}) {
    _setBlock(quill.Attribute.clone(quill.Attribute.header, level), lineStart);
  }

  void toggleBulletList({int? lineStart}) =>
      _toggleBlock(quill.Attribute.ul, lineStart: lineStart);

  void toggleOrderedList({int? lineStart}) =>
      _toggleBlock(quill.Attribute.ol, lineStart: lineStart);

  /// Toggles a checklist at the current selection. A slash invocation passes
  /// its captured line start, which creates an unchecked item on that line;
  /// the toolbar omits the line start and toggles the existing item in place.
  void toggleChecklist({int? lineStart}) {
    if (lineStart != null) {
      _setBlock(quill.Attribute.unchecked, lineStart);
      return;
    }
    _toggleBlock(quill.Attribute.unchecked);
  }

  void toggleQuote({int? lineStart}) =>
      _toggleBlock(quill.Attribute.blockQuote, lineStart: lineStart);

  void toggleBold() => toggleAttribute(quill.Attribute.bold);

  void toggleItalic() => toggleAttribute(quill.Attribute.italic);

  void toggleUnderline() => toggleAttribute(quill.Attribute.underline);

  void toggleStrike() => toggleAttribute(quill.Attribute.strikeThrough);

  void toggleHighlight() =>
      toggleAttribute(const quill.BackgroundAttribute(highlightColor));

  void toggleInlineCode() => toggleAttribute(quill.Attribute.inlineCode);

  /// Toggles an inline attribute supplied by an entry layer.
  ///
  /// The named methods above are preferred for the standard toolbar. This
  /// method keeps the command boundary useful for a custom document surface
  /// without exposing controller mutation to that surface.
  void toggleAttribute(quill.Attribute attribute) {
    if (!_isUsable) return;
    editor.formatSelection(isActive(attribute)
        ? quill.Attribute.clone(attribute, null)
        : attribute);
  }

  /// Replaces the current selection with text and restores the caret after it.
  void insertText(String value) {
    if (value.isEmpty || !_isUsable) return;
    final selection = editor.selection;
    final start = _selectionStart(selection);
    final end = _selectionEnd(selection, start);
    editor.replaceText(
      start,
      end - start,
      value,
      TextSelection.collapsed(offset: start + value.length),
    );
    requestFocus?.call();
  }

  /// Inserts the slash trigger through the same text insertion path as time
  /// and other textual toolbar commands.
  void insertSlash() => insertText('/');

  /// Inserts a WorkFollow block embed at [at], or at the current caret.
  /// Returns the actual insertion offset so an owner can restore a caret when
  /// it is coordinating a larger interaction such as the slash palette.
  int insertBlock(Map<String, dynamic> node, {int? at}) {
    final insertAt = _insertOffset(at);
    if (!_isUsable) return insertAt;
    editor.replaceText(
      insertAt,
      0,
      quill.BlockEmbed('workfollow-block', jsonEncode(node)),
      TextSelection.collapsed(offset: insertAt + 1),
    );
    requestFocus?.call();
    return insertAt;
  }

  void insertDivider({int? at}) =>
      insertBlock({'type': 'horizontalRule'}, at: at);

  /// Inserts the relation block used by the task source-note panel.
  void insertRelation(String noteId, {int? at}) => insertBlock(
        {
          'type': 'relation',
          'attrs': {'noteId': noteId},
        },
        at: at,
      );

  /// Requests and inserts an attachment while retaining the caller's offset.
  /// A cancelled picker is a no-op and returns false.
  Future<bool> insertAttachment({int? at}) async {
    final picker = pickAttachment;
    if (picker == null) return false;
    final filename = await picker();
    if (!_isUsable || filename == null || filename.isEmpty) return false;
    insertBlock(
      {
        'type': 'attachment',
        'attrs': {'name': filename, 'localFile': filename},
      },
      at: at,
    );
    return true;
  }

  /// Opens a URL picker supplied by the owning surface and applies the link
  /// mutation here. The picker is UI; applying the link is a document command.
  Future<bool> insertLink({required Future<String?> Function() pickUrl}) async {
    final url = await pickUrl();
    if (url == null || url.trim().isEmpty) return false;
    return applyLink(url.trim());
  }

  /// Applies a link to the selection, or inserts linked text at a collapsed
  /// caret. This is shared by task and note link dialogs.
  bool applyLink(String url) {
    final value = url.trim();
    if (value.isEmpty || !_isUsable) return false;
    final selection = editor.selection;
    if (selection.isCollapsed) {
      final at = _selectionStart(selection);
      editor.replaceText(
        at,
        0,
        value,
        TextSelection.collapsed(offset: at + value.length),
      );
      editor.formatText(at, value.length, quill.LinkAttribute(value));
    } else {
      final start = _selectionStart(selection);
      final end = _selectionEnd(selection, start);
      editor.formatText(start, end - start, quill.LinkAttribute(value));
    }
    requestFocus?.call();
    return true;
  }

  /// Removes a range, used by the slash owner after it has captured the
  /// command session. The slash lifecycle stays in the editor; the mutation
  /// still goes through this command boundary.
  void deleteRange(int start, int length) {
    if (length <= 0 || !_isUsable) return;
    final max = _maxContentOffset;
    final safeStart = start.clamp(0, max).toInt();
    final safeLength = math.min(length, max - safeStart);
    if (safeLength <= 0) return;
    editor.replaceText(
      safeStart,
      safeLength,
      '',
      TextSelection.collapsed(offset: safeStart),
    );
  }

  void _setBlock(quill.Attribute attribute, int? lineStart) {
    if (!_isUsable) return;
    if (lineStart == null) {
      editor.formatSelection(attribute);
      return;
    }
    _formatLine(lineStart, attribute);
  }

  void _toggleBlock(quill.Attribute attribute, {int? lineStart}) {
    if (lineStart != null) {
      _formatLine(lineStart, attribute);
      return;
    }
    toggleAttribute(attribute);
  }

  /// Applies a block attribute to the line at [lineStart], and to no other.
  ///
  /// The range stops at the line's own newline instead of one past it. Quill
  /// resolves a block attribute onto every newline inside the range, and then
  /// onto the first newline beyond it — that second pass is what lets a
  /// caret-only format land on the caret's line, and it is also why a range
  /// ending past the newline marks the line below as well. Stopping short
  /// leaves that second pass to mark this line, which is how the toolbar path
  /// already behaved; asking for both marked two lines, so one 检查项 drew a
  /// box on its own line and an empty one under it.
  void _formatLine(int lineStart, quill.Attribute attribute) {
    if (!_isUsable) return;
    final text = editor.document.toPlainText();
    if (text.isEmpty) return;
    final start = lineStart.clamp(0, text.length - 1).toInt();
    final endIndex = text.indexOf('\n', start);
    // No newline at all means the line runs to the end of the document.
    final end = endIndex < 0 ? text.length : endIndex;
    final length = (end - start).clamp(0, text.length - start).toInt();
    editor.formatText(start, length, attribute);
  }

  int get _maxContentOffset => math.max(0, editor.document.length - 1);

  bool get _isUsable => canMutate?.call() ?? true;

  int _insertOffset(int? requested) =>
      (requested ?? editor.selection.baseOffset)
          .clamp(0, _maxContentOffset)
          .toInt();

  int _selectionStart(TextSelection selection) =>
      selection.start.clamp(0, _maxContentOffset).toInt();

  int _selectionEnd(TextSelection selection, int start) =>
      selection.end.clamp(start, _maxContentOffset).toInt();
}
