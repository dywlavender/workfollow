import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import 'desktop_popover.dart';

class TaskListPicker {
  const TaskListPicker._();

  static Future<String?> show(BuildContext anchor,
      {required WorkspaceController controller, String? selected}) {
    return showDesktopMenu<String>(anchor,
        selected: selected,
        entries: [
          for (final list in controller.orderedLists)
            DesktopMenuEntry(list.name, list.name, icon: Icons.list_rounded),
        ]);
  }
}
