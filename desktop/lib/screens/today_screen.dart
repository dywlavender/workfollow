import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/desktop_popover.dart';
import '../widgets/quick_add.dart';
import '../widgets/task_date_picker.dart';
import '../widgets/task_inspector.dart';
import '../widgets/task_row.dart';

/// Task list pages (今天 / 计划 / 收集箱 / 全部 / 已完成 / individual lists).
/// The redesigned layout floats grouped cards on the canvas: each date or
/// status group becomes one card, rows expand into an inline editor in place,
/// and the today view gets a progress ring in the header.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  bool detailOnly = false;
  bool showCompleted = false;
  late int openVersion;
  final expandedEditorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    openVersion = widget.controller.taskOpenVersion;
    detailOnly = widget.controller.selectedTaskId != null;
    showCompleted = widget.controller.selectedTask?.completed ?? false;
    if (detailOnly) _revealEditor();
  }

  @override
  void didUpdateWidget(covariant TodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (openVersion != widget.controller.taskOpenVersion) {
      openVersion = widget.controller.taskOpenVersion;
      detailOnly = true;
      if (widget.controller.selectedTask?.completed == true)
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
    final active = tasks.where((task) => !task.completed).toList();
    final completed = tasks.where((task) => task.completed).toList();
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      // Short windows get a dense header so the first tasks stay on screen.
      final compact = constraints.maxHeight < 680;
      final selected = c.selectedTask;
      final detail = narrow && detailOnly && selected != null;
      final groups = <(String, List<TaskItem>, bool)>[];
      if (completedView) {
        groups.add(('', completed, false));
      } else if (c.view == WorkspaceView.today && c.selectedListName == null) {
        final overdue =
            active.where((t) => t.bucket == TaskBucket.overdue).toList();
        if (overdue.isNotEmpty) groups.add(('之前安排', overdue, true));
        groups.add((
          '今天',
          active.where((t) => t.bucket != TaskBucket.overdue).toList(),
          false
        ));
      } else if (c.view == WorkspaceView.plan) {
        active.sort((a, b) => (a.dueAt ?? '').compareTo(b.dueAt ?? ''));
        for (final task in active) {
          final label = calendarDateLabel(localDateTimeFromStorage(task.dueAt));
          if (groups.isEmpty || groups.last.$1 != label)
            groups.add((label, [], false));
          groups.last.$2.add(task);
        }
      } else {
        groups.add(('', active, false));
      }
      final list = Container(
          color: tokens.canvas,
          child: Stack(children: [
            Column(children: [
              Expanded(
                  child: Center(
                      child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                          padding: EdgeInsets.fromLTRB(
                              narrow ? 22 : 8,
                              compact ? 14 : 26,
                              narrow ? 22 : 8,
                              compact ? 12 : 18),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PageHeader(
                                    dense: compact,
                                    eyebrow: c.view == WorkspaceView.today &&
                                            c.selectedListName == null
                                        ? _todayLabel()
                                        : null,
                                    title: c.viewTitle,
                                    subtitle: completedView
                                        ? '已经完成的事，都在这里。'
                                        : c.view == WorkspaceView.inbox
                                            ? '先记下来，稍后再安排。'
                                            : c.view == WorkspaceView.plan
                                                ? '按日期查看接下来的安排。'
                                                : '${active.length} 件待办 · 已完成 ${completed.length} 件',
                                    trailing: c.view == WorkspaceView.today &&
                                            c.selectedListName == null &&
                                            !completedView
                                        ? _ProgressSummary(
                                            compact: compact,
                                            done: completed.length,
                                            total: active.length +
                                                completed.length)
                                        : null),
                                if (!completedView) ...[
                                  SizedBox(height: compact ? 12 : 20),
                                  QuickAddField(controller: c)
                                ],
                              ])),
                      Expanded(
                          child: ListView(
                        key: PageStorageKey(
                            'tasks-${c.view.name}-${c.selectedListName}'),
                        padding: EdgeInsets.fromLTRB(
                            narrow ? 12 : 0, 2, narrow ? 12 : 0, 56),
                        children: [
                          if ((completedView ? completed : active).isEmpty)
                            AppCard(
                                padding: EdgeInsets.zero,
                                child: EmptyHint(
                                    icon: completedView
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.checklist_rounded,
                                    title: completedView
                                        ? '完成的任务会出现在这里'
                                        : c.view == WorkspaceView.today
                                            ? '今天，留一点从容'
                                            : c.view == WorkspaceView.plan
                                                ? '还没有未来的安排'
                                                : '这里还是空的',
                                    hint: completedView
                                        ? '每完成一件事，都是一点进展。'
                                        : '在上方记下一件事，按 Return 添加。')),
                          for (final group in groups) ...[
                            if (group.$2.isNotEmpty)
                              ..._groupSlivers(group, narrow),
                          ],
                          if (!completedView && completed.isNotEmpty)
                            ..._completedSlivers(completed),
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

  /// Group cards are assembled from per-row slivers (top cap, row boxes with
  /// side borders, hairline dividers, bottom cap) so every task row stays a
  /// direct scroll child — `ensureVisible` and the in-place editor reveal
  /// stay pixel-accurate even in very long groups.
  Widget _cardSide(Widget child, Color edge) => DecoratedBox(
      decoration: BoxDecoration(
          color: WorkFollowTheme.of(context).content,
          border: Border(
              left: BorderSide(color: edge), right: BorderSide(color: edge))),
      child: child);

  Widget _cardTop({Widget? header, required Color edge, double height = 8}) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
        height: header == null ? height : null,
        padding:
            header == null ? null : const EdgeInsets.fromLTRB(16, 12, 12, 6),
        decoration: BoxDecoration(
            color: tokens.content,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(
                top: BorderSide(color: edge),
                left: BorderSide(color: edge),
                right: BorderSide(color: edge))),
        child: header);
  }

  Widget _cardBottom(Color edge) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
        height: 10,
        decoration: BoxDecoration(
            color: tokens.content,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(14)),
            border: Border(
                bottom: BorderSide(color: edge),
                left: BorderSide(color: edge),
                right: BorderSide(color: edge))));
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
              fontSize: 12.5, fontWeight: FontWeight.w700, color: textColor)),
      const SizedBox(width: 6),
      Text('$count',
          style: TextStyle(fontSize: 11, color: tokens.textTertiary)),
      if (trailing != null) trailing,
    ]);
  }

  List<Widget> _groupSlivers(
      (String, List<TaskItem>, bool) group, bool narrow) {
    final tokens = WorkFollowTheme.of(context);
    final (label, tasks, danger) = group;
    final edge = danger ? tokens.warning.withValues(alpha: .5) : tokens.border;
    return [
      const SizedBox(height: 12),
      _cardTop(
          edge: edge,
          header: label.isEmpty
              ? null
              : _groupHeaderRow(
                  label: label,
                  count: tasks.length,
                  dotColor: danger ? tokens.warning : tokens.accent,
                  textColor: danger ? tokens.warning : tokens.textSecondary)),
      for (var i = 0; i < tasks.length; i++) ...[
        _cardSide(_task(tasks[i], narrow), edge),
        if (i < tasks.length - 1)
          _cardSide(
              Container(
                  height: 1,
                  margin: const EdgeInsets.only(left: 48, right: 12),
                  color: tokens.border),
              edge),
      ],
      _cardBottom(edge),
    ];
  }

  List<Widget> _completedSlivers(List<TaskItem> completed) {
    final tokens = WorkFollowTheme.of(context);
    return [
      const SizedBox(height: 12),
      _cardTop(
          edge: tokens.border,
          header: GestureDetector(
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
                    AppIconButton(
                        icon: showCompleted
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        tooltip: showCompleted ? '收起已完成' : '展开已完成',
                        size: 28,
                        iconSize: 18,
                        onPressed: () =>
                            setState(() => showCompleted = !showCompleted)),
                  ]))))),
      if (showCompleted)
        for (var i = 0; i < completed.length; i++) ...[
          _cardSide(_task(completed[i], false), tokens.border),
          if (i < completed.length - 1)
            _cardSide(
                Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 48, right: 12),
                    color: tokens.border),
                tokens.border),
        ],
      _cardBottom(tokens.border),
    ];
  }

  Widget _task(TaskItem task, bool narrow) {
    final c = widget.controller, tokens = WorkFollowTheme.of(context);
    if (!narrow && c.selectedTaskId == task.id && c.multiSelectCount == 0) {
      return Container(
          key: expandedEditorKey,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
          child: TaskInspector(
              key: ValueKey('editor-${task.id}'),
              task: task,
              controller: c,
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

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.month} 月 ${now.day} 日 · 星期${'一二三四五六日'[now.weekday - 1]}';
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
              fontSize: compact ? 10 : 10.5, color: tokens.textTertiary)),
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
        radius: 12,
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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary))),
              TextButton(
                  onPressed: controller.bulkCompleteSelected,
                  child: const Text('完成')),
              Builder(
                  builder: (anchor) => TextButton(
                      onPressed: () async {
                        final result = await showTaskDatePicker(anchor);
                        if (result != null)
                          controller.bulkRescheduleSelected(result.date,
                              hasTime: result.hasTime);
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
                          controller.bulkMoveSelectedToList(result);
                      },
                      child: const Text('移动'))),
              TextButton(
                  onPressed: controller.bulkDeleteSelected,
                  child: const Text('删除')),
              TextButton(
                  onPressed: controller.clearMultiSelect,
                  child: const Text('取消选择')),
            ]));
  }
}
