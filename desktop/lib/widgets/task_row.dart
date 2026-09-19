import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/feedback/feedback_scope.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import 'app_icon_button.dart';
import 'task_completion_box.dart';
import 'task_schedule_panel.dart';
import 'task_context_menu.dart';
import 'task_menu_actions.dart';
import 'task_list/task_list_row.dart';
import 'task_list/task_metadata_trail.dart';
import 'task_list/task_list_row_transition.dart';

/// One task in a task list.
///
/// The row owns behaviour — selection, keyboard, context menu, inline date
/// editing — and delegates every visual decision to the shared task-list
/// components: [TaskListRowFrame] for the three-column geometry and the
/// neutral state fill, [TaskMetadataTrail] for the trailing column. Nothing
/// here picks a font size, a padding or a fill colour on its own, which is
/// what lets 今天 / 最近 7 天 / 收集箱 / 计划 / 单个清单 all look like one list.
class TaskRow extends StatefulWidget {
  const TaskRow(
      {super.key,
      required this.task,
      required this.controller,
      required this.selected,
      this.multiSelected = false,
      this.compact = false,
      this.depth = 0,
      this.expander,
      this.onActivate});
  final TaskItem task;
  final WorkspaceController controller;
  final bool selected;
  final bool multiSelected;
  final bool compact;

  /// Nesting level: 0 for top-level rows, 1 for subtasks. Subtask rows
  /// keep the full row grammar and only shift right.
  final int depth;

  /// Leading fold control for parents with children, rendered before
  /// the checkbox in the row's tree gutter.
  final Widget? expander;
  final VoidCallback? onActivate;
  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool hovering = false;
  bool focused = false;
  late final FocusNode focus;

