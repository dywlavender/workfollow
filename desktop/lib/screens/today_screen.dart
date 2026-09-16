import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/desktop_popover.dart';
import '../widgets/quick_add.dart';
import '../widgets/task_date_picker.dart';
import '../widgets/task_schedule_picker.dart';
import '../widgets/task_inspector.dart';
import '../widgets/task_row.dart';

enum _TaskSort { manual, due, priority }

extension on _TaskSort {
  String get label => switch (this) {
        _TaskSort.manual => '手动',
        _TaskSort.due => '日期',
        _TaskSort.priority => '优先级',
      };
}

/// Task list pages (最近 7 天 / 今天 / 过期 / 计划 / 收集箱 / 全部 / 已完成 /
/// individual lists).
/// Wide macOS windows use a TickTick-style list + inspector split. Smaller
/// windows keep the existing list/detail fallback so the task editor never
/// gets squeezed into an unusable column.
class TodayScreen extends StatefulWidget {
  const TodayScreen(
      {super.key,
      required this.controller,
      this.compactDensity = false,
      this.persistentInspector = true,
      this.onOpenFocusTimer});
  final WorkspaceController controller;
  final bool compactDensity;
  final VoidCallback? onOpenFocusTimer;

  /// When enabled, a wide window keeps the right-hand inspector visible even
  /// before a task is selected. This is the macOS default to match TickTick;
  /// when disabled, the selected task uses the list-first inline fallback.
  final bool persistentInspector;
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  // TodayScreen receives the width left after AppRail. The Web workspace
  // enters its 1024/1120 layouts based on the full window, so the native
  // equivalent uses the same usable-width threshold after the merged rail.
  static const double _wideInspectorBreakpoint = 760;
  // Keep the Web contract in WorkFollowLayout, but use the deliberately
  // compact native profile for the macOS list pane. This leaves more room for
  // the fixed inspector without making the task rows feel cramped.
  static const double _minListPaneWidth =
      WorkFollowLayout.compactTaskListMinWidth;
  static const double _maxListPaneWidth = WorkFollowLayout.compactTaskListWidth;
  static const double _detailMinWidth = WorkFollowLayout.taskDetailMinWidth;
  static const double _listDividerWidth = WorkFollowLayout.taskListDividerWidth;
  static const double _taskRowHeight =
      WorkFollowLayout.taskRowComfortableHeight;

