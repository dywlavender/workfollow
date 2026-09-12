import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/quick_add.dart';
import '../widgets/section_label.dart';
import '../widgets/task_inspector.dart';
import '../widgets/task_row.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  // Below 700pt the inspector does not fit; activating a row swaps the pane
  // to a detail view with a back path that restores the list (kept offstage
  // so scroll position and selection survive the round trip).
  bool _detailOnly = false;

  void _handleActivate() {
    if (_listWidth != null && _listWidth! < 700) {
      setState(() => _detailOnly = true);
    }
  }

  double? _listWidth;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tasks = controller.visibleTasks;
    final title = controller.viewTitle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        _listWidth = constraints.maxWidth;
        final selected = controller.selectedTask;
        final showInspector = !narrow && selected != null;
        final narrowDetail = narrow && _detailOnly && selected != null;
        final listPane = Container(
          color: WorkFollowTheme.of(context).content,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ListHeader(title: title, controller: controller),
              Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 3),
                  child: QuickAddField(controller: controller)),
              Expanded(
                  child: Offstage(
                offstage: narrowDetail,
                child: _TaskList(
                  tasks: tasks,
                  controller: controller,
                  onActivate: _handleActivate,
                ),
              )),
              if (controller.multiSelectCount > 0)
                _BulkActionBar(controller: controller),
            ],
          ),
        );
        if (narrowDetail) {
          return TaskInspector(
              task: selected,
              controller: controller,
              showBack: true,
              onBack: () => setState(() => _detailOnly = false));
        }
        return Row(
          children: [
            Expanded(
              flex: showInspector ? 6 : 1,
              child: listPane,
            ),
            if (showInspector) ...[
              VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: WorkFollowTheme.of(context).border),
              Expanded(
                  flex: 5,
                  child: TaskInspector(task: selected, controller: controller)),
            ],
          ],
        );
      },
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.controller,
  });

  final String title;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final now = DateTime.now();
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1];
    final openCount = controller.selectedListName == null
        ? controller.countFor(controller.view)
        : controller.countForList(controller.selectedListName!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 18, 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.45)),
              const SizedBox(height: 5),
              Text(
                  title == '今天'
                      ? '${now.month} 月 ${now.day} 日 · 星期$weekday'
                      : '$openCount 件待处理',
                  style: TextStyle(
                      color: tokens.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          if (title == '今天')
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                    color: tokens.accentFaint,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Icon(Icons.auto_awesome_outlined,
                      size: 12, color: tokens.accent),
                  const SizedBox(width: 5),
                  Text('$openCount 件待完成',
                      style: TextStyle(
                          color: tokens.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))
                ])),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    required this.controller,
    this.onActivate,
  });

  final List<TaskItem> tasks;
  final WorkspaceController controller;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const _EmptyTaskState();
    final todayView = controller.view == WorkspaceView.today;
    if (!todayView) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
        itemCount: tasks.length,
        itemBuilder: (context, index) => TaskRow(
            task: tasks[index],
            controller: controller,
            selected: tasks[index].id == controller.selectedTaskId,
            multiSelected: controller.isTaskMultiSelected(tasks[index].id),
            onActivate: onActivate),
      );
    }
    final overdue = tasks
        .where((task) => task.bucket == TaskBucket.overdue && !task.completed)
        .toList();
    final today = tasks
        .where((task) => task.bucket == TaskBucket.today && !task.completed)
        .toList();
    final completed = tasks.where((task) => task.completed).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
      children: [
        if (overdue.isNotEmpty) ...[
          SectionLabel(
              label: '逾期',
              count: overdue.length,
              color: WorkFollowTheme.of(context).warning),
          ...overdue.map(_draggableRow),
        ],
        SectionLabel(
            label: '今天',
            count: today.length,
            color: WorkFollowTheme.of(context).accent),
        if (today.isEmpty)
          const Padding(
              padding: EdgeInsets.fromLTRB(14, 7, 14, 10),
              child: Text('今天的清单已经清空了。',
                  style: TextStyle(color: Colors.grey, fontSize: 12))),
        ...today.map(_draggableRow),
        if (completed.isNotEmpty) ...[
          SectionLabel(
              label: '已完成',
              count: completed.length,
              color: WorkFollowTheme.of(context).success),
          ...completed.map(_draggableRow),
        ],
      ],
    );
  }

  Widget _draggableRow(TaskItem task) {
    return DragTarget<String>(
      key: ValueKey('target-${task.id}'),
      onWillAccept: (draggedId) => draggedId != null && draggedId != task.id,
      onAccept: (draggedId) => controller.moveTaskBefore(draggedId, task.id),
      builder: (context, candidateData, rejectedData) {
        final tokens = WorkFollowTheme.of(context);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
              border: candidateData.isNotEmpty
                  ? Border(top: BorderSide(color: tokens.accent, width: 2))
                  : null),
          child: LongPressDraggable<String>(
            data: task.id,
            delay: const Duration(milliseconds: 160),
            feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                    width: 420,
                    child: Opacity(
                        opacity: .88,
                        child: TaskRow(
                            task: task,
                            controller: controller,
                            selected: true)))),
            childWhenDragging: Opacity(
                opacity: .28,
                child: TaskRow(
                    task: task,
                    controller: controller,
                    selected: task.id == controller.selectedTaskId,
                    multiSelected: controller.isTaskMultiSelected(task.id))),
            child: TaskRow(
                key: ValueKey(task.id),
                task: task,
                controller: controller,
                selected: task.id == controller.selectedTaskId,
                multiSelected: controller.isTaskMultiSelected(task.id),
                onActivate: onActivate),
          ),
        );
      },
    );
  }
}

