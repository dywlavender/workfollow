import 'dart:async';

import '../../../models/task.dart';
import '../domain/task_draft.dart';
import '../domain/task_schedule.dart';
import '../domain/task_schedule_settings.dart';

enum TaskDestination {
  current,
  today,
  recent,
  overdue,
  inbox,
  plan,
  list,
  completed,
  hidden,
}

class TaskActionError {
  const TaskActionError(this.code, this.message);

  final String code;
  final String message;
}

typedef UndoCallback = FutureOr<bool> Function();

class UndoCommand {
  const UndoCommand({required this.label, required this.execute});

  final String label;
  final UndoCallback execute;
}

/// The only result shape exposed to task widgets.  A UI can render feedback
/// and navigation from this value without recomputing projections itself.
class TaskActionResult {
  const TaskActionResult({
    required this.success,
    this.taskId,
    this.destination,
    this.message,
    this.showFeedback = false,
    this.undo,
    this.error,
    this.feedback = TaskFeedbackIntent.none,
  });

  const TaskActionResult.success({
    String? taskId,
    TaskDestination? destination,
    String? message,
    bool showFeedback = false,
    UndoCommand? undo,
    TaskFeedbackIntent feedback = TaskFeedbackIntent.none,
  }) : this(
          success: true,
          taskId: taskId,
          destination: destination,
          message: message,
          showFeedback: showFeedback,
          undo: undo,
          feedback: feedback,
        );

  TaskActionResult.failure(String code, String message)
      : this(
          success: false,
          error: TaskActionError(code, message),
          message: message,
        );

  final bool success;
  final String? taskId;
  final TaskDestination? destination;
  final String? message;

  /// Some successful actions (for example creating a duplicate) keep the
  /// task in the current projection and have no undo command, but still need
  /// one concise confirmation in the originating surface.
  final bool showFeedback;

  /// What this result means, so the UI does not have to infer it.
  ///
  /// `none` is the not-yet-migrated case: the presenter falls back to the
  /// previous heuristics (undo present, destination changed, `showFeedback`).
  /// Every action that has been migrated states its intent here instead of
  /// leaving the reader to match on `undo.label`.
  final TaskFeedbackIntent feedback;

  final UndoCommand? undo;
  final TaskActionError? error;

  bool get changed => success;
}

/// The semantic outcome of a task action.
///
/// Not a visual style: `completion` means "the user finished something", and
/// whether that becomes a dark HUD, a chime, a banner or nothing at all is
/// decided by the feedback layer.
enum TaskFeedbackIntent {
  /// Unset; the presenter falls back to legacy inference.
  none,

  /// A task or batch was finished. The only intent that carries a sound.
  completion,

  /// Something changed and there is nothing to take back.
  success,

  /// Something changed and can be undone.
  undoable,

  /// The task left the current projection; the message is about where it went.
  navigation,
}

/// Stable application boundary used by QuickAdd, rows, inspectors, menus and
/// keyboard commands. Implementations are deliberately synchronous at the UI
/// boundary; persistence and notification scheduling remain controller work.
abstract class TaskActions {
  TaskActionResult create(TaskDraft draft);

  TaskActionResult setTitle(String id, String title);

  TaskActionResult setDescription(String id, String description);

  /// Replaces the task's structured document and its plain-text projection in
  /// one action. The projection keeps list/search/legacy exports compatible
  /// while `contentJson` remains the editor's source of truth.
  TaskActionResult setContent(
      String id, Map<String, dynamic> contentJson, String plainText);

  TaskActionResult setSourceNote(String id, String? noteId);

  TaskActionResult complete(String id);

  /// Skips only the current occurrence of a recurring task. This is not a
  /// completion and must create the next occurrence through the recurrence
  /// engine before removing the current instance from active projections.
  TaskActionResult skipOccurrence(String id);

  TaskActionResult restore(String id);

  TaskActionResult setSchedule(String id, TaskScheduleDraft value);

  TaskActionResult setScheduleSettings(String id, TaskScheduleSettings value);

  TaskActionResult clearSchedule(String id);

  TaskActionResult setReminder(String id, DateTime? reminder);

  TaskActionResult clearReminder(String id);

  TaskActionResult setRecurrence(String id, RecurrenceDraft recurrence);

  TaskActionResult clearRecurrence(String id);

  TaskActionResult setPriority(String id, TaskPriority priority);

  TaskActionResult moveToList(String id, String listName);

  TaskActionResult setTags(String id, List<String> tags);

  TaskActionResult setDeadline(String id, DateTime? deadline);