  bool detailOnly = false;
  bool showCompleted = false;
  _TaskSort sortMode = _TaskSort.manual;
  late int openVersion;
  final expandedEditorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    openVersion = widget.controller.taskOpenVersion;
    detailOnly = widget.controller.selectedTaskId != null;
    showCompleted = widget.controller.selectedTask?.isClosed ?? false;
    if (detailOnly) _revealEditor();
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (openVersion != widget.controller.taskOpenVersion) {
      openVersion = widget.controller.taskOpenVersion;
      detailOnly = true;
      if (widget.controller.selectedTask?.isClosed == true)
        showCompleted = true;
      _revealEditor();
    }
  }

  void _revealEditor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = expandedEditorKey.currentContext;
      if (mounted && context != null)
        Scrollable.ensureVisible(context, alignment: 0.08);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final tokens = WorkFollowTheme.of(context);
    final tasks = c.visibleTasks;
    final completedView = c.view == WorkspaceView.completed;
    final active = _ordered(tasks.where((task) => !task.isClosed).toList());
    final completed = tasks.where((task) => task.completed).toList();
    final abandoned = tasks.where((task) => task.isAbandoned).toList();
    final pinned = active.where((task) => task.isPinned).toList();
    final ordinary = active.where((task) => !task.isPinned).toList();
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      final wideInspector = constraints.maxWidth >= _wideInspectorBreakpoint &&
          (widget.persistentInspector || c.selectedTaskId != null);
      // Short windows get a dense header so the first tasks stay on screen.
      final compact = widget.compactDensity || constraints.maxHeight < 680;
      final selected = c.selectedTask;
      final detail = narrow && detailOnly && selected != null;
      final groups = <(String, List<TaskItem>, bool)>[];
      if (!completedView && pinned.isNotEmpty)
        groups.add(('置顶', pinned, false));
      if (completedView) {
        groups.add(('已完成', completed, false));
        groups.add(('已放弃', abandoned, false));
      } else if ((c.view == WorkspaceView.today ||
              c.view == WorkspaceView.recent) &&
          c.selectedListName == null) {
        if (c.view == WorkspaceView.today) {
          final overdue =
              ordinary.where((t) => t.bucket == TaskBucket.overdue).toList();
          if (overdue.isNotEmpty) groups.add(('已过期', overdue, true));
          groups.add((
            '今天',
            ordinary.where((t) => t.bucket != TaskBucket.overdue).toList(),
            false
          ));
        } else {
          ordinary.sort((a, b) => (a.dueAt ?? '').compareTo(b.dueAt ?? ''));
          String? currentLabel;
          for (final task in ordinary) {
            final due = localDateTimeFromStorage(task.dueAt);
            final label = task.bucket == TaskBucket.overdue
                ? '已过期'
                : due == null
                    ? '未安排'
                    : calendarDateLabel(due);
            final danger = task.bucket == TaskBucket.overdue;
            if (groups.isEmpty || currentLabel != label) {
              groups.add((label, [], danger));
              currentLabel = label;
            }
            groups.last.$2.add(task);
          }
        }
      } else if (c.view == WorkspaceView.plan) {
        ordinary.sort((a, b) => (a.dueAt ?? '').compareTo(b.dueAt ?? ''));
        for (final task in ordinary) {
          final label = calendarDateLabel(localDateTimeFromStorage(task.dueAt));
          if (groups.isEmpty || groups.last.$1 != label)
            groups.add((label, [], false));
          groups.last.$2.add(task);
        }
      } else {
        groups.add(('', ordinary, false));
      }
      final list = Container(
          color: tokens.canvas,
          child: Stack(children: [
            Column(children: [
              Expanded(
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        // Align passes loose vertical constraints to its
                        // child. Give the list column the finite height from
                        // the surrounding Expanded so its inner ListView can
                        // own scrolling instead of overflowing.
                        width: constraints.maxWidth.clamp(0, 860).toDouble(),
                        height: double.infinity,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      narrow
                                          ? 22
                                          : WorkFollowLayout
                                                  .taskDetailEmptyPadding -
                                              14,
                                      14,
                                      narrow
                                          ? 22
                                          : WorkFollowLayout
                                                  .taskDetailEmptyPadding -
                                              14,
                                      12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        PageHeader(
                                            key: const ValueKey(
                                                'list-view-title'),
                                            dense: compact || wideInspector,
                                            icon: _viewIcon(c.view),
                                            eyebrow: c.view ==
                                                        WorkspaceView.today &&
                                                    c.selectedListName == null
                                                ? _todayLabel()
                                                : null,
                                            title: c.viewTitle,
                                            subtitle: wideInspector
                                                ? null
                                                : completedView
                                                    ? '已经完成的事，都在这里。'
                                                    : c.view ==
                                                            WorkspaceView.inbox
                                                        ? '先记下来，稍后再安排。'
                                                        : c.view ==
                                                                    WorkspaceView
                                                                        .plan ||
                                                                c.view ==
                                                                    WorkspaceView
                                                                        .recent
                                                            ? '按日期查看接下来的安排。'
                                                            : c.view ==
                                                                    WorkspaceView
                                                                        .overdue
                                                                ? '把逾期任务重新安排好。'
                                                                : '${active.length} 件待办 · 已完成 ${completed.length} 件',
                                            trailing: _listHeaderActions(
                                                compact: compact,
                                                wideInspector: wideInspector,
                                                completedView: completedView,
                                                done: completed.length,
                                                total: active.length +
                                                    completed.length)),
                                        if (!completedView) ...[
                                          const SizedBox(height: 0),
                                          QuickAddField(
                                              controller: c, listStyle: true)
                                        ],
                                      ])),
                              Expanded(
                                  child: ListView(
                                key: PageStorageKey(
                                    'tasks-${c.view.name}-${c.selectedListName}'),
                                padding: EdgeInsets.fromLTRB(
                                    narrow
                                        ? WorkFollowSpacing.space3
                                        : WorkFollowSpacing.space4,
                                    2,
                                    narrow
                                        ? WorkFollowSpacing.space3
                                        : WorkFollowSpacing.space4,
                                    WorkFollowSpacing.space7),
                                children: [
                                  if ((completedView
                                          ? [...completed, ...abandoned]
                                          : active)
                                      .isEmpty)
                                    AppCard(
                                        padding: EdgeInsets.zero,
                                        child: EmptyHint(
                                            icon: completedView
                                                ? WorkFollowIcons.completed
                                                : WorkFollowIcons.tasks,
                                            title: completedView
                                                ? '完成的任务会出现在这里'
                                                : c.view == WorkspaceView.today
                                                    ? '今天，留一点从容'
                                                    : c.view ==
                                                            WorkspaceView.recent
                                                        ? '最近 7 天没有需要处理的任务'
                                                        : c.view ==
                                                                WorkspaceView
                                                                    .overdue
                                                            ? '没有逾期任务'
                                                            : c.view ==
                                                                    WorkspaceView
                                                                        .plan
                                                                ? '还没有未来的安排'
                                                                : '这里还是空的',
                                            hint: completedView
                                                ? '每完成一件事，都是一点进展。'
                                                : '在上方记下一件事，按 Return 添加。')),
                                  for (final group in groups) ...[
                                    if (group.$2.isNotEmpty)
                                      ..._groupSlivers(group, narrow,
                                          compact: compact,
                                          wideInspector: wideInspector),
                                  ],
                                  if (!completedView && abandoned.isNotEmpty)
                                    ..._groupSlivers(
                                        ('已放弃', abandoned, false), narrow,
                                        compact: compact,
                                        wideInspector: wideInspector),
                                  if (!completedView && completed.isNotEmpty)
                                    ..._completedSlivers(completed,
                                        compact: compact,
                                        wideInspector: wideInspector),
                                ],
                              )),
                            ]),
                      ))),
            ]),
            if (c.multiSelectCount > 0)
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: Center(child: _BulkBar(controller: c))),
          ]));
      if (wideInspector) {
        final listWidth =
            (constraints.maxWidth - _detailMinWidth - _listDividerWidth)
                .clamp(_minListPaneWidth, _maxListPaneWidth)
                .toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('web-task-list-pane'),
              width: listWidth,
              child: list,
            ),
            VerticalDivider(
                width: _listDividerWidth,
                thickness: _listDividerWidth,
                color: tokens.border),
            Expanded(
              child: ConstrainedBox(
                key: const ValueKey('web-task-detail-pane'),
                constraints: const BoxConstraints(minWidth: _detailMinWidth),
                child: selected == null
                    ? const _EmptyInspector()
                    : TaskInspector(
                        key: ValueKey('wide-detail-${selected.id}'),
                        task: selected,
                        controller: c,
                        onOpenFocusTimer: widget.onOpenFocusTimer),
              ),
            ),
          ],
        );
      }
      if (!narrow) return list;
      return Stack(fit: StackFit.expand, children: [
        Offstage(offstage: detail, child: list),
        if (detail)
          TaskInspector(
              key: ValueKey('detail-${selected.id}'),
              task: selected,
              controller: c,
              onOpenFocusTimer: widget.onOpenFocusTimer,
              showBack: true,
              onBack: () => setState(() => detailOnly = false)),
      ]);
    });
  }

  List<TaskItem> _ordered(List<TaskItem> tasks) {
    if (sortMode == _TaskSort.manual) return tasks;
    tasks.sort((a, b) {
      if (sortMode == _TaskSort.priority) {
        final byPriority = b.priority.index.compareTo(a.priority.index);
        if (byPriority != 0) return byPriority;
      }
      final aDue = localDateTimeFromStorage(a.dueAt);
      final bDue = localDateTimeFromStorage(b.dueAt);
      if (aDue == null && bDue == null) return 0;
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });
    return tasks;
  }

  Widget? _listHeaderActions({
    required bool compact,
    required bool wideInspector,
    required bool completedView,
    required int done,
    required int total,
  }) {
    final c = widget.controller;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!wideInspector &&
            c.view == WorkspaceView.today &&
            c.selectedListName == null &&
            !completedView)
          _ProgressSummary(compact: compact, done: done, total: total),
        Builder(
          builder: (anchor) => AppIconButton(
            key: const ValueKey('list-sort'),
            icon: WorkFollowIcons.sort,
            tooltip: '排序：${sortMode.label}',
            size: WorkFollowMetrics.iconHitTarget,
            iconSize: WorkFollowMetrics.toolbarIcon,
            onPressed: () => _showListMenu(anchor),
          ),
        ),
        Builder(
          builder: (anchor) => AppIconButton(
            key: const ValueKey('list-actions'),
            icon: WorkFollowIcons.more,
            tooltip: '列表操作',
            size: WorkFollowMetrics.iconHitTarget,
            iconSize: WorkFollowMetrics.toolbarIcon,
            onPressed: () => _showListMenu(anchor, showOnlyActions: true),
          ),
        ),
      ],
    );
  }

  Future<void> _showListMenu(BuildContext anchor,
      {bool showOnlyActions = false}) async {
    final entries = <DesktopMenuEntry<String>>[
      if (!showOnlyActions) ...[
        const DesktopMenuEntry('manual', '手动排序', icon: WorkFollowIcons.drag),
        const DesktopMenuEntry('due', '按日期排序', icon: WorkFollowIcons.schedule),
        const DesktopMenuEntry('priority', '按优先级排序',
            icon: WorkFollowIcons.flag),
      ],
      const DesktopMenuEntry('toggle-completed', '展开/收起已完成',
          icon: WorkFollowIcons.completed),
    ];
    final action = await showDesktopMenu<String>(anchor,
        entries: entries,
        selected: switch (sortMode) {
          _TaskSort.manual => 'manual',
          _TaskSort.due => 'due',
          _TaskSort.priority => 'priority',
        });
    if (!mounted || action == null) return;
    switch (action) {
      case 'manual':
        setState(() => sortMode = _TaskSort.manual);
      case 'due':
        setState(() => sortMode = _TaskSort.due);
      case 'priority':
        setState(() => sortMode = _TaskSort.priority);
      case 'toggle-completed':
        setState(() => showCompleted = !showCompleted);
    }
  }

  Widget _groupHeaderRow(
      {required String label,
      required int count,
      required Color dotColor,
      required Color textColor,
      Widget? trailing}) {
    final tokens = WorkFollowTheme.of(context);
    return Row(children: [
      Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
              fontSize: WorkFollowMacTypography.sectionTitle,
              height: WorkFollowMacTypography.lineControl,
              fontWeight: WorkFollowMacWeight.semibold,
              color: textColor)),
      const SizedBox(width: 6),
      Text('$count',
          style: TextStyle(
              fontSize: WorkFollowMacTypography.listMeta,
              height: WorkFollowMacTypography.lineControl,
              color: tokens.textTertiary)),
      if (trailing != null) trailing,
    ]);
  }

  List<Widget> _groupSlivers((String, List<TaskItem>, bool) group, bool narrow,
      {bool compact = false, bool wideInspector = false}) {
    final tokens = WorkFollowTheme.of(context);
    final (label, tasks, danger) = group;
    final edge = danger ? tokens.warning : tokens.border;
    return [
      const SizedBox(height: 8),
      if (label.isNotEmpty)
        Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: _groupHeaderRow(
                label: label,
                count: tasks.length,
                dotColor: edge,
                textColor: danger ? tokens.warning : tokens.textSecondary)),
      for (var i = 0; i < tasks.length; i++) ...[
        _task(tasks[i], narrow, compact: true, wideInspector: wideInspector),
        if (i < tasks.length - 1)
          Container(
              height: 1,
              margin: const EdgeInsets.only(left: 41),
              color: tokens.border),
      ],
    ];
  }

  List<Widget> _completedSlivers(List<TaskItem> completed,
      {bool compact = false, bool wideInspector = false}) {
    final tokens = WorkFollowTheme.of(context);
    return [
      const SizedBox(height: 12),
      Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: GestureDetector(
              onTap: () => setState(() => showCompleted = !showCompleted),
              behavior: HitTestBehavior.opaque,
              child: _groupHeaderRow(
                  label: '已完成',
                  count: completed.length,
                  dotColor: tokens.success,
                  textColor: tokens.textSecondary,
                  trailing: Expanded(
                      child: Row(children: [
                    const Spacer(),
                    AppIcon(
                        showCompleted
                            ? WorkFollowIcons.expandLess
                            : WorkFollowIcons.expandMore,
                        size: WorkFollowMetrics.navigationIcon,
                        color: tokens.textTertiary),
                  ]))))),
      if (showCompleted)
        for (var i = 0; i < completed.length; i++) ...[
          _task(completed[i], false,
              compact: true, wideInspector: wideInspector),
          if (i < completed.length - 1)
            Container(
                height: 1,
                margin: const EdgeInsets.only(left: 41),
                color: tokens.border),
        ],
    ];
  }

  Widget _task(TaskItem task, bool narrow,
      {bool compact = false, bool wideInspector = false}) {
    final c = widget.controller, tokens = WorkFollowTheme.of(context);
    if (!narrow &&
        !wideInspector &&
        c.selectedTaskId == task.id &&
        c.multiSelectCount == 0) {
      return Container(
          key: expandedEditorKey,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
          child: TaskInspector(
              key: ValueKey('editor-${task.id}'),
              task: task,
              controller: c,
              onOpenFocusTimer: widget.onOpenFocusTimer,
              inline: true));
    }
    return DragTarget<String>(
        onWillAcceptWithDetails: (data) => data.data != task.id,
        onAcceptWithDetails: (data) => c.moveTaskBefore(data.data, task.id),
        builder: (context, candidates, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (candidates.isNotEmpty)
                  Container(
                      height: 3,
                      margin: const EdgeInsets.fromLTRB(14, 2, 14, 2),
                      decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(2))),
                LongPressDraggable<String>(
                  data: task.id,
                  delay: const Duration(milliseconds: 300),
                  feedback: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                          width: 360,
                          child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)))),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minHeight: _taskRowHeight),
                    child: TaskRow(
                        key: ValueKey(task.id),
                        task: task,
                        controller: c,
                        selected: c.selectedTaskId == task.id,
                        multiSelected: c.isTaskMultiSelected(task.id),
                        compact: compact,
                        onActivate: () {
                          if (narrow) {
                            setState(() => detailOnly = true);
                          } else {
                            _revealEditor();
                          }
                        }),
                  ),
                ),
              ],
            ));
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.month} 月 ${now.day} 日 · 星期${'一二三四五六日'[now.weekday - 1]}';
  }

  IconData _viewIcon(WorkspaceView view) => switch (view) {
        WorkspaceView.recent => WorkFollowIcons.recent,
        WorkspaceView.today => WorkFollowIcons.today,
        WorkspaceView.overdue => WorkFollowIcons.overdue,
        WorkspaceView.inbox => WorkFollowIcons.inbox,
        WorkspaceView.plan => WorkFollowIcons.plan,
        WorkspaceView.all => WorkFollowIcons.allTasks,
        WorkspaceView.completed => WorkFollowIcons.completed,
        WorkspaceView.work ||
        WorkspaceView.study ||
        WorkspaceView.personal =>
          WorkFollowIcons.list,
        _ => WorkFollowIcons.tasks,
      };
}

