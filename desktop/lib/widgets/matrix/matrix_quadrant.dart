import 'package:flutter/material.dart';

import '../../features/matrix/matrix_models.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_theme_parity.dart';
import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';
import '../desktop_popover.dart';
import 'matrix_group.dart';

class MatrixQuadrant extends StatefulWidget {
  const MatrixQuadrant({
    super.key,
    required this.model,
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

  final MatrixQuadrantViewModel model;
  final WorkspaceController controller;
  final bool showCompleted;
  final bool Function(MatrixGroupViewModel group) isGroupExpanded;
  final void Function(MatrixGroupViewModel group) onToggleGroup;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final void Function(BuildContext anchor) onAddTask;
  final String? selectedTaskId;
  final void Function(BuildContext anchor, String taskId) onOpenTask;

  @override
  State<MatrixQuadrant> createState() => _MatrixQuadrantState();
}

class _MatrixQuadrantState extends State<MatrixQuadrant> {
  bool hovering = false;

  MatrixQuadrantStyle get style => widget.model.style;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) =>
          widget.controller.moveTaskToMatrix(details.data, style.quadrant),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return MouseRegion(
          onEnter: (_) => setState(() => hovering = true),
          onExit: (_) => setState(() => hovering = false),
          child: AnimatedContainer(
            duration: WorkFollowMotion.instant,
            decoration: BoxDecoration(
              color: highlighted
                  ? style.color.withValues(alpha: .07)
                  : tokens.content,
              borderRadius: BorderRadius.circular(MatrixMetrics.quadrantRadius),
              border: Border.all(
                color: highlighted
                    ? style.color.withValues(alpha: .60)
                    : tokens.border.withValues(alpha: .35),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  WorkFollowSpacing.relaxedGap,
                  WorkFollowSpacing.space3,
                  WorkFollowSpacing.space3,
                  WorkFollowSpacing.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  const SizedBox(height: WorkFollowSpacing.inlineGap),
                  Expanded(
                    child: widget.model.groups.isEmpty
                        ? Center(
                            child: Text(
                              '把任务拖到这里',
                              style: TextStyle(
                                color: tokens.textTertiary,
                                fontSize: WorkFollowMacTypography.caption,
                              ),
                            ),
                          )
                        : Scrollbar(
                            thumbVisibility: false,
                            child: ListView(
                              padding: EdgeInsets.zero,
                              physics: const ClampingScrollPhysics(),
                              children: [
                                for (final group in widget.model.groups)
                                  MatrixGroup(
                                    key: ValueKey(
                                        'matrix-group-${style.quadrant.name}-${group.id}'),
                                    model: group,
                                    controller: widget.controller,
                                    accentColor: style.color,
                                    expanded: widget.isGroupExpanded(group),
                                    onToggle: () => widget.onToggleGroup(group),
                                    selectedTaskId: widget.selectedTaskId,
                                    onOpenTask: widget.onOpenTask,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Container(
          width: MatrixMetrics.quadrantHeaderMarkerSize,
          height: MatrixMetrics.quadrantHeaderMarkerSize,
          decoration: BoxDecoration(
            color: style.color,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            style.numeral,
            style: TextStyle(
              color: WorkFollowThemeContrast.markerForeground,
              fontSize: WorkFollowMacTypography.caption,
              height: WorkFollowMacTypography.lineNone,
              fontWeight: WorkFollowMacWeight.semibold,
            ),
          ),
        ),
        const SizedBox(width: WorkFollowSpacing.space2),
        Expanded(
          child: Text(
            style.title,
            style: TextStyle(
              color: style.color,
              fontSize: WorkFollowMacTypography.body,
              height: WorkFollowMacTypography.lineControl,
              fontWeight: WorkFollowMacWeight.semibold,
            ),
          ),
        ),
        Builder(
          builder: (anchor) => _hoverAction(
            key: ValueKey('matrix-quadrant-add-${style.quadrant.name}'),
            tooltip: '在${style.title}中新建任务',
            icon: WorkFollowIcons.add,
            visible: hovering,
            onPressed: () => widget.onAddTask(anchor),
          ),
        ),
        Builder(
          builder: (anchor) => _hoverAction(
            key: ValueKey('matrix-quadrant-more-${style.quadrant.name}'),
            tooltip: '${style.title}更多操作',
            icon: WorkFollowIcons.more,
            visible: hovering,
            onPressed: () => _openMenu(anchor),
          ),
        ),
      ],
    );
  }

  Widget _hoverAction({
    required Key key,
    required String tooltip,
    required IconData icon,
    required bool visible,
    required VoidCallback onPressed,
  }) {
    return ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        duration: WorkFollowMotion.instant,
        opacity: visible ? 1 : 0,
        child: AppIconButton(
          key: key,
          icon: icon,
          tooltip: tooltip,
          size: 28,
          iconSize: WorkFollowMetrics.toolbarIcon,
          iconColor: WorkFollowTheme.of(context).textSecondary,
          onPressed: visible ? onPressed : null,
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(
      anchor,
      placement: PopoverPlacement.bottomEnd,
      entries: [
        const DesktopMenuEntry('add', '新建任务', icon: WorkFollowIcons.add),
        DesktopMenuEntry(
          'show-completed',
          widget.showCompleted ? '隐藏已完成任务' : '显示已完成任务',
          icon: WorkFollowIcons.completed,
        ),
        const DesktopMenuEntry('expand', '展开全部分组',
            icon: WorkFollowIcons.expandMore),
        const DesktopMenuEntry('collapse', '折叠全部分组',
            icon: WorkFollowIcons.expandLess),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'add':
        widget.onAddTask(anchor);
      case 'show-completed':
        // The page owns the completed-visibility preference. The menu item is
        // deliberately kept as a page callback in the next layer so a
        // quadrant never invents a second copy of that state.
        widget.onToggleGroup(const MatrixGroupViewModel(
          id: '__toggle-completed__',
          title: '',
          count: 0,
          completedGroup: true,
          tasks: const [],
        ));
      case 'expand':
        widget.onExpandAll();
      case 'collapse':
        widget.onCollapseAll();
    }
  }
}
