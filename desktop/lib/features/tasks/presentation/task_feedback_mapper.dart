import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../theme/workfollow_icons.dart';
import '../../feedback/feedback_controller.dart';
import '../../feedback/feedback_event.dart';
import '../../feedback/feedback_scope.dart';
import '../application/task_actions.dart';

/// Translates a [TaskActionResult] into feedback, or into nothing.
///
/// This is the only place that knows a task result and the feedback model at
/// the same time. Entry points call [presentTaskResult] and stop thinking about
/// it; they no longer inspect `undo.label` to guess whether they are allowed to
/// show an undo, and they no longer own a `SnackBar`.
///
/// A null return means "say nothing" — most property edits are visible in the
/// row itself and do not need a HUD.
WorkFollowFeedback? feedbackForTaskResult(TaskActionResult result) {
  if (!result.success) {
    final message = result.message;
    if (message == null || message.isEmpty) return null;
    // Failures never borrow the completion treatment: a chime and a dark HUD
    // for "无法创建任务" reads as success.
    return WorkFollowFeedback(
        kind: WorkFollowFeedbackKind.error, message: message);
  }
  final message = result.message;
  if (message == null || message.isEmpty) return null;
  final undo = result.undo;
  final canUndo = undo != null;

  switch (result.feedback) {
    case TaskFeedbackIntent.completion:
      return WorkFollowFeedback(
          kind: WorkFollowFeedbackKind.completion,
          message: message,
          actionLabel: '撤销',
          actionIcon: WorkFollowIcons.undo,
          onAction: canUndo ? () => _runUndo(undo) : null,
          sound: WorkFollowFeedbackSound.completion,
          // Only a single task is aggregated. A batch already reports its own
          // total ("已完成 3 个任务"), and folding a later single completion
          // into it would recount to 2.
          coalesceKey: result.taskId == null ? null : 'task-completed',
          coalescedMessage: result.taskId == null
              ? null
              : (count) => '已完成 $count 个任务');
    case TaskFeedbackIntent.undoable:
      return WorkFollowFeedback(
          kind: WorkFollowFeedbackKind.undoable,
          message: message,
          actionLabel: canUndo ? '撤销' : null,
          actionIcon: canUndo ? WorkFollowIcons.undo : null,
          onAction: canUndo ? () => _runUndo(undo) : null);
    case TaskFeedbackIntent.success:
      return WorkFollowFeedback(
          kind: WorkFollowFeedbackKind.success, message: message);
    case TaskFeedbackIntent.navigation:
      return _navigation(result, message);
    case TaskFeedbackIntent.none:
      break;
  }

  // Not yet migrated: the result carries no intent, so fall back to what the
  // previous implementation inferred, minus the row-local SnackBar.
  if (result.showFeedback && !canUndo) {
    return WorkFollowFeedback(
        kind: WorkFollowFeedbackKind.success, message: message);
  }
  if (canUndo) {
    return WorkFollowFeedback(
        kind: WorkFollowFeedbackKind.undoable,
        message: message,
        actionLabel: '撤销',
        actionIcon: WorkFollowIcons.undo,
        onAction: () => _runUndo(undo));
  }
  if (_movedAway(result)) return _navigation(result, message);
  return null;
}

/// Presents [result] through the app's single feedback channel.
///
/// [actionVersion] marks the mutation as already reported, which is what keeps
/// the shell's legacy `actionVersion` watcher from showing the same action a
/// second time.
void presentTaskResult(FeedbackController feedback, TaskActionResult result,
    {int? actionVersion}) {
  final item = feedbackForTaskResult(result);
  if (item == null) return;
  feedback.show(item, actionVersion: actionVersion);
}

/// Looks the shell's controller up from [context] and presents [result].
///
/// The form every entry point uses. A widget mounted without a host — a row in
/// a widget test, a preview — silently reports nothing instead of throwing,
/// which is why this goes through [FeedbackScope.maybeOf].
void presentTaskResultIn(BuildContext context, TaskActionResult result,
    {int? actionVersion}) {
  final feedback = FeedbackScope.maybeOf(context);
  if (feedback == null) return;
  presentTaskResult(feedback, result, actionVersion: actionVersion);
}

/// The result moved the task out of the current list but has nothing to undo.
WorkFollowFeedback? _navigation(TaskActionResult result, String message) {
  final id = result.taskId;
  if (id == null || !_movedAway(result)) return null;
  return WorkFollowFeedback(kind: WorkFollowFeedbackKind.success, message: message);
}

/// Feedback for a task that landed somewhere the user is not looking, with the
/// affordance to follow it instead of an undo.
///
/// Creation is the case that needs this: the row is not in the current list, so
/// the result is otherwise invisible, and 撤销 is the wrong offer — the user
/// wanted the task, not to take it back.
WorkFollowFeedback movedAwayFeedback(TaskActionResult result,
    {required VoidCallback onOpen}) {
  return WorkFollowFeedback(
      kind: WorkFollowFeedbackKind.success,
      message: result.message ?? '已创建任务',
      actionLabel: '查看任务',
      actionIcon: WorkFollowIcons.next,
      onAction: onOpen);
}

bool _movedAway(TaskActionResult result) {
  final destination = result.destination;
  return result.taskId != null &&
      destination != null &&
      destination != TaskDestination.current &&
      destination != TaskDestination.hidden;
}

/// Undo commands may be async; the HUD does not wait for them.
void _runUndo(UndoCommand? undo) {
  if (undo == null) return;
  final outcome = undo.execute();
  if (outcome is Future<bool>) unawaited(outcome);
}
