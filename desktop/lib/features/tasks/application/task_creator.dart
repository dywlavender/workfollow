import '../domain/task_draft.dart';
import 'task_actions.dart';

/// Creates one complete task from one Draft. Keeping this tiny object
/// separate makes it impossible for QuickAdd to accidentally fall back to a
/// sequence of add-then-update calls.
class TaskCreator {
  const TaskCreator(this.actions);

  final TaskActions actions;

  TaskActionResult create(TaskDraft draft) {
    final normalized = draft.normalized();
    if (!normalized.isValid) {
      return TaskActionResult.failure('empty-title', '请输入任务标题');
    }
    return actions.create(normalized);
  }
}
