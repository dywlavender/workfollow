import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/quick_add.dart';
import '../widgets/section_label.dart';
import '../widgets/sidebar.dart';
import '../widgets/task_inspector.dart';
import '../widgets/task_row.dart';

class TaskWorkspaceScreen extends StatelessWidget {
  const TaskWorkspaceScreen({
    super.key,
    required this.controller,
    required this.navigationCollapsed,
    required this.onToggleNavigation,
  });

  final WorkspaceController controller;
  final bool navigationCollapsed;
  final VoidCallback onToggleNavigation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the four-zone composition at comfortable widths. As space gets
        // tight, the task navigation yields before list/detail readability.
        final showNavigation =
            !navigationCollapsed && constraints.maxWidth >= 960;
        return Row(
          children: [
            if (showNavigation) ...[
              TaskViewSidebar(
                controller: controller,
                onAddList: () => _showListNotice(context),
              ),
              VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: WorkFollowTheme.of(context).border),
            ],
            Expanded(
              child: TodayScreen(
                controller: controller,
                navigationCollapsed: !showNavigation,
                onToggleNavigation: onToggleNavigation,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showListNotice(BuildContext context) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建清单'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: '例如：旅行准备'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(nameController.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (!context.mounted || name == null) return;
    if (!controller.addList(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清单名称为空，或已经存在。')),
      );
    }
  }
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.controller,
    this.navigationCollapsed = false,
    this.onToggleNavigation,
  });

  final WorkspaceController controller;
  final bool navigationCollapsed;
  final VoidCallback? onToggleNavigation;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final tasks = controller.visibleTasks;
    final title = controller.viewTitle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showInspector =
            constraints.maxWidth >= 700 && controller.selectedTask != null;
        return Row(
          children: [
            Expanded(
              flex: showInspector ? 6 : 1,
              child: Container(
                color: tokens.content,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ListHeader(
                      title: title,
                      controller: controller,
                      navigationCollapsed: navigationCollapsed,
                      onToggleNavigation: onToggleNavigation,
                    ),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 3),
                        child: QuickAddField(controller: controller)),
                    Expanded(
                        child: _TaskList(tasks: tasks, controller: controller)),
                  ],
                ),
              ),
            ),
            if (showInspector) ...[
              VerticalDivider(width: 1, thickness: 1, color: tokens.border),
              Expanded(
                  flex: 5,
                  child: TaskInspector(
                      task: controller.selectedTask!, controller: controller)),
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
    required this.navigationCollapsed,
    required this.onToggleNavigation,
  });

  final String title;
  final WorkspaceController controller;
  final bool navigationCollapsed;
  final VoidCallback? onToggleNavigation;

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
          if (onToggleNavigation != null) ...[
            AppIconButton(
              icon: navigationCollapsed
                  ? Icons.view_sidebar_outlined
                  : Icons.view_sidebar_rounded,
              tooltip: navigationCollapsed ? '展开任务导航' : '收起任务导航',
              onPressed: onToggleNavigation,
              size: 30,
              iconSize: 17,
            ),
            const SizedBox(width: 6),
          ],
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
  const _TaskList({required this.tasks, required this.controller});

  final List<TaskItem> tasks;
  final WorkspaceController controller;

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
            selected: tasks[index].id == controller.selectedTaskId),
      );
    }
    final overdue =
        tasks.where((task) => task.bucket == TaskBucket.overdue).toList();
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
                    selected: task.id == controller.selectedTaskId)),
            child: TaskRow(
                key: ValueKey(task.id),
                task: task,
                controller: controller,
                selected: task.id == controller.selectedTaskId),
          ),
        );
      },
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