  @override
  void initState() {
    super.initState();
    focus = FocusNode(debugLabel: 'task-row-${widget.task.id}');
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    }
  }

  void open() {
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed) {
      widget.controller.toggleMultiSelect(widget.task.id);
      return;
    }
    if (keys.isShiftPressed) {
      widget.controller.extendMultiSelectTo(widget.task.id);
      return;
    }
    focus.requestFocus();
    widget.controller.clearMultiSelect();
    widget.controller.selectTask(widget.task.id);
    widget.onActivate?.call();
  }

  Future<void> menu(BuildContext anchor, {Offset? globalPosition}) async {
    final action = await TaskContextMenu.show(anchor,
        task: widget.task,
        controller: widget.controller,
        globalPosition: globalPosition);
    if (!mounted || action == null) return;
    final result = await runTaskMenuAction(
        context, widget.controller, widget.task, action);
    if (result != null) _showActionFeedback(result);
  }

  Future<void> date(BuildContext anchor) async {
    if (!anchor.mounted) return;
    final result = await showTaskSchedulePanel(anchor, widget.task);
    if (result != null && mounted) {
      final c = widget.controller, id = widget.task.id;
      _showActionFeedback(c.taskActions.setScheduleSettings(id, result));
    }
  }

  void _showActionFeedback(TaskActionResult result) {
    if (!mounted) return;
    final id = result.taskId;
    final moved = id != null &&
        result.feedback != TaskFeedbackIntent.completion &&
        result.destination != null &&
        result.destination != TaskDestination.current &&
        result.destination != TaskDestination.hidden;
    // A task that left the current list is otherwise invisible. Offer to follow
    // it rather than an undo: the user asked for the move, not for it to be
    // taken back.
    final feedback = FeedbackScope.maybeOf(context);
    if (feedback == null) return;
    if (moved) {
      feedback.show(
          movedAwayFeedback(result,
              onOpen: () => widget.controller.openTask(id)),
          actionVersion: widget.controller.actionVersion);
      return;
    }
    // Everything else — including completion, which now carries its own undo —
    // is decided by the shared mapper.
    presentTaskResult(feedback, result,
        actionVersion: widget.controller.actionVersion);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context), task = widget.task;
    final selected = widget.selected || widget.multiSelected;
    final priorityColor = taskPriorityColor(task.priority, tokens);
    final preview = (task.description ?? task.note ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): open,
          const SingleActivator(LogicalKeyboardKey.space): _complete,
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              widget.controller.selectAdjacentTask(task.id, 1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              widget.controller.selectAdjacentTask(task.id, -1),
        },
        child: Focus(
          focusNode: focus,
          onFocusChange: (value) {
            if (mounted) setState(() => focused = value);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => hovering = true),
            onExit: (_) => setState(() => hovering = false),
            child: Builder(
                builder: (anchor) => Semantics(
                      selected: selected,
                      button: true,
                      label: task.title,
                      child: GestureDetector(
                        onTap: open,
                        onSecondaryTapDown: (details) =>
                            _contextMenuPosition = details.globalPosition,
                        onSecondaryTap: () =>
                            menu(anchor, globalPosition: _contextMenuPosition),
                        behavior: HitTestBehavior.opaque,
                        // The row fill never eases. Hover, selection and focus
                        // all move with the pointer or the click, so they have
                        // to land in the same frame: a 120ms transition left
                        // every row the pointer swept past still tinted (0.19 of
                        // the fill up to 90ms later) and left the row that just
                        // lost the selection at 157/255 — both read as a stray
                        // click on a row the user never touched.
                        child: TaskListRowTransition(
                          taskId: task.id,
                          closed: task.isClosed,
                          child: Padding(
                            padding: EdgeInsets.only(
                                left: widget.depth *
                                    TaskListMetrics.hierarchyIndent),
                            child: TaskListRowFrame(
                              surfaceKey:
                                  ValueKey('task-row-surface-${task.id}'),
                              compact: widget.compact,
                              selected: selected,
                              hovering: hovering,
                              focused: focused,
                              leading: widget.expander ??
                                  // Every row reserves the disclosure gutter
                                  // so checkbox columns stay aligned (S10.10).
                                  const SizedBox(
                                      width: TaskListMetrics.disclosureWidth),
                              checkbox: _checkbox(tokens, priorityColor),
                              content: _content(tokens, preview),
                              metadata: TaskMetadataTrail(
                                  task: task,
                                  controller: widget.controller,
                                  onEditDate: date),
                            ),
                          ),
                        ),
                      ),
                    )),
          ),
        ));
  }

  Offset? _contextMenuPosition;

  /// The completion box.
  ///
  /// It keeps its priority colour while the task is open, because priority is
  /// the one property that has no other place on a collapsed row. Once the
  /// task closes the box goes neutral: finishing something should not make it
  /// the brightest thing on the list.
  Widget _checkbox(WorkFollowTheme tokens, Color priorityColor) {
    final task = widget.task;
    if (task.isAbandoned) {
      return SizedBox(
          width: TaskListMetrics.checkboxSize,
          height: TaskListMetrics.checkboxSize,
          child: IconButton(
              tooltip: '恢复任务',
              padding: EdgeInsets.zero,
              iconSize: WorkFollowMetrics.metadataIcon,
              constraints: const BoxConstraints(),
              icon: AppIcon(WorkFollowIcons.abandon,
                  size: WorkFollowMetrics.metadataIcon,
                  color: tokens.textTertiary),
              onPressed: _complete));
    }
    return SizedBox(
        width: TaskListMetrics.checkboxSize,
        height: TaskListMetrics.checkboxSize,
        child: Checkbox(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            key: ValueKey('task-row-checkbox-${task.id}'),
            // Multi-selection is a row state, not a completion state. A
            // selected but unfinished task must keep an empty checkbox,
            // otherwise Cmd-click makes it look completed.
            value: task.isClosed,
            activeColor: taskCompletionFill(tokens),
            checkColor: tokens.content,
            // No ink around the box. Material draws a circle on hover and
            // press; it is the only round thing in a row built from rectangles,
            // and it reads as a second, smaller target inside the row's own.
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            semanticLabel: task.isClosed ? '标记未完成' : '完成任务',
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WorkFollowRadii.checkbox)),
            side: BorderSide(
                color: task.isClosed
                    ? taskCompletionFill(tokens)
                    : priorityColor,
                width: WorkFollowMetrics.checkboxBorderWidth),
            onChanged: (_) => _complete()));
  }

  Widget _content(WorkFollowTheme tokens, String preview) {
    final task = widget.task;
    final closed = task.isClosed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // One line, every row. A title that wraps makes the group's rhythm
      // depend on how long the words happen to be, and the row stops reading
      // as a scannable entry; the full title stays legible in the editor one
      // click away.
      Text(taskDisplayTitle(task),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: WorkFollowMacTypography.listTitle,
              height: WorkFollowMacTypography.lineList,
              fontWeight: WorkFollowMacWeight.regular,
              fontStyle: task.title.trim().isEmpty
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: closed || task.title.trim().isEmpty
                  ? tokens.textTertiary
                  : tokens.textPrimary)),
      if (preview.isNotEmpty) ...[
        const SizedBox(height: TaskListMetrics.titlePreviewGap),
        Text(preview,
            key: ValueKey('task-row-preview-${task.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: WorkFollowMacTypography.listBody,
                height: WorkFollowMacTypography.lineList,
                fontWeight: WorkFollowMacWeight.regular,
                color: task.isClosed
                    ? tokens.textTertiary
                    : tokens.textSecondary)),
      ],
    ]);
  }

  void _complete() {
    final result = widget.task.isClosed
        ? widget.controller.taskActions.restore(widget.task.id)
        : widget.controller.taskActions.complete(widget.task.id);
    _showActionFeedback(result);
  }
}
