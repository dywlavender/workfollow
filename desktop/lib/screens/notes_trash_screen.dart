import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/task_list/task_list_divider.dart';
import '../widgets/task_list/task_list_header.dart';
import '../widgets/task_list/task_list_row.dart';
import '../widgets/task_list_inspector_split.dart';
import '../widgets/trash_confirmation_dialog.dart';

/// The notes-only trash. It follows the task trash's flat, newest-deleted-first
/// list, while the note itself is shown read-only until it is restored.
class NotesTrashScreen extends StatefulWidget {
  const NotesTrashScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<NotesTrashScreen> createState() => _NotesTrashScreenState();
}

class _NotesTrashScreenState extends State<NotesTrashScreen> {
  static const double _detailMinWidth = WorkFollowLayout.taskDetailMinWidth;
  static const double _dividerWidth = WorkFollowLayout.taskListDividerWidth;
  static const double _wideBreakpoint =
      TaskListMetrics.minPaneWidth + _detailMinWidth + _dividerWidth;

  String? selectedNoteId;
  bool detailOnly = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final controller = widget.controller;
    final notes = _orderedDeletedNotes(controller);
    final selected =
        notes.where((note) => note.id == selectedNoteId).firstOrNull ??
            notes.firstOrNull;

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < _wideBreakpoint;
      final list = _list(context, constraints.maxWidth, notes, selected);
      final detail = selected == null
          ? const _EmptyNotesTrashInspector()
          : _DeletedNoteInspector(
              key: ValueKey('notes-trash-detail-${selected.id}'),
              note: selected,
              controller: controller,
              showBack: narrow,
              onBack: () => setState(() => detailOnly = false),
            );

      if (!narrow) {
        final available =
            constraints.maxWidth - _detailMinWidth - _dividerWidth;
        final upper = available.clamp(
            TaskListMetrics.minPaneWidth, TaskListMetrics.maxPaneWidth);
        final lower = TaskListMetrics.minPaneWidth;
        final listWidth =
            (controller.taskListPaneWidth ?? TaskListMetrics.preferredPaneWidth)
                .clamp(lower, upper)
                .toDouble();
        return TaskListInspectorSplit(
          list: list,
          listWidth: listWidth,
          onResize: (delta) {
            final current = controller.taskListPaneWidth ??
                TaskListMetrics.preferredPaneWidth;
            controller.setTaskListPaneWidth(
                (current + delta).clamp(lower, upper).toDouble());
          },
          inspector: detail,
        );
      }

