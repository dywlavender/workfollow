import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../../models/rich_document.dart';
import '../../../models/task.dart';
import '../../../state/workspace_controller.dart';
import '../../../theme/workfollow_icons.dart';
import '../../../theme/workfollow_surface_tokens.dart';
import '../../../theme/workfollow_theme.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/task_children_panel.dart';
import '../document_slash_menu.dart';
import '../domain/document_selection_action.dart';
import '../domain/editor_capability.dart';
import '../domain/editor_profile.dart';

/// The task document: a Quill body that projects back to the task's plain text
/// for lists and search, plus the panels and blocks a task adds around it.
///
/// Everything task-specific lives here — the subtask block, the source-note
/// relation, the attachment and property entry points. The editor core only
/// sees a profile.
///
/// It extends [EditorProfile] rather than implementing it so the shared
/// Delta-to-document conversion with its malformed-input fallback is inherited
/// instead of repeated per document type.
class TaskEditorProfile extends EditorProfile {
  TaskEditorProfile({
    required this.task,
    required this.controller,
    this.onAddChildTask,
    this.onOpenTags,
    this.onOpenRelation,
    this.onOpenDeadline,
  });

  final TaskItem task;
  final WorkspaceController controller;

  /// Creates a real child task under [task]. Wired by the owning inspector;
  /// the editor only reports the intent (slash palette → 添加子任务).
  final VoidCallback? onAddChildTask;

  final Future<void> Function(BuildContext anchor)? onOpenTags;
  final Future<void> Function(BuildContext anchor)? onOpenRelation;
  final Future<void> Function(BuildContext anchor)? onOpenDeadline;

  @override
  String get documentId => task.id;

  @override
  Object get documentHost => controller;

  @override
  Set<EditorCapability> get capabilities => const {
        EditorCapability.slashPalette,
        EditorCapability.formattingToolbar,
        EditorCapability.trailingPanels,
      };

  @override
  List<dynamic> get ownedDelta => taskDocumentDelta(task);

  @override
  void persist(List<dynamic> delta, String plainText) => controller.taskActions
      .setContent(task.id, richContentFromDelta(delta), plainText);

  @override
  String get placeholder => '添加描述，输入 / 插入内容';

  @override
  TextCapitalization get textCapitalization => TextCapitalization.sentences;

  @override
  double get documentMinHeight => TaskDocumentMetrics.documentMinHeight;

  /// The inspector gives the document a fixed pane and no scrolling page of its
  /// own: the pane is the canvas, so a click below the last line is a click in
  /// the description. The fill only applies while nothing follows the prose —
  /// with a subtask or attachment panel under it, the panel is what sits below
  /// the last line.
  @override
  bool get expandsToViewport => true;

  @override
  double get documentBottomPadding => WorkFollowSpacing.space5;

  @override
  double get paragraphGap => WorkFollowSpacing.editorParagraphGap;

  /// The child's palette: the same commands, minus the one a child cannot run.
  ///
  /// The hierarchy allows a single level, and that rule is enforced in the
  /// inspector (`TaskInspector._addChildTask` returns early for a child), not
  /// here. A palette that still offered 子任务 would be a command that opens,
  /// closes and does nothing — the second silent no-op this feature has had,
  /// so the rule is stated where the command is offered instead.
  static const List<DocumentSlashAction> childSlashActions =
      <DocumentSlashAction>[
    ...DocumentSlashMenu.textActions,
    DocumentSlashAction.attachment,
    DocumentSlashAction.tag,
    DocumentSlashAction.relation,
  ];

  /// The full palette, or [childSlashActions] under a child.
  ///
  /// `null` is not "no commands": the core reads it as its own default set —
  /// eight text commands, then attachment → subtask → tag → relation.
  /// `deadline` and `focus` are reachable from the row context menu and the
  /// inspector's property rows, so they are not palette entries.
  @override
  List<DocumentSlashAction>? get slashActions =>
      task.isChildTask ? childSlashActions : null;

  @override
  List<quill.EmbedBuilder> buildEmbeds(BuildContext context) => [
        TaskDocumentBlockBuilder(task: task, controller: controller),
      ];

  @override
  List<Widget> buildTrailingPanels(BuildContext context) {
    final hasAttachmentBlock = _hasBlock(task, 'attachment');
    return [
      // The child list joins the trailing stack only once it has content, so
      // an empty parent keeps the full-height prose surface. First children
      // come from the More menu, the row context menu or the slash palette.
      if (!task.isChildTask && controller.childrenOf(task.id).isNotEmpty)
        TaskChildrenPanel(task: task, controller: controller),
      if (task.attachments.isNotEmpty && !hasAttachmentBlock)
        TaskAttachmentsPanel(
            task: task,
            controller: controller,
            onAttach: () => unawaited(controller.attachFileToTask(task.id))),
      if (controller.sourceNoteFor(task.id) != null &&
          !_hasBlock(task, 'relation'))
        TaskSourceNotePanel(task: task, controller: controller),
    ];
  }

  @override
  List<DocumentSelectionAction> get selectionActions => const [];

  @override
  Future<String?> pickAttachment() => controller.pickTaskAttachment(task.id);

  @override
  Key get bodyKey => const ValueKey('task-document-editor');

  @override
  Key get surfaceKey => const ValueKey('task-document-surface');
}

