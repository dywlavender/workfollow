import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/quick_add.dart';

/// Personal dashboard. The redesigned home leads with a greeting, a stat
/// strip (今天待办 / 今日完成 / 逾期 / 笔记), then the familiar panel grid:
/// task lists stay real and tappable, the mini calendar keeps every date.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final now = DateTime.now();
    final tasks = controller.activeTasks;
    final dueTodayOrOverdue = controller.needsAttentionToday;
    final todayTasks = tasks
        .where((task) => !task.completed && dueTodayOrOverdue(task))
        .toList();
    final overdueTasks = tasks
        .where((task) => !task.completed && task.bucket == TaskBucket.overdue)
        .toList();
    final upcomingTasks = tasks
        .where((task) => !task.completed && task.bucket == TaskBucket.later)
        .toList();
    // "Done today" only counts completions recorded today, not every task
    // that happens to be completed.
    final doneToday = tasks.where((task) {
      if (!task.completed) return false;
      final completedAt = localDateTimeFromStorage(task.completedAt);
      if (completedAt == null) return false;
      return completedAt.year == now.year &&
          completedAt.month == now.month &&
          completedAt.day == now.day;
    }).length;

    return Container(
      color: tokens.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The Wrap lives inside the shared page gutter on each side. Use
          // its actual content width; otherwise two half-width cards are
          // always 56pt too wide and Flutter falls back to one column.
          final contentWidth = (constraints.maxWidth -
                  WorkFollowSpacing.pageHorizontalPadding * 2)
              .clamp(0.0, double.infinity);
          final panelWidth =
              contentWidth >= 1060
                  ? (contentWidth - WorkFollowSpacing.relaxedGap) / 2
                  : contentWidth;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.pageHorizontalPadding, WorkFollowSpacing.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(now),
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: WorkFollowMacTypography.pageTitle,
                              fontWeight: WorkFollowMacWeight.semibold,
                              height: WorkFollowMacTypography.lineTight,
                              letterSpacing: WorkFollowMacTracking.none,
                            ),
                          ),
                          const SizedBox(height: WorkFollowSpacing.inlineGap),
                          Text(
                            '${now.month} 月 ${now.day} 日 · 星期${_weekday(now.weekday)} · 把注意力留给要紧的事。',
                            style: TextStyle(
                                color: tokens.textTertiary,
                                fontSize: WorkFollowMacTypography.control,
                                height: WorkFollowMacTypography.lineList),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: WorkFollowSpacing.sectionGap),
                    SizedBox(
                        width: HomeMetrics.quickAddWidth,
                        child: QuickAddField(controller: controller)),
                  ],
                ),
                const SizedBox(height: WorkFollowSpacing.space5),
                if (controller.shouldShowWeeklyReview) ...[
                  _WeeklyReviewCard(
                      summary: controller.weeklyReview,
                      onOpen: () =>
                          controller.selectView(WorkspaceView.completed)),
                  const SizedBox(height: WorkFollowSpacing.relaxedGap),
                ],
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                          label: '今天待办',
                          value: '${todayTasks.length}',
                          icon: WorkFollowIcons.today,
                          color: tokens.accent,
                          onTap: () =>
                              controller.selectView(WorkspaceView.today)),
                    ),
                    const SizedBox(width: WorkFollowSpacing.space3),
                    Expanded(
                      child: StatCard(
                          label: '今日完成',
                          value: '$doneToday',
                          icon: WorkFollowIcons.completed,
                          color: tokens.success,
                          onTap: () =>
                              controller.selectView(WorkspaceView.completed)),
                    ),
                    const SizedBox(width: WorkFollowSpacing.space3),
                    Expanded(
                      child: StatCard(
                          label: '逾期',
                          value: '${overdueTasks.length}',
                          icon: WorkFollowIcons.warning,
                          color: tokens.warning,
                          onTap: () =>
                              controller.selectView(WorkspaceView.today)),
                    ),
                    const SizedBox(width: WorkFollowSpacing.space3),
                    Expanded(
                      child: StatCard(
                          label: '笔记',
                          value: '${controller.activeNotes.length}',
                          icon: WorkFollowIcons.notes,
                          color: tokens.accent,
                          onTap: () =>
                              controller.selectView(WorkspaceView.notes)),
                    ),
                  ],
                ),
                const SizedBox(height: WorkFollowSpacing.space4),
                Wrap(
                  spacing: WorkFollowSpacing.relaxedGap,
                  runSpacing: WorkFollowSpacing.relaxedGap,
                  children: [
                    SizedBox(
                      width: panelWidth,
                      height: HomeMetrics.panelHeight,
                      child: _HomePanel(
                        icon: WorkFollowIcons.today,
                        title: '今天',
                        subtitle:
                            '${todayTasks.length} 件待处理 · 已完成 $doneToday 件',
                        action: '查看今天',
                        onAction: () =>
                            controller.selectView(WorkspaceView.today),
                        child: todayTasks.isEmpty
                            ? _PanelEmpty(
                                icon: WorkFollowIcons.completed,
                                label: '今天的任务已经处理完了。',
                                tokens: tokens)
                            : _HomeTaskList(
                                tasks: todayTasks.take(5).toList(),
                                controller: controller),
                      ),
                    ),
                    SizedBox(
                      width: panelWidth,
                      height: HomeMetrics.panelHeight,
                      child: _HomePanel(
                        icon: WorkFollowIcons.calendar,
                        title: '日历',
                        subtitle: '${now.year} 年 ${now.month} 月',
                        action: '打开日历',
                        onAction: () =>
                            controller.selectView(WorkspaceView.calendar),
                        child: _MiniCalendar(
                            controller: controller,
                            month: DateTime(now.year, now.month)),
                      ),
                    ),
                    SizedBox(
                      width: panelWidth,
                      height: HomeMetrics.panelHeight,
                      child: _HomePanel(
                        icon: WorkFollowIcons.plan,
                        title: '接下来',
                        subtitle: '未来安排',
                        action: '打开计划',
                        onAction: () =>
                            controller.selectView(WorkspaceView.plan),
                        child: upcomingTasks.isEmpty
                            ? _PanelEmpty(
                                icon: WorkFollowIcons.deadline,
                                label: '近期没有安排好的任务。',
                                tokens: tokens)
                            : _HomeTaskList(
                                tasks: upcomingTasks.take(5).toList(),
                                controller: controller),
                      ),
                    ),
                    SizedBox(
                      width: panelWidth,
                      height: HomeMetrics.panelHeight,
                      child: _HomePanel(
                        icon: WorkFollowIcons.notes,
                        title: '最近笔记',
                        subtitle: '${controller.activeNotes.length} 条个人笔记',
                        action: '查看全部',
                        onAction: () =>
                            controller.selectView(WorkspaceView.notes),
                        child: _HomeNoteList(controller: controller),
                      ),
                    ),
                    SizedBox(
                      width: panelWidth,
                      height: HomeMetrics.panelHeight,
                      child: _HomePanel(
                        icon: WorkFollowIcons.overdue,
                        title: '逾期',
                        subtitle: overdueTasks.isEmpty
                            ? '清爽的进度'
                            : '${overdueTasks.length} 件需要处理',
                        action: overdueTasks.isEmpty ? null : '处理逾期',
                        onAction: overdueTasks.isEmpty
                            ? null
                            : () => controller.selectView(WorkspaceView.today),
                        child: overdueTasks.isEmpty
                            ? _PanelEmpty(
                                icon: WorkFollowIcons.today,
                                label: '没有逾期任务。',
                                tokens: tokens)
                            : _HomeTaskList(
                                tasks: overdueTasks.take(5).toList(),
                                controller: controller,
                                overdue: true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _greeting(DateTime now) {
    if (now.hour >= 5 && now.hour < 11) return '早上好';
    if (now.hour >= 11 && now.hour < 13) return '中午好';
    if (now.hour >= 13 && now.hour < 18) return '下午好';
    return '晚上好';
  }

  String _weekday(int value) =>
      const ['一', '二', '三', '四', '五', '六', '日'][value - 1];
}

class _WeeklyReviewCard extends StatelessWidget {
  const _WeeklyReviewCard({required this.summary, required this.onOpen});

  final WeeklyReviewSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final message = summary.completed == 0
        ? '上周还没有完成记录，先完成一件事。'
        : '上周完成 ${summary.completed} 件 · ${summary.weekdayLabel}'
            '${summary.overdue > 0 ? ' · 还有 ${summary.overdue} 件逾期未清' : ''}';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.sectionGap, WorkFollowSpacing.controlInset, WorkFollowSpacing.space3, WorkFollowSpacing.controlInset),
      color: tokens.accentFaint,
      borderColor: tokens.accent.withValues(alpha: .16),
      child: Row(children: [
        Container(
            width: HomeMetrics.reviewIconSize,
            height: HomeMetrics.reviewIconSize,
            decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
            child: AppIcon(WorkFollowIcons.autoAwesome,
                size: WorkFollowMetrics.toolbarIcon, color: tokens.accent)),
        const SizedBox(width: WorkFollowSpacing.iconLabelGap),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('上周回顾',
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.sectionTitle,
                  fontWeight: WorkFollowMacWeight.semibold)),
          const SizedBox(height: WorkFollowSpacing.tightGap),
          Text(message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, fontSize: WorkFollowMacTypography.supporting)),
        ])),
        TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(
                foregroundColor: tokens.accent,
                padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space2, vertical: WorkFollowSpacing.denseGap),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('看完成', style: TextStyle(fontSize: WorkFollowMacTypography.control))),
      ]),
    );
  }
}

