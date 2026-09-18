import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../../models/note_document.dart';
import '../../../models/task.dart';
import '../../../state/workspace_controller.dart';
import '../../../theme/workfollow_icons.dart';
import '../../../theme/workfollow_theme.dart';
import '../../../widgets/app_icon_button.dart';
import '../../feedback/feedback_event.dart';
import '../../feedback/feedback_scope.dart';
import '../document_slash_menu.dart';
import '../domain/document_selection_action.dart';
import '../domain/editor_capability.dart';
import '../domain/editor_profile.dart';

/// The note document: free prose with images, and a selection action that turns
/// a highlighted paragraph into a task.
///
/// The relation to a task runs the other way here, which is why notes do not
/// carry the task blocks: a note is the source, not the destination.
class NoteEditorProfile extends EditorProfile {
  NoteEditorProfile({required this.note, required this.controller});

  final NoteItem note;
  final WorkspaceController controller;

  /// Document commands a note offers. The task-only entries (subtask, tag,
  /// relation) are absent because a note has no records to point at and no
  /// property rows to open.
  static const slashActionValues = <DocumentSlashAction>[
    DocumentSlashAction.heading1,
    DocumentSlashAction.heading2,
    DocumentSlashAction.heading3,
    DocumentSlashAction.bullet,
    DocumentSlashAction.ordered,
    DocumentSlashAction.checklist,
    DocumentSlashAction.quote,
    DocumentSlashAction.divider,
    DocumentSlashAction.attachment,
  ];

  @override
  String get documentId => note.id;

  @override
  Object get documentHost => controller;

  @override
  Set<EditorCapability> get capabilities => const {
        EditorCapability.slashPalette,
        EditorCapability.formattingToolbar,
      };

  @override
  List<dynamic> get ownedDelta => noteDocumentDelta(note);

  @override
  void persist(List<dynamic> delta, String plainText) => controller
      .updateNoteRichContent(note.id, noteContentFromDelta(delta), plainText);

  @override
  String get placeholder => '写下你的想法、会议记录或下一步行动…';

  /// A note body is an unguarded writing surface, so the first character is
  /// left exactly as typed.
  @override
  TextCapitalization get textCapitalization => TextCapitalization.none;

  @override
  double get documentMinHeight => NotesMetrics.editorContentMinHeight;

  /// The page scrolls, so the page owns the blank space under the prose.
  ///
  /// Inflating the document to reach the bottom of the pane is what used to
  /// strand the related-task list in the middle of a one-line note. The page
  /// routes clicks in that blank space back into the document instead — see
  /// `DocumentEditorState.focusEnd`.
  @override
  bool get expandsToViewport => false;

  @override
  double get documentBottomPadding => WorkFollowSpacing.space6;

  /// The note body spaces paragraphs one step looser than a task description,
  /// where the prose shares the inspector with property rows.
  @override
  double get paragraphGap => WorkFollowSpacing.space2;

  @override
  List<DocumentSlashAction>? get slashActions => slashActionValues;

  @override
  List<quill.EmbedBuilder> buildEmbeds(BuildContext context) => [
        NoteBlockBuilder(controller: controller),
        const NoteImageBuilder(),
      ];

  @override
  List<Widget> buildTrailingPanels(BuildContext context) => const [];

  @override
  List<DocumentSelectionAction> get selectionActions => [
        DocumentSelectionAction(
          id: 'create-task',
          label: '创建任务',
          icon: WorkFollowIcons.playlistAdd,
          onInvoke: _taskFromSelection,
        ),
      ];

  @override
  Future<String?> pickAttachment() => controller.pickNoteAttachment();

  /// A note has no property rows of its own, so the palette carries no entry
  /// point for tags, relations, deadlines or the focus timer.
  @override
  Future<void> Function(BuildContext anchor)? get onOpenTags => null;

  @override
  Future<void> Function(BuildContext anchor)? get onOpenRelation => null;

  @override
  Future<void> Function(BuildContext anchor)? get onOpenDeadline => null;

  @override
  VoidCallback? get onOpenFocus => null;

  @override
  Key get bodyKey => const ValueKey('note-body-editor');

  @override
  Key get surfaceKey => const ValueKey('note-document-surface');

