import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/feedback/feedback_event.dart';
import '../features/feedback/feedback_scope.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_schedule.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/desktop_popover.dart';
import '../widgets/quick_add.dart';
import '../widgets/task_date_picker.dart';
import '../widgets/task_schedule_panel.dart';
import '../widgets/task_inspector.dart';
import '../widgets/task_row.dart';
import '../widgets/task_list/task_group_header.dart';
import '../widgets/task_list/task_list_divider.dart';
import '../widgets/task_list/task_list_header.dart';

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
///
/// This screen owns grouping, sorting, selection and the responsive split. It
/// owns no visual values: pane width, gutter, row padding, group headings and
/// dividers all come from [TaskListMetrics] and the shared task-list widgets,
/// so a second list view cannot drift into its own design.
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
  static const double _detailMinWidth = WorkFollowLayout.taskDetailMinWidth;
  static const double _listDividerWidth = WorkFollowLayout.taskListDividerWidth;

  bool detailOnly = false;

  /// Groups the user folded away, keyed by the heading label.
  ///
  /// Membership means "collapsed", so an empty set is the default posture:
  /// every group open, including 已完成 — starting that one collapsed hides the
  /// tasks the user finished a moment ago, which are exactly the ones they are
  /// still looking at.
  ///
  /// Keyed by label rather than by index so folding survives a rebuild that
  /// reorders the groups (a task turning overdue must not fold 今天 by
  /// accident). Labels are unique within one view; [PageStorageKey] on the list
  /// scopes the set per view.
  final collapsedGroups = <String>{};

  /// The heading that the list menu's 展开/收起已完成 entry drives.
  static const String _completedGroup = '已完成';

  /// Heading of the overdue group. Named because the grouping code that
  /// produces it and the heading code that hangs 顺延 off it must not drift.
  static const String _overdueGroup = '已过期';

  bool _isCollapsed(String label) => collapsedGroups.contains(label);

  void _toggleGroup(String label) {
    setState(() {
      if (!collapsedGroups.remove(label)) collapsedGroups.add(label);
    });
  }

  _TaskSort sortMode = _TaskSort.manual;
  late int openVersion;
  final expandedEditorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    openVersion = widget.controller.taskOpenVersion;
    detailOnly = widget.controller.selectedTaskId != null;
    if (detailOnly) _revealEditor();
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (openVersion != widget.controller.taskOpenVersion) {
      openVersion = widget.controller.taskOpenVersion;
      detailOnly = true;
      // Opening a finished task has to reveal it, so clear the fold first.
      if (widget.controller.selectedTask?.isClosed == true)
        collapsedGroups.remove(_completedGroup);
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
      final groups = <(String, List<TaskItem>)>[];
      if (!completedView && pinned.isNotEmpty)
        groups.add(('置顶', pinned));
      if (completedView) {
        groups.add((_completedGroup, completed));
        groups.add(('已放弃', abandoned));
      } else if ((c.view == WorkspaceView.today ||
              c.view == WorkspaceView.recent) &&
          c.selectedListName == null) {
        if (c.view == WorkspaceView.today) {
          final overdue =
              ordinary.where((t) => t.bucket == TaskBucket.overdue).toList();
          if (overdue.isNotEmpty) groups.add((_overdueGroup, overdue));
          groups.add((
            calendarGroupLabel(DateTime.now()),
            ordinary.where((t) => t.bucket != TaskBucket.overdue).toList()
          ));
        } else {
          ordinary.sort((a, b) => (a.dueAt ?? '').compareTo(b.dueAt ?? ''));
          String? currentLabel;
          for (final task in ordinary) {
            final due = localDateTimeFromStorage(task.dueAt);
            final label = task.bucket == TaskBucket.overdue
                ? _overdueGroup
                : calendarGroupLabel(due, empty: '未安排');
            if (groups.isEmpty || currentLabel != label) {
              groups.add((label, []));
              currentLabel = label;
            }
            groups.last.$2.add(task);
          }
        }
      } else if (c.view == WorkspaceView.plan) {
        ordinary.sort((a, b) => (a.dueAt ?? '').compareTo(b.dueAt ?? ''));
        for (final task in ordinary) {
          final label =
              calendarGroupLabel(localDateTimeFromStorage(task.dueAt));
          if (groups.isEmpty || groups.last.$1 != label) groups.add((label, []));
          groups.last.$2.add(task);
        }
      } else {
        groups.add(('', ordinary));
      }
      final list = Container(
          color: tokens.content,
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
                                      TaskListMetrics.horizontalPadding,
                                      TaskListMetrics.headerTopPadding,
                                      TaskListMetrics.horizontalPadding,
                                      0),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        TaskListHeader(
                                            icon: _viewIcon(c.view),
                                            title: c.viewTitle,
                                            trailing: _listHeaderActions()),
                                        SizedBox(
                                            height: TaskListMetrics
                                                .headerBottomGap),
                                        if (!completedView)
                                          QuickAddField(
                                              controller: c, listStyle: true)
                                      ])),
                              Expanded(
                                  child: ListView(
                                key: PageStorageKey(
                                    'tasks-${c.view.name}-${c.selectedListName}'),
                                padding: EdgeInsets.fromLTRB(
                                    TaskListMetrics.horizontalPadding,
                                    0,
                                    TaskListMetrics.horizontalPadding,
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
                                  for (final group in groups)
                                    if (group.$2.isNotEmpty)
                                      ..._groupSlivers(group, narrow,
                                          compact: compact,
                                          wideInspector: wideInspector),
                                  if (!completedView && abandoned.isNotEmpty)
                                    ..._groupSlivers(
                                        ('已放弃', abandoned), narrow,
                                        compact: compact,
                                        wideInspector: wideInspector),
                                  if (!completedView && completed.isNotEmpty)
                                    ..._groupSlivers(
                                        (_completedGroup, completed), false,
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
        final listWidth = TaskListMetrics.paneWidth(
            constraints.maxWidth - _detailMinWidth - _listDividerWidth);
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

  /// The list header carries sort and more, nothing else. The progress ring
  /// that used to sit here measured the day instead of showing the day, and
  /// the count it displayed is already in the group headings below.
  Widget _listHeaderActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        _toggleGroup(_completedGroup);
    }
  }

  /// One group: heading plus rows.
  ///
  /// Folding is decided here, not by each caller, so 今天 / 最近 7 天 / 计划 /
  /// 已完成 all fold the same way. 顺延 rides the heading's `trailing` slot for
  /// the same reason — a group-level action is part of the list grammar, and a
  /// screen that forgot to pass it would silently lose the affordance.
  List<Widget> _groupSlivers((String, List<TaskItem>) group, bool narrow,
      {bool compact = false, bool wideInspector = false}) {
    final (label, tasks) = group;
    final expanded = !_isCollapsed(label);
    return [
      const SizedBox(height: TaskListMetrics.groupTopGap),
      if (label.isNotEmpty)
        TaskGroupHeader(
            title: label,
            count: tasks.length,
            expanded: expanded,
            onToggle: () => _toggleGroup(label),
            trailing: label == _overdueGroup ? _postponeButton(tasks) : null),
      // The unnamed group (a plain list of tasks) has no heading to fold with.
      if (label.isEmpty || expanded)
        for (var i = 0; i < tasks.length; i++) ...[
          _task(tasks[i], narrow, compact: true, wideInspector: wideInspector),
          if (i < tasks.length - 1) const TaskListDivider(),
        ],
    ];
  }

  /// Moves every overdue task in [tasks] to today, the group's default.
  ///
  /// Deliberately one `setSchedule` per task instead of `bulkSchedule`: that
  /// command applies a single draft to the whole selection, which would strip
  /// the clock off every timed task — "昨天 09:30" has to land on "今天 09:30",
  /// not on an all-day today. Each call hands back its own snapshot undo, so
  /// they are chained and offered as one 撤销.
  void _postponeOverdue(List<TaskItem> tasks) {
    final actions = widget.controller.taskActions;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final undos = <UndoCommand>[];
    var moved = 0;
    for (final task in tasks) {
      final result = actions.setSchedule(
          task.id,
          TaskScheduleDraft.forDay(today,
              preserveClock: localDateTimeFromStorage(task.dueAt),
              hasTime: task.scheduledWithTime));
      if (!result.success) continue;
      moved++;
      final undo = result.undo;
      if (undo != null) undos.add(undo);
    }
    if (!mounted) return;
    final feedback = FeedbackScope.maybeOf(context);
    if (feedback == null) return;
    if (moved == 0) {
      feedback.show(const WorkFollowFeedback(
          kind: WorkFollowFeedbackKind.info, message: '没有可顺延的任务'));
      return;
    }
    // One HUD for the whole group move, with one undo that replays every
    // snapshot in reverse.
    feedback.show(WorkFollowFeedback(
        kind: WorkFollowFeedbackKind.undoable,
        message: '已顺延 $moved 项到 今天',
        actionLabel: '撤销',
        actionIcon: WorkFollowIcons.undo,
        onAction: undos.isEmpty
            ? null
            : () {
                for (final undo in undos.reversed) {
                  undo.execute();
                }
              }));
  }

  Widget _postponeButton(List<TaskItem> tasks) {
    return TextButton(
        key: const ValueKey('group-postpone-overdue'),
        onPressed: () => _postponeOverdue(tasks),
        style: TextButton.styleFrom(
            foregroundColor: WorkFollowTheme.of(context).textTertiary,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            // 20pt, measured: `VisualDensity.compact` shaves 8 off the minimum,
            // which left a 16pt target — too short to hit reliably beside a
            // 30pt heading.
            minimumSize: const Size(0, 20),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: Text('顺延',
            style: TextStyle(
                fontSize: WorkFollowMacTypography.navigationMeta,
                height: WorkFollowMacTypography.lineControl,
                fontWeight: WorkFollowMacWeight.regular)));
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
              ],
            ));
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
                  onPressed: () {
                    final result = controller.taskActions
                        .bulkComplete(controller.multiSelectedTaskIds);
                    // Marked as reported on the way out: the batch bumps the
                    // shell's action version, and this call is the report.
                    presentTaskResultIn(context, result,
                        actionVersion: controller.actionVersion);
                  },
                  child: const Text('完成')),
              Builder(
                  builder: (anchor) => TextButton(
                      onPressed: () async {
                        final firstSelected = controller.tasks
                            .where((task) => controller.multiSelectedTaskIds
                                .contains(task.id))
                            .firstOrNull;
                        final task = firstSelected ??
                            const TaskItem(
                                id: 'bulk-date',
                                title: '批量安排日期',
                                listName: '收集箱',
                                bucket: TaskBucket.unscheduled);
                        final settings =
                            await showTaskSchedulePanel(anchor, task);
                        if (settings != null) {
                          final actionResult = controller.taskActions.bulkSchedule(
                              controller.multiSelectedTaskIds,
                              settings.schedule);
                          presentTaskResultIn(context, actionResult,
                              actionVersion: controller.actionVersion);
                        }
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
                        if (result != null) {
                          final actionResult = controller.taskActions.bulkMove(
                              controller.multiSelectedTaskIds, result);
                          presentTaskResultIn(context, actionResult,
                              actionVersion: controller.actionVersion);
                        }
                      },
                      child: const Text('移动'))),
              TextButton(
                  onPressed: () {
                    final result = controller.taskActions
                        .bulkDelete(controller.multiSelectedTaskIds);
                    presentTaskResultIn(context, result,
                        actionVersion: controller.actionVersion);
                  },
                  child: const Text('删除')),
              TextButton(
                  onPressed: controller.clearMultiSelect,
                  child: const Text('取消选择')),
            ]));
  }
}
