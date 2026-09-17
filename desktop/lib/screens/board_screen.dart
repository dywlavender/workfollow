import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';

/// A compact Kanban projection of the same task records used by list, matrix
/// and calendar views. Dropping a card changes only the field represented by
/// the selected grouping: priority columns update priority, date columns
/// update due date.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  BoardGroupBy grouping = BoardGroupBy.priority;
  bool showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final tasks = widget.controller.boardTasks(includeCompleted: showCompleted);
    final columns = _columns(tokens);
    return Container(
      color: tokens.canvas,
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.pageTopPadding, WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.pageScreenBottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '看板',
            subtitle: '拖动任务，让下一步变得清楚。',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GroupingSegment(
                    grouping: grouping,
                    onChanged: (value) => setState(() => grouping = value)),
                const SizedBox(width: WorkFollowSpacing.space3),
                FilterChip(
                  label: const Text('显示已完成'),
                  selected: showCompleted,
                  onSelected: (value) => setState(() => showCompleted = value),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: tokens.border),
                  selectedColor: tokens.accentSoft,
                  checkmarkColor: tokens.accent,
                  labelStyle: TextStyle(
                      color:
                          showCompleted ? tokens.accent : tokens.textSecondary,
                      fontSize: WorkFollowMacTypography.control),
                ),
              ],
            ),
          ),
          const SizedBox(height: WorkFollowSpacing.sectionGap),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth < 900
                  ? BoardMetrics.compactColumnWidth
                  : 0.0;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: WorkFollowSpacing.inlineGap),
                itemCount: columns.length,
                separatorBuilder: (_, __) => const SizedBox(width: WorkFollowSpacing.space3),
                itemBuilder: (context, index) {
                  final column = columns[index];
                  final items = tasks
                      .where((task) =>
                          widget.controller.boardColumnFor(task, grouping) ==
                          column.key)
                      .toList();
                  return SizedBox(
                    width: width == 0.0
                        ? (constraints.maxWidth - 36) / columns.length
                        : width,
                    child: _BoardColumn(
                      key: ValueKey(
                          'board-column-${grouping.name}-${column.key}'),
                      controller: widget.controller,
                      grouping: grouping,
                      meta: column,
                      tasks: items,
                      showCompleted: showCompleted,
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  List<_BoardColumnMeta> _columns(WorkFollowTheme tokens) {
    if (grouping == BoardGroupBy.priority) {
      return [
        _BoardColumnMeta('high', '高优先级', '先处理最重要的事', tokens.danger),
        _BoardColumnMeta('medium', '中优先级', '保持稳定推进', tokens.warning),
        _BoardColumnMeta('low', '低优先级', '有空再做', tokens.accent),
        _BoardColumnMeta('none', '未设优先级', '稍后再决定', tokens.textTertiary),
      ];
    }
    return [
      _BoardColumnMeta('thisWeek', '本周', '今天到本周日', tokens.accent),
      _BoardColumnMeta('nextWeek', '下周', '给未来留出空间', tokens.warning),
      _BoardColumnMeta('later', '以后', '还没到需要处理的时候', tokens.success),
      _BoardColumnMeta('unscheduled', '未安排', '先放进收集箱', tokens.textTertiary),
    ];
  }
}

class _GroupingSegment extends StatelessWidget {
  const _GroupingSegment({required this.grouping, required this.onChanged});

  final BoardGroupBy grouping;
  final ValueChanged<BoardGroupBy> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(WorkFollowSpacing.microGap),
      decoration: BoxDecoration(
          color: tokens.content,
          borderRadius: BorderRadius.circular(WorkFollowRadii.control),
          border: Border.all(color: tokens.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final option in const <(BoardGroupBy, String)>[
          (BoardGroupBy.priority, '优先级'),
          (BoardGroupBy.date, '日期'),
        ])
          InkWell(
            onTap: () => onChanged(option.$1),
            borderRadius: BorderRadius.circular(WorkFollowRadii.control),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.cardInset, vertical: WorkFollowSpacing.inlineGap),
              decoration: BoxDecoration(
                  color: grouping == option.$1
                      ? tokens.accentSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
              child: Text(option.$2,
                  style: TextStyle(
                      color: grouping == option.$1
                          ? tokens.accent
                          : tokens.textSecondary,
                      fontSize: WorkFollowMacTypography.control,
                      fontWeight: WorkFollowMacWeight.semibold)),
            ),
          ),
      ]),
    );
  }
}

class _BoardColumnMeta {
  const _BoardColumnMeta(this.key, this.title, this.subtitle, this.color);

