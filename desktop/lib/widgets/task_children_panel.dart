import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'task_completion_box.dart';
import 'task_date_picker.dart';

/// The child-task list under a parent task's body — TickTick's subtask flow.
///
/// A child is a real [TaskItem]; this panel only offers the lightweight
/// surface: complete it, rename it inline, follow its date, and open the full
/// inspector with the trailing chevron. Date editing deliberately lives in
/// the child's own inspector, not here.
class TaskChildrenPanel extends StatefulWidget {
  const TaskChildrenPanel(
      {super.key, required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  State<TaskChildrenPanel> createState() => _TaskChildrenPanelState();
}

class _TaskChildrenPanelState extends State<TaskChildrenPanel> {
  final Map<String, TextEditingController> edits = {};
  final Map<String, FocusNode> focuses = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    _consumeFocusRequest();
  }

  void _controllerChanged() {
    if (mounted) _consumeFocusRequest();
  }

  void _consumeFocusRequest() {
    final pending = widget.controller.taskUiState.pendingChildFocusTaskId;
    if (pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.taskUiState.pendingChildFocusTaskId = null;
      final node = _focusFor(pending);
      node.requestFocus();
      final context = node.context;
      if (context != null) Scrollable.ensureVisible(context, alignment: .3);
    });
  }

  TextEditingController _editFor(TaskItem child) => edits.putIfAbsent(
      child.id, () => TextEditingController(text: child.title));

  FocusNode _focusFor(String childId) =>
      focuses.putIfAbsent(childId, FocusNode.new);

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    for (final controller in edits.values) {
      controller.dispose();
    }
    for (final node in focuses.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _toggle(TaskItem child) {
    final actions = widget.controller.taskActions;
    final result =
        child.isClosed ? actions.restore(child.id) : actions.complete(child.id);
    assert(result.taskId == child.id || !result.success);
  }

  Color _dateColor(TaskItem child, WorkFollowTheme tokens) {
    if (child.isClosed) return tokens.textTertiary;
    final due = localDateTimeFromStorage(child.dueAt);
    if (due == null) return tokens.textTertiary;
    final now = DateTime.now();
    final overdue = child.scheduledWithTime
        ? due.isBefore(now)
        : DateTime(due.year, due.month, due.day)
            .isBefore(DateTime(now.year, now.month, now.day));
    return overdue ? tokens.danger : tokens.accent;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final children = widget.controller.childrenOf(widget.task.id);
          return Padding(
              key: const ValueKey('task-children-panel'),
              padding: const EdgeInsets.only(top: WorkFollowSpacing.headingGap),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in children)
                      _ChildRow(
                        key: ValueKey('task-child-row-${child.id}'),
                        child: child,
                        edit: _editFor(child),
                        focus: _focusFor(child.id),
                        dateColor: _dateColor(child, tokens),
                        onToggle: () => _toggle(child),
                        onRename: (value) => widget.controller.taskActions
                            .setTitle(child.id, value),
                        onOpen: () => widget.controller.openTask(child.id),
                      ),
                    InkWell(
                        key: const ValueKey('task-add-child'),
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.control),
                        onTap: () =>
                            widget.controller.createChildTask(widget.task.id),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: WorkFollowSpacing.tightGap),
                            child: Row(children: [
                              AppIcon(WorkFollowIcons.add,
                                  size: WorkFollowMetrics.toolbarIcon,
                                  color: tokens.textTertiary),
                              const SizedBox(width: WorkFollowSpacing.denseGap),
                              Text('添加子任务',
                                  style: TextStyle(
                                      fontSize:
                                          WorkFollowMacTypography.listTitle,
                                      height: WorkFollowMacTypography.lineList,
                                      fontWeight: WorkFollowMacWeight.medium,
                                      color: tokens.textTertiary)),
                            ]))),
                  ]));
        });
  }
}

class _ChildRow extends StatelessWidget {
  const _ChildRow({
    super.key,
    required this.child,
    required this.edit,
    required this.focus,
    required this.dateColor,
    required this.onToggle,
    required this.onRename,
    required this.onOpen,
  });

  final TaskItem child;
  final TextEditingController edit;
  final FocusNode focus;
  final Color dateColor;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final due = localDateTimeFromStorage(child.dueAt);
    return Padding(
        padding:
            const EdgeInsets.symmetric(vertical: WorkFollowSpacing.microGap),
        child: Row(children: [
          GestureDetector(
            onTap: onToggle,
            child: TaskCompletionBox(
                size: WorkFollowMetrics.toolbarIcon,
                completed: child.completed,
                openColor: tokens.textSecondary,
                doneColor: tokens.success),
          ),
          const SizedBox(width: WorkFollowSpacing.denseGap),
          Expanded(
            child: TextField(
              key: ValueKey('task-child-title-${child.id}'),
              controller: edit,
              focusNode: focus,
              onChanged: onRename,
              style: TextStyle(
                  fontSize: WorkFollowMacTypography.listTitle,
                  height: WorkFollowMacTypography.lineList,
                  fontWeight: WorkFollowMacWeight.medium,
                  color: child.completed
                      ? tokens.textTertiary
                      : tokens.textPrimary),
              decoration: const InputDecoration(
                  hintText: '无标题', border: InputBorder.none, isDense: true),
            ),
          ),
          if (due != null)
            Text(calendarDateLabel(due, hasTime: child.scheduledWithTime),
                key: ValueKey('task-child-date-${child.id}'),
                style: TextStyle(
                    fontSize: WorkFollowMacTypography.listMeta,
                    height: WorkFollowMacTypography.lineControl,
                    fontWeight: WorkFollowMacWeight.regular,
                    color: dateColor)),
          IconButton(
              key: ValueKey('task-child-open-${child.id}'),
              tooltip: '打开子任务',
              visualDensity: VisualDensity.compact,
              onPressed: onOpen,
              icon: AppIcon(WorkFollowIcons.chevronNext,
                  size: WorkFollowMetrics.metadataIcon,
                  color: tokens.textTertiary)),
        ]));
  }
}

/// The `父任务 >` crumb above a child task's title. Tapping returns to the
/// parent, which also restores the list selection to the parent row.
class TaskParentBreadcrumb extends StatelessWidget {
  const TaskParentBreadcrumb({super.key, required this.parent, this.onOpen});

  final TaskItem parent;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return InkWell(
        key: const ValueKey('task-parent-breadcrumb'),
        borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        onTap: onOpen,
        child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: WorkFollowSpacing.microGap),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(
                      parent.title.trim().isEmpty ? '无标题' : parent.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.supporting,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.medium,
                          color: tokens.textTertiary))),
              const SizedBox(width: WorkFollowSpacing.microGap),
              AppIcon(WorkFollowIcons.chevronNext,
                  size: WorkFollowMetrics.metadataIcon,
                  color: tokens.textTertiary),
            ])));
  }
}
