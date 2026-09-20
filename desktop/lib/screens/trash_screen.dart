import 'package:flutter/material.dart';

import '../features/tasks/application/task_list_projection.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/task_completion_box.dart';
import '../widgets/task_floating_editor.dart';
import '../widgets/task_list/task_list_divider.dart';
import '../widgets/task_list/task_list_header.dart';
import '../widgets/task_list/task_list_row.dart';

/// The persistent trash: soft-deleted tasks and notes can be restored or
/// permanently removed here. Everything survives an app restart.
///
/// The page is a task list rather than a report about one. It draws the header,
/// the row frame and the divider the rest of the product draws, because 已完成
/// sits directly above it in the rail and the two are reached for in the same
/// breath: a user who learned to read one list should not have to learn a
/// second layout to get something back.
///
/// Rows run newest deletion first — the order 已完成 uses for closing dates,
/// answering the same "what did I just put away" question. Deleted notes follow
/// the task rows rather than filing between them: a note is not a task, and the
/// row grammar a task carries (its box, its list, its dates) has no honest
/// meaning for one. Each run is ordered by the same rule, so the page still
/// reads as one timeline.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key, required this.controller});

  final WorkspaceController controller;

  /// Rows come from the same projection every other list asks: which tasks are
  /// in the trash, and how a child folds under its parent, are not questions a
  /// screen gets to answer for itself.
  static const TaskListProjection _projection = TaskListProjection();

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final c = controller;
    final tasks = _projection
        .groupsFor(view: c.view, tasks: c.tasks, reference: c.dateReference)
        .expand((group) => group.tasks)
        .toList();
    final notes = c.deletedNotes;
    final rows = <Widget>[
      for (final task in tasks) _taskRow(context, task),
      for (final note in notes) _noteRow(context, note),
    ];
    return Container(
      color: tokens.content,
      child: LayoutBuilder(
          builder: (context, constraints) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  // The list column's own cap: the trash page and the task
                  // pages beside it have to end on the same vertical.
                  width: constraints.maxWidth
                      .clamp(0, TaskListMetrics.listColumnMaxWidth)
                      .toDouble(),
                  height: double.infinity,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                            padding: EdgeInsets.fromLTRB(
                                TaskListMetrics.horizontalPadding,
                                TaskListMetrics.headerTopPadding,
                                TaskListMetrics.horizontalPadding,
                                WorkFollowSpacing.zero),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TaskListHeader(
                                      icon: WorkFollowIcons.trash,
                                      title: c.viewTitle),
                                  SizedBox(
                                      height: TaskListMetrics.headerBottomGap),
                                ])),
                        Expanded(
                            child: ListView(
                          key: const PageStorageKey('trash-rows'),
                          padding: EdgeInsets.fromLTRB(
                              TaskListMetrics.horizontalPadding,
                              WorkFollowSpacing.zero,
                              TaskListMetrics.horizontalPadding,
                              WorkFollowSpacing.space7),
                          children: [
                            if (rows.isEmpty)
                              AppCard(
                                  padding: EdgeInsets.zero,
                                  child: EmptyHint(
                                      icon: WorkFollowIcons.trash,
                                      title: '垃圾桶是空的',
                                      hint: '删除的任务和笔记会先到这里。')),
                            for (var i = 0; i < rows.length; i++) ...[
                              rows[i],
                              if (i < rows.length - 1)
                                const TaskListDivider(),
                            ],
                          ],
                        )),
                      ]),
                ),
              )),
    );
  }

  Widget _taskRow(BuildContext context, TaskItem task) {
    final tokens = WorkFollowTheme.of(context);
    return _TrashRow(
      key: ValueKey('trash-task-${task.id}'),
      surfaceKey: ValueKey('trash-row-surface-${task.id}'),
      title: task.title,
      meta: '${task.listName} · ${noteUpdatedLabelFor(task.deletedAt)}删除',
      // The task's own box, in the state it was thrown away in. It reports and
      // takes no input, which is exactly right here: a trashed task is not
      // something to tick off, and the row's single target is the row.
      marker: TaskCompletionBox(
          size: WorkFollowMetrics.completionBoxSize,
          completed: task.isClosed,
          openColor: taskPriorityColor(task.priority, tokens)),
      onOpen: () => showTaskFloatingEditor(context,
          controller: controller,
          taskId: task.id,
          allowDeletedTasks: true),
      onRestore: () => controller.restoreTask(task.id),
      onPurge: () => _confirmPurge(context, '永久删除这个任务？',
          '「${task.title}」将无法恢复。', () => controller.purgeTask(task.id)),
    );
  }

  Widget _noteRow(BuildContext context, NoteItem note) {
    final tokens = WorkFollowTheme.of(context);
    return _TrashRow(
      key: ValueKey('trash-note-${note.id}'),
      surfaceKey: ValueKey('trash-row-surface-${note.id}'),
      title: note.title,
      meta: '${note.folder} · ${noteUpdatedLabelFor(note.deletedAt)}删除',
      // A note has no completion state to report, so the marker says what the
      // row is instead of pretending to be a task's box.
      marker: AppIcon(WorkFollowIcons.notes,
          size: WorkFollowMetrics.completionBoxSize,
          color: tokens.textTertiary),
      // No onOpen. A deleted note has no surface to open: the notes tree shows
      // live notes only, so selecting this one would switch to a page that
      // cannot draw it. 恢复 puts it back where it can be read.
      onRestore: () => controller.restoreNote(note.id),
      onPurge: () => _confirmPurge(context, '永久删除这条笔记？',
          '「${note.title}」将无法恢复。', () => controller.purgeNote(note.id)),
    );
  }
}