  /// Creates a task from the highlighted range and offers to follow it. The new
  /// task lands in the inbox, so there is nothing to undo here — only a place
  /// to go next.
  void _taskFromSelection(BuildContext context, quill.QuillController editor) {
    if (editor.selection.isCollapsed) return;
    final body = editor.document.toPlainText();
    final start =
        math.min(editor.selection.baseOffset, editor.selection.extentOffset);
    final end =
        math.max(editor.selection.baseOffset, editor.selection.extentOffset);
    final text = body.substring(start, end).trim();
    if (text.isEmpty) return;
    final id = controller.addTaskFromNote(note.id, text);
    showFeedback(
        context,
        WorkFollowFeedback(
            kind: WorkFollowFeedbackKind.success,
            message: '已添加到收集箱',
            actionLabel: '查看任务',
            actionIcon: WorkFollowIcons.next,
            onAction: () => controller.openTask(id)));
  }
}

class NoteImageBuilder extends quill.EmbedBuilder {
  const NoteImageBuilder();

  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final source = embedContext.node.value.data.toString();
    Widget fallback(BuildContext _, Object error, StackTrace? stack) =>
        Container(
            padding: const EdgeInsets.all(WorkFollowSpacing.sectionGap),
            color: WorkFollowTheme.of(context).canvas,
            child: const Row(children: [
              AppIcon(WorkFollowIcons.brokenImage,
                  size: WorkFollowMetrics.navigationIcon),
              SizedBox(width: WorkFollowSpacing.xs),
              Text('图片暂时无法显示')
            ]));
    final image = source.startsWith('http://') || source.startsWith('https://')
        ? Image.network(source, fit: BoxFit.contain, errorBuilder: fallback)
        : source.startsWith('data:')
            ? Image.memory(UriData.parse(source).contentAsBytes(),
                errorBuilder: fallback)
            : Image.file(
                File(source.startsWith('file:')
                    ? Uri.parse(source).toFilePath()
                    : source),
                fit: BoxFit.contain,
                errorBuilder: fallback);
    return ConstrainedBox(
        constraints:
            const BoxConstraints(maxHeight: NotesMetrics.imageMaxHeight),
        child: image);
  }
}

/// Renders a note's own blocks: the hairline, an attachment, an imported table
/// and the generic imported content block the Web editor leaves behind.
class NoteBlockBuilder extends quill.EmbedBuilder {
  const NoteBlockBuilder({required this.controller});

  final WorkspaceController controller;

  @override
  String get key => 'workfollow-block';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = jsonDecode(embedContext.node.value.data.toString()) as Map;
    final tokens = WorkFollowTheme.of(context);
    if (node['type'] == 'horizontalRule')
      return Divider(
          color: tokens.borderStrong,
          height: TaskEditorMetrics.horizontalRuleHeight);
    if (node['type'] == 'attachment') {
      final attrs = node['attrs'] as Map;
      final filename = attrs['localFile']?.toString();
      return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
              key: ValueKey('note-attachment-${filename ?? 'file'}'),
              icon: const AppIcon(WorkFollowIcons.file,
                  size: WorkFollowMetrics.navigationIcon),
              label: Text(attrs['name']?.toString() ?? '附件'),
              onPressed: filename == null
                  ? null
                  : () => controller.revealWorkspaceAttachment(filename)));
    }
    if (node['type'] == 'table') {
      final rows = (node['content'] as List? ?? []).whereType<Map>().toList();
      final columns = rows.fold<int>(
          0,
          (max, row) => (row['content'] as List? ?? []).length > max
              ? (row['content'] as List).length
              : max);
      if (columns > 0)
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: columns * 170,
                child: Table(
                    border: TableBorder.all(color: tokens.border),
                    children: [
                      for (final row in rows)
                        TableRow(children: [
                          for (var i = 0; i < columns; i++)
                            Padding(
                                padding: const EdgeInsets.all(
                                    WorkFollowSpacing.cardInset),
                                child: SelectableText(
                                    i < (row['content'] as List).length
                                        ? notePlainTextFromContentJson(
                                                (row['content'] as List)[i])
                                            .trimRight()
                                        : '',
                                    style: TextStyle(
                                        fontSize:
                                            WorkFollowMacTypography.control,
                                        color: tokens.textPrimary))),
                        ]),
                    ])));
    }
    return Container(
        padding: const EdgeInsets.all(WorkFollowSpacing.space4),
        decoration: BoxDecoration(
            color: tokens.canvas,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(WorkFollowRadii.surface)),
        child: SelectableText(
            notePlainTextFromContentJson(node).trim().isEmpty
                ? '导入的内容块'
                : notePlainTextFromContentJson(node).trim(),
            style: TextStyle(
                fontSize: WorkFollowMacTypography.control,
                color: tokens.textSecondary)));
  }
}
