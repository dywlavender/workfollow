import 'package:flutter/material.dart';

import '../features/tasks/application/task_list_projection.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/trash_confirmation_dialog.dart';
import '../widgets/task_completion_box.dart';
import '../widgets/task_inspector.dart';
import '../widgets/task_list/task_list_divider.dart';
import '../widgets/task_list/task_list_header.dart';
import '../widgets/task_list/task_list_row.dart';
import '../widgets/task_list_inspector_split.dart';

/// The persistent task trash. Soft-deleted tasks can be restored or
/// permanently removed here; notes have their own destination in the notes
/// workspace.
///
/// The page is a task list rather than a report about one. It draws the header,
/// the row frame and the divider the rest of the product draws, because 已完成
/// sits directly above it in the rail and the two are reached for in the same
/// breath: a user who learned to read one list should not have to learn a
/// second layout to get something back.
///
/// The task list is one flat removal timeline, newest first, with no dated
/// groups.
class TrashScreen extends StatefulWidget {
  const TrashScreen({
    super.key,
    required this.controller,
    this.compactDensity = false,
    this.persistentInspector = true,
  });

  final WorkspaceController controller;
  final bool compactDensity;
  final bool persistentInspector;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  static const double _detailMinWidth = WorkFollowLayout.taskDetailMinWidth;
  static const double _listDividerWidth = WorkFollowLayout.taskListDividerWidth;
  static const double _wideInspectorBreakpoint =
      TaskListMetrics.minPaneWidth + _detailMinWidth + _listDividerWidth;

  /// Rows come from the same projection every other list asks: which tasks are
  /// in the trash, and how a child folds under its parent, are not questions a
  /// screen gets to answer for itself.
  static const TaskListProjection _projection = TaskListProjection();

  bool detailOnly = false;

