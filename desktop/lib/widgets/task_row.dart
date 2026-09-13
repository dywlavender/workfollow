import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';
import 'task_date_picker.dart';

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
    widget.controller.clearMultiSelect();
    widget.controller.selectTask(widget.task.id);
    widget.onActivate?.call();
  }

  Future<void> menu(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(anchor, entries: [
      DesktopMenuEntry('complete', widget.task.completed ? '标记未完成' : '完成任务',
          icon: Icons.check),
      const DesktopMenuEntry('today', '安排到今天', icon: Icons.today_outlined),
      const DesktopMenuEntry('date', '安排其他日期…',
          icon: Icons.calendar_today_outlined),
      const DesktopMenuEntry('duplicate', '创建副本',
          icon: Icons.control_point_duplicate_outlined),
      const DesktopMenuEntry('delete', '移到废纸篓',
          icon: Icons.delete_outline, destructive: true),
    ]);
    if (!mounted) return;
    switch (action) {
      case 'complete':
        widget.controller.toggleTask(widget.task.id);
      case 'today':
        widget.controller.moveTaskToToday(widget.task.id);
      case 'duplicate':
        widget.controller.duplicateTask(widget.task.id);
      case 'delete':
        widget.controller.removeTask(widget.task.id);
      case 'date':
        await date(anchor);
    }
  }

  Future<void> date(BuildContext anchor) async {
    if (!anchor.mounted) return;
    final result = await showTaskDatePicker(anchor,
        value: widget.task.dueAt, hasTime: widget.task.scheduledWithTime);
    if (result != null && mounted) {
      final c = widget.controller, id = widget.task.id;
      c.updateTaskDue(id, result.date, hasTime: result.hasTime);
      if (!c.visibleTasks.any((task) => task.id == id)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.date == null
                ? '已清除安排日期'
                : '已安排到${calendarDateLabel(result.date, hasTime: result.hasTime)}'),
            action: SnackBarAction(
                label: '查看任务', onPressed: () => c.openTask(id))));
      }
    }
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
          const SingleActivator(LogicalKeyboardKey.space): () =>
              widget.controller.toggleTask(task.id),
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
                        onSecondaryTap: () => menu(anchor),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: EdgeInsets.symmetric(
                              horizontal: widget.compact ? 8 : 10,
                              vertical: widget.compact ? 5 : 8),
                          decoration: BoxDecoration(
                              color: selected
                                  ? tokens.accentSoft.withValues(alpha: .82)
                                  : hovering
                                      ? tokens.accent.withValues(alpha: .06)
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
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
                                  width: 26,
                                  height: 28,
                                  child: Checkbox(
                                      value: widget.multiSelected ||
                                          task.completed,
                                      activeColor: task.completed
                                          ? tokens.success
                                          : priorityColor,
                                      semanticLabel: widget.multiSelected
                                          ? '取消选择'
                                          : task.completed
                                              ? '标记未完成'
                                              : '完成任务',
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(5)),
                                      side: BorderSide(
                                          color: priorityColor, width: 1.6),
                                      onChanged: (_) => widget.multiSelected
                                          ? widget.controller
                                              .toggleMultiSelect(task.id)
                                          : widget.controller
                                              .toggleTask(task.id))),
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
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize:
                                                    widget.compact ? 13.5 : 14,
                                                height: 1.35,
                                                fontWeight: FontWeight.w600,
                                                color: task.completed
                                                    ? tokens.textTertiary
                                                    : tokens.textPrimary,
                                                decoration: task.completed
                                                    ? TextDecoration.lineThrough
                                                    : null),
                                          ),
                                        ),
                                        _moreButton(anchor, tokens,
                                            hovering || selected),
                                      ],
                                    ),
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(preview,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              height: 1.25,
                                              color: tokens.textTertiary)),
                                    ],
                                    if (_metadata.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Wrap(
                                        spacing: 7,
                                        runSpacing: 2,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: _metadata,
                                      ),
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

  Widget _moreButton(
      BuildContext anchor, WorkFollowTheme tokens, bool visible) {
    return SizedBox(
        width: 26,
        height: 24,
        child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: visible ? 1 : 0,
            child: IconButton(
                tooltip: '更多操作',
                padding: EdgeInsets.zero,
                iconSize: 18,
                onPressed: visible ? () => menu(anchor) : null,
                icon: Icon(Icons.more_horiz, color: tokens.textTertiary))));
  }

  List<Widget> get _metadata {
    final tokens = WorkFollowTheme.of(context);
    final task = widget.task;
    final due = localDateTimeFromStorage(task.dueAt);
    final deadline = localDateTimeFromStorage(task.deadlineAt);
    final result = <Widget>[];
    if (widget.controller.selectedListName == null && task.listName != '收集箱') {
      result.add(_metaText(task.listName, tokens.textTertiary));
    }
    if (task.priority != TaskPriority.none) {
      result.add(_metaIcon(
          Icons.flag_outlined,
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
      result.add(_metaIcon(Icons.repeat_rounded, tokens.textTertiary,
          semanticLabel: '重复任务'));
    }
    if (task.hasAttachment) {
      result.add(_metaIcon(Icons.attach_file_rounded, tokens.textTertiary,
          semanticLabel: '有附件'));
    }
    if (deadline != null) {
      final today = DateTime.now();
      final overdue = !task.completed &&
          !deadline.isAfter(DateTime(today.year, today.month, today.day));
      result.add(_metaText('${calendarDateLabel(deadline)}截止',
          overdue ? tokens.danger : tokens.textTertiary));
    }
    if (due != null) {
      final dateColor = task.bucket == TaskBucket.overdue && !task.completed
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
                  calendarDateLabel(due, hasTime: task.scheduledWithTime),
                  style: TextStyle(fontSize: 11, color: dateColor)))));
    }
    return result;
  }

  Widget _metaText(String value, Color color) => Text(value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10.5, color: color));

  Widget _metaIcon(IconData icon, Color color,
          {required String semanticLabel}) =>
      Semantics(
          label: semanticLabel, child: Icon(icon, size: 14, color: color));
}
