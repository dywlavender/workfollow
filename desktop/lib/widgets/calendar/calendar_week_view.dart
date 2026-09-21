import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_interaction_states.dart';
import '../../theme/workfollow_theme.dart';
import '../task_completion_box.dart';

/// The week, as seven day columns.
///
/// It starts on Sunday like the month grid does, so switching modes does not
/// silently shift which column belongs to which weekday. The columns are still
/// the older card-per-day shape: this view's own redesign — taller rows, the
/// shared task bar, a time axis — is a separate pass, and only the week's
/// origin changed here.
class CalendarWeekView extends StatelessWidget {
  const CalendarWeekView({
    super.key,
    required this.controller,
    required this.anchor,
    this.today,
    this.onSelectDay,
    this.onOpenTask,
  });

  final WorkspaceController controller;

  /// Any day of the week to show.
  final DateTime anchor;

  final DateTime? today;
  final ValueChanged<DateTime>? onSelectDay;

  /// Opens a task in the page's floating editor. The column lends its context
  /// so the editor is anchored to the day it was opened from.
  final void Function(String taskId, BuildContext anchor)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final normalized = DateTime(anchor.year, anchor.month, anchor.day);
    // Dart counts weekdays from Monday as 1, so Sunday is 7 and `% 7` makes it
    // the week's first column.
    final start = normalized.subtract(Duration(days: normalized.weekday % 7));
    final now = today ?? DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < 7; index++)
          Expanded(
            child: _WeekDayColumn(
              controller: controller,
              day: start.add(Duration(days: index)),
              today: now,
              accent: tokens.accent,
              onSelectDay: onSelectDay,
              onOpenTask: onOpenTask,
            ),
          ),
      ],
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    required this.controller,
    required this.day,
    required this.today,
    required this.accent,
    this.onSelectDay,
    this.onOpenTask,
  });

  final WorkspaceController controller;
  final DateTime day;
  final DateTime today;
  final Color accent;
  final ValueChanged<DateTime>? onSelectDay;
  final void Function(String taskId, BuildContext anchor)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final tasks = controller.tasksForDay(day);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) =>
          controller.rescheduleTask(details.data, day),
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: onSelectDay == null ? null : () => onSelectDay!(day),
          child: Container(
            margin: const EdgeInsets.only(right: WorkFollowSpacing.space2),
            padding: const EdgeInsets.fromLTRB(
                WorkFollowSpacing.compactInset,
                WorkFollowSpacing.compactInset,
                WorkFollowSpacing.compactInset,
                WorkFollowSpacing.space2),
            decoration: BoxDecoration(
                color: active ? tokens.accentSoft : tokens.content,
                borderRadius: BorderRadius.circular(WorkFollowRadii.card),
                border: Border.all(
                    color: active
                        ? tokens.accent.withValues(alpha: .6)
                        : tokens.border)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(
                        '周${_weekday(day.weekday)} ${day.month}/${day.day}',
                        style: TextStyle(
                            color: isToday ? accent : tokens.textPrimary,
                            fontSize: WorkFollowMacTypography.sectionTitle,
                            fontWeight: WorkFollowMacWeight.semibold))),
                if (tasks.isNotEmpty)
                  Text('${tasks.length}',
                      style: TextStyle(
                          color: accent,
                          fontSize: WorkFollowMacTypography.caption)),
              ]),
              const SizedBox(height: WorkFollowSpacing.space2),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text('没有安排',
                            style: TextStyle(
                                color: tokens.textTertiary,
                                fontSize: WorkFollowMacTypography.caption)))
                    : ListView.separated(
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: WorkFollowSpacing.denseGap),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final listColor = Color(
                              controller.colorValueForList(task.listName));
                          return Draggable<String>(
                            data: task.id,
                            feedback: Material(
                              color: Colors.transparent,
                              child: _WeekTaskPill(
                                  task: task, color: listColor, tokens: tokens),
                            ),
                            childWhenDragging: Opacity(
                                opacity: .3,
                                child: _WeekTaskPill(
                                    task: task,
                                    color: listColor,
                                    tokens: tokens)),
                            child: _WeekTaskPill(
                                task: task,
                                color: listColor,
                                tokens: tokens,
                                onTap: onOpenTask == null
                                    ? null
                                    : () => onOpenTask!(task.id, context)),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }

  static String _weekday(int value) =>
      const ['一', '二', '三', '四', '五', '六', '日'][value - 1];
}

class _WeekTaskPill extends StatelessWidget {
  const _WeekTaskPill(
      {required this.task,
      required this.color,
      required this.tokens,
      this.onTap});

  final TaskItem task;
  final Color color;
  final WorkFollowTheme tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WorkFollowRadii.control),
      // The pill is tinted in the task's list colour; the pointer deepens that
      // tint instead of the shared neutral hover painting it out.
      overlayColor: WorkFollowInteractionStyles.tintedOverlay(color),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: WorkFollowSpacing.compactGap,
            vertical: WorkFollowSpacing.inlineGap),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            border: Border.all(color: color.withValues(alpha: .34))),
        // The box leads the title, the way it does in a month cell's bar and in
        // a task row. A title that wraps keeps the box beside its first line
        // rather than centred on the block.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaskCompletionBox(
              key: ValueKey('calendar-week-box-${task.id}'),
              size: CalendarMetrics.taskBarCheckboxSize,
              completed: task.completed,
              openColor: color,
            ),
            const SizedBox(width: WorkFollowSpacing.denseGap),
            Expanded(
              child: Text(task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      // Grey, not struck through — the same reading of
                      // completion the month grid's bars and the task rows use.
                      color: task.completed
                          ? tokens.textTertiary
                          : tokens.textPrimary,
                      fontSize: WorkFollowMacTypography.caption,
                      height: WorkFollowMacTypography.lineTight)),
            ),
          ],
        ),
      ),
    );
  }
}
