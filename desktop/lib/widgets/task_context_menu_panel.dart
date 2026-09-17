import 'task_menu_glyph.dart';
import 'task_menu_style.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_interaction_states.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import '../state/workspace_controller.dart';
import 'desktop_popover.dart';
import 'task_menu_selection.dart';
import 'task_list_picker.dart';
import 'task_tag_picker.dart';

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
class TaskContextMenuPanel extends StatefulWidget {
  const TaskContextMenuPanel(
      {super.key,
      required this.task,
      this.controller,
      this.inspectorActions = false});

  final TaskItem task;
  final WorkspaceController? controller;
  final bool inspectorActions;

  @override
  State<TaskContextMenuPanel> createState() => _TaskContextMenuPanelState();
}

class _TaskContextMenuPanelState extends State<TaskContextMenuPanel> {
  TaskItem get task => widget.task;
  Timer? hoverTimer;
  String? submenu;

  @override
  void dispose() {
    hoverTimer?.cancel();
    super.dispose();
  }

  Future<void> _openSubmenu(BuildContext anchor, String action) async {
    hoverTimer?.cancel();
    final controller = widget.controller;
    if (controller == null || submenu != null) return;
    setState(() => submenu = action);
    final result = action == 'tags'
        ? await TaskTagPicker.show(anchor,
            initial: task.tags.join('，'),
            availableTags: controller.allTags().keys,
            placement: const PopoverPlacement(
                preferredSide: PopoverSide.right,
                gap: WorkFollowSpacing.relaxedGap))
        : await TaskListPicker.show(anchor,
            controller: controller,
            selected: task.listName,
            placement: const PopoverPlacement(
                preferredSide: PopoverSide.right,
                gap: WorkFollowSpacing.relaxedGap));
    if (!mounted) return;
    setState(() => submenu = null);
    if (result != null)
      Navigator.of(context)
          .pop(TaskMenuSelection('set-$action', value: result));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = TaskMenuStyle.colors(context);
    return Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent)
            return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            FocusScope.of(context).nextFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            FocusScope.of(context).previousFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          container: true,
          label: '任务操作',
          child: Padding(
            key: const ValueKey('task-context-menu-panel'),
            padding: const EdgeInsets.symmetric(
                vertical: WorkFollowSpacing.inlineGap,
                horizontal: WorkFollowSpacing.compactGap),
            child: Column(
              key: const ValueKey('task-context-menu-content'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.inspectorActions) ...[
                  _sectionLabel('日期', tokens),
                  _dateSection(context, tokens),
                  _sectionLabel('优先级', tokens),
                  _prioritySection(context, tokens),
                  const _MenuDivider(),
                ],
                _actionSection(context, tokens),
                const _MenuDivider(),
                _processingSection(context, tokens),
              ],
            ),
          ),
        ));
  }

  Widget _sectionLabel(String label, WorkFollowTheme tokens) => Padding(
        padding: const EdgeInsets.fromLTRB(
            WorkFollowSpacing.space3,
            WorkFollowSpacing.space2,
            WorkFollowSpacing.space3,
            WorkFollowSpacing.denseGap),
        child: Text(label,
            style: TextStyle(
                fontSize: WorkFollowMacTypography.sectionTitle,
                color: tokens.textTertiary)),
      );

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
        ? tokens.textDisabled
        : action == TaskContextDateAction.skipOccurrence
            ? tokens.warning
            : selected
                ? tokens.accent
                : tokens.textPrimary;
    final tooltip = action == TaskContextDateAction.next7 ? '安排到 7 天后' : label;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: InkWell(
          key: ValueKey('menu-option-$value'),
          autofocus: action == TaskContextDateAction.today,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          focusColor: WorkFollowInteractionStyles.focusColor(tokens),
          overlayColor: WorkFollowInteractionStyles.overlay(
            tokens,
            menu: true,
          ),
          onTap: enabled
              ? () => Navigator.of(context).pop(TaskMenuSelection(value))
              : null,
          child: Container(
            height: TaskMenuMetrics.dateGridCellHeight,
            margin: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.hairlineGap),
            decoration: BoxDecoration(
              color: WorkFollowInteractionStyles.fill(
                tokens,
                selected: selected,
                menu: true,
              ),
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            ),
            alignment: Alignment.center,
            child: action == TaskContextDateAction.skipOccurrence
                ? AppIcon(icon!,
                    size: WorkFollowMetrics.fieldIcon, color: foreground)
                : TaskMenuGlyph(value,
                    size: WorkFollowMetrics.fieldIcon, color: foreground),
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
      TaskPriority.none => tokens.textPrimary,
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
          focusColor: WorkFollowInteractionStyles.focusColor(tokens),
          overlayColor: WorkFollowInteractionStyles.overlay(
            tokens,
            menu: true,
          ),
          onTap: () => Navigator.of(context).pop(TaskMenuSelection(value)),
          child: Container(
            height: WorkFollowMetrics.menuRowHeight,
            margin: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.hairlineGap),
            decoration: BoxDecoration(
              color: WorkFollowInteractionStyles.fill(
                tokens,
                selected: selected,
                menu: true,
              ),
              borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            ),
            alignment: Alignment.center,
            child: TaskMenuGlyph('flag',
                size: WorkFollowMetrics.fieldIcon,
                color: foreground,
                filled: priority != TaskPriority.none),
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
        _row(context, tokens, value: 'add-subtask', label: '添加子任务'),
        _row(context, tokens,
            value: 'pin', label: task.isPinned ? '取消置顶' : '置顶'),
        _row(context, tokens,
            value: 'abandon',
            label: task.isAbandoned ? '恢复任务' : '放弃',
            enabled: !task.completed),
        _row(context, tokens,
            value: 'list', label: '移动到', trailing: WorkFollowIcons.chevronNext),
        _row(context, tokens,
            value: 'tags', label: '标签', trailing: WorkFollowIcons.chevronNext),
      ],
    );
  }

  Widget _processingSection(BuildContext context, WorkFollowTheme tokens) {
    return Column(
      key: const ValueKey('task-context-processing-section'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context, tokens, value: 'convert-note', label: '转换为笔记'),
        if (widget.inspectorActions) ...[
          const _MenuDivider(),
          _row(context, tokens, value: 'reminder', label: '设置提醒'),
          _row(context, tokens, value: 'repeat', label: '设置重复'),
          _row(context, tokens, value: 'deadline', label: '截止日期'),
          _row(context, tokens, value: 'attachment', label: '添加附件'),
          _row(context, tokens, value: 'focus', label: '专注记录'),
          _row(context, tokens, value: 'relation', label: '关联笔记'),
          const _MenuDivider(),
        ],
        _row(context, tokens, value: 'delete', label: '删除', destructive: true),
      ],
    );
  }

  Widget _row(BuildContext context, WorkFollowTheme tokens,
      {required String value,
      required String label,
      IconData? trailing,
      bool destructive = false,
      bool enabled = true}) {
    final foreground = !enabled
        ? WorkFollowInteractionStyles.foreground(tokens, enabled: false)
        : WorkFollowInteractionStyles.foreground(tokens,
            destructive: destructive);
    return Builder(
        builder: (rowContext) => MouseRegion(
            onEnter: (_) {
              if (trailing == null || widget.controller == null) return;
              hoverTimer?.cancel();
              hoverTimer = Timer(const Duration(milliseconds: 220), () {
                if (mounted && rowContext.mounted)
                  _openSubmenu(rowContext, value);
              });
            },
            onExit: (_) => hoverTimer?.cancel(),
            child: Semantics(
              button: true,
              enabled: enabled,
              label: label,
              child: InkWell(
                  key: ValueKey('menu-option-$value'),
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                  focusColor: WorkFollowInteractionStyles.focusColor(tokens),
                  overlayColor: WorkFollowInteractionStyles.overlay(
                    tokens,
                    destructive: destructive,
                    menu: true,
                  ),
                  onTap: !enabled
                      ? null
                      : () {
                          if (trailing != null && widget.controller != null) {
                            _openSubmenu(rowContext, value);
                          } else {
                            Navigator.of(context).pop(TaskMenuSelection(value));
                          }
                        },
                  child: Ink(
                    decoration: BoxDecoration(
                        color: WorkFollowInteractionStyles.fill(
                          tokens,
                          selected: submenu == value,
                          menu: true,
                        ),
                        borderRadius:
                            BorderRadius.circular(WorkFollowRadii.control)),
                    child: SizedBox(
                      height: TaskMenuStyle.rowHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal:
                                WorkFollowSpacing.contextMenuHorizontalPadding),
                        child: Row(children: [
                          AppIcon(
                              WorkFollowIcons.taskAction(value,
                                  restored:
                                      value == 'abandon' && task.isAbandoned),
                              size: WorkFollowMetrics.fieldIcon,
                              color: foreground),
                          const SizedBox(width: WorkFollowSpacing.space3),
                          Expanded(
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: WorkFollowMacTypography.menu,
                                    height: WorkFollowMacTypography.lineControl,
                                    fontWeight: WorkFollowMacWeight.regular,
                                    letterSpacing: WorkFollowMacTracking.none,
                                    color: foreground)),
                          ),
                          if (trailing != null)
                            AppIcon(trailing,
                                size: WorkFollowMetrics.metadataIcon,
                                color:
                                    enabled ? tokens.textTertiary : foreground),
                        ]),
                      ),
                    ),
                  )),
            )));
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
    final tokens = TaskMenuStyle.colors(context);
    return Divider(
      height: 13,
      thickness: 1,
      color: tokens.border.withValues(alpha: .72),
      indent: 4,
      endIndent: 4,
    );
  }
}
