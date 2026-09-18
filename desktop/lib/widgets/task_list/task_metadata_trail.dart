import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';
import '../task_date_picker.dart';

/// The trailing column of one task row.
///
/// Rules, so the next list does not have to rediscover them: a list name, a
/// repeat mark, an attachment mark and a reminder are *context* and stay
/// tertiary. A date is the one item that carries state, so it is the only one
/// that changes colour — overdue is danger (red, not the orange the row used
/// to borrow from the warning palette), today is accent, and every other date
/// stays secondary. All 12pt, 6 apart, right-aligned within the metadata
/// column.
class TaskMetadataTrail extends StatelessWidget {
  const TaskMetadataTrail(
      {super.key, required this.task, required this.controller, this.onEditDate});

  final TaskItem task;
  final WorkspaceController controller;

  /// Opens the schedule picker for this task, anchored to the date chip that
  /// was pressed. Null renders the date as plain text.
  final void Function(BuildContext anchor)? onEditDate;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final items = _items(tokens);
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
        alignment: WrapAlignment.end,
        spacing: TaskListMetrics.metadataGap,
        runSpacing: WorkFollowSpacing.microGap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items);
  }

  List<Widget> _items(WorkFollowTheme tokens) {
    final due = localDateTimeFromStorage(task.dueAt);
    final deadline = localDateTimeFromStorage(task.deadlineAt);
    final result = <Widget>[];
    final closed = task.isClosed;
    final muted = closed ? tokens.textTertiary : null;
    if (task.isPinned)
      result.add(_icon(WorkFollowIcons.pin, closed ? tokens.textTertiary : tokens.accent,
          semanticLabel: '已置顶'));
    if (task.isAbandoned) result.add(_text('已放弃', tokens.textTertiary));
    if (controller.selectedListName == null && task.listName != '收集箱') {
      result.add(_text(task.listName, tokens.textTertiary));
    }
    if (task.priority != TaskPriority.none) {
      result.add(_icon(
          WorkFollowIcons.flag,
          closed
              ? tokens.textTertiary
              : switch (task.priority) {
                  TaskPriority.high => tokens.danger,
                  TaskPriority.medium => tokens.warning,
                  _ => tokens.accent,
                },
          semanticLabel: task.priority.label));
    }
    if (task.subtaskTotal > 0) {
      result.add(_text(
          '${task.subtaskCompleted}/${task.subtaskTotal}', tokens.textTertiary));
    }
    if (task.recurrenceType != 'NONE') {
      result.add(_icon(WorkFollowIcons.repeat, tokens.textTertiary,
          semanticLabel: '重复任务'));
    }
    // A relative reminder is still a reminder even when the task has no
    // legacy `reminderAt` value. Resolve the effective times through the
    // model so list rows show the same state as the inspector and schedule
    // panel for both absolute and due-date-relative reminders.
    if (task.reminderTimes.isNotEmpty) {
      result.add(_icon(WorkFollowIcons.reminder, tokens.textTertiary,
          semanticLabel: '有提醒'));
    }
    if (_hasDescription) {
      result.add(_icon(WorkFollowIcons.article, tokens.textTertiary,
          semanticLabel: '有描述'));
    }
    if (task.hasAttachment) {
      result.add(_icon(WorkFollowIcons.attachment, tokens.textTertiary,
          semanticLabel: '有附件'));
    }
    if (deadline != null) {
      final now = DateTime.now();
      final overdue = !closed &&
          !deadline.isAfter(DateTime(now.year, now.month, now.day));
      result.add(_text('${calendarDateLabel(deadline)}截止',
          overdue ? tokens.danger : tokens.textTertiary));
    }
    if (due != null) {
      final dateColor = muted ?? _dueColor(tokens);
      // A task with a clock time shows the clock and the time. The date is
      // already in the group heading above it, and `今天 10:30` said the same
      // thing twice on a row that only has room for the time.
      final timed = task.scheduledWithTime;
      final label = timed
          ? '${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}'
          : calendarDateLabel(due);
      if (timed) {
        result.add(_icon(WorkFollowIcons.schedule, dateColor,
            semanticLabel: '具体时间'));
      }
      final edit = onEditDate;
      result.add(edit == null
          ? Text(label,
              key: ValueKey('task-row-date-${task.id}'),
              style: _dateStyle(dateColor))
          : Builder(
              builder: (anchor) => TextButton(
                  onPressed: () => edit(anchor),
                  style: TextButton.styleFrom(
                      foregroundColor: dateColor,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 22),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact),
                  child: Text(label,
                      key: ValueKey('task-row-date-${task.id}'),
                      style: _dateStyle(dateColor)))));
    }
    return result;
  }

  bool get _hasDescription {
    final description = task.description;
    return description != null && description.trim().isNotEmpty;
  }

  Color _dueColor(WorkFollowTheme tokens) {
    if (task.bucket == TaskBucket.overdue) return tokens.danger;
    if (task.bucket == TaskBucket.today) return tokens.accent;
    return tokens.textSecondary;
  }

  TextStyle _dateStyle(Color color) => TextStyle(
      fontSize: WorkFollowMacTypography.listMeta,
      height: WorkFollowMacTypography.lineControl,
      fontWeight: WorkFollowMacWeight.regular,
      color: color);

  Widget _text(String value, Color color) => Text(value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: WorkFollowMacTypography.listMeta,
          height: WorkFollowMacTypography.lineControl,
          fontWeight: WorkFollowMacWeight.regular,
          color: color));

  Widget _icon(IconData icon, Color color, {required String semanticLabel}) =>
      Semantics(
          label: semanticLabel,
          child: AppIcon(icon,
              size: WorkFollowMetrics.metadataIcon, color: color));
}
