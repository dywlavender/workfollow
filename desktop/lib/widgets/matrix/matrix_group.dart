import 'package:flutter/material.dart';

import '../../features/matrix/matrix_models.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';
import 'matrix_task_row.dart';

class MatrixGroup extends StatelessWidget {
  const MatrixGroup({
    super.key,
    required this.model,
    required this.controller,
    required this.accentColor,
    required this.expanded,
    required this.onToggle,
    required this.selectedTaskId,
    required this.onOpenTask,
  });

  final MatrixGroupViewModel model;
  final WorkspaceController controller;
  final Color accentColor;
  final bool expanded;
  final VoidCallback onToggle;
  final String? selectedTaskId;
  final void Function(BuildContext anchor, String taskId) onOpenTask;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: '${model.title} ${expanded ? '收起' : '展开'}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: SizedBox(
              height: MatrixMetrics.groupRowHeight,
              child: Row(
                children: [
                  AppIcon(
                    expanded
                        ? WorkFollowIcons.expandMore
                        : WorkFollowIcons.chevronNext,
                    key: ValueKey('matrix-group-chevron-${model.id}'),
                    size: WorkFollowMetrics.metadataIcon,
                    color: tokens.textTertiary,
                  ),
                  const SizedBox(width: WorkFollowSpacing.tightGap),
                  Text(
                    model.title,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: WorkFollowMacTypography.sectionTitle,
                      height: WorkFollowMacTypography.lineControl,
                      fontWeight: WorkFollowMacWeight.semibold,
                    ),
                  ),
                  const SizedBox(width: WorkFollowSpacing.inlineGap),
                  Text(
                    '${model.count}',
                    style: TextStyle(
                      color: tokens.textTertiary,
                      fontSize: WorkFollowMacTypography.listMeta,
                      height: WorkFollowMacTypography.lineControl,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          for (final task in model.tasks)
            MatrixTaskRow(
              key: ValueKey('matrix-task-${task.task.id}'),
              model: task,
              controller: controller,
              accentColor: accentColor,
              selected: task.task.id == selectedTaskId,
              onOpenTask: (anchor) => onOpenTask(anchor, task.task.id),
            ),
      ],
    );
  }
}
