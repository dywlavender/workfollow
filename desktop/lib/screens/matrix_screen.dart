import 'package:flutter/material.dart';

import '../features/feedback/feedback_scope.dart';
import '../features/matrix/matrix_models.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/desktop_popover.dart';
import '../widgets/matrix/matrix_board.dart';
import '../widgets/task_add_surface.dart';
import '../widgets/task_editor_popover.dart';
import '../widgets/task_floating_editor.dart';

class MatrixScreen extends StatefulWidget {
  const MatrixScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends State<MatrixScreen> {
  /// Completed tasks are part of the matrix by default, matching the target
  /// screenshot. The optional filter lives in the page menu, not the header.
  bool showCompleted = true;
  final Set<String> collapsedGroups = <String>{};
  String? editingTaskId;

  List<MatrixQuadrantViewModel> get projection =>
      widget.controller.matrixProjection(includeCompleted: showCompleted);

  bool _isGroupExpanded(MatrixGroupViewModel group) {
    return !collapsedGroups.contains(group.id);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final quadrants = projection;
    return ColoredBox(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeader(context),
          Expanded(
            child: MatrixBoard(
              quadrants: quadrants,
              controller: widget.controller,
              showCompleted: showCompleted,
              isGroupExpanded: _isGroupExpanded,
              onToggleGroup: (group) {
                if (group.id == '__toggle-completed__') {
                  setState(() => showCompleted = !showCompleted);
                  return;
                }
                setState(() {
                  if (!collapsedGroups.remove(group.id)) {
                    collapsedGroups.add(group.id);
                  }
                });
              },
              onExpandAll: (quadrant) => setState(() {
                collapsedGroups
                    .removeWhere((key) => key.startsWith('${quadrant.name}:'));
              }),
              onCollapseAll: (quadrant) => setState(() {
                final value =
                    quadrants.firstWhere((item) => item.quadrant == quadrant);
                for (final group in value.groups) {
                  collapsedGroups.add(group.id);
                }
              }),
              onAddTask: _addTask,
              selectedTaskId: editingTaskId,
              onOpenTask: _openTaskEditor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTaskEditor(BuildContext anchor, String taskId) async {
    if (editingTaskId != null) return;
    setState(() => editingTaskId = taskId);
    await showTaskFloatingEditor(
      anchor,
      controller: widget.controller,
      taskId: taskId,
    );
    if (!mounted || editingTaskId != taskId) return;
    setState(() => editingTaskId = null);
  }

  Widget _pageHeader(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      height: MatrixMetrics.pageHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            WorkFollowSpacing.relaxedGap,
            WorkFollowSpacing.cardInset,
            WorkFollowSpacing.space3,
            WorkFollowSpacing.space1),
        child: Row(
          children: [
            Text(
              '四象限',
              key: const ValueKey('matrix-page-title'),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: WorkFollowMacTypography.pageTitle,
                height: WorkFollowMacTypography.lineTight,
                fontWeight: WorkFollowMacWeight.semibold,
              ),
            ),
            const Spacer(),
            Builder(
              builder: (anchor) => AppIconButton(
                key: const ValueKey('matrix-page-more'),
                icon: WorkFollowIcons.more,
                tooltip: '四象限设置',
                size: WorkFollowMetrics.iconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon,
                onPressed: () => _openPageMenu(anchor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPageMenu(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(
      anchor,
      placement: PopoverPlacement.bottomEnd,
      entries: const [
        DesktopMenuEntry('show-completed', '显示已完成任务',
            icon: WorkFollowIcons.completed),
        DesktopMenuEntry('expand-all', '展开全部分组',
            icon: WorkFollowIcons.expandMore),
        DesktopMenuEntry('collapse-all', '折叠全部分组',
            icon: WorkFollowIcons.expandLess),
      ],
      selected: showCompleted ? 'show-completed' : null,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'show-completed':
        setState(() => showCompleted = !showCompleted);
      case 'expand-all':
        setState(() => collapsedGroups.clear());
      case 'collapse-all':
        setState(() {
          for (final quadrant in projection) {
            for (final group in quadrant.groups) {
              collapsedGroups.add(group.id);
            }
          }
        });
    }
  }

  void _addTask(BuildContext anchor, MatrixQuadrant quadrant) {
    showTaskEditorPopover<TaskAddDraft>(
      anchor,
      width: TaskSurfaceMetrics.composerWidth,
      maxHeight: TaskSurfaceMetrics.composerMaxHeight,
      placement: PopoverPlacement.bottomEnd,
      focusPolicy: PopoverFocusPolicy.searchField,
      builder: (_) => TaskAddSurface(
        controller: widget.controller,
        defaultPriority: quadrant.defaultPriority,
      ),
    ).then((draft) {
      if (!mounted || draft == null) return;
      final result = widget.controller.createTaskInMatrixQuadrant(
        draft.title,
        quadrant,
        listName: draft.listName,
        schedule: draft.schedule,
        scheduleOverridden: draft.scheduleOverridden,
        reminderAt: draft.reminderAt,
        recurrence: draft.recurrence,
        priority: draft.priority,
      );
      final feedback = FeedbackScope.maybeOf(context);
      if (feedback != null) {
        presentTaskResult(feedback, result,
            actionVersion: widget.controller.actionVersion);
      }
    });
  }
}