/// Whether the document already carries a block of [type], including one
/// nested inside another block's content.
bool _hasBlock(TaskItem task, String type) {
  final content = task.contentJson?['content'];
  if (content is! List) return false;
  for (final block in content.whereType<Map>()) {
    if (block['type'] == type) return true;
    final nested = block['content'];
    if (nested is List &&
        nested.whereType<Map>().any((item) => item['type'] == type)) {
      return true;
    }
  }
  return false;
}

/// Renders WorkFollow-specific blocks inside a task document.
class TaskDocumentBlockBuilder extends quill.EmbedBuilder {
  const TaskDocumentBlockBuilder(
      {required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  String get key => 'workfollow-block';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final raw = embedContext.node.value.data.toString();
    Map<String, dynamic> node;
    try {
      node = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on Object {
      return const SizedBox.shrink();
    }
    return switch (node['type']) {
      'horizontalRule' => Divider(
          key: const ValueKey('task-horizontal-rule'),
          color: WorkFollowTheme.of(context).borderStrong,
          height: TaskEditorMetrics.horizontalRuleHeight),
      'attachment' =>
        _TaskAttachmentBlock(node: node, task: task, controller: controller),
      'relation' => TaskSourceNotePanel(task: task, controller: controller),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The attachment records of a task, kept next to the prose rather than inside
/// the Delta when they predate the attachment block.
class TaskAttachmentsPanel extends StatelessWidget {
  const TaskAttachmentsPanel(
      {super.key, required this.task, required this.controller, this.onAttach});

  final TaskItem task;
  final WorkspaceController controller;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      key: const ValueKey('task-attachments-block'),
      padding: const EdgeInsets.only(top: WorkFollowSpacing.headingGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('附件与关联',
              style: TextStyle(
                  fontSize: WorkFollowMacTypography.sectionTitle,
                  height: WorkFollowMacTypography.lineControl,
                  fontWeight: WorkFollowMacWeight.semibold,
                  color: tokens.textPrimary)),
          const SizedBox(height: WorkFollowSpacing.compactGap),
          Wrap(
            spacing: WorkFollowSpacing.compactGap,
            runSpacing: WorkFollowSpacing.space1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final file in task.attachments)
                InputChip(
                  label: Text(file,
                      style: const TextStyle(
                          fontSize: WorkFollowMacTypography.control,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.regular)),
                  avatar: const AppIcon(WorkFollowIcons.file,
                      size: WorkFollowMetrics.metadataIcon),
                  onPressed: () => controller.revealAttachment(task.id, file),
                  onDeleted: () => controller.removeAttachment(task.id, file),
                ),
              TextButton.icon(
                  key: const ValueKey('task-attach-file'),
                  onPressed:
                      onAttach ?? () => controller.attachFileToTask(task.id),
                  icon: AppIcon(WorkFollowIcons.attachment,
                      size: WorkFollowMetrics.compactFieldIcon,
                      color: tokens.accent),
                  label: const Text('添加附件',
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.control,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.medium))),
            ],
          ),
        ],
      ),
    );
  }
}

/// The note a task was created from, so the document keeps its provenance
/// without a second navigation step.
class TaskSourceNotePanel extends StatelessWidget {
  const TaskSourceNotePanel(
      {super.key, required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final source = controller.sourceNoteFor(task.id);
    if (source == null) return const SizedBox.shrink();
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      key: const ValueKey('task-source-note'),
      padding: const EdgeInsets.only(top: WorkFollowSpacing.sectionGap),
      child: Material(
        color: tokens.accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
        child: InkWell(
          borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
          onTap: () => controller.openNote(source.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.cardInset,
                vertical: WorkFollowSpacing.space2),
            child: Row(children: [
              AppIcon(WorkFollowIcons.article,
                  size: WorkFollowMetrics.navigationIcon, color: tokens.accent),
              const SizedBox(width: WorkFollowSpacing.space2),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.listTitle,
                              height: WorkFollowMacTypography.lineList,
                              fontWeight: WorkFollowMacWeight.medium,
                              color: tokens.textPrimary)),
                      Text('来自笔记 · ${source.folder}',
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.listMeta,
                              height: WorkFollowMacTypography.lineControl,
                              fontWeight: WorkFollowMacWeight.regular,
                              color: tokens.textTertiary)),
                    ]),
              ),
              AppIcon(WorkFollowIcons.chevronNext,
                  size: WorkFollowMetrics.navigationIcon,
                  color: tokens.textTertiary),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TaskAttachmentBlock extends StatelessWidget {
  const _TaskAttachmentBlock(
      {required this.node, required this.task, required this.controller});

  final Map<String, dynamic> node;
  final TaskItem task;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final attrs = node['attrs'] is Map
        ? Map<String, dynamic>.from(node['attrs'] as Map)
        : const <String, dynamic>{};
    final filename =
        attrs['localFile']?.toString() ?? attrs['name']?.toString();
    final tokens = WorkFollowTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: ValueKey('task-attachment-${filename ?? 'file'}'),
        onPressed: filename == null
            ? null
            : () => controller.revealAttachment(task.id, filename),
        icon: AppIcon(WorkFollowIcons.file,
            size: WorkFollowMetrics.navigationIcon, color: tokens.accent),
        label: Text(attrs['name']?.toString() ?? '附件',
            style: const TextStyle(
                fontSize: WorkFollowMacTypography.control,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.regular)),
      ),
    );
  }
}
