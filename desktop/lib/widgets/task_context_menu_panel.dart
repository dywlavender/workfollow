import 'package:flutter/material.dart';

import '../models/task.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

/// The small date actions shown at the top of a task context menu.
///
/// Keeping this vocabulary separate from the string values returned by the
/// panel makes the recurring-only action explicit. In particular,
/// [skipOccurrence] is not an alternate spelling of completion or clearing a
/// schedule: it is a distinct business command handled by TaskActions.
enum TaskContextDateAction {
  today,
  tomorrow,
  next7,
  skipOccurrence,
  custom,
  clearDate,
}

/// TickTick-inspired task menu surface.
///
/// The surface is intentionally a composite instead of a flat list. Date
/// shortcuts and priority are compact grids, while the rest of the menu uses
/// grouped rows with consistent chevrons and destructive styling.
class TaskContextMenuPanel extends StatelessWidget {
  const TaskContextMenuPanel({super.key, required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Semantics(
      container: true,
      label: '任务操作',
      child: Padding(
        key: const ValueKey('task-context-menu-panel'),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 7),
        child: Column(
          key: const ValueKey('task-context-menu-content'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dateSection(context, tokens),
            const _MenuDivider(),
            _prioritySection(context, tokens),
            const _MenuDivider(),
            _actionSection(context, tokens),
            const _MenuDivider(),
            _processingSection(context, tokens),
          ],
        ),
      ),
    );
  }

  Widget _dateSection(BuildContext context, WorkFollowTheme tokens) {
    final actions = <TaskContextDateAction>[
      TaskContextDateAction.today,
      TaskContextDateAction.tomorrow,
      TaskContextDateAction.next7,
      if (task.recurrenceType.toUpperCase() != 'NONE')
        TaskContextDateAction.skipOccurrence,
      TaskContextDateAction.custom,
      TaskContextDateAction.clearDate,
    ];
    return Row(
      key: const ValueKey('task-context-date-section'),
      children: [
        for (final action in actions)
          Expanded(child: _dateButton(context, tokens, action)),
      ],
    );
  }

