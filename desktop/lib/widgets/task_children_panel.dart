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
                    for (var i = 0; i < children.length; i++) ...[
                      TaskChildInlineRow(
                        key: ValueKey('task-child-row-${children[i].id}'),
                        child: children[i],
                        edit: _editFor(children[i]),
                        focus: _focusFor(children[i].id),
                        onToggle: () => _toggle(children[i]),
                        onRename: (value) => widget.controller.taskActions
                            .setTitle(children[i].id, value),
                        onOpen: () =>
                            widget.controller.openTask(children[i].id),
                      ),
                      // Hairline between rows, inset to start at the title —
                      // the checkbox column stays visually outside the rule.
                      if (i < children.length - 1)
                        Container(
                            height: WorkFollowMetrics.dividerThickness,
                            margin: const EdgeInsets.only(
                                left: TaskChildInlineRow.checkboxSpace),
                            color: tokens.border),
                    ],
                    InkWell(
                        key: const ValueKey('task-add-child'),
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.control),
                        hoverColor: tokens.accentFaint,
                        onTap: () =>
                            widget.controller.createChildTask(widget.task.id),
                        child: Container(
                            constraints: const BoxConstraints(minHeight: 42),
                            alignment: Alignment.centerLeft,
                            child: Row(children: [
                              AppIcon(WorkFollowIcons.add,
                                  size: WorkFollowMetrics.toolbarIcon,
                                  color: tokens.accent),
                              const SizedBox(width: WorkFollowSpacing.denseGap),
                              Text('添加子任务',
                                  style: TextStyle(
                                      fontSize:
                                          WorkFollowMacTypography.listTitle,
                                      height: WorkFollowMacTypography.lineList,
                                      fontWeight: WorkFollowMacWeight.medium,
                                      color: tokens.accent)),
                            ]))),
                  ]));
        });
  }
}

/// One inline child row inside the parent's inspector:
/// `[checkbox] [editable title…] [date] [>]` — nothing else.
///
/// The row is transparent (no card), 48pt tall, and shares the parent's
/// horizontal padding. Only the checkbox, title, date and chevron are shown;
/// chips and property text stay in the child's own inspector.
class TaskChildInlineRow extends StatefulWidget {
  const TaskChildInlineRow({
    super.key,
    required this.child,
    required this.edit,
    required this.focus,
    required this.onToggle,
    required this.onRename,
    required this.onOpen,
  });

  static const double checkboxSpace = 32;
  static const double rowMinHeight = 48;

  final TaskItem child;
  final TextEditingController edit;
  final FocusNode focus;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onOpen;

  @override
  State<TaskChildInlineRow> createState() => _TaskChildInlineRowState();
}

class _TaskChildInlineRowState extends State<TaskChildInlineRow> {
  bool hoveringArrow = false;
  bool hoveringRow = false;
  bool titleFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() => titleFocused = widget.focus.hasFocus);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_focusChanged);
    super.dispose();
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
    final child = widget.child;
    final due = localDateTimeFromStorage(child.dueAt);
    return MouseRegion(
        onEnter: (_) => setState(() => hoveringRow = true),
        onExit: (_) => setState(() => hoveringRow = false),
        child: Container(
            constraints: const BoxConstraints(
                minHeight: TaskChildInlineRow.rowMinHeight),
            alignment: Alignment.centerLeft,
            // S10.13: a whisper of neutral fill on hover only — never opacity,
            // never a selected state inside the parent's own panel.
            color: hoveringRow ? tokens.canvas : Colors.transparent,
            child: Row(children: [
              GestureDetector(
                key: ValueKey('task-child-check-${child.id}'),
                onTap: widget.onToggle,
                child: TaskCompletionBox(
                    size: WorkFollowMetrics.toolbarIcon,
                    completed: child.completed,
                    openColor: tokens.textSecondary,
                    doneColor: tokens.success),
              ),
              const SizedBox(width: WorkFollowSpacing.space2),
              Expanded(
                child: TextField(
                  key: ValueKey('task-child-title-${child.id}'),
                  controller: widget.edit,
                  focusNode: widget.focus,
                  onChanged: widget.onRename,
                  style: TextStyle(
                      fontSize: WorkFollowMacTypography.listTitle,
                      height: WorkFollowMacTypography.lineList,
                      fontWeight: WorkFollowMacWeight.medium,
                      color: child.completed
                          ? tokens.textTertiary
                          : tokens.textPrimary),
                  decoration: InputDecoration(
                      hintText: titleFocused ? null : '无标题',
                      border: InputBorder.none,
                      isDense: true),
                ),
              ),
              if (due != null)
                Padding(
                    padding:
                        const EdgeInsets.only(left: WorkFollowSpacing.tightGap),
                    child: Text(
                        calendarDateLabel(due,
                            hasTime: child.scheduledWithTime),
                        key: ValueKey('task-child-date-${child.id}'),
                        style: TextStyle(
                            fontSize: WorkFollowMacTypography.listMeta,
                            height: WorkFollowMacTypography.lineControl,
                            fontWeight: WorkFollowMacWeight.regular,
                            color: _dateColor(child, tokens)))),
              const SizedBox(width: WorkFollowSpacing.space2),
              // The chevron is the only navigation affordance; the title edits in
              // place and never jumps to the child inspector.
              MouseRegion(
                onEnter: (_) => setState(() => hoveringArrow = true),
                onExit: (_) => setState(() => hoveringArrow = false),
                child: IconButton(
                    key: ValueKey('task-child-open-${child.id}'),
                    tooltip: '打开子任务',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onOpen,
                    icon: AppIcon(WorkFollowIcons.chevronNext,
                        size: WorkFollowMetrics.metadataIcon,
                        color: hoveringArrow
                            ? tokens.textSecondary
                            : tokens.textTertiary)),
              ),
            ])));
  }
}

/// The `父任务 ›` crumb above a child task's title. Tapping returns to the
/// parent, which also restores the list selection to the parent row.
class TaskParentBreadcrumb extends StatefulWidget {
  const TaskParentBreadcrumb({super.key, required this.parent, this.onOpen});

  final TaskItem parent;
  final VoidCallback? onOpen;

  @override
  State<TaskParentBreadcrumb> createState() => _TaskParentBreadcrumbState();
}

class _TaskParentBreadcrumbState extends State<TaskParentBreadcrumb> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // Quiet navigation text, not a button: secondary ink that warms to
    // primary on hover, chevron staying tertiary.
    final titleColor = hovering ? tokens.textPrimary : tokens.textSecondary;
    return MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: InkWell(
            key: const ValueKey('task-parent-breadcrumb'),
            borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            onTap: widget.onOpen,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: WorkFollowSpacing.space1),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: Text(taskDisplayTitle(widget.parent),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: WorkFollowMacTypography.control,
                              height: WorkFollowMacTypography.lineControl,
                              fontWeight: WorkFollowMacWeight.medium,
                              color: titleColor))),
                  const SizedBox(width: WorkFollowSpacing.microGap),
                  AppIcon(WorkFollowIcons.chevronNext,
                      size: WorkFollowMetrics.metadataIcon,
                      color: tokens.textTertiary),
                ]))));
  }
}
