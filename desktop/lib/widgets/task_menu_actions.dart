import 'package:flutter/material.dart';

import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import 'task_menu_selection.dart';
import 'task_schedule_picker.dart';

/// Both task menu entry points execute the same application commands.
Future<TaskActionResult?> runTaskMenuAction(
    BuildContext context,
    WorkspaceController controller,
    TaskItem task,
    TaskMenuSelection selection) async {
  final actions = controller.taskActions;
  final id = task.id;
  switch (selection.action) {
    case 'today':
    case 'tomorrow':
    case 'next-7':
      final offset =
          switch (selection.action) { 'tomorrow' => 1, 'next-7' => 7, _ => 0 };
      final now = DateTime.now();
      return actions.setSchedule(
          id,
          TaskScheduleDraft.forDay(
              DateTime(now.year, now.month, now.day + offset),
              preserveClock: localDateTimeFromStorage(task.dueAt),
              hasTime: task.scheduledWithTime));
    case 'date':
      final value = await TaskSchedulePicker.show(context,
          value: task.dueAt, hasTime: task.scheduledWithTime);
      if (value == null) return null;
      return actions.setSchedule(
          id, TaskScheduleDraft(dueAt: value.date, hasTime: value.hasTime));
    case 'clear-date':
      return actions.clearSchedule(id);
    case 'skip-occurrence':
      return actions.skipOccurrence(id);
    case 'priority-high':
      return actions.setPriority(id, TaskPriority.high);
    case 'priority-medium':
      return actions.setPriority(id, TaskPriority.medium);
    case 'priority-low':
      return actions.setPriority(id, TaskPriority.low);
    case 'priority-none':
      return actions.setPriority(id, TaskPriority.none);
    case 'set-list':
      return actions.moveToList(id, selection.value!);
    case 'set-tags':
      return actions.setTags(id, selection.value!.split(RegExp('[,，]')));
    case 'add-subtask':
      controller.requestSubtaskEditor(id);
      return null;
    case 'pin':
      return actions.setPinned(id, !task.isPinned);
    case 'abandon':
      final messenger = ScaffoldMessenger.of(context);
      final result =
          task.isAbandoned ? actions.restore(id) : actions.abandon(id);
      if (result.success)
        messenger.showSnackBar(SnackBar(
          content: Text(result.message!),
          action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                result.undo?.execute();
              }),
        ));
      return null;
    case 'convert-note':
      // The originating row disappears on conversion; its feedback belongs to
      // the workspace messenger and must outlive that row.
      final messenger = ScaffoldMessenger.of(context);
      final result = actions.convertToNote(id);
      if (result.success)
        messenger.showSnackBar(SnackBar(
          content: Text(result.message!),
          action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                result.undo?.execute();
              }),
        ));
      return null;
    case 'delete':
      return actions.delete(id);
  }
  return null;
}