class _HomePanel extends StatelessWidget {
  const _HomePanel({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.icon,
    this.action,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onAction;
  final Widget child;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.sectionGap, WorkFollowSpacing.space4, WorkFollowSpacing.sectionGap, WorkFollowSpacing.statusGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  width: HomeMetrics.panelIconSize,
                  height: HomeMetrics.panelIconSize,
                  decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: .1),
                      borderRadius:
                          BorderRadius.circular(WorkFollowRadii.control)),
                  child: AppIcon(icon,
                      size: WorkFollowMetrics.toolbarIcon,
                      color: tokens.accent)),
              const SizedBox(width: WorkFollowSpacing.controlGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: WorkFollowMacTypography.listTitle,
                            fontWeight: WorkFollowMacWeight.semibold,
                            height: WorkFollowMacTypography.lineControl,
                            letterSpacing: WorkFollowMacTracking.none)),
                    const SizedBox(height: WorkFollowSpacing.tightGap),
                    Text(subtitle,
                        style: TextStyle(
                            color: tokens.textTertiary,
                            fontSize: WorkFollowMacTypography.supporting,
                            height: WorkFollowMacTypography.lineList)),
                  ],
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.denseGap, vertical: WorkFollowSpacing.tightGap),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(action!,
                      style: TextStyle(
                          color: tokens.accent,
                          fontSize: WorkFollowMacTypography.control,
                          fontWeight: WorkFollowMacWeight.semibold)),
                ),
            ],
          ),
          const SizedBox(height: WorkFollowSpacing.relaxedGap),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _HomeTaskList extends StatelessWidget {
  const _HomeTaskList(
      {required this.tasks, required this.controller, this.overdue = false});

  final List<TaskItem> tasks;
  final WorkspaceController controller;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final task in tasks)
          _HomeTaskRow(
            task: task,
            controller: controller,
            overdue: overdue,
            onOpen: () => controller.openTask(task.id),
            onToggle: () {
              final result = task.completed
                  ? controller.taskActions.restore(task.id)
                  : controller.taskActions.complete(task.id);
              presentTaskResultIn(context, result,
                  actionVersion: controller.actionVersion);
            },
          ),
      ],
    );
  }
}

