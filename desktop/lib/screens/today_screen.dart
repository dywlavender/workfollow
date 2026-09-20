import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_surface_tokens.dart';
import '../theme/workfollow_theme.dart';
import '../features/feedback/feedback_event.dart';
import '../features/tasks/application/task_tree_projection.dart';
import '../features/feedback/feedback_scope.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/application/task_list_projection.dart';
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

/// Task list pages (最近 7 天 / 今天 / 收集箱 / 所有任务 / 已完成 / individual
/// lists).
///
/// This screen owns sorting, selection and the responsive split. It does *not*
/// own grouping: which heading a row belongs under is a business rule and lives
/// in [TaskListProjection]. It owns no visual values either: pane width,
/// gutter, row padding, group headings and dividers all come from
/// [TaskListMetrics] and the shared task-list widgets, so a second list view
/// cannot drift into its own design.
/// Wide macOS windows use a TickTick-style list + inspector split. Smaller
/// windows keep the existing list/detail fallback so the task editor never
/// gets squeezed into an unusable column.
class TodayScreen extends StatefulWidget {
  const TodayScreen(
      {super.key,
      required this.controller,
      this.compactDensity = false,
      this.persistentInspector = true});
  final WorkspaceController controller;
  final bool compactDensity;

  /// When enabled, a wide window keeps the right-hand inspector visible even
  /// before a task is selected. This is the macOS default to match TickTick;
  /// when disabled, the selected task uses the list-first inline fallback.
  final bool persistentInspector;
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  /// Where the groups come from. Stateless and pure, so building it here costs
  /// nothing and there is no instance state to keep in step with the view.
  static const TaskListProjection _listProjection = TaskListProjection();

  // TodayScreen receives the width left after AppRail. Keep the breakpoints
  // derived from the panes they protect: a wide workspace is only entered
  // when the list can keep its minimum width beside the inspector, while the
  // narrow fallback keeps enough room for the compact detail view.
  static const double _detailMinWidth = WorkFollowLayout.taskDetailMinWidth;
  static const double _listDividerWidth = WorkFollowLayout.taskListDividerWidth;
  static const double _wideInspectorBreakpoint =
      TaskListMetrics.minPaneWidth + _detailMinWidth + _listDividerWidth;

  bool detailOnly = false;

  /// Groups the user folded away, keyed by [TaskListGroup.id].
  ///
  /// Membership means "collapsed", so an empty set is the default posture:
  /// every group open, including 已完成 — starting that one collapsed hides the
  /// tasks the user finished a moment ago, which are exactly the ones they are
  /// still looking at.
  ///
  /// Keyed by id rather than by heading so folding survives a rebuild that
  /// reorders or renames the groups: a task turning overdue must not fold 今天
  /// by accident, and the closing group's heading follows its content
  /// (已完成 / 已放弃 / 已完成&已放弃) without the fold being lost to the
  /// rename. [PageStorageKey] on the list scopes the set per view.
  final collapsedGroups = <String>{};

  bool _isCollapsed(String id) => collapsedGroups.contains(id);

  void _toggleGroup(String id) {
    setState(() {
      if (!collapsedGroups.remove(id)) collapsedGroups.add(id);
    });
  }

  /// The list menu's 展开/收起已完成: one switch for every heading that holds
  /// finished tasks.
  ///
  /// The dated views carry one such group; 已完成 carries one per closing day.
  /// The entry cannot name a single heading, so it acts on whichever are on
  /// screen and folds them together — a control that collapsed half of them
  /// would leave the list in a state no second press could describe.
  void _toggleClosedGroups() {
    final ids = [
      for (final group in _groups)
        if (group.kind == TaskListGroupKind.closed && group.tasks.isNotEmpty)
          group.id,
    ];
    if (ids.isEmpty) return;
    final collapse = !ids.every(_isCollapsed);
    setState(() {
      for (final id in ids) {
        if (collapse) {
          collapsedGroups.add(id);
        } else {
          collapsedGroups.remove(id);
        }
      }
    });
  }

