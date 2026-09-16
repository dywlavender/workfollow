import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import 'desktop_popover.dart';
import 'task_context_menu_panel.dart';
import 'task_menu_selection.dart';
import 'task_menu_style.dart';

/// Shared row context-menu definition. Keeping labels and action identifiers
/// in one place prevents the list row, board and future table views from
/// drifting apart.
class TaskContextMenu {
  const TaskContextMenu._();

  static Future<TaskMenuSelection?> show(
    BuildContext anchor, {
    required TaskItem task,
    required WorkspaceController controller,
    Offset? globalPosition,
    bool inspectorActions = false,
    PopoverPlacement placement = PopoverPlacement.bottomStart,
  }) {
    var maxHeight = 660.0;
    if (inspectorActions) {
      final box = anchor.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final top = box.localToGlobal(Offset.zero).dy;
        final above = math.max(0.0, top - 18);
        final below = math.max(
            0.0, MediaQuery.sizeOf(anchor).height - top - box.size.height - 18);
        maxHeight =
            math.min(maxHeight, above >= 200 ? above : math.max(above, below));
      }
    }
    return showAnchoredPopover<TaskMenuSelection>(anchor,
        width: TaskMenuStyle.width,
        maxHeight: maxHeight,
        placement: placement,
        focusPolicy: PopoverFocusPolicy.firstItem,
        scrollable: true,
        anchorRect:
            globalPosition == null ? null : globalPosition & const Size(1, 1),
        builder: (_) => TaskContextMenuPanel(
            task: task,
            controller: controller,
            inspectorActions: inspectorActions));
  }
}
