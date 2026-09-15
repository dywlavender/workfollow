import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import 'desktop_popover.dart';

/// Shared row context-menu definition. Keeping labels and action identifiers
/// in one place prevents the list row, board and future table views from
/// drifting apart.
class TaskContextMenu {
  const TaskContextMenu._();

  static Future<String?> show(
    BuildContext anchor, {
    required TaskItem task,
    required WorkspaceController controller,
    Offset? globalPosition,
  }) {
    return showDesktopMenu<String>(anchor,
        placement: PopoverPlacement.bottomStart,
        anchorRect:
            globalPosition == null ? null : globalPosition & const Size(1, 1),
        entries: [
          DesktopMenuEntry('complete', task.completed ? '标记未完成' : '完成任务',
              icon: Icons.check),
          const DesktopMenuEntry('today', '安排到今天', icon: Icons.today_outlined),
          const DesktopMenuEntry('tomorrow', '安排到明天',
              icon: Icons.event_outlined),
          const DesktopMenuEntry('date', '安排其他日期…',
              icon: Icons.calendar_today_outlined),
          if (task.dueAt != null || task.hasDueTime == true)
            const DesktopMenuEntry('clear-date', '清除日期',
                icon: Icons.event_busy_outlined),
          const DesktopMenuEntry('priority-high', '设置高优先级',
              icon: Icons.flag_outlined),
          const DesktopMenuEntry('priority-medium', '设置中优先级',
              icon: Icons.flag_outlined),
          const DesktopMenuEntry('priority-low', '设置低优先级',
              icon: Icons.flag_outlined),
          const DesktopMenuEntry('priority-none', '取消优先级',
              icon: Icons.flag_outlined),
          const DesktopMenuEntry('list', '移动到清单…',
              icon: Icons.drive_file_move_outlined),
          const DesktopMenuEntry('tags', '编辑标签…', icon: Icons.tag_rounded),
          const DesktopMenuEntry('reminder', '设置提醒…',
              icon: Icons.notifications_none_rounded),
          const DesktopMenuEntry('repeat', '设置重复…', icon: Icons.repeat_rounded),
          const DesktopMenuEntry('deadline', '设置截止日期…',
              icon: Icons.flag_outlined),
          const DesktopMenuEntry('duplicate', '创建副本',
              icon: Icons.control_point_duplicate_outlined),
          const DesktopMenuEntry('delete', '移到废纸篓',
              icon: Icons.delete_outline, destructive: true),
        ]);
  }
}