  /// The groups the last build drew, so the list menu can act on them without
  /// recomputing the projection.
  List<TaskListGroup> _groups = const [];

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
        collapsedGroups.remove(TaskListProjection.closedId);
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
    // The screen owns its rebuilds: fold toggles and task edits mutate the
    // controller directly, and a standalone pump (tests) has no shell above.
    return AnimatedBuilder(
        animation: widget.controller, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final c = widget.controller;
    final tokens = WorkFollowTheme.of(context);
    final completedView = c.view == WorkspaceView.completed;
    // Where each row goes is a business rule, not a rendering detail: the
    // projection decides the groups, the screen draws them. Sorting stays here
    // because it is the user's own control over the rows inside a group.
    final groups = [
      for (final group in _listProjection.groupsFor(
        view: c.view,
        tasks: c.tasks,
        selectedListName: c.selectedListName,
        selectedTagName: c.selectedTagName,
        reference: c.dateReference,
      ))
        group,
    ];
    _groups = groups;
    return LayoutBuilder(builder: (context, constraints) {
      // Until both panes fit their desktop minimums, keep the list/detail
      // stack available instead of leaving a selected task without a detail
      // surface in the intermediate-width band.
      final narrow = constraints.maxWidth < _wideInspectorBreakpoint;
      final wideInspector = constraints.maxWidth >= _wideInspectorBreakpoint &&
          (widget.persistentInspector || c.selectedTaskId != null);
      // Short windows get a dense header so the first tasks stay on screen.
      final compact = widget.compactDensity || constraints.maxHeight < 680;
      final selected = c.selectedTask;
      final detail = narrow && detailOnly && selected != null;
      final empty = groups.every((group) => group.tasks.isEmpty);
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
                        width: constraints.maxWidth
                            .clamp(0, TaskListMetrics.listColumnMaxWidth)
                            .toDouble(),
                        height: double.infinity,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      TaskListMetrics.horizontalPadding,
                                      TaskListMetrics.headerTopPadding,
                                      TaskListMetrics.horizontalPadding,
                                      WorkFollowSpacing.zero),
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
                                    WorkFollowSpacing.zero,
                                    TaskListMetrics.horizontalPadding,
                                    WorkFollowSpacing.space7),
                                children: [
                                  if (empty)
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
                                                        : '这里还是空的',
                                            hint: completedView
                                                ? '每完成一件事，都是一点进展。'
                                                : '在上方记下一件事，按 Return 添加。')),
                                  for (final group in groups)
                                    if (group.tasks.isNotEmpty)
                                      ..._groupSlivers(group, narrow,
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
        final available =
            constraints.maxWidth - _detailMinWidth - _listDividerWidth;
        final listWidth = _boundedListPaneWidth(available);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('web-task-list-pane'),
              width: listWidth,
              child: list,
            ),
            _ResizablePaneDivider(
              key: const ValueKey('task-pane-divider'),
              onDrag: (delta) => _resizeListPane(available, delta),
            ),
            Expanded(
              child: ConstrainedBox(
                key: const ValueKey('web-task-detail-pane'),
                constraints: const BoxConstraints(minWidth: _detailMinWidth),
                // The detail pane is the list's peer, not the page behind it:
                // it holds the content surface even while it is empty, so the
                // shell never breaks into a grey field beside a white list.
                child: ColoredBox(
                  color: tokens.content,
                  child: selected == null
                      ? const _EmptyInspector()
                      : TaskInspector(
                          key: ValueKey('wide-detail-${selected.id}'),
                          task: selected,
                          controller: c),
                ),
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
              showBack: true,
              onBack: () => setState(() => detailOnly = false)),
      ]);
    });
  }

  double _boundedListPaneWidth(double available) {
    final upper = available < TaskListMetrics.maxPaneWidth
        ? available
        : TaskListMetrics.maxPaneWidth;
    final lower = upper < TaskListMetrics.minPaneWidth
        ? upper
        : TaskListMetrics.minPaneWidth;
    return _currentListPaneWidth.clamp(lower, upper).toDouble();
  }

  void _resizeListPane(double available, double delta) {
    final upper = available < TaskListMetrics.maxPaneWidth
        ? available
        : TaskListMetrics.maxPaneWidth;
    final lower = upper < TaskListMetrics.minPaneWidth
        ? upper
        : TaskListMetrics.minPaneWidth;
    final next = (_currentListPaneWidth + delta).clamp(lower, upper).toDouble();
    if (next == _currentListPaneWidth) return;
    widget.controller.setTaskListPaneWidth(next);
    // TodayScreen is also mounted directly in widget tests and in a few
    // embedders that do not listen to the controller. Keep the current pane
    // responsive immediately while the controller carries the value to the
    // next task-view instance.
    if (mounted) setState(() {});
  }

  double get _currentListPaneWidth =>
      widget.controller.taskListPaneWidth ?? TaskListMetrics.preferredPaneWidth;

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
        _toggleClosedGroups();
    }
  }

  /// One group: heading plus rows.
  ///
  /// Folding is decided here, not by each caller, so 今天 / 最近 7 天 / 更远 /
  /// 已完成 all fold the same way. 顺延 rides the overdue heading's `trailing`
  /// slot for the same reason — a group-level action is part of the list
  /// grammar, and a screen that forgot to pass it would silently lose the
  /// affordance.
  List<Widget> _groupSlivers(TaskListGroup group, bool narrow,
      {bool compact = false, bool wideInspector = false}) {
    // A date group is named by its day; a group named by a rule carries its own
    // heading. The plain group is the one with no heading at all.
    final label = group.label ?? calendarGroupLabel(group.day);
    // The sort control orders live work. A group of finished tasks is read by
    // when it was closed — 已完成 is newest-first on purpose — so re-sorting it
    // by due date or priority would answer a question nobody asked.
    final tasks = group.kind == TaskListGroupKind.closed
        ? group.tasks.toList()
        : _ordered(group.tasks.toList());
    final expanded = !_isCollapsed(group.id);
    return [
      const SizedBox(height: TaskListMetrics.groupTopGap),
      if (label.isNotEmpty)
        TaskGroupHeader(
            title: label,
            count: tasks.length,
            expanded: expanded,
            onToggle: () => _toggleGroup(group.id),
            trailing: group.kind == TaskListGroupKind.overdue
                ? _postponeButton(tasks)
                : null),
      // The unnamed group (a plain list of tasks) has no heading to fold with.
      // Rows come from the tree projection: parents carry their children, so
      // a child never renders twice and roots stay grouped with their tree.
      if (label.isEmpty || expanded)
        for (var i = 0; i < tasks.length; i++) ...[
          ..._treeRows(tasks[i], narrow,
              compact: compact, wideInspector: wideInspector),
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

  /// The overdue group's one action, drawn in the ink a scheduled date wears.
  ///
  /// A row's date is the list's only coloured text — overdue is `danger` and
  /// anything still open is `accent` — and 顺延 was reading `textTertiary`,
  /// the same muted grey as the count beside it, so a control and a number
  /// looked like the same kind of thing. It takes `accent` instead, the one
  /// token [TaskMetadataTrail] gives a date that is still ahead of the reader:
  /// postponing onto today and a row dated today are the same statement about
  /// the same day. Sharing the token is the point — a palette move has to take
  /// both, or the offer stops matching the thing it offers.
  Widget _postponeButton(List<TaskItem> tasks) {
    return TextButton(
        key: const ValueKey('group-postpone-overdue'),
        onPressed: () => _postponeOverdue(tasks),
        style: TextButton.styleFrom(
            foregroundColor: WorkFollowTheme.of(context).accent,
            padding: const EdgeInsets.symmetric(
                horizontal: WorkFollowSpacing.inlineGap),
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
      {bool compact = false, bool wideInspector = false, TaskTreeNode? node}) {
    final c = widget.controller, tokens = WorkFollowTheme.of(context);
    if (!narrow &&
        !wideInspector &&
        c.selectedTaskId == task.id &&
        c.multiSelectCount == 0) {
      return Container(
          key: expandedEditorKey,
          padding: const EdgeInsets.fromLTRB(
              WorkFollowSpacing.space2,
              WorkFollowSpacing.space2,
              WorkFollowSpacing.space2,
              WorkFollowSpacing.relaxedGap),
          child: TaskInspector(
              key: ValueKey('editor-${task.id}'),
              task: task,
              controller: c,
              presentation: TaskInspectorPresentation.inline));
    }
    return DragTarget<String>(
        onWillAcceptWithDetails: (data) => data.data != task.id,
        onAcceptWithDetails: (data) => c.moveTaskBefore(data.data, task.id),
        builder: (context, candidates, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (candidates.isNotEmpty)
                  Container(
                      height: TaskListMetrics.dragMarkerHeight,
                      margin: const EdgeInsets.fromLTRB(
                          WorkFollowSpacing.relaxedGap,
                          WorkFollowSpacing.microGap,
                          WorkFollowSpacing.relaxedGap,
                          WorkFollowSpacing.microGap),
                      decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(
                              TaskListMetrics.dragMarkerRadius))),
                LongPressDraggable<String>(
                  data: task.id,
                  delay: WorkFollowMotion.dragStartDelay,
                  feedback: Material(
                      elevation: WorkFollowShadows.level1Elevation,
                      borderRadius: BorderRadius.circular(
                          TaskListMetrics.dragPreviewRadius),
                      child: SizedBox(
                          width: TaskListMetrics.dragPreviewWidth,
                          child: Padding(
                              padding: const EdgeInsets.all(
                                  WorkFollowSpacing.relaxedGap),
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
                      expander: c.hasChildren(task.id)
                          ? _Expander(
                              expanded: c.isTaskExpanded(task.id),
                              onToggle: () => c.toggleTaskExpanded(task.id))
                          : null,
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

  /// Flattens one root task through the tree projection into list rows: the
  /// parent (with its disclosure gutter) followed by its visible children.
  List<Widget> _treeRows(TaskItem root, bool narrow,
      {bool compact = false, bool wideInspector = false}) {
    final c = widget.controller;
    final nodes = taskTreeNodes(
        roots: [root],
        childrenOf: c.childRowsFor,
        hasChildren: c.hasChildren,
        isExpanded: c.isTaskExpanded);
    return [
      for (final node in nodes)
        if (node.depth == 0)
          _task(node.task, narrow,
              compact: compact, wideInspector: wideInspector, node: node)
        else
          _childRow(node.task, compact, narrow),
    ];
  }

  /// A subtask row in the list: the full TaskRow grammar, indented one level.
  /// Children are not draggable and are not drop targets in this phase.
  Widget _childRow(TaskItem child, bool compact, bool narrow) {
    final c = widget.controller;
    return TaskRow(
        key: ValueKey(child.id),
        task: child,
        controller: c,
        depth: 1,
        selected: c.selectedTaskId == child.id,
        compact: compact,
        onActivate: () {
          if (narrow) setState(() => detailOnly = true);
        });
  }

  IconData _viewIcon(WorkspaceView view) => switch (view) {
        WorkspaceView.recent => WorkFollowIcons.recent,
        WorkspaceView.today => WorkFollowIcons.today,
        WorkspaceView.inbox => WorkFollowIcons.inbox,
        WorkspaceView.all => WorkFollowIcons.allTasks,
        WorkspaceView.completed => WorkFollowIcons.completed,
        WorkspaceView.work ||
        WorkspaceView.study ||
        WorkspaceView.personal =>
          WorkFollowIcons.list,
        _ => WorkFollowIcons.tasks,
      };
}

/// A one-pixel visual divider with a larger invisible hit target. Keeping the
/// layout width at one pixel preserves the list/detail geometry while making
/// the resize gesture usable with a trackpad or mouse.
class _ResizablePaneDivider extends StatefulWidget {
  const _ResizablePaneDivider({super.key, required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_ResizablePaneDivider> createState() => _ResizablePaneDividerState();
}

class _ResizablePaneDividerState extends State<_ResizablePaneDivider> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      width: WorkFollowLayout.taskListDividerWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: hovering ? tokens.accent : tokens.border,
            ),
          ),
          Positioned(
            left: -6,
            right: -6,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              onEnter: (_) => setState(() => hovering = true),
              onExit: (_) => setState(() => hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    widget.onDrag(details.delta.dx),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
        padding: const EdgeInsets.all(WorkFollowSpacing.pageBottomSpace),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(WorkFollowIcons.touch,
                size: WorkFollowMetrics.headerIcon, color: tokens.textTertiary),
            const SizedBox(height: WorkFollowSpacing.space3),
            Text('选择一个任务开始编辑',
                style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: WorkFollowMacTypography.listTitle,
                    height: WorkFollowMacTypography.lineControl,
                    fontWeight: WorkFollowMacWeight.semibold)),
            const SizedBox(height: WorkFollowSpacing.inlineGap),
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
        padding: const EdgeInsets.symmetric(
            horizontal: WorkFollowSpacing.space3,
            vertical: WorkFollowSpacing.denseGap),
        child: Wrap(
            spacing: WorkFollowSpacing.microGap,
            runSpacing: WorkFollowSpacing.space1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                  padding:
                      const EdgeInsets.only(right: WorkFollowSpacing.inlineGap),
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
                          final actionResult = controller.taskActions
                              .bulkSchedule(controller.multiSelectedTaskIds,
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

/// The tree fold chevron in the row gutter: down when expanded, right when
/// folded. Pure UI state — the fold never lives in the task data.
class _Expander extends StatelessWidget {
  const _Expander({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  /// The gutter every row reserves, so checkbox columns never shift when a
  /// disclosure appears.
  static const double width = TaskListMetrics.disclosureWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return SizedBox(
      width: width,
      child: GestureDetector(
        key: ValueKey(expanded ? 'task-expander-open' : 'task-expander-closed'),
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AppIcon(
              expanded
                  ? WorkFollowIcons.expandMore
                  : WorkFollowIcons.chevronNext,
              size: WorkFollowMetrics.metadataIcon,
              color: tokens.textTertiary),
        ),
      ),
    );
  }
}
