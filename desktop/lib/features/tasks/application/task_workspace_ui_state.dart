/// Ephemeral task-workspace state that belongs to the desktop shell rather
/// than to the persisted task collection.
///
/// Keeping focus requests and open-version counters here prevents a purely
/// visual event (opening an inspector or asking Quick Add to focus) from being
/// mistaken for a task mutation.  The workspace controller still exposes
/// compatibility getters while this value object remains framework-agnostic.
class TaskWorkspaceUiState {
  /// Width chosen for the task-list pane during this app session.
  ///
  /// It is deliberately nullable: the first task view resolves the default
  /// from [TaskListMetrics], while every later task view reuses the user's
  /// workspace choice. Persistence belongs to a later preference decision,
  /// not to this ephemeral shell state.
  double? taskListPaneWidth;
  int taskOpenVersion = 0;
  int noteOpenVersion = 0;
  bool quickAddFocusPending = false;
  int inspectorTitleFocusVersion = 0;
  String? pendingInspectorTitleTaskId;
  String? pendingSubtaskTaskId;

  void requestQuickAddFocus() {
    quickAddFocusPending = true;
  }

  void consumeQuickAddFocus() {
    quickAddFocusPending = false;
  }

  void requestInspectorTitleFocus() {
    inspectorTitleFocusVersion += 1;
  }

  void markTaskOpened() {
    taskOpenVersion += 1;
  }

  void markNoteOpened() {
    noteOpenVersion += 1;
  }
}