class _HomeTaskRow extends StatelessWidget {
  const _HomeTaskRow(
      {required this.task,
      required this.controller,
      required this.onOpen,
      required this.onToggle,
      required this.overdue});

  final TaskItem task;
  final WorkspaceController controller;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final listColor = Color(controller.colorValueForList(task.listName));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.denseGap),
      child: Row(
        children: [
          Container(
              width: HomeMetrics.taskMarkerWidth,
              height: HomeMetrics.taskMarkerHeight,
              decoration: BoxDecoration(
                  color: listColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: WorkFollowSpacing.denseGap),
          GestureDetector(
            onTap: onToggle,
            child: Semantics(
              button: true,
              checked: task.completed,
              label: task.completed ? '标记未完成' : '标记完成',
              child: Container(
                width: HomeMetrics.taskCheckboxHitTarget,
                height: HomeMetrics.taskCheckboxHitTarget,
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: HomeMetrics.taskCheckboxVisualWidth,
                  height: HomeMetrics.taskCheckboxVisualHeight,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: task.completed ? tokens.success : Colors.transparent,
                    border: Border.all(
                        color: task.completed
                            ? tokens.success
                            : overdue
                                ? tokens.warning
                                : tokens.borderStrong,
                        width: 1.5),
                  ),
                  child: task.completed
                      ? const AppIcon(WorkFollowIcons.check,
                          size: WorkFollowMetrics.metadataIcon - 3,
                          color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: WorkFollowSpacing.compactGap),
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: WorkFollowMacTypography.listTitle,
                    fontWeight: WorkFollowMacWeight.semibold),
              ),
            ),
          ),
          const SizedBox(width: WorkFollowSpacing.space2),
          Text(task.displayTimeLabel ?? '未安排',
              style: TextStyle(
                  color: overdue ? tokens.warning : tokens.textTertiary,
                  fontSize: WorkFollowMacTypography.listMeta)),
        ],
      ),
    );
  }
}