      final showDetail = detailOnly && selected != null;
      return Stack(fit: StackFit.expand, children: [
        Offstage(offstage: showDetail, child: list),
        if (showDetail) detail,
      ]);
    });
  }

  Widget _list(BuildContext context, double maxWidth, List<NoteItem> notes,
      NoteItem? selected) {
    final tokens = WorkFollowTheme.of(context);
    final controller = widget.controller;
    final rows = <Widget>[
      for (final note in notes)
        _DeletedNoteRow(
          key: ValueKey('notes-trash-row-${note.id}'),
          note: note,
          selected: note.id == selected?.id,
          onOpen: () => setState(() {
            selectedNoteId = note.id;
            detailOnly = true;
          }),
          onRestore: () => controller.restoreNote(note.id),
          onPurge: () => _confirmPurgeNote(context, controller, note),
        ),
    ];

    return Container(
      color: tokens.content,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width:
              maxWidth.clamp(0, TaskListMetrics.listColumnMaxWidth).toDouble(),
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TaskListMetrics.horizontalPadding,
                  TaskListMetrics.headerTopPadding,
                  TaskListMetrics.horizontalPadding,
                  WorkFollowSpacing.zero,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TaskListHeader(
                      icon: WorkFollowIcons.trash,
                      title: '垃圾桶',
                      trailing: AppIconButton(
                        key: const ValueKey('empty-notes-trash-button'),
                        icon: WorkFollowIcons.deleteForever,
                        tooltip: '清空笔记垃圾桶',
                        semanticLabel: '清空笔记垃圾桶',
                        onPressed: notes.isEmpty
                            ? null
                            : () => _confirmClear(context, controller),
                      ),
                    ),
                    const SizedBox(height: TaskListMetrics.headerBottomGap),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  key: const PageStorageKey('notes-trash-rows'),
                  padding: const EdgeInsets.fromLTRB(
                    TaskListMetrics.horizontalPadding,
                    WorkFollowSpacing.zero,
                    TaskListMetrics.horizontalPadding,
                    WorkFollowSpacing.space7,
                  ),
                  children: [
                    if (rows.isEmpty)
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: EmptyHint(
                          icon: WorkFollowIcons.trash,
                          title: '笔记垃圾桶是空的',
                          hint: '删除的笔记会先到这里。',
                        ),
                      ),
                    for (var i = 0; i < rows.length; i++) ...[
                      rows[i],
                      if (i < rows.length - 1) const TaskListDivider(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(
      BuildContext context, WorkspaceController controller) async {
    if (controller.deletedNotes.isEmpty) return;
    final confirmed = await showTrashConfirmationDialog(
      context: context,
      title: '清空笔记垃圾桶',
      message: '笔记垃圾桶中的内容将被永久删除，确定清空笔记垃圾桶吗？',
      barrierLabel: '确认清空笔记垃圾桶',
    );
    if (confirmed == true) controller.purgeAllDeletedNotes();
  }
}

List<NoteItem> _orderedDeletedNotes(WorkspaceController controller) {
  final notes = controller.deletedNotes.toList();
  notes.sort((a, b) => _compareDeletedAt(a.deletedAt, b.deletedAt));
  return notes;
}

int _compareDeletedAt(String? a, String? b) {
  final aAt = localDateTimeFromStorage(a);
  final bAt = localDateTimeFromStorage(b);
  if (aAt == null || bAt == null) {
    if (aAt == null && bAt != null) return 1;
    if (bAt == null && aAt != null) return -1;
    return 0;
  }
  return bAt.compareTo(aAt);
}

class _DeletedNoteRow extends StatefulWidget {
  const _DeletedNoteRow({
    super.key,
    required this.note,
    required this.selected,
    required this.onOpen,
    required this.onRestore,
    required this.onPurge,
  });

  final NoteItem note;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  State<_DeletedNoteRow> createState() => _DeletedNoteRowState();
}

class _DeletedNoteRowState extends State<_DeletedNoteRow> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final note = widget.note;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: TaskListRowFrame(
          surfaceKey: ValueKey('notes-trash-row-surface-${note.id}'),
          selected: widget.selected,
          hovering: hovering,
          checkbox: SizedBox(
            width: TaskListMetrics.checkboxSize,
            height: TaskListMetrics.checkboxSize,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppIcon(
                WorkFollowIcons.notes,
                size: WorkFollowMetrics.metadataIcon,
                color: tokens.textTertiary,
              ),
            ),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.listTitle,
                  height: WorkFollowMacTypography.lineList,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: tokens.textDisabled,
                ),
              ),
              const SizedBox(height: WorkFollowSpacing.microGap),
              Text(
                note.preview.isEmpty ? '还没有内容' : note.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: WorkFollowMacTypography.listMeta,
                  height: WorkFollowMacTypography.lineList,
                ),
              ),
            ],
          ),
          metadata: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                note.folder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: WorkFollowMacTypography.listMeta,
                ),
              ),
              const SizedBox(height: WorkFollowSpacing.microGap),
              Text(
                '${noteUpdatedLabelFor(note.deletedAt)}删除',
                maxLines: 1,
                style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: WorkFollowMacTypography.listMeta,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: WorkFollowIcons.restore,
                tooltip: '恢复笔记',
                size: WorkFollowMetrics.iconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon,
                onPressed: widget.onRestore,
              ),
              AppIconButton(
                icon: WorkFollowIcons.deleteForever,
                tooltip: '永久删除笔记',
                size: WorkFollowMetrics.iconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon,
                onPressed: widget.onPurge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeletedNoteInspector extends StatelessWidget {
  const _DeletedNoteInspector({
    super.key,
    required this.note,
    required this.controller,
    this.showBack = false,
    this.onBack,
  });

  final NoteItem note;
  final WorkspaceController controller;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final body = (note.plainText ?? note.preview).trim();
    return ColoredBox(
      color: tokens.content,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: WorkFollowLayout.appHeaderHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: WorkFollowSpacing.space5),
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      tooltip: '返回笔记垃圾桶',
                      onPressed: onBack,
                      icon: const AppIcon(WorkFollowIcons.back,
                          size: WorkFollowMetrics.headerIcon),
                    ),
                  AppIcon(WorkFollowIcons.trash,
                      size: WorkFollowMetrics.metadataIcon,
                      color: tokens.textTertiary),
                  const SizedBox(width: WorkFollowSpacing.space2),
                  Text(
                    '已删除的笔记',
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: WorkFollowMacTypography.navigation,
                    ),
                  ),
                  const Spacer(),
                  AppIconButton(
                    icon: WorkFollowIcons.restore,
                    tooltip: '恢复笔记',
                    onPressed: () => controller.restoreNote(note.id),
                  ),
                  AppIconButton(
                    icon: WorkFollowIcons.deleteForever,
                    tooltip: '永久删除笔记',
                    onPressed: () =>
                        _confirmPurgeNote(context, controller, note),
                  ),
                ],
              ),
            ),
          ),
          Container(
              height: WorkFollowMetrics.dividerThickness, color: tokens.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                WorkFollowSpacing.space7,
                WorkFollowSpacing.relaxedGap,
                WorkFollowSpacing.space7,
                WorkFollowSpacing.space7,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      maxWidth: NotesMetrics.editorContentMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        note.title,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: WorkFollowMacTypography.detailTitle,
                          height: WorkFollowMacTypography.lineTight,
                          fontWeight: WorkFollowMacWeight.semibold,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: tokens.textDisabled,
                        ),
                      ),
                      const SizedBox(height: WorkFollowSpacing.space2),
                      Text(
                        '${note.folder} · ${noteUpdatedStampFor(note.deletedAt)}删除',
                        style: TextStyle(
                          color: tokens.textTertiary,
                          fontSize: WorkFollowMacTypography.listMeta,
                        ),
                      ),
                      const SizedBox(height: WorkFollowSpacing.space5),
                      Container(
                          height: WorkFollowMetrics.dividerThickness,
                          color: tokens.border),
                      const SizedBox(height: WorkFollowSpacing.space5),
                      SelectableText(
                        body.isEmpty ? '还没有正文。' : body,
                        style: TextStyle(
                          color: body.isEmpty
                              ? tokens.textTertiary
                              : tokens.textPrimary,
                          fontSize: WorkFollowMacTypography.body,
                          height: WorkFollowMacTypography.lineBody,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotesTrashInspector extends StatelessWidget {
  const _EmptyNotesTrashInspector();

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(WorkFollowIcons.trash,
              size: WorkFollowMetrics.headerIcon, color: tokens.textTertiary),
          const SizedBox(height: WorkFollowSpacing.space3),
          Text(
            '没有可预览的笔记',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: WorkFollowMacTypography.listTitle,
              fontWeight: WorkFollowMacWeight.semibold,
            ),
          ),
          const SizedBox(height: WorkFollowSpacing.inlineGap),
          Text(
            '删除的笔记会显示在这里。',
            style: TextStyle(
              color: tokens.textTertiary,
              fontSize: WorkFollowMacTypography.supporting,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmPurgeNote(
    BuildContext context, WorkspaceController controller, NoteItem note) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('永久删除这条笔记？'),
      content: Text('「${note.title}」将无法恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('永久删除'),
        ),
      ],
    ),
  );
  if (confirmed == true) controller.purgeNote(note.id);
}
