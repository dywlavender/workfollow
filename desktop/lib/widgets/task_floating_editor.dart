import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';
import 'task_editor_popover.dart';
import 'task_inspector.dart';

/// Opens the task editor as a floating surface anchored where the pointer is.
///
/// Pages organised by something other than a task list — the Matrix's
/// quadrants, the Calendar's days — have no detail pane to give up, so opening
/// a task cannot navigate away from them. The surface underneath is the page
/// itself, unchanged: this is the same document editor the detail pane hosts,
/// with the same properties and the same document, only anchored to the row or
/// the bar that was clicked.
///
/// The editor owns its own lifetime. It closes when the task it holds is gone,
/// so a task removed from inside the editor does not leave the surface behind
/// pointing at nothing.
Future<void> showTaskFloatingEditor(
  BuildContext anchor, {
  required WorkspaceController controller,
  required String taskId,
}) async {
  final viewport = MediaQuery.sizeOf(anchor);
  final maxHeight = (viewport.height - TaskSurfaceMetrics.editorViewportMargin)
      .clamp(
        TaskSurfaceMetrics.editorMinHeight,
        TaskSurfaceMetrics.editorMaxHeight,
      )
      .toDouble();

  await showTaskEditorPopover<void>(
    anchor,
    width: TaskSurfaceMetrics.editorWidth,
    maxHeight: maxHeight,
    placement: PopoverPlacement.bottomCenter,
    focusPolicy: PopoverFocusPolicy.none,
    builder: (context) => _FloatingTaskEditorContent(
      controller: controller,
      taskId: taskId,
    ),
  );
}

class _FloatingTaskEditorContent extends StatefulWidget {
  const _FloatingTaskEditorContent({
    required this.controller,
    required this.taskId,
  });

  final WorkspaceController controller;
  final String taskId;

  @override
  State<_FloatingTaskEditorContent> createState() =>
      _FloatingTaskEditorContentState();
}

class _FloatingTaskEditorContentState extends State<_FloatingTaskEditorContent> {
  bool closing = false;

  TaskItem? get task => widget.controller.tasks
      .where((candidate) => candidate.id == widget.taskId)
      .firstOrNull;

  void _closeWhenMissing() {
    if (closing) return;
    closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final current = task;
        if (current == null || current.deletedAt != null) {
          _closeWhenMissing();
          return const SizedBox.shrink();
        }
        return TaskInspector(
          key: ValueKey('floating-task-editor-${widget.taskId}'),
          task: current,
          controller: widget.controller,
          presentation: TaskInspectorPresentation.popup,
          onBack: () => Navigator.of(context).maybePop(),
        );
      },
    );
  }
}
