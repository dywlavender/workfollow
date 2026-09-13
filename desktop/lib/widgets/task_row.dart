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
    final due = localDateTimeFromStorage(task.dueAt);
    final deadline = localDateTimeFromStorage(task.deadlineAt);
    final listColor = Color(widget.controller.colorValueForList(task.listName));
    final dateColor = task.bucket == TaskBucket.overdue && !task.completed
        ? tokens.warning
        : tokens.textTertiary;
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): open,
          const SingleActivator(LogicalKeyboardKey.space): () =>
              widget.controller.toggleTask(task.id),
        },
        child: Focus(
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
                              horizontal: 10, vertical: widget.compact ? 5 : 9),
                          decoration: BoxDecoration(
                              color: selected
                                  ? tokens.accentSoft
                                  : hovering
                                      ? tokens.accent.withValues(alpha: .05)
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              border: selected
                                  ? Border.all(
                                      color:
                                          tokens.accent.withValues(alpha: .35))
                                  : Border.all(color: Colors.transparent)),
                          child: Row(children: [
                            Container(
                                width: 4,
                                height: 30,
                                decoration: BoxDecoration(
                                    color: listColor,
                                    borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 7),
                            SizedBox(
                                width: 26,
                                height: 28,
                                child: Checkbox(
                                    value:
                                        widget.multiSelected || task.completed,
                                    activeColor:
                                        task.priority == TaskPriority.high
                                            ? tokens.danger
                                            : tokens.accent,
                                    semanticLabel: widget.multiSelected
                                        ? '取消选择'
                                        : task.completed
                                            ? '标记未完成'
                                            : '完成任务',
                                    shape: const CircleBorder(),
                                    side: BorderSide(
                                        color: tokens.borderStrong, width: 1.5),
                                    onChanged: (_) => widget.multiSelected
                                        ? widget.controller
                                            .toggleMultiSelect(task.id)
                                        : widget.controller
                                            .toggleTask(task.id))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(task.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: widget.compact ? 13.5 : 14,
                                          height: 1.4,
                                          fontWeight: FontWeight.w500,
                                          color: task.completed
                                              ? tokens.textTertiary
                                              : tokens.textPrimary,
                                          decoration: task.completed
                                              ? TextDecoration.lineThrough
                                              : null)),
                                  if (widget.controller.selectedListName ==
                                          null &&
                                      task.listName != '收集箱') ...[
                                    const SizedBox(height: 3),
                                    Text(task.listName,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: tokens.textTertiary)),
                                  ],
                                ])),
                            if (task.priority != TaskPriority.none)
                              Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.flag_rounded,
                                      size: 14,
                                      color: switch (task.priority) {
                                        TaskPriority.high => tokens.danger,
                                        TaskPriority.medium => tokens.warning,
                                        _ => tokens.accent,
                                      })),
                            if (task.subtaskTotal > 0)
                              Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                      '${task.subtaskCompleted}/${task.subtaskTotal}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: tokens.textTertiary))),
                            if (task.recurrenceType != 'NONE')
                              Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.repeat,
                                      size: 14, color: tokens.textTertiary)),
                            if (task.hasAttachment)
                              Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.attach_file,
                                      size: 14, color: tokens.textTertiary)),
                            const SizedBox(width: 12),
                            if (deadline != null)
                              Tooltip(
                                  message: '截止日期',
                                  child: Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Text(
                                          '⚑ ${calendarDateLabel(deadline)}截止',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: !task.completed &&
                                                      !deadline.isAfter(
                                                          DateTime(
                                                              DateTime.now()
                                                                  .year,
                                                              DateTime.now()
                                                                  .month,
                                                              DateTime.now()
                                                                  .day))
                                                  ? tokens.danger
                                                  : tokens.textTertiary)))),
                            if (due != null)
                              Builder(
                                  builder: (dateAnchor) => TextButton(
                                      onPressed: () => date(dateAnchor),
                                      style: TextButton.styleFrom(
                                          foregroundColor: dateColor,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6),
                                          minimumSize: const Size(0, 30)),
                                      child: Text(
                                          calendarDateLabel(due,
                                              hasTime: task.scheduledWithTime),
                                          style:
                                              const TextStyle(fontSize: 11)))),
                            SizedBox(
                                width: 28,
                                child: Opacity(
                                    opacity: hovering || selected ? 1 : 0,
                                    child: IconButton(
                                        tooltip: '更多操作',
                                        padding: EdgeInsets.zero,
                                        iconSize: 18,
                                        onPressed: () => menu(anchor),
                                        icon: Icon(Icons.more_horiz,
                                            color: tokens.textTertiary)))),
                          ]),
                        ),
                      ),
                    )),
          ),
        ));
  }
}
