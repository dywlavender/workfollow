import 'package:flutter/material.dart';

import '../models/task.dart';
import 'desktop_popover.dart';

class TaskPriorityPicker {
  const TaskPriorityPicker._();

  static Future<TaskPriority?> show(BuildContext anchor,
      {TaskPriority? selected}) {
    return showDesktopMenu<TaskPriority>(anchor,
        selected: selected,
        placement: PopoverPlacement.bottomStart,
        entries: [
          for (final priority in TaskPriority.values)
            DesktopMenuEntry(
              priority,
              priority == TaskPriority.none ? '无优先级' : priority.label,
              icon: Icons.flag_outlined,
            ),
        ]);
  }
}