  TaskActionResult clearDeadline(String id);

  TaskActionResult setPinned(String id, bool pinned);

  TaskActionResult abandon(String id);

  TaskActionResult convertToNote(String id);

  TaskActionResult duplicate(String id);

  TaskActionResult delete(String id);

  TaskActionResult undo();

  TaskActionResult bulkComplete(Iterable<String> ids);

  TaskActionResult bulkSchedule(Iterable<String> ids, TaskScheduleDraft value);

  TaskActionResult bulkMove(Iterable<String> ids, String listName);

  TaskActionResult bulkDelete(Iterable<String> ids);
}

typedef TaskActionDispatcher = TaskActionResult Function(
    String action, Object? payload);

/// Adapter used by the current WorkspaceController while responsibilities are
/// migrated out of the legacy facade. It keeps old public methods compatible
/// while guaranteeing every new UI entry point uses one action vocabulary.
class CallbackTaskActions implements TaskActions {
  const CallbackTaskActions(this.dispatch);

  final TaskActionDispatcher dispatch;

  @override
  TaskActionResult create(TaskDraft draft) => dispatch('create', draft);

  @override
  TaskActionResult setTitle(String id, String title) =>
      dispatch('setTitle', (id, title));

  @override
  TaskActionResult setDescription(String id, String description) =>
      dispatch('setDescription', (id, description));

  @override
  TaskActionResult setContent(
          String id, Map<String, dynamic> contentJson, String plainText) =>
      dispatch('setContent', (id, contentJson, plainText));

  @override
  TaskActionResult setSourceNote(String id, String? noteId) =>
      dispatch('setSourceNote', (id, noteId));

  @override
  TaskActionResult complete(String id) => dispatch('complete', id);

  @override
  TaskActionResult skipOccurrence(String id) => dispatch('skipOccurrence', id);

  @override
  TaskActionResult restore(String id) => dispatch('restore', id);

  @override
  TaskActionResult setSchedule(String id, TaskScheduleDraft value) =>
      dispatch('setSchedule', (id, value));

  @override
  TaskActionResult setScheduleSettings(String id, TaskScheduleSettings value) =>
      dispatch('setScheduleSettings', (id, value));

  @override
  TaskActionResult clearSchedule(String id) => dispatch('clearSchedule', id);

  @override
  TaskActionResult setReminder(String id, DateTime? reminder) =>
      dispatch('setReminder', (id, reminder));

  @override
  TaskActionResult clearReminder(String id) => dispatch('clearReminder', id);

  @override
  TaskActionResult setRecurrence(String id, RecurrenceDraft recurrence) =>
      dispatch('setRecurrence', (id, recurrence));

  @override
  TaskActionResult clearRecurrence(String id) =>
      dispatch('clearRecurrence', id);

  @override
  TaskActionResult setPriority(String id, TaskPriority priority) =>
      dispatch('setPriority', (id, priority));

  @override
  TaskActionResult moveToList(String id, String listName) =>
      dispatch('moveToList', (id, listName));

  @override
  TaskActionResult setTags(String id, List<String> tags) =>
      dispatch('setTags', (id, tags));

  @override
  TaskActionResult setDeadline(String id, DateTime? deadline) =>
      dispatch('setDeadline', (id, deadline));

  @override
  TaskActionResult clearDeadline(String id) => dispatch('clearDeadline', id);

  @override
  TaskActionResult setPinned(String id, bool pinned) =>
      dispatch('setPinned', (id, pinned));

  @override
  TaskActionResult abandon(String id) => dispatch('abandon', id);

  @override
  TaskActionResult convertToNote(String id) => dispatch('convertToNote', id);

  @override
  TaskActionResult duplicate(String id) => dispatch('duplicate', id);

  @override
  TaskActionResult delete(String id) => dispatch('delete', id);

  @override
  TaskActionResult undo() => dispatch('undo', null);

  @override
  TaskActionResult bulkComplete(Iterable<String> ids) =>
      dispatch('bulkComplete', ids.toList(growable: false));

  @override
  TaskActionResult bulkSchedule(
          Iterable<String> ids, TaskScheduleDraft value) =>
      dispatch('bulkSchedule', (ids.toList(growable: false), value));

  @override
  TaskActionResult bulkMove(Iterable<String> ids, String listName) =>
      dispatch('bulkMove', (ids.toList(growable: false), listName));

  @override
  TaskActionResult bulkDelete(Iterable<String> ids) =>
      dispatch('bulkDelete', ids.toList(growable: false));
}
