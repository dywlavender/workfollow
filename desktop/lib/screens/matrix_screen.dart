import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';

class MatrixScreen extends StatefulWidget {
  const MatrixScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends State<MatrixScreen> {
  bool showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final tasks =
        widget.controller.matrixTasks(includeCompleted: showCompleted);
    final groups = <MatrixQuadrant, List<TaskItem>>{
      for (final quadrant in MatrixQuadrant.values) quadrant: [],
    };
    for (final task in tasks) {
      groups[widget.controller.matrixQuadrantFor(task)]!.add(task);
    }
    return Container(
      color: tokens.canvas,
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 34),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: '四象限',
                  subtitle: '按重要与紧急程度安排下一步。',
                  trailing: FilterChip(
                    label: const Text('仅看未完成'),
                    selected: !showCompleted,
                    onSelected: (value) =>
                        setState(() => showCompleted = !value),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 18),
                if (tasks.isEmpty)
                  AppCard(
                      child: EmptyHint(
                          icon: WorkFollowIcons.matrix,
                          title: '还没有可以放入象限的任务',
                          hint: '在列表中设置优先级或日期，任务会自动出现在这里。'))
                else
                  GridView.count(
                    crossAxisCount: narrow ? 1 : 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: narrow ? 2.1 : 1.55,
                    children: [
                      for (final quadrant in MatrixQuadrant.values)
                        _QuadrantCard(
                            controller: widget.controller,
                            quadrant: quadrant,
                            tasks: groups[quadrant]!),
                    ],
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  const _QuadrantCard({
    required this.controller,
    required this.quadrant,
    required this.tasks,
  });

  final WorkspaceController controller;
  final MatrixQuadrant quadrant;
  final List<TaskItem> tasks;

  ({
    String title,
    String subtitle,
    IconData icon,
    Color Function(WorkFollowTheme) color
  }) get _meta => switch (quadrant) {
        MatrixQuadrant.doNow => (
            title: '立即做',
            subtitle: '重要 · 紧急',
            icon: WorkFollowIcons.priorityHigh,
            color: (t) => t.danger
          ),
        MatrixQuadrant.schedule => (
            title: '安排做',
            subtitle: '重要 · 不紧急',
            icon: WorkFollowIcons.deadline,
            color: (t) => t.accent
          ),
        MatrixQuadrant.delegate => (
            title: '委托看',
            subtitle: '紧急 · 不重要',
            icon: WorkFollowIcons.forward,
            color: (t) => t.warning
          ),
        MatrixQuadrant.later => (
            title: '缓一缓',
            subtitle: '不重要 · 不紧急',
            icon: WorkFollowIcons.snooze,
            color: (t) => t.textTertiary
          ),
      };

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final meta = _meta;
    final color = meta.color(tokens);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) =>
          controller.moveTaskToMatrix(details.data, quadrant),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
              color:
                  highlighted ? color.withValues(alpha: .08) : tokens.content,
              borderRadius: BorderRadius.circular(WorkFollowRadii.card),
              border: Border.all(
                  color: highlighted
                      ? color.withValues(alpha: .55)
                      : tokens.border)),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius:
                          BorderRadius.circular(WorkFollowRadii.control)),
                  child: AppIcon(meta.icon,
                      size: WorkFollowMetrics.toolbarIcon, color: color)),
              const SizedBox(width: 9),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(meta.title,
                        style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(meta.subtitle,
                        style: TextStyle(
                            color: tokens.textTertiary, fontSize: 11)),
                  ])),
              Text('${tasks.length}',
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            if (tasks.isEmpty)
              Expanded(
                  child: Center(
                      child: Text('把任务拖到这里',
                          style: TextStyle(
                              color: tokens.textTertiary, fontSize: 11))))
            else
              Expanded(
                  child: ListView.separated(
                      physics: const ClampingScrollPhysics(),
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: tokens.border.withValues(alpha: .7)),
                      itemBuilder: (context, index) => _MatrixTaskRow(
                          task: tasks[index], controller: controller))),
          ]),
        );
      },
    );
  }
}

class _MatrixTaskRow extends StatelessWidget {
  const _MatrixTaskRow({required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final listColor = Color(controller.colorValueForList(task.listName));
    return Draggable<String>(
      data: task.id,
      feedback: Material(
          color: Colors.transparent,
          child: Container(
              width: 260,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: tokens.overlay,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: listColor.withValues(alpha: .6))),
              child: Text(task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 12)))),
      childWhenDragging: Opacity(opacity: .3, child: _body(tokens, listColor)),
      child: _body(tokens, listColor),
    );
  }

  Widget _body(WorkFollowTheme tokens, Color listColor) => InkWell(
        onTap: () => controller.openTask(task.id),
        borderRadius: BorderRadius.circular(WorkFollowRadii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                    color: listColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(
                child: Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: task.completed
                            ? tokens.textTertiary
                            : tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        decoration: task.completed
                            ? TextDecoration.lineThrough
                            : null))),
            if (task.priority != TaskPriority.none)
              AppIcon(WorkFollowIcons.flag,
                  size: WorkFollowMetrics.metadataIcon,
                  color: task.priority == TaskPriority.high
                      ? tokens.danger
                      : tokens.warning),
          ]),
        ),
      );
}