/// Empty state for the persistent wide-window inspector. It keeps the right
/// pane visually present, just like the reference app, while explaining the
/// next action instead of leaving an unexplained blank region.
class _EmptyInspector extends StatelessWidget {
  const _EmptyInspector();

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(WorkFollowIcons.touch,
                size: WorkFollowMetrics.headerIcon, color: tokens.textTertiary),
            const SizedBox(height: 12),
            Text('选择一个任务开始编辑',
                style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: WorkFollowMacTypography.listTitle,
                    height: WorkFollowMacTypography.lineControl,
                    fontWeight: WorkFollowMacWeight.semibold)),
            const SizedBox(height: 6),
            Text('标题、备注、日期和子任务都会在这里展开。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: WorkFollowMacTypography.supporting,
                    height: WorkFollowMacTypography.lineList)),
          ],
        ),
      ),
    );
  }
}

/// Header progress for the today view: a ring plus a one-line summary.
class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary(
      {required this.done, required this.total, this.compact = false});

  final int done;
  final int total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Column(children: [
      ProgressRing(
          value: total == 0 ? 0 : done / total,
          done: done,
          total: total,
          size: compact ? 42 : 54),
      SizedBox(height: compact ? 3 : 5),
      Text(total == 0 ? '还没有安排' : '已完成 $done/$total',
          style: TextStyle(
              fontSize: WorkFollowMacTypography.listMeta,
              height: WorkFollowMacTypography.lineControl,
              color: tokens.textTertiary)),
    ]);
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return AppCard(
        elevated: true,
        radius: WorkFollowRadii.card,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Wrap(
            spacing: 2,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text('已选择 ${controller.multiSelectCount} 项',
                      style: TextStyle(
                          fontSize: WorkFollowMacTypography.listMeta,
                          height: WorkFollowMacTypography.lineControl,
                          fontWeight: WorkFollowMacWeight.medium,
                          color: tokens.textPrimary))),
              TextButton(
                  onPressed: () => controller.taskActions
                      .bulkComplete(controller.multiSelectedTaskIds),
                  child: const Text('完成')),
              Builder(
                  builder: (anchor) => TextButton(
                      onPressed: () async {
                        // Bulk date changes start as an all-day draft; an
                        // explicit time is opt-in, matching the single-task
                        // schedule picker and avoiding an accidental "now"
                        // time on every selected task.
                        final result = await TaskSchedulePicker.show(anchor,
                            hasTime: false);
                        if (result != null)
                          controller.taskActions.bulkSchedule(
                              controller.multiSelectedTaskIds,
                              TaskScheduleDraft(
                                  dueAt: result.date, hasTime: result.hasTime));
                      },
                      child: const Text('安排日期'))),
              Builder(
                  builder: (anchor) => TextButton(
                      onPressed: () async {
                        final result = await showDesktopMenu<String>(anchor,
                            entries: [
                              for (final list in controller.lists)
                                DesktopMenuEntry(list.name, list.name)
                            ]);
                        if (result != null)
                          controller.taskActions.bulkMove(
                              controller.multiSelectedTaskIds, result);
                      },
                      child: const Text('移动'))),
              TextButton(
                  onPressed: () => controller.taskActions
                      .bulkDelete(controller.multiSelectedTaskIds),
                  child: const Text('删除')),
              TextButton(
                  onPressed: controller.clearMultiSelect,
                  child: const Text('取消选择')),
            ]));
  }
}
