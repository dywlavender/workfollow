import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import 'desktop_popover.dart';
import 'task_context_menu_panel.dart';

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
    return showAnchoredPopover<String>(anchor,
        width: 264,
        maxHeight: 660,
        placement: PopoverPlacement.bottomStart,
        focusPolicy: PopoverFocusPolicy.firstItem,
        scrollable: true,
        anchorRect:
            globalPosition == null ? null : globalPosition & const Size(1, 1),
        builder: (_) => TaskContextMenuPanel(task: task));
  }
}