  final String key;
  final String title;
  final String subtitle;
  final Color color;
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    super.key,
    required this.controller,
    required this.grouping,
    required this.meta,
    required this.tasks,
    required this.showCompleted,
  });

  final WorkspaceController controller;
  final BoardGroupBy grouping;
  final _BoardColumnMeta meta;
  final List<TaskItem> tasks;
  final bool showCompleted;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data.isNotEmpty &&
          controller.boardColumnFor(
                  controller.tasks
                          .where((task) => task.id == details.data)
                          .firstOrNull ??
                      _placeholderTask,
                  grouping) !=
              meta.key,
      onAcceptWithDetails: (details) =>
          controller.moveTaskToBoardColumn(details.data, grouping, meta.key),
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: active
                ? meta.color.withValues(alpha: .08)
                : tokens.content.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(WorkFollowRadii.card),
            border: Border.all(
                color:
                    active ? meta.color.withValues(alpha: .65) : tokens.border),
          ),
          padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.cardInset, WorkFollowSpacing.cardInset, WorkFollowSpacing.cardInset, WorkFollowSpacing.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: BoardMetrics.columnStatusDotSize,
                    height: BoardMetrics.columnStatusDotSize,
                    decoration: BoxDecoration(
                        color: meta.color, shape: BoxShape.circle)),
                const SizedBox(width: WorkFollowSpacing.space2),
                Expanded(
                    child: Text(meta.title,
                        style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: WorkFollowMacTypography.sectionTitle,
                            fontWeight: WorkFollowMacWeight.semibold))),
                Text('${tasks.length}',
                    style: TextStyle(
                        color: meta.color,
                        fontSize: WorkFollowMacTypography.listMeta,
                        fontWeight: WorkFollowMacWeight.semibold)),
              ]),
              const SizedBox(height: WorkFollowSpacing.tightGap),
              Padding(
                  padding: const EdgeInsets.only(left: WorkFollowSpacing.space4),
                  child: Text(meta.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.listMeta))),
              const SizedBox(height: WorkFollowSpacing.controlGap),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text('拖到这里',
                            style: TextStyle(
                                color:
                                    active ? meta.color : tokens.textTertiary,
                                fontSize: WorkFollowMacTypography.caption,
                                fontWeight: WorkFollowMacWeight.semibold)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: WorkFollowSpacing.space1),
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: WorkFollowSpacing.space2),
                        itemBuilder: (context, index) => _BoardTaskCard(
                            controller: controller,
                            task: tasks[index],
                            accent: meta.color,
                            showCompleted: showCompleted),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// DragTarget's predicate only needs an object with a legal task shape when a
// card is deleted between drag start and drop. Keeping this sentinel private
// avoids making the public TaskItem constructor less expressive.
final _placeholderTask = TaskItem(
  id: '',
  title: '',
  listName: '收集箱',
  bucket: TaskBucket.unscheduled,
);

class _BoardTaskCard extends StatelessWidget {
  const _BoardTaskCard({
    required this.controller,
    required this.task,
    required this.accent,
    required this.showCompleted,
  });

  final WorkspaceController controller;
  final TaskItem task;
  final Color accent;
  final bool showCompleted;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final listColor = Color(controller.colorValueForList(task.listName));
    final content = AppCard(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.cardInset, WorkFollowSpacing.cardInset, WorkFollowSpacing.space2, WorkFollowSpacing.compactInset),
      radius: 10,
      color: tokens.overlay,
      borderColor:
          task.completed ? tokens.border : listColor.withValues(alpha: .45),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: BoardMetrics.listMarkerWidth,
            height: BoardMetrics.listMarkerHeight,
            margin: const EdgeInsets.only(right: WorkFollowSpacing.space2, top: WorkFollowSpacing.hairlineGap),
            decoration: BoxDecoration(
                color: listColor, borderRadius: BorderRadius.circular(2))),
        SizedBox(
          width: BoardMetrics.taskCheckboxSize,
          height: BoardMetrics.taskCheckboxSize,
          child: Checkbox(
              value: task.completed,
              onChanged: (_) {
                final result = task.completed
                    ? controller.taskActions.restore(task.id)
                    : controller.taskActions.complete(task.id);
                presentTaskResultIn(context, result,
                    actionVersion: controller.actionVersion);
              },
              activeColor: tokens.success,
              side: BorderSide(color: accent, width: 1.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5)),
              semanticLabel: task.completed ? '标记未完成' : '完成任务'),
        ),
        const SizedBox(width: WorkFollowSpacing.inlineGap),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: task.completed
                        ? tokens.textTertiary
                        : tokens.textPrimary,
                    fontSize: WorkFollowMacTypography.listTitle,
                    height: WorkFollowMacTypography.lineList,
                    fontWeight: WorkFollowMacWeight.semibold,
                    decoration:
                        task.completed ? TextDecoration.lineThrough : null)),
            const SizedBox(height: WorkFollowSpacing.inlineGap),
            Wrap(spacing: WorkFollowSpacing.inlineGap, runSpacing: WorkFollowSpacing.tightGap, children: [
              Text(task.listName,
                  style: TextStyle(color: listColor, fontSize: WorkFollowMacTypography.listMeta)),
              if (task.displayTimeLabel != null)
                Text(task.displayTimeLabel!,
                    style: TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.listMeta)),
              if (task.focusCount > 0)
                Text('专注 ${task.focusCount}',
                    style: TextStyle(color: tokens.accent, fontSize: WorkFollowMacTypography.listMeta)),
            ]),
          ]),
        ),
        AppIconButton(
            icon: WorkFollowIcons.open,
            tooltip: '打开任务',
            size: WorkFollowMetrics.iconHitTarget,
            iconSize: WorkFollowMetrics.metadataIcon,
            onPressed: () => controller.openTask(task.id)),
      ]),
    );
    return Draggable<String>(
      data: task.id,
      maxSimultaneousDrags: 1,
      feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
              width: BoardMetrics.relationPreviewWidth, child: content)),
      childWhenDragging: Opacity(opacity: .32, child: content),
      child: Semantics(
          button: true,
          label: '${task.title}，${task.listName}',
          child: InkWell(
              onTap: () => controller.openTask(task.id),
              borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
              child: content)),
    );
  }
}
