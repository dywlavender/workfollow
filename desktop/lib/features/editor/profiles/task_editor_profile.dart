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
import '../document_slash_menu.dart';
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
    required this.subtaskInputFocus,
    this.onOpenTags,
    this.onOpenRelation,
    this.onOpenDeadline,
    this.onOpenFocus,
  });

  final TaskItem task;
  final WorkspaceController controller;

  /// Focus target of the inline subtask input. The owning widget creates it so
  /// it outlives a profile rebuild and survives the panel being re-inserted.
  final FocusNode subtaskInputFocus;

  final Future<void> Function(BuildContext anchor)? onOpenTags;
  final Future<void> Function(BuildContext anchor)? onOpenRelation;
  final Future<void> Function(BuildContext anchor)? onOpenDeadline;
  final VoidCallback? onOpenFocus;

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

  @override
  double get documentBottomPadding => WorkFollowSpacing.space5;

  @override
  double get paragraphGap => WorkFollowSpacing.editorParagraphGap;

  /// The full palette: eight text commands, then attachment → subtask → tag →
  /// relation. `deadline` and `focus` are reachable from the row context menu
  /// and the inspector's property rows, so they are not palette entries.
  @override
  List<DocumentSlashAction>? get slashActions => null;

  @override
  List<quill.EmbedBuilder> buildEmbeds(BuildContext context) => [
        TaskDocumentBlockBuilder(
          subtaskFocus: subtaskInputFocus,
          task: task,
          controller: controller,
        ),
      ];

  @override
  List<Widget> buildTrailingPanels(BuildContext context) {
    final hasSubtaskBlock = _hasBlock(task, 'taskSubtasks');
    final hasAttachmentBlock = _hasBlock(task, 'attachment');
    return [
      if (task.subtasks.isNotEmpty && !hasSubtaskBlock)
        TaskSubtasksPanel(
            focusNode: subtaskInputFocus, task: task, controller: controller),
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

  /// The task footer lives in the inspector, next to the More menu, so the
  /// editor does not render one.
  @override
  Widget? buildFooterLeading(
    BuildContext context, {
    required quill.QuillController editor,
    required bool selectionPresent,
  }) =>
      null;

  @override
  Future<String?> pickAttachment() => controller.pickTaskAttachment(task.id);

  @override
  Key get bodyKey => const ValueKey('task-document-editor');

  @override
  Key get surfaceKey => const ValueKey('task-document-surface');

  /// Whether a subtask block is already part of the document, so inserting it
  /// again would produce a second editor for the same records.
  bool get hasSubtaskBlock =>
      _hasBlock(task, 'taskSubtasks') || task.subtasks.isNotEmpty;

  /// Brings the inline subtask input into view after the block was inserted.
  /// The record itself is written by [TaskSubtasksPanel]; this only reveals it.
  void focusSubtaskInput() {
    subtaskInputFocus.requestFocus();
    final inputContext = subtaskInputFocus.context;
    if (inputContext != null) {
      Scrollable.ensureVisible(inputContext, alignment: .5);
    }
  }
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
      {required this.task, required this.controller, this.subtaskFocus});

  final TaskItem task;
  final WorkspaceController controller;
  final FocusNode? subtaskFocus;

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
      'taskSubtasks' => TaskSubtasksPanel(
          focusNode: subtaskFocus,
          key: const ValueKey('task-subtasks-block'),
          task: task,
          controller: controller),
      'attachment' =>
        _TaskAttachmentBlock(node: node, task: task, controller: controller),
      'relation' => TaskSourceNotePanel(task: task, controller: controller),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The subtask records of a task, edited in place inside the document.
class TaskSubtasksPanel extends StatefulWidget {
  const TaskSubtasksPanel(
      {super.key,
      required this.task,
      required this.controller,
      this.focusNode});

  final TaskItem task;
  final WorkspaceController controller;
  final FocusNode? focusNode;

  @override
  State<TaskSubtasksPanel> createState() => _TaskSubtasksPanelState();
}

class _TaskSubtasksPanelState extends State<TaskSubtasksPanel> {
  late final TextEditingController input;

  @override
  void initState() {
    super.initState();
    input = TextEditingController();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void _add() {
    if (widget.controller.addSubtask(widget.task.id, input.text)) {
      input.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final task = widget.controller.tasks
                .where((item) => item.id == widget.task.id)
                .firstOrNull ??
            widget.task;
        final progress = task.subtaskTotal == 0
            ? 0.0
            : task.subtaskCompleted / task.subtaskTotal;
        return Padding(
          key: const ValueKey('task-subtasks-panel'),
          padding: const EdgeInsets.only(top: WorkFollowSpacing.headingGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('子任务',
                    style: TextStyle(
                        fontSize: WorkFollowMacTypography.sectionTitle,
                        height: WorkFollowMacTypography.lineControl,
                        fontWeight: WorkFollowMacWeight.semibold,
                        color: tokens.textPrimary)),
                const Spacer(),
                if (task.subtaskTotal > 0)
                  Text('${task.subtaskCompleted}/${task.subtaskTotal}',
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.listMeta,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.regular,
                          color: tokens.textTertiary)),
              ]),
              if (task.subtaskTotal > 0) ...[
                const SizedBox(height: WorkFollowSpacing.compactGap),
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                      WorkFollowSurfaceTokens.markerRadius),
                  child: LinearProgressIndicator(
                      value: progress,
                      minHeight: TaskEditorMetrics.subtaskProgressHeight,
                      backgroundColor: tokens.border,
                      color: progress == 1 ? tokens.success : tokens.accent),
                ),
              ],
              for (final item in task.subtasks)
                Row(key: ValueKey('task-subtask-${item.id}'), children: [
                  Checkbox(
                    value: item.completed,
                    onChanged: (_) =>
                        widget.controller.toggleSubtask(task.id, item.id),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: tokens.borderStrong),
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: item.title,
                      onChanged: (value) => widget.controller
                          .renameSubtask(task.id, item.id, value),
                      decoration: const InputDecoration(
                          border: InputBorder.none, isDense: true),
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.listTitle,
                          height: WorkFollowMacTypography.lineList,
                          fontWeight: WorkFollowMacWeight.medium,
                          color: item.completed
                              ? tokens.textTertiary
                              : tokens.textPrimary,
                          decoration: item.completed
                              ? TextDecoration.lineThrough
                              : null),
                    ),
                  ),
                  IconButton(
                    tooltip: '删除子任务',
                    visualDensity: VisualDensity.compact,
                    icon: AppIcon(WorkFollowIcons.close,
                        size: WorkFollowMetrics.metadataIcon,
                        color: tokens.textTertiary),
                    onPressed: () =>
                        widget.controller.removeSubtask(task.id, item.id),
                  ),
                ]),
              Padding(
                padding: const EdgeInsets.only(top: WorkFollowSpacing.tightGap),
                child: Row(children: [
                  AppIcon(WorkFollowIcons.add,
                      size: WorkFollowMetrics.toolbarIcon,
                      color: tokens.textTertiary),
                  const SizedBox(width: WorkFollowSpacing.denseGap),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('task-subtask-input'),
                      focusNode: widget.focusNode,
                      controller: input,
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(
                          hintText: '添加子任务，按 Return 确认',
                          border: InputBorder.none,
                          isDense: true),
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.listTitle,
                          height: WorkFollowMacTypography.lineList,
                          fontWeight: WorkFollowMacWeight.regular,
                          color: tokens.textPrimary),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
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
