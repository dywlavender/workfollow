import 'package:flutter/material.dart';

import '../../features/tasks/domain/task_draft.dart';
import '../../features/tasks/domain/task_schedule.dart';
import '../../features/tasks/domain/task_schedule_settings.dart';
import '../../models/task.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';
import '../desktop_popover.dart';
import '../task_date_picker.dart';
import '../task_list_picker.dart';
import '../task_priority_picker.dart';
import '../task_repeat_picker.dart';
import '../task_reminder_picker.dart';
import '../task_schedule_panel.dart';

@immutable
class MatrixAddDraft {
  const MatrixAddDraft({
    required this.title,
    required this.listName,
    required this.schedule,
    required this.scheduleOverridden,
    required this.reminderAt,
    required this.recurrence,
    required this.priority,
  });

  final String title;
  final String listName;
  final TaskScheduleDraft schedule;
  final bool scheduleOverridden;
  final DateTime? reminderAt;
  final RecurrenceDraft recurrence;
  final TaskPriority priority;
}

/// The compact editor opened by a quadrant's plus button.
///
/// It deliberately keeps the editor local to the popover. The only value that
/// leaves this surface is a draft; task creation and quadrant defaults remain
/// controller responsibilities.
class MatrixAddSurface extends StatefulWidget {
  const MatrixAddSurface({
    super.key,
    required this.controller,
    required this.quadrant,
  });

  final WorkspaceController controller;
  final MatrixQuadrant quadrant;

  @override
  State<MatrixAddSurface> createState() => _MatrixAddSurfaceState();
}

class _MatrixAddSurfaceState extends State<MatrixAddSurface> {
  late final TextEditingController title;
  late final FocusNode focus;
  late TaskPriority priority;
  late String listName;
  TaskScheduleDraft schedule = const TaskScheduleDraft();
  bool scheduleOverridden = false;
  DateTime? reminderAt;
  RecurrenceDraft recurrence = const RecurrenceDraft();

  @override
  void initState() {
    super.initState();
    title = TextEditingController();
    focus = FocusNode(debugLabel: 'matrix-add-title');
    priority = _defaultPriority(widget.quadrant);
    listName = '收集箱';
  }

  @override
  void dispose() {
    title.dispose();
    focus.dispose();
    super.dispose();
  }

  TaskPriority _defaultPriority(MatrixQuadrant quadrant) => switch (quadrant) {
        MatrixQuadrant.doNow || MatrixQuadrant.schedule => TaskPriority.high,
        MatrixQuadrant.delegate => TaskPriority.low,
        MatrixQuadrant.later => TaskPriority.none,
      };

  TaskItem _scheduleTask() {
    final due = schedule.dueAt;
    return TaskItem(
      id: 'matrix-add-schedule',
      title: title.text.trim().isEmpty ? '准备做什么?' : title.text.trim(),
      listName: listName,
      bucket: taskBucketForDate(due),
      dueAt: due?.toIso8601String(),
      hasDueTime: due != null && schedule.hasTime,
      reminderAt: reminderAt?.toIso8601String(),
      recurrenceType: recurrence.type,
      recurrenceConfig: recurrence.config,
    );
  }

  Future<void> _pickSchedule(BuildContext anchor) async {
    final result = await showTaskSchedulePanel(anchor, _scheduleTask());
    if (!mounted || result == null) return;
    setState(() {
      schedule = result.schedule;
      scheduleOverridden = true;
      reminderAt = _reminderFromSchedule(result);
      recurrence = result.recurrence;
    });
  }

  DateTime? _reminderFromSchedule(TaskScheduleSettings settings) {
    if (settings.schedule.dueAt == null) return null;
    if (settings.reminderOffsets.isEmpty) return settings.reminderAt;
    final due = settings.schedule.normalizedDueAt!;
    final base = settings.schedule.hasTime
        ? due
        : DateTime(due.year, due.month, due.day, 9);
    final offset = settings.reminderOffsets
        .reduce((largest, value) => value > largest ? value : largest);
    return base.subtract(Duration(minutes: offset));
  }

  Future<void> _pickPriority(BuildContext anchor) async {
    final value = await TaskPriorityPicker.show(anchor, selected: priority);
    if (!mounted || value == null) return;
    setState(() => priority = value);
  }

  Future<void> _pickList(BuildContext anchor) async {
    final value = await TaskListPicker.show(
      anchor,
      controller: widget.controller,
      selected: listName,
    );
    if (!mounted || value == null) return;
    setState(() => listName = value);
  }

  Future<void> _pickReminder(BuildContext anchor) async {
    final value = await TaskReminderPicker.show(
      anchor,
      value: reminderAt?.toIso8601String(),
    );
    if (!mounted || value == null) return;
    setState(() => reminderAt = value.date);
  }

