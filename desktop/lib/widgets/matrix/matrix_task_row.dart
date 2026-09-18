import 'package:flutter/material.dart';

import '../../features/feedback/feedback_scope.dart';
import '../../features/matrix/matrix_models.dart';
import '../../features/tasks/presentation/task_feedback_mapper.dart';
import '../../models/task.dart';
import '../../state/workspace_controller.dart';
import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_surface_tokens.dart';
import '../../theme/workfollow_theme.dart';
import '../app_icon_button.dart';
import '../task_completion_box.dart';
import '../task_schedule_panel.dart';

/// A flat matrix row. The matrix already communicates importance through its
/// quadrant, so a row carries no extra priority stripe or card border.
class MatrixTaskRow extends StatefulWidget {
  const MatrixTaskRow({
    super.key,
    required this.model,
    required this.controller,
    required this.accentColor,
    required this.onOpenTask,
    this.selected = false,
  });

  final MatrixTaskViewModel model;
  final WorkspaceController controller;
  final Color accentColor;
  final ValueChanged<BuildContext> onOpenTask;
  final bool selected;

  @override
  State<MatrixTaskRow> createState() => _MatrixTaskRowState();
}

class _MatrixTaskRowState extends State<MatrixTaskRow> {
  bool hovering = false;

  TaskItem get task => widget.model.task;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Container(
        decoration: BoxDecoration(
          color: widget.selected || hovering
              ? tokens.listRowHover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(
              widget.selected || hovering ? WorkFollowRadii.card : 0),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: WorkFollowSpacing.inlineGap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _checkbox(tokens),
                  const SizedBox(width: WorkFollowSpacing.compactInset),
                  Expanded(
                    child: Builder(
                      builder: (anchor) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onOpenTask(anchor),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: WorkFollowSpacing.tightGap),
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: task.completed
                                  ? tokens.textTertiary
                                  : tokens.textPrimary,
                              fontSize: WorkFollowMacTypography.listTitle,
                              height: WorkFollowMacTypography.lineControl,
                              fontWeight: WorkFollowMacWeight.regular,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: WorkFollowSpacing.controlGap),
                  _metadata(tokens),
                ],
              ),
            ),
            Container(
              height: MatrixMetrics.taskRowDividerHeight,
              margin: const EdgeInsets.only(
                  left: WorkFollowSpacing.nestedContentIndent),
              color: tokens.border.withValues(alpha: .65),
            ),
          ],
        ),
      ),
    );

    return Draggable<String>(
      data: task.id,
      feedback: _dragFeedback(tokens),
      childWhenDragging: Opacity(opacity: .32, child: row),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: task.title,
        child: row,
      ),
    );
  }

  Widget _dragFeedback(WorkFollowTheme tokens) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: MatrixMetrics.taskRowDragPreviewWidth,
        padding: const EdgeInsets.symmetric(
            horizontal: WorkFollowSpacing.space3,
            vertical: WorkFollowSpacing.cardInset),
        decoration: WorkFollowSurfaceTokens.card(
          tokens,
          color: tokens.content,
          elevated: true,
        ),
        child: Text(
          task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: WorkFollowMacTypography.listTitle,
          ),
        ),
      ),
    );
  }

  Widget _checkbox(WorkFollowTheme tokens) {
    final completed = task.completed;
    final border = completed ? tokens.textTertiary : widget.accentColor;
    return SizedBox(
      width: MatrixMetrics.taskRowCheckboxHitTarget,
      height: MatrixMetrics.taskRowCheckboxHitTarget,
      child: IconButton(
        key: ValueKey('matrix-task-checkbox-${task.id}'),
        tooltip: completed ? '恢复任务' : '完成任务',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: MatrixMetrics.taskRowCheckboxHitTarget,
          height: MatrixMetrics.taskRowCheckboxHitTarget,
        ),
        splashRadius: 12,
        onPressed: _toggle,
        icon: Container(
          width: MatrixMetrics.taskRowCheckboxSize,
          height: MatrixMetrics.taskRowCheckboxSize,
          decoration: BoxDecoration(
            color: completed
                ? tokens.textTertiary.withValues(alpha: .27)
                : Colors.transparent,
            // The row's own corner scaled to this box's size, so the quadrant
            // draws the shape the task list draws rather than a near miss.
            borderRadius: BorderRadius.circular(
                taskCompletionBoxRadius(MatrixMetrics.taskRowCheckboxSize)),
            border: completed
                ? null
                : Border.all(
                    color: border,
                    width: WorkFollowMetrics.checkboxBorderWidth),
          ),
          child: completed
              ? AppIcon(WorkFollowIcons.check,
                  size: WorkFollowMetrics.metadataIcon, color: tokens.content)
              : null,
        ),
      ),
    );
  }

  Widget _metadata(WorkFollowTheme tokens) {
    final model = widget.model;
    final muted = tokens.textTertiary;
    final dateColor = task.completed
        ? muted
        : model.overdue
            ? tokens.danger
            : tokens.accent;
    final items = <Widget>[
      _label(model.listName, muted),
      if (model.recurring) _icon(WorkFollowIcons.repeat, muted, '重复任务'),
      if (model.hasNote) _icon(WorkFollowIcons.article, muted, '有备注'),
      if (model.hasSubtasks) _icon(WorkFollowIcons.subtask, muted, '有子任务'),
      if (model.hasReminder) _icon(WorkFollowIcons.reminder, muted, '有提醒'),
      if (model.dateLabel != null) _dateLabel(model.dateLabel!, dateColor),
    ];
    // Keep metadata non-flex so the title receives all width left after the
    // actual metadata trail. As the final row child, the trail naturally
    // remains pinned to the right edge without reserving half the row.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WorkFollowSpacing.inlineGap,
      runSpacing: WorkFollowSpacing.microGap,
      children: items,
    );
  }

  Widget _dateLabel(String value, Color color) {
    return Builder(
      builder: (anchor) => TextButton(
        key: ValueKey('matrix-task-date-${task.id}'),
        onPressed: () => _editDate(anchor),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 22),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(value, style: _dateStyle(color)),
      ),
    );
  }

  Widget _label(String value, Color color) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: WorkFollowMacTypography.listMeta,
        height: WorkFollowMacTypography.lineControl,
      ),
    );
  }

  Widget _icon(IconData icon, Color color, String label) {
    return Semantics(
      label: label,
      child: AppIcon(icon, size: WorkFollowMetrics.metadataIcon, color: color),
    );
  }

  void _toggle() {
    final result = task.completed
        ? widget.controller.taskActions.restore(task.id)
        : widget.controller.taskActions.complete(task.id);
    final feedback = FeedbackScope.maybeOf(context);
    if (feedback != null) {
      presentTaskResult(feedback, result,
          actionVersion: widget.controller.actionVersion);
    }
  }

  Future<void> _editDate(BuildContext anchor) async {
    final settings = await showTaskSchedulePanel(anchor, task);
    if (!mounted || settings == null) return;
    final result = widget.controller.taskActions.setScheduleSettings(
      task.id,
      settings,
    );
    final feedback = FeedbackScope.maybeOf(context);
    if (feedback != null) {
      presentTaskResult(
        feedback,
        result,
        actionVersion: widget.controller.actionVersion,
      );
    }
  }

  TextStyle _dateStyle(Color color) => TextStyle(
        color: color,
        fontSize: WorkFollowMacTypography.listMeta,
        height: WorkFollowMacTypography.lineControl,
        fontWeight: WorkFollowMacWeight.regular,
      );
}