  @override
  void initState() {
    super.initState();
    detailOnly = widget.controller.selectedTaskId != null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final c = widget.controller;
    final tasks = _projection
        .groupsFor(view: c.view, tasks: c.tasks, reference: c.dateReference)
        .expand((group) => group.tasks)
        .toList();
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < _wideInspectorBreakpoint;
      final wideInspector = constraints.maxWidth >= _wideInspectorBreakpoint &&
          (widget.persistentInspector || c.selectedTaskId != null);
      final compact = widget.compactDensity || constraints.maxHeight < 680;
      final selected = c.selectedTask;
      // A task restored from the trash leaves this view immediately, even if
      // the controller is also being driven directly by another surface.
      final selectedTrashTask = selected?.deletedAt != null ? selected : null;
      final detail = narrow && detailOnly && selectedTrashTask != null;
      final list = _list(context, constraints.maxWidth, tasks, c, tokens,
          compact: compact, narrow: narrow);

      if (wideInspector) {
        final available =
            constraints.maxWidth - _detailMinWidth - _listDividerWidth;
        final listWidth = _boundedListPaneWidth(available, c);
        return TaskListInspectorSplit(
          list: list,
          listWidth: listWidth,
          onResize: (delta) => _resizeListPane(available, delta, c),
          inspector: selectedTrashTask == null
              ? const EmptyTaskInspector()
              : TaskInspector(
                  key: ValueKey('wide-detail-${selectedTrashTask.id}'),
                  task: selectedTrashTask,
                  controller: c),
        );
      }
      if (!narrow) return list;
      return Stack(fit: StackFit.expand, children: [
        Offstage(offstage: detail, child: list),
        if (detail)
          TaskInspector(
              key: ValueKey('detail-${selectedTrashTask.id}'),
              task: selectedTrashTask,
              controller: c,
              showBack: true,
              onBack: () => setState(() => detailOnly = false)),
      ]);
    });
  }

  Widget _list(BuildContext context, double maxWidth, List<TaskItem> tasks,
      WorkspaceController c, WorkFollowTheme tokens,
      {required bool compact, required bool narrow}) {
    final hasTrash = c.deletedTasks.isNotEmpty;
    final rows = <Widget>[
      for (final task in tasks)
        _taskRow(context, task,
            compact: compact,
            narrow: narrow,
            selected: c.selectedTaskId == task.id),
    ];
    return Container(
      color: tokens.content,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width:
              maxWidth.clamp(0, TaskListMetrics.listColumnMaxWidth).toDouble(),
          height: double.infinity,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                          title: c.viewTitle,
                          trailing: AppIconButton(
                            key: const ValueKey('empty-trash-button'),
                            icon: WorkFollowIcons.deleteForever,
                            tooltip: '清空垃圾桶',
                            semanticLabel: '清空垃圾桶',
                            onPressed: hasTrash
                                ? () => _confirmEmptyTrash(context, c)
                                : null,
                          )),
                      SizedBox(height: TaskListMetrics.headerBottomGap),
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
                          hint: '删除的任务会先到这里。')),
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1) const TaskListDivider(),
                ],
              ],
            )),
          ]),
        ),
      ),
    );
  }

  double _boundedListPaneWidth(double available, WorkspaceController c) {
    final upper = available < TaskListMetrics.maxPaneWidth
        ? available
        : TaskListMetrics.maxPaneWidth;
    final lower = upper < TaskListMetrics.minPaneWidth
        ? upper
        : TaskListMetrics.minPaneWidth;
    return (c.taskListPaneWidth ?? TaskListMetrics.preferredPaneWidth)
        .clamp(lower, upper)
        .toDouble();
  }

  void _resizeListPane(double available, double delta, WorkspaceController c) {
    final upper = available < TaskListMetrics.maxPaneWidth
        ? available
        : TaskListMetrics.maxPaneWidth;
    final lower = upper < TaskListMetrics.minPaneWidth
        ? upper
        : TaskListMetrics.minPaneWidth;
    final current = c.taskListPaneWidth ?? TaskListMetrics.preferredPaneWidth;
    final next = (current + delta).clamp(lower, upper).toDouble();
    if (next != current) c.setTaskListPaneWidth(next);
  }

  Widget _taskRow(BuildContext context, TaskItem task,
      {required bool compact, required bool narrow, required bool selected}) {
    final tokens = WorkFollowTheme.of(context);
    return _TrashRow(
      key: ValueKey('trash-task-${task.id}'),
      surfaceKey: ValueKey('trash-row-surface-${task.id}'),
      title: task.title,
      meta: '${task.listName} · ${noteUpdatedLabelFor(task.deletedAt)}删除',
      compact: compact,
      selected: selected,
      // The task's own box, in the state it was thrown away in. It reports and
      // takes no input, which is exactly right here: a trashed task is not
      // something to tick off, and the row's single target is the row.
      marker: TaskCompletionBox(
          size: WorkFollowMetrics.completionBoxSize,
          completed: task.isClosed,
          openColor: taskPriorityColor(task.priority, tokens)),
      onOpen: () {
        widget.controller.selectTask(task.id);
        if (narrow) setState(() => detailOnly = true);
      },
      onRestore: () {
        widget.controller.restoreTask(task.id);
        if (widget.controller.selectedTaskId == task.id) {
          widget.controller.clearTaskSelection();
        }
      },
      onPurge: () => _confirmPurge(context, '永久删除这个任务？',
          '「${task.title}」将无法恢复。', () => widget.controller.purgeTask(task.id)),
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
    this.selected = false,
    this.compact = false,
    this.onOpen,
  });

  /// Key of the fill surface. Tests read the row fill from it.
  final Key surfaceKey;
  final String title;
  final String meta;
  final Widget marker;
  final VoidCallback onRestore;
  final VoidCallback onPurge;
  final bool selected;
  final bool compact;

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
            selected: widget.selected,
            hovering: hovering,
            compact: widget.compact,
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

Future<void> _confirmEmptyTrash(
    BuildContext context, WorkspaceController controller) async {
  if (controller.deletedTasks.isEmpty) return;
  final confirmed = await showTrashConfirmationDialog(
    context: context,
    title: '清空垃圾桶',
    message: '垃圾桶中的任务将被永久删除，确定清空垃圾桶吗？',
    barrierLabel: '确认清空任务垃圾桶',
  );
  if (confirmed == true) controller.purgeAllDeletedTasks();
}