  Future<void> _pickRepeat(BuildContext anchor) async {
    final value = await TaskRepeatPicker.show(anchor, task: _scheduleTask());
    if (!mounted || value == null) return;
    setState(() => recurrence = value);
  }

  Future<void> _openMore(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(
      anchor,
      placement: PopoverPlacement.topEnd,
      entries: const [
        DesktopMenuEntry('reminder', '提醒', icon: WorkFollowIcons.reminder),
        DesktopMenuEntry('repeat', '重复', icon: WorkFollowIcons.repeat),
      ],
    );
    if (!mounted || action == null) return;
    final stableAnchor = context;
    switch (action) {
      case 'reminder':
        await _pickReminder(stableAnchor);
      case 'repeat':
        await _pickRepeat(stableAnchor);
    }
  }

  void _submit() {
    if (title.text.trim().isEmpty) return;
    Navigator.of(context).pop(MatrixAddDraft(
      title: title.text.trim(),
      listName: listName,
      schedule: schedule,
      scheduleOverridden: scheduleOverridden,
      reminderAt: reminderAt,
      recurrence: recurrence,
      priority: priority,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final due = schedule.dueAt;
    final scheduleLabel = !scheduleOverridden || due == null
        ? '设置日期'
        : calendarDateLabel(due, hasTime: schedule.hasTime);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MatrixMetrics.addSurfaceRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.space3),
            child: Row(
              children: [
                Builder(
                  builder: (anchor) => InkWell(
                    key: const ValueKey('matrix-add-schedule'),
                    borderRadius:
                        BorderRadius.circular(MatrixMetrics.addSurfaceRadius),
                    onTap: () => _pickSchedule(anchor),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal:
                              WorkFollowSpacing.compactActionHorizontalPadding,
                          vertical:
                              WorkFollowSpacing.compactActionVerticalPadding),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(WorkFollowIcons.calendar,
                              size: WorkFollowMetrics.fieldIcon,
                              color: tokens.textSecondary),
                          const SizedBox(width: WorkFollowSpacing.space2),
                          Text(
                            scheduleLabel,
                            style: TextStyle(
                              color: due == null
                                  ? tokens.textTertiary
                                  : tokens.accent,
                              fontSize: WorkFollowMacTypography.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Builder(
                  builder: (anchor) => AppIconButton(
                    key: const ValueKey('matrix-add-priority'),
                    icon: WorkFollowIcons.flag,
                    tooltip: '设置优先级',
                    iconColor: _priorityColor(tokens),
                    onPressed: () => _pickPriority(anchor),
                    size: 30,
                    iconSize: WorkFollowMetrics.fieldIcon,
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(
            height: MatrixMetrics.taskRowDividerHeight, color: tokens.border),
        SizedBox(
          height: MatrixMetrics.addSurfaceBodyHeight,
          child: TextField(
            key: const ValueKey('matrix-add-title'),
            controller: title,
            focusNode: focus,
            autofocus: true,
            maxLines: 4,
            minLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: WorkFollowMacTypography.detailTitle,
              height: WorkFollowMacTypography.lineControl,
              fontWeight: WorkFollowMacWeight.regular,
            ),
            decoration: InputDecoration(
              hintText: '准备做什么?',
              hintStyle: TextStyle(color: tokens.textTertiary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: WorkFollowSpacing.space4,
                  vertical: WorkFollowSpacing.relaxedGap),
            ),
          ),
        ),
        Divider(
            height: MatrixMetrics.taskRowDividerHeight, color: tokens.border),
        SizedBox(
          height: MatrixMetrics.addSurfaceRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.cardInset),
            child: Row(
              children: [
                Builder(
                  builder: (anchor) => InkWell(
                    key: const ValueKey('matrix-add-list'),
                    borderRadius:
                        BorderRadius.circular(MatrixMetrics.addSurfaceRadius),
                    onTap: () => _pickList(anchor),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal:
                              WorkFollowSpacing.compactActionHorizontalPadding,
                          vertical:
                              WorkFollowSpacing.compactActionVerticalPadding),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(WorkFollowIcons.inbox,
                              size: WorkFollowMetrics.fieldIcon,
                              color: tokens.textSecondary),
                          const SizedBox(width: WorkFollowSpacing.space2),
                          Text(
                            listName,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: WorkFollowMacTypography.body,
                              fontWeight: WorkFollowMacWeight.semibold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Builder(
                  builder: (anchor) => AppIconButton(
                    key: const ValueKey('matrix-add-more'),
                    icon: WorkFollowIcons.more,
                    tooltip: '更多属性',
                    onPressed: () => _openMore(anchor),
                    size: 30,
                    iconSize: WorkFollowMetrics.fieldIcon,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _priorityColor(WorkFollowTheme tokens) => switch (priority) {
        TaskPriority.high => tokens.danger,
        TaskPriority.medium => tokens.warning,
        TaskPriority.low => tokens.accent,
        TaskPriority.none => tokens.textTertiary,
      };
}