class _HomeNoteList extends StatelessWidget {
  const _HomeNoteList({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    if (controller.activeNotes.isEmpty) {
      return _PanelEmpty(
          icon: WorkFollowIcons.noteAlt, label: '还没有笔记。', tokens: tokens);
    }
    return Column(
      children: [
        for (final note in controller.activeNotes.take(4))
          GestureDetector(
            onTap: () => controller.openNote(note.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.denseGap),
              child: Row(
                children: [
                  Container(
                      width: HomeMetrics.noteDotSize,
                      height: HomeMetrics.noteDotSize,
                      decoration: BoxDecoration(
                          color: Color(note.accent.value),
                          shape: BoxShape.circle)),
                  const SizedBox(width: WorkFollowSpacing.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: WorkFollowMacTypography.listTitle,
                                fontWeight: WorkFollowMacWeight.semibold)),
                        const SizedBox(height: WorkFollowSpacing.microGap),
                        Text(note.folder,
                            style: TextStyle(
                                color: tokens.textTertiary, fontSize: WorkFollowMacTypography.listMeta)),
                      ],
                    ),
                  ),
                  const SizedBox(width: WorkFollowSpacing.space2),
                  Text(note.updatedLabel,
                      style:
                          TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.listMeta)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniCalendar extends StatelessWidget {
  const _MiniCalendar({required this.controller, required this.month});

  final WorkspaceController controller;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final count = ((leading + days) / 7).ceil() * 7;
    final today = DateTime.now();
    final taskCount = controller.countFor(WorkspaceView.today);
    final rowCount = count ~/ 7;
    return LayoutBuilder(
      builder: (context, constraints) {
        // GridView's default delegate derives row height from cell width.
        // That makes a wide two-column home card taller than its fixed panel
        // and clips the later weeks. Derive an explicit row extent from the
        // actual height left after the weekday header instead.
        const weekdayHeight = 16.0;
        const headerGap = 7.0;
        const rowSpacing = 3.0;
        final gridHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - weekdayHeight - headerGap)
                .clamp(1.0, double.infinity)
                .toDouble()
            : 1.0;
        final rowExtent =
            ((gridHeight - rowSpacing * (rowCount - 1)) / rowCount)
                .clamp(1.0, double.infinity)
                .toDouble();
        return Column(
          children: [
            SizedBox(
              height: weekdayHeight,
              child: Row(
                children: [
                  for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                        child: Center(
                            child: Text(label,
                                style: TextStyle(
                                    color: tokens.textTertiary,
                                    fontSize: WorkFollowMacTypography.caption,
                                    fontWeight: WorkFollowMacWeight.semibold)))),
                ],
              ),
            ),
            const SizedBox(height: headerGap),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: rowSpacing,
                    crossAxisSpacing: WorkFollowSpacing.tightGap,
                    mainAxisExtent: rowExtent),
                itemCount: count,
                itemBuilder: (context, index) {
                  final day = index - leading + 1;
                  if (day < 1 || day > days) return const SizedBox.shrink();
                  final isToday = day == today.day &&
                      month.month == today.month &&
                      month.year == today.year;
                  final hasTasks = isToday && taskCount > 0;
                  return Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: isToday ? tokens.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$day',
                            style: TextStyle(
                                color: isToday
                                    ? Colors.white
                                    : tokens.textSecondary,
                                fontSize: WorkFollowMacTypography.caption,
                                fontWeight: isToday
                                    ? WorkFollowMacWeight.semibold
                                    : WorkFollowMacWeight.medium)),
                        if (hasTasks) ...[
                          const SizedBox(height: WorkFollowSpacing.microGap),
                          Container(
                              width: HomeMetrics.miniCalendarDotSize,
                              height: HomeMetrics.miniCalendarDotSize,
                              decoration: BoxDecoration(
                                  color: isToday ? Colors.white : tokens.accent,
                                  shape: BoxShape.circle)),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty(
      {required this.icon, required this.label, required this.tokens});

  final IconData icon;
  final String label;
  final WorkFollowTheme tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: HomeMetrics.emptyIconSize,
              height: HomeMetrics.emptyIconSize,
              decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: .08),
                  shape: BoxShape.circle),
              child: AppIcon(icon,
                  size: WorkFollowMetrics.navigationIcon,
                  color: tokens.accent)),
          const SizedBox(height: WorkFollowSpacing.controlGap),
          Text(label,
              style: TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.supporting)),
        ],
      ),
    );
  }
}
