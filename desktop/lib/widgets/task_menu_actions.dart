import 'package:flutter/material.dart';

import '../features/feedback/feedback_scope.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import '../models/task.dart';
import '../state/workspace_controller.dart';
import 'task_menu_selection.dart';
import 'task_schedule_panel.dart';

/// Both task menu entry points execute the same application commands.
Future<TaskActionResult?> runTaskMenuAction(
    BuildContext context,
    WorkspaceController controller,
    TaskItem task,
    TaskMenuSelection selection) async {
  final actions = controller.taskActions;
  final id = task.id;
  // Resolved before anything runs. Converting or abandoning removes the
  // originating row, so looking the channel up afterwards would depend on a
  // context that is already gone.
  final feedback = FeedbackScope.maybeOf(context);
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
      final value = await showTaskSchedulePanel(context, task);
      if (value == null) return null;
      return actions.setScheduleSettings(id, value);
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
      // The menu only reports the intent. The inspector owns the document
      // editor and turns this request into DocumentCommands.insertSubtaskBlock.
      controller.requestSubtaskEditor(id);
      return null;
    case 'pin':
      return actions.setPinned(id, !task.isPinned);
    case 'abandon':
      final result =
          task.isAbandoned ? actions.restore(id) : actions.abandon(id);
      // Reported here rather than returned: the menu is the last frame the row
      // exists in, so the caller has nothing left to show it from.
      if (feedback != null) {
        presentTaskResult(feedback, result,
            actionVersion: controller.actionVersion);
      }
      return null;
    case 'convert-note':
      final result = actions.convertToNote(id);
      if (feedback != null) {
        presentTaskResult(feedback, result,
            actionVersion: controller.actionVersion);
      }
      return null;
    case 'delete':
      return actions.delete(id);
  }
  return null;
}