  Widget _dateButton(BuildContext context, WorkFollowTheme tokens,
      TaskContextDateAction action) {
    final enabled = action != TaskContextDateAction.clearDate ||
        task.dueAt != null ||
        task.hasDueTime == true;
    final selected = switch (action) {
      TaskContextDateAction.today =>
        _isSameDay(localDateTimeFromStorage(task.dueAt), DateTime.now()),
      TaskContextDateAction.tomorrow => _isSameDay(
          localDateTimeFromStorage(task.dueAt),
          DateTime.now().add(const Duration(days: 1))),
      _ => false,
    };
    final icon = switch (action) {
      TaskContextDateAction.today => WorkFollowIcons.today,
      TaskContextDateAction.tomorrow => WorkFollowIcons.tomorrow,
      TaskContextDateAction.next7 => null,
      TaskContextDateAction.skipOccurrence => WorkFollowIcons.skip,
      TaskContextDateAction.custom => WorkFollowIcons.calendar,
      TaskContextDateAction.clearDate => WorkFollowIcons.clearDate,
    };
    final label = switch (action) {
      TaskContextDateAction.today => '今天',
      TaskContextDateAction.tomorrow => '明天',
      TaskContextDateAction.next7 => '+7',
      TaskContextDateAction.skipOccurrence => '跳过此周期',
      TaskContextDateAction.custom => '选择日期',
      TaskContextDateAction.clearDate => '清除日期',
    };
    final value = switch (action) {
      TaskContextDateAction.today => 'today',
      TaskContextDateAction.tomorrow => 'tomorrow',
      TaskContextDateAction.next7 => 'next-7',
      TaskContextDateAction.skipOccurrence => 'skip-occurrence',
      TaskContextDateAction.custom => 'date',
      TaskContextDateAction.clearDate => 'clear-date',
    };
    final foreground = !enabled
        ? tokens.textTertiary.withValues(alpha: .45)
        : action == TaskContextDateAction.skipOccurrence
            ? tokens.warning
            : selected
                ? tokens.accent
                : tokens.textSecondary;
    final tooltip = action == TaskContextDateAction.next7 ? '安排到 7 天后' : label;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: InkWell(
          key: ValueKey('menu-option-$value'),
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          onTap: enabled ? () => Navigator.of(context).pop(value) : null,
          child: Container(
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: selected ? tokens.accentFaint : null,
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            ),
            alignment: Alignment.center,
            child: icon == null
                ? Text(label,
                    style: TextStyle(
                        fontSize: WorkFollowTypography.webLabel,
                        fontWeight: FontWeight.w600,
                        color: foreground))
                : AppIcon(icon,
                    size: WorkFollowMetrics.toolbarIcon, color: foreground),
          ),
        ),
      ),
    );
  }

  Widget _prioritySection(BuildContext context, WorkFollowTheme tokens) {
    const values = <TaskPriority>[
      TaskPriority.high,
      TaskPriority.medium,
      TaskPriority.low,
      TaskPriority.none,
    ];
    return Row(
      key: const ValueKey('task-context-priority-section'),
      children: [
        for (final priority in values)
          Expanded(child: _priorityButton(context, tokens, priority)),
      ],
    );
  }

  Widget _priorityButton(
      BuildContext context, WorkFollowTheme tokens, TaskPriority priority) {
    final selected = task.priority == priority;
    final foreground = switch (priority) {
      TaskPriority.high => tokens.danger,
      TaskPriority.medium => tokens.warning,
      TaskPriority.low => tokens.accent,
      TaskPriority.none => tokens.textTertiary,
    };
    final value = 'priority-${priority.name}';
    return Tooltip(
      message: priority.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: priority.label,
        child: InkWell(
          key: ValueKey('menu-option-$value'),
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          onTap: () => Navigator.of(context).pop(value),
          child: Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: selected ? tokens.accentFaint : null,
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            ),
            alignment: Alignment.center,
            child: AppIcon(WorkFollowIcons.flag,
                size: WorkFollowMetrics.toolbarIcon, color: foreground),
          ),
        ),
      ),
    );
  }

  Widget _actionSection(BuildContext context, WorkFollowTheme tokens) {
    return Column(
      key: const ValueKey('task-context-action-section'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context, tokens,
            value: 'add-subtask',
            label: '添加子任务',
            icon: WorkFollowIcons.subtask),
        _row(context, tokens,
            value: 'pin',
            label: '置顶',
            icon: WorkFollowIcons.favoriteOutline,
            enabled: false),
        _row(context, tokens,
            value: 'abandon',
            label: '放弃',
            icon: WorkFollowIcons.forward,
            enabled: false),
        _row(context, tokens,
            value: 'list',
            label: '移动到',
            icon: WorkFollowIcons.move,
            trailing: WorkFollowIcons.chevronNext),
        _row(context, tokens,
            value: 'tags',
            label: '标签',
            icon: WorkFollowIcons.tag,
            trailing: WorkFollowIcons.chevronNext),
      ],
    );
  }

  Widget _processingSection(BuildContext context, WorkFollowTheme tokens) {
    return Column(
      key: const ValueKey('task-context-processing-section'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context, tokens,
            value: 'duplicate', label: '创建副本', icon: WorkFollowIcons.duplicate),
        _row(context, tokens,
            value: 'copy-link', label: '复制链接', icon: WorkFollowIcons.link),
        _row(context, tokens,
            value: 'open-note',
            label: '打开便签',
            icon: WorkFollowIcons.notes,
            enabled: task.sourceNoteId != null),
        _row(context, tokens,
            value: 'convert-note',
            label: '转换为笔记',
            icon: WorkFollowIcons.noteAlt,
            enabled: false),
        _row(context, tokens,
            value: 'delete',
            label: '删除',
            icon: WorkFollowIcons.delete,
            destructive: true),
      ],
    );
  }

  Widget _row(BuildContext context, WorkFollowTheme tokens,
      {required String value,
      required String label,
      required IconData icon,
      IconData? trailing,
      bool destructive = false,
      bool enabled = true}) {
    final foreground = !enabled
        ? tokens.textTertiary.withValues(alpha: .42)
        : destructive
            ? tokens.danger
            : tokens.textPrimary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        key: ValueKey('menu-option-$value'),
        borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        onTap: enabled ? () => Navigator.of(context).pop(value) : null,
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              AppIcon(icon,
                  size: WorkFollowMetrics.toolbarIcon, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: WorkFollowTypography.webControlSize,
                        fontWeight: FontWeight.w500,
                        color: foreground)),
              ),
              if (trailing != null)
                AppIcon(trailing,
                    size: WorkFollowMetrics.metadataIcon,
                    color: enabled ? tokens.textTertiary : foreground),
            ]),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime? left, DateTime right) {
    return left != null &&
        left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Divider(
      height: 13,
      thickness: 1,
      color: tokens.border.withValues(alpha: .72),
      indent: 4,
      endIndent: 4,
    );
  }
}