/// One deleted row.
///
/// The frame, the marker slot, the title and the trailing meta are the task
/// list's; only the two actions differ. 恢复 and 永久删除 stay visible rather
/// than appearing on hover: they are the whole reason the page exists, and an
/// action a user has to find by sweeping the pointer across a list of
/// near-identical rows is one they will not find.
class _TrashRow extends StatefulWidget {
  const _TrashRow({
    super.key,
    required this.surfaceKey,
    required this.title,
    required this.meta,
    required this.marker,
    required this.onRestore,
    required this.onPurge,
    this.onOpen,
  });

  /// Key of the fill surface. Tests read the row fill from it.
  final Key surfaceKey;
  final String title;
  final String meta;
  final Widget marker;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  /// Opens the row. Null for a row with nothing to open, which is also what
  /// keeps such a row from offering a pointer cursor it cannot honour.
  final VoidCallback? onOpen;

  @override
  State<_TrashRow> createState() => _TrashRowState();
}

class _TrashRowState extends State<_TrashRow> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return MouseRegion(
      cursor: widget.onOpen == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: widget.onOpen != null,
          label: widget.title,
          child: TaskListRowFrame(
            surfaceKey: widget.surfaceKey,
            // The row fill never eases, for the same reason no other list row
            // eases: the pointer has already moved on by the time a transition
            // would finish, and the row under it stays tinted.
            hovering: hovering,
            // The slot the list's box sits in, so titles start on one vertical
            // whether the row above is a task with a box or a note.
            checkbox: SizedBox(
                width: TaskListMetrics.checkboxSize,
                height: TaskListMetrics.checkboxSize,
                child: Align(
                    alignment: Alignment.centerLeft, child: widget.marker)),
            content: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.listTitle,
                  height: WorkFollowMacTypography.lineList,
                  fontWeight: WorkFollowMacWeight.regular,
                  // The rule through the words is the trash's own: here it
                  // means "deleted", not "done".
                  decoration: TextDecoration.lineThrough,
                  decorationColor: tokens.textDisabled),
            ),
            metadata: Text(
              widget.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: WorkFollowMacTypography.listMeta,
                  height: WorkFollowMacTypography.lineList),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIconButton(
                  icon: WorkFollowIcons.restore,
                  tooltip: '恢复',
                  size: WorkFollowMetrics.iconHitTarget,
                  iconSize: WorkFollowMetrics.toolbarIcon,
                  onPressed: widget.onRestore),
              AppIconButton(
                  icon: WorkFollowIcons.deleteForever,
                  tooltip: '永久删除',
                  size: WorkFollowMetrics.iconHitTarget,
                  iconSize: WorkFollowMetrics.toolbarIcon,
                  onPressed: widget.onPurge),
            ]),
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmPurge(BuildContext context, String title, String message,
    VoidCallback onConfirm) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消')),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('永久删除')),
      ],
    ),
  );
  if (confirmed == true) onConfirm();
}