/// Actions for the current multi-selection. Every action is revertible
/// through the undo toast (bulk complete / delete / reschedule / move).
class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      decoration: BoxDecoration(
          color: tokens.inspector,
          border: Border(top: BorderSide(color: tokens.border))),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          Text('已选 ${controller.multiSelectCount} 项',
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          _BulkAction(
              label: '全选',
              icon: Icons.select_all_rounded,
              onPressed: controller.selectAllVisibleTasks),
          const SizedBox(width: 6),
          _BulkAction(
              label: '完成',
              icon: Icons.check_rounded,
              color: tokens.success,
              onPressed: controller.bulkCompleteSelected),
          _BulkAction(
              label: '今天',
              icon: Icons.today_outlined,
              onPressed: () =>
                  controller.bulkRescheduleSelected(DateTime.now())),
          _BulkAction(
              label: '明天',
              icon: Icons.event_outlined,
              onPressed: () {
                final now = DateTime.now();
                controller.bulkRescheduleSelected(
                    DateTime(now.year, now.month, now.day + 1));
              }),
          _BulkAction(
              label: '移到清单…',
              icon: Icons.drive_file_move_outline,
              onPressed: () => _pickList(context)),
          _BulkAction(
              label: '删除',
              icon: Icons.delete_outline_rounded,
              color: tokens.danger,
              onPressed: controller.bulkDeleteSelected),
          const Spacer(),
          TextButton(
              onPressed: controller.clearMultiSelect,
              style: TextButton.styleFrom(
                  foregroundColor: tokens.textTertiary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('取消选择',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Future<void> _pickList(BuildContext context) async {
    final tokens = WorkFollowTheme.of(context);
    final listName = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: tokens.overlay,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('移动到清单',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            for (final list in controller.lists)
              ListTile(
                  title: Text(list.name),
                  onTap: () => Navigator.of(sheetContext).pop(list.name)),
          ],
        ),
      ),
    );
    if (listName != null) controller.bulkMoveSelectedToList(listName);
  }
}

class _BulkAction extends StatelessWidget {
  const _BulkAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final foreground = color ?? tokens.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _EmptyTaskState extends StatelessWidget {
  const _EmptyTaskState();

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(38),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                      color: tokens.accentFaint, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded,
                      color: tokens.accent, size: 25)),
              const SizedBox(height: 15),
              Text('这里暂时没有任务',
                  style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text('把注意力留给真正重要的事。',
                  style: TextStyle(color: tokens.textTertiary, fontSize: 12)),
            ])));
  }
}
