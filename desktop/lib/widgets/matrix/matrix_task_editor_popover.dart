import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_theme.dart';
import '../desktop_popover.dart';
import '../task_editor_popover.dart';
import '../task_inspector.dart';

/// Opens the same task editor used by the normal detail pane, but keeps the
/// Matrix page underneath the anchored surface.
Future<void> showMatrixTaskEditor(
  BuildContext anchor, {
  required WorkspaceController controller,
  required String taskId,
}) async {
  final viewport = MediaQuery.sizeOf(anchor);
  final maxHeight = (viewport.height - MatrixMetrics.taskEditorViewportMargin)
      .clamp(
        MatrixMetrics.taskEditorMinHeight,
        MatrixMetrics.taskEditorMaxHeight,
      )
      .toDouble();

  await showTaskEditorPopover<void>(
    anchor,
    width: MatrixMetrics.taskEditorWidth,
    maxHeight: maxHeight,
    placement: PopoverPlacement.bottomCenter,
    focusPolicy: PopoverFocusPolicy.none,
    builder: (context) => _MatrixTaskEditorContent(
      controller: controller,
      taskId: taskId,
    ),
  );
}

class _MatrixTaskEditorContent extends StatefulWidget {
  const _MatrixTaskEditorContent({
    required this.controller,
    required this.taskId,
  });

  final WorkspaceController controller;
  final String taskId;

  @override
  State<_MatrixTaskEditorContent> createState() =>
      _MatrixTaskEditorContentState();
}

class _MatrixTaskEditorContentState extends State<_MatrixTaskEditorContent> {
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
          key: ValueKey('matrix-task-inspector-${widget.taskId}'),
          task: current,
          controller: widget.controller,
          presentation: TaskInspectorPresentation.popup,
          onBack: () => Navigator.of(context).maybePop(),
        );
      },
    );
  }
}
