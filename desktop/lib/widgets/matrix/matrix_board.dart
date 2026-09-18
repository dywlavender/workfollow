import 'package:flutter/material.dart';

import '../../features/matrix/matrix_models.dart';
import '../../state/workspace_controller.dart'
    show MatrixQuadrant, WorkspaceController;
import '../../theme/workfollow_theme.dart';
import 'matrix_quadrant.dart' as matrix_widgets;

/// A fixed 2×2 board. Each child owns its own scroll view, so a long list in
/// one quadrant never pushes the other three quadrants down the page.
class MatrixBoard extends StatelessWidget {
  const MatrixBoard({
    super.key,
    required this.quadrants,
    required this.controller,
    required this.showCompleted,
    required this.isGroupExpanded,
    required this.onToggleGroup,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onAddTask,
    required this.selectedTaskId,
    required this.onOpenTask,
  });

  final List<MatrixQuadrantViewModel> quadrants;
  final WorkspaceController controller;
  final bool showCompleted;
  final bool Function(MatrixGroupViewModel group) isGroupExpanded;
  final void Function(MatrixGroupViewModel group) onToggleGroup;
  final void Function(MatrixQuadrant quadrant) onExpandAll;
  final void Function(MatrixQuadrant quadrant) onCollapseAll;
  final void Function(BuildContext anchor, MatrixQuadrant quadrant) onAddTask;
  final String? selectedTaskId;
  final void Function(BuildContext anchor, String taskId) onOpenTask;

  @override
  Widget build(BuildContext context) {
    MatrixQuadrantViewModel model(MatrixQuadrant quadrant) => quadrants
        .firstWhere((item) => item.quadrant == quadrant);

    Widget cell(MatrixQuadrant quadrant) {
      final value = model(quadrant);
      return Expanded(
        child: matrix_widgets.MatrixQuadrant(
          key: ValueKey('matrix-quadrant-${quadrant.name}'),
          model: value,
          controller: controller,
          showCompleted: showCompleted,
          isGroupExpanded: isGroupExpanded,
          onToggleGroup: onToggleGroup,
          onExpandAll: () => onExpandAll(quadrant),
          onCollapseAll: () => onCollapseAll(quadrant),
          onAddTask: (anchor) => onAddTask(anchor, quadrant),
          selectedTaskId: selectedTaskId,
          onOpenTask: onOpenTask,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.cardInset, WorkFollowSpacing.zero, WorkFollowSpacing.cardInset, WorkFollowSpacing.cardInset),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                cell(MatrixQuadrant.doNow),
                const SizedBox(width: WorkFollowSpacing.controlGap),
                cell(MatrixQuadrant.schedule),
              ],
            ),
          ),
          const SizedBox(height: WorkFollowSpacing.controlGap),
          Expanded(
            child: Row(
              children: [
                cell(MatrixQuadrant.delegate),
                const SizedBox(width: WorkFollowSpacing.controlGap),
                cell(MatrixQuadrant.later),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
