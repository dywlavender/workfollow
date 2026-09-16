import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_schedule.dart';
import 'task_date_picker.dart';
import 'app_icon_button.dart';
import 'task_schedule_picker.dart';
import 'task_context_menu.dart';
import 'task_menu_actions.dart';

class TaskRow extends StatefulWidget {
  const TaskRow(
      {super.key,
      required this.task,
      required this.controller,
      required this.selected,
      this.multiSelected = false,
      this.compact = false,
      this.onActivate});
  final TaskItem task;
  final WorkspaceController controller;
  final bool selected;
  final bool multiSelected;
  final bool compact;
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
    final result = await TaskSchedulePicker.show(anchor,
        value: widget.task.dueAt, hasTime: widget.task.scheduledWithTime);
    if (result != null && mounted) {
      final c = widget.controller, id = widget.task.id;
      _showActionFeedback(result.date == null
          ? c.taskActions.clearSchedule(id)
          : c.taskActions.setSchedule(id,
              TaskScheduleDraft(dueAt: result.date, hasTime: result.hasTime)));
    }
  }

  void _showActionFeedback(TaskActionResult result) {
    if (!mounted || !result.success || result.message == null) return;
    // Property changes return a snapshot undo command. Keep that affordance
    // visible even when the task remains in the current list; navigation-only
    // actions continue to use the existing "查看任务" feedback.
    final undo = result.undo;
    // Deletions are surfaced by the shell's single global undo toast. Keeping
    // a second row-local undo snackbar would duplicate the same affordance;
    // inline property edits still expose their snapshot undo here.
    final canUndo =
        undo != null && (undo.label == '撤销修改' || undo.label == '撤销跳过本周期');
    final id = result.taskId;
    final moved = id != null &&
        result.destination != null &&
        result.destination != TaskDestination.current &&
        result.destination != TaskDestination.hidden;
    if (!moved && !canUndo && !result.showFeedback) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      // Keep the fixed inspector footer and its property controls clickable.
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 64),
      content: Row(children: [
        Expanded(child: Text(result.message!)),
        if (canUndo)
          TextButton(
              onPressed: () => _runUndo(undo),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('撤销')),
      ]),
      action: moved
          ? SnackBarAction(
              label: '查看任务', onPressed: () => widget.controller.openTask(id))
          : null,
    ));
  }

  void _runUndo(UndoCommand undo) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final outcome = undo.execute();
    if (outcome is Future<bool>) unawaited(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context), task = widget.task;
    final selected = widget.selected || widget.multiSelected;
    final listColor = Color(widget.controller.colorValueForList(task.listName));
    final priorityColor = switch (task.priority) {
      TaskPriority.high => tokens.danger,
      TaskPriority.medium => tokens.warning,
      TaskPriority.low => tokens.accent,
      TaskPriority.none => tokens.borderStrong,
    };
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
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          constraints: const BoxConstraints(
                              minHeight:
                                  WorkFollowMetrics.taskRowComfortableHeight),
                          padding: EdgeInsets.symmetric(
                              horizontal: WorkFollowSpacing.space2,
                              vertical: widget.compact ? 5 : 6),
                          decoration: BoxDecoration(
                              color: selected
                                  ? tokens.accentSoft.withValues(alpha: .82)
                                  : hovering
                                      ? tokens.accent.withValues(alpha: .06)
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                  WorkFollowRadii.control),
                              border: Border.all(
                                  color: focused
                                      ? tokens.accent.withValues(alpha: .65)
                                      : selected
                                          ? tokens.accent.withValues(alpha: .18)
                                          : Colors.transparent)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  width: 3,
                                  height: widget.compact ? 28 : 32,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                      color: listColor,
                                      borderRadius: BorderRadius.circular(2))),
                              const SizedBox(width: 8),
                              SizedBox(
                                  width: WorkFollowMetrics.iconHitTarget - 8,
                                  height: WorkFollowMetrics.iconHitTarget - 4,
                                  child: task.isAbandoned
                                      ? IconButton(
                                          tooltip: '恢复任务',
                                          padding: EdgeInsets.zero,
                                          icon: AppIcon(WorkFollowIcons.abandon,
                                              size: 20,
                                              color: tokens.textTertiary),
                                          onPressed: _complete)
                                      : Checkbox(
                                          key: ValueKey(
                                              'task-row-checkbox-${task.id}'),
                                          // Multi-selection is a row state, not a
                                          // completion state. A selected but
                                          // unfinished task must keep an empty
                                          // checkbox, otherwise Cmd-click makes
                                          // it look completed.
                                          value: task.isClosed,
                                          activeColor: task.isClosed
                                              ? tokens.success
                                              : priorityColor,
                                          semanticLabel:
                                              task.isClosed ? '标记未完成' : '完成任务',
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5)),
                                          side: BorderSide(
                                              color: priorityColor, width: 1.6),
                                          onChanged: (_) => _complete())),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            task.title,
                                            maxLines: widget.compact ? 1 : 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize:
                                                    WorkFollowMacTypography.listTitle,
                                                height:
                                                    WorkFollowMacTypography.lineList,
                                                fontWeight:
                                                    WorkFollowMacWeight.regular,
                                                color: task.isClosed
                                                    ? tokens.textTertiary
                                                    : tokens.textPrimary,
                                                decoration: task.isClosed
                                                    ? TextDecoration.lineThrough
                                                    : null),
                                          ),
                                        ),
                                        if (_metadata.isNotEmpty)
                                          Flexible(
                                            child: Align(
                                              alignment: Alignment.topRight,
                                              child: Wrap(
                                                alignment: WrapAlignment.end,
                                                spacing: 7,
                                                runSpacing: 2,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: _metadata,
                                              ),
                                            ),
                                          ),
                                        _moreButton(
                                            tokens, hovering || selected),
                                      ],
                                    ),
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(preview,
                                          key: ValueKey(
                                              'task-row-preview-${task.id}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: WorkFollowMacTypography
                                                  .listBody,
                                              height: WorkFollowMacTypography
                                                  .lineList,
                                              fontWeight: WorkFollowMacWeight
                                                  .regular,
                                              color: tokens.textSecondary)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
          ),
        ));
  }

  Offset? _contextMenuPosition;

  Widget _moreButton(WorkFollowTheme tokens, bool visible) {
    return SizedBox(
        width: WorkFollowMetrics.iconHitTarget,
        height: WorkFollowMetrics.iconHitTarget,
        child: Builder(
            builder: (moreAnchor) => ExcludeSemantics(
                excluding: !visible,
                child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: visible ? 1 : 0,
                    child: IconButton(
                        key: ValueKey('task-row-more-${widget.task.id}'),
                        tooltip: '更多操作',
                        padding: EdgeInsets.zero,
                        iconSize: WorkFollowMetrics.toolbarIcon,
                        onPressed: visible ? () => menu(moreAnchor) : null,
                        icon: AppIcon(WorkFollowIcons.more,
                            size: WorkFollowMetrics.toolbarIcon,
                            color: tokens.textTertiary))))));
  }

  void _complete() {
    final result = widget.task.isClosed
        ? widget.controller.taskActions.restore(widget.task.id)
        : widget.controller.taskActions.complete(widget.task.id);
    _showActionFeedback(result);
  }

  List<Widget> get _metadata {
    final tokens = WorkFollowTheme.of(context);
    final task = widget.task;
    final due = localDateTimeFromStorage(task.dueAt);
    final deadline = localDateTimeFromStorage(task.deadlineAt);
    final result = <Widget>[];
    if (task.isPinned)
      result.add(
          _metaIcon(WorkFollowIcons.pin, tokens.accent, semanticLabel: '已置顶'));
    if (task.isAbandoned) result.add(_metaText('已放弃', tokens.textTertiary));
    if (widget.controller.selectedListName == null && task.listName != '收集箱') {
      result.add(_metaText(task.listName, tokens.textTertiary));
    }
    if (task.priority != TaskPriority.none) {
      result.add(_metaIcon(
          WorkFollowIcons.flag,
          switch (task.priority) {
            TaskPriority.high => tokens.danger,
            TaskPriority.medium => tokens.warning,
            _ => tokens.accent,
          },
          semanticLabel: task.priority.label));
    }
    if (task.subtaskTotal > 0) {
      result.add(_metaText('${task.subtaskCompleted}/${task.subtaskTotal}',
          tokens.textTertiary));
    }
    if (task.recurrenceType != 'NONE') {
      result.add(_metaIcon(WorkFollowIcons.repeat, tokens.textTertiary,
          semanticLabel: '重复任务'));
    }
    if (task.hasAttachment) {
      result.add(_metaIcon(WorkFollowIcons.attachment, tokens.textTertiary,
          semanticLabel: '有附件'));
    }
    if (deadline != null) {
      final today = DateTime.now();
      final overdue = !task.isClosed &&
          !deadline.isAfter(DateTime(today.year, today.month, today.day));
      result.add(_metaText('${calendarDateLabel(deadline)}截止',
          overdue ? tokens.danger : tokens.textTertiary));
    }
    if (due != null) {
      final dateColor = task.bucket == TaskBucket.overdue && !task.isClosed
          ? tokens.warning
          : tokens.textTertiary;
      result.add(Builder(
          builder: (dateAnchor) => TextButton(
              onPressed: () => date(dateAnchor),
              style: TextButton.styleFrom(
                  foregroundColor: dateColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 22),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact),
              child: Text(
                  key: ValueKey('task-row-date-${task.id}'),
                  calendarDateLabel(due, hasTime: task.scheduledWithTime),
                  style: TextStyle(
                      fontSize: WorkFollowMacTypography.listMeta,
                      height: WorkFollowMacTypography.lineControl,
                      fontWeight: WorkFollowMacWeight.regular,
                      color: dateColor)))));
    }
    return result;
  }

  Widget _metaText(String value, Color color) => Text(value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: WorkFollowMacTypography.listMeta,
          height: WorkFollowMacTypography.lineControl,
          fontWeight: WorkFollowMacWeight.regular,
          color: color));

  Widget _metaIcon(IconData icon, Color color,
          {required String semanticLabel}) =>
      Semantics(
          label: semanticLabel,
          child: AppIcon(icon,
              size: WorkFollowMetrics.metadataIcon, color: color));
}
