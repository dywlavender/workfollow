import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../features/feedback/feedback_event.dart';
import '../features/feedback/feedback_scope.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/presentation/task_feedback_mapper.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';
import 'task_date_picker.dart';
import 'task_schedule_panel.dart';
import 'task_deadline_picker.dart';
import 'task_priority_picker.dart';
import 'task_list_picker.dart';
import 'task_tag_picker.dart';
import 'task_document_editor.dart';
import 'task_editor_viewport.dart';
import 'task_more_menu.dart';
import 'task_menu_actions.dart';

/// TickTick-style task workbench. The inspector stays mounted in the right
/// pane on wide windows and presents one continuous document surface instead
/// of hiding normal task capabilities behind an "advanced" toggle.
class TaskInspector extends StatefulWidget {
  const TaskInspector({
    super.key,
    required this.task,
    required this.controller,
    this.showBack = false,
    this.onBack,
    this.inline = false,
    this.onOpenFocusTimer,
  });

  final TaskItem task;
  final WorkspaceController controller;
  final bool showBack;
  final VoidCallback? onBack;
  final bool inline;
  final VoidCallback? onOpenFocusTimer;

  @override
  State<TaskInspector> createState() => _TaskInspectorState();
}

class _TaskInspectorState extends State<TaskInspector> {
  late final TextEditingController title;
  final titleFocus = FocusNode();
  final inspectorFocus = FocusNode(debugLabel: 'task-inspector');
  final editingScope = FocusScopeNode(debugLabel: 'task-content');
  final documentKey = GlobalKey<TaskDocumentEditorState>();
  late int focusVersion;
  bool listOpen = false, dateOpen = false, moreOpen = false;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task.title);
    focusVersion = widget.controller.inspectorTitleFocusVersion;
    _consumeSubtaskRequest();
    widget.controller.addListener(_focusRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.pendingInspectorTitleTaskId == widget.task.id) {
        widget.controller.consumeInspectorTitleFocus();
        titleFocus.requestFocus();
      } else {
        inspectorFocus.requestFocus();
      }
    });
  }

  void _consumeSubtaskRequest() {
    if (widget.controller.taskUiState.pendingSubtaskTaskId != widget.task.id)
      return;
    widget.controller.taskUiState.pendingSubtaskTaskId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) documentKey.currentState?.insertSubtasksBlock();
    });
  }

  void _focusRequested() {
    _consumeSubtaskRequest();
    if (focusVersion == widget.controller.inspectorTitleFocusVersion) return;
    focusVersion = widget.controller.inspectorTitleFocusVersion;
    if (widget.controller.selectedTaskId != widget.task.id) return;
    widget.controller.consumeInspectorTitleFocus();
    titleFocus.requestFocus();
  }

  void _escape() {
    if (documentKey.currentState?.dismissSlashMenu() ?? false) return;
    if (documentKey.currentState?.dismissFormattingToolbar() ?? false) return;
    if (editingScope.hasFocus) {
      inspectorFocus.requestFocus();
      return;
    }
    if (widget.inline || widget.showBack) close();
  }

  @override
  void didUpdateWidget(covariant TaskInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!titleFocus.hasFocus && title.text != widget.task.title) {
      title.text = widget.task.title;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_focusRequested);
    title.dispose();
    titleFocus.dispose();
    inspectorFocus.dispose();
    editingScope.dispose();
    super.dispose();
  }

  void close() {
    FocusScope.of(context).unfocus();
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      widget.controller.clearTaskSelection();
    }
  }

  void _complete(TaskItem task) {
    final result = task.isClosed
        ? widget.controller.taskActions.restore(task.id)
        : widget.controller.taskActions.complete(task.id);
    _showActionFeedback(result);
  }

  Future<void> _date(BuildContext anchor, String kind) async {
    final task = widget.task;
    if (kind != 'deadline') {
      setState(() => dateOpen = true);
      final value = await showTaskSchedulePanel(anchor, task);
      if (!mounted) return;
      setState(() => dateOpen = false);
      if (value != null)
        _showActionFeedback(
            widget.controller.taskActions.setScheduleSettings(task.id, value));
      return;
    }
    final value = await TaskDeadlinePicker.show(anchor, value: task.deadlineAt);
    if (value == null || !mounted) return;
    _showActionFeedback(value.date == null
        ? widget.controller.taskActions.clearDeadline(task.id)
        : widget.controller.taskActions.setDeadline(task.id, value.date));
  }

  Future<void> _list(BuildContext anchor) async {
    setState(() => listOpen = true);
    final selected = await TaskListPicker.show(anchor,
        controller: widget.controller, selected: widget.task.listName);
    if (!mounted) return;
    setState(() => listOpen = false);
    if (selected == null) return;
    _showActionFeedback(
        widget.controller.taskActions.moveToList(widget.task.id, selected));
  }

  Future<void> _priority(BuildContext anchor) async {
    final value =
        await TaskPriorityPicker.show(anchor, selected: widget.task.priority);
    if (value == null || !mounted) return;
    _showActionFeedback(
        widget.controller.taskActions.setPriority(widget.task.id, value));
  }

  Future<void> _tags(BuildContext anchor) async {
    final value = await TaskTagPicker.show(anchor,
        initial: widget.task.tags.join('，'),
        availableTags: widget.controller.allTags().keys);
    if (value == null || !mounted) return;
    _showActionFeedback(widget.controller.taskActions
        .setTags(widget.task.id, value.split(RegExp('[,，]'))));
  }

  Future<void> _repeat(BuildContext anchor) => _date(anchor, 'schedule');

  Future<void> _relation(BuildContext anchor) async {
    final noteId = await showDesktopPopover<String>(anchor,
        width: 330,
        maxHeight: 420,
        placement: PopoverPlacement.bottomStart,
        focusPolicy: PopoverFocusPolicy.searchField,
        scrollable: true,
        builder: (context) => _RelationPicker(
              controller: widget.controller,
              selected: widget.task.sourceNoteId,
            ));
    if (noteId == null || !mounted) return;
    final result =
        widget.controller.taskActions.setSourceNote(widget.task.id, noteId);
    _showActionFeedback(result);
    if (result.success) documentKey.currentState?.insertRelationBlock(noteId);
  }

  void _openFocus() {
    if (widget.onOpenFocusTimer != null) {
      widget.onOpenFocusTimer!();
    } else {
      final count = widget.task.focusCount;
      _report(WorkFollowFeedback(
          kind: WorkFollowFeedbackKind.info,
          message: count == 0 ? '还没有专注记录' : '已专注 $count 个番茄'));
    }
  }

  /// Reports something that is not the outcome of a task command — a failed
  /// load, a focus count — through the same channel as command results.
  void _report(WorkFollowFeedback feedback) =>
      FeedbackScope.maybeOf(context)?.show(feedback);

  Future<void> _more(BuildContext anchor) async {
    setState(() => moreOpen = true);
    final action = await TaskMoreMenu.show(anchor,
        task: widget.task, controller: widget.controller);
    if (!mounted) return;
    setState(() => moreOpen = false);
    if (action == null) return;
    switch (action.action) {
      case 'add-subtask':
        documentKey.currentState?.insertSubtasksBlock();
      case 'reminder':
        await _date(anchor, 'reminder');
      case 'repeat':
        await _repeat(anchor);
      case 'deadline':
        await _date(anchor, 'deadline');
      case 'tags':
        await _tags(anchor);
      case 'attachment':
        await documentKey.currentState?.attachFile();
      case 'focus':
        _openFocus();
      case 'relation':
        await _relation(anchor);
      default:
        final result = await runTaskMenuAction(
            context, widget.controller, widget.task, action);
        if (result != null) _showActionFeedback(result);
    }
  }

  void _showActionFeedback(TaskActionResult result) {
    if (!mounted) return;
    final id = result.taskId;
    final moved = id != null &&
        result.feedback != TaskFeedbackIntent.completion &&
        result.destination != null &&
        result.destination != TaskDestination.current &&
        result.destination != TaskDestination.hidden;
    final feedback = FeedbackScope.maybeOf(context);
    if (feedback == null) return;
    if (moved) {
      feedback.show(
          movedAwayFeedback(result,
              onOpen: () => widget.controller.openTask(id)),
          actionVersion: widget.controller.actionVersion);
      return;
    }
    presentTaskResult(feedback, result,
        actionVersion: widget.controller.actionVersion);
  }

  Color _scheduleColor(TaskItem task, WorkFollowTheme tokens) {
    if (task.completed) return tokens.textTertiary;
    final due = localDateTimeFromStorage(task.dueAt);
    if (due == null) return tokens.textSecondary;
    final now = DateTime.now();
    final overdue = task.scheduledWithTime
        ? due.isBefore(now)
        : DateTime(due.year, due.month, due.day)
            .isBefore(DateTime(now.year, now.month, now.day));
    return overdue ? tokens.danger : tokens.accent;
  }

  String _scheduleLabel(TaskItem task) {
    String label(String? stored) {
      final date = localDateTimeFromStorage(stored);
      if (date == null) return '安排日期';
      var value = calendarDateLabel(date, hasTime: false);
      if (['今天', '昨天', '明天', '前天', '后天'].contains(value) ||
          value.contains('周')) {
        value = '$value, ${date.month}月${date.day}日';
      }
      if (task.scheduledWithTime)
        value =
            '$value, ${'${date.hour}'.padLeft(2, '0')}:${'${date.minute}'.padLeft(2, '0')}';
      return value;
    }

    final start = label(task.dueAt);
    return task.dueEndAt == null ? start : '$start – ${label(task.dueEndAt)}';
  }

  Widget _header(BuildContext context, TaskItem task, WorkFollowTheme tokens) {
    return Container(
      key: const ValueKey('task-inspector-header'),
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.space5, vertical: WorkFollowSpacing.cardInset),
      decoration: widget.inline
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border))),
      child: Row(children: [
        if (widget.showBack)
          IconButton(
              tooltip: '返回列表',
              onPressed: close,
              icon: const AppIcon(WorkFollowIcons.back,
                  size: WorkFollowMetrics.headerIcon)),
        _TopPropertyButton(
            key: const ValueKey('task-complete'),
            icon: task.isAbandoned
                ? WorkFollowIcons.abandon
                : task.completed
                    ? WorkFollowIcons.completeBox
                    : WorkFollowIcons.incompleteBox,
            label: task.isAbandoned
                ? '恢复任务'
                : task.completed
                    ? '标记未完成'
                    : '完成任务',
            active: task.completed,
            color: task.completed ? tokens.success : null,
            onPressed: (_) => _complete(task),
            iconOnly: true),
        _headerDivider(tokens),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _TopPropertyButton(
                  key: const ValueKey('task-schedule'),
                  popupOpen: dateOpen,
                  icon: WorkFollowIcons.calendar,
                  label: _scheduleLabel(task),
                  color: _scheduleColor(task, tokens),
                  onPressed: (anchor) => _date(anchor, 'schedule')),
              if (task.reminderAt != null)
                _TopPropertyButton(
                    key: const ValueKey('task-reminder'),
                    icon: WorkFollowIcons.reminder,
                    label:
                        '提醒：${calendarDateLabel(localDateTimeFromStorage(task.reminderAt), hasTime: true)}',
                    active: true,
                    color: task.completed ? tokens.textTertiary : null,
                    onPressed: (anchor) => _date(anchor, 'reminder'),
                    iconOnly: true),
              if (task.recurrenceType != 'NONE')
                _TopPropertyButton(
                    key: const ValueKey('task-repeat'),
                    icon: WorkFollowIcons.repeat,
                    label: switch (task.recurrenceType) {
                      'DAILY' => '每天重复',
                      'WEEKLY' => '每周重复',
                      'MONTHLY' => '每月重复',
                      _ => '重复',
                    },
                    active: true,
                    color: task.completed ? tokens.textTertiary : null,
                    onPressed: _repeat,
                    iconOnly: true),
            ]),
          ),
        ),
        const SizedBox(width: WorkFollowSpacing.space2),
        _TopPropertyButton(
            key: const ValueKey('task-priority'),
            icon: WorkFollowIcons.flag,
            label: task.priority == TaskPriority.none
                ? '优先级'
                : task.priority.label,
            active: task.priority != TaskPriority.none,
            color: task.priority == TaskPriority.high
                ? tokens.danger
                : task.priority == TaskPriority.medium
                    ? tokens.warning
                    : null,
            onPressed: _priority,
            iconOnly: true),
        if (widget.inline)
          IconButton(
              tooltip: '收起任务',
              visualDensity: VisualDensity.compact,
              onPressed: close,
              icon: AppIcon(WorkFollowIcons.close,
                  color: tokens.textTertiary,
                  size: WorkFollowMetrics.headerIcon)),
      ]),
    );
  }

  Widget _headerDivider(WorkFollowTheme tokens) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.compactGap),
        color: tokens.border,
      );

  Widget _saveIndicator(WorkFollowTheme tokens) {
    final loadError = widget.controller.loadError;
    if (loadError == null &&
        widget.controller.saveStatus != SaveStatus.failed) {
      return const SizedBox.shrink();
    }
    final label = loadError ?? '保存失败：${widget.controller.saveError ?? '请重试'}';
    return Tooltip(
      message: label,
      child: TextButton.icon(
        key: const ValueKey('save-status-indicator'),
        onPressed: loadError == null
            ? () => unawaited(widget.controller.retrySave())
            : () => _report(WorkFollowFeedback(
                kind: WorkFollowFeedbackKind.error, message: loadError)),
        icon: AppIcon(WorkFollowIcons.error,
            size: WorkFollowMetrics.metadataIcon, color: tokens.danger),
        label: Text(loadError == null ? '保存失败 · 重试' : '读取失败'),
        style: TextButton.styleFrom(
            foregroundColor: tokens.danger,
            textStyle: const TextStyle(
                fontSize: WorkFollowMacTypography.control,
                fontWeight: WorkFollowMacWeight.medium),
            padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.inlineGap)),
      ),
    );
  }

  Widget _footer(BuildContext context, TaskItem task, WorkFollowTheme tokens) {
    return Container(
      key: const ValueKey('task-inspector-footer'),
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.space5, WorkFollowSpacing.space2, WorkFollowSpacing.space5, WorkFollowSpacing.compactInset),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: tokens.border))),
      child: Row(children: [
        Expanded(
            child: Align(
                alignment: Alignment.centerLeft,
                child: Builder(
                    builder: (anchor) => TextButton.icon(
                        key: const ValueKey('task-list-footer'),
                        onPressed: () => _list(anchor),
                        icon: AppIcon(
                            task.listName == '收集箱'
                                ? WorkFollowIcons.inbox
                                : WorkFollowIcons.list,
                            size: WorkFollowMetrics.compactFieldIcon,
                            color: tokens.textSecondary),
                        label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Text(task.listName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: WorkFollowMacTypography.control,
                                    height: WorkFollowMacTypography.lineControl,
                                    fontWeight: WorkFollowMacWeight.medium,
                                    letterSpacing: WorkFollowMacTracking.none))),
                        style: TextButton.styleFrom(
                            backgroundColor:
                                listOpen ? tokens.canvas : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: WorkFollowSpacing.inlineGap),
                            minimumSize: const Size(
                                0, WorkFollowMetrics.compactButtonHeight),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact))))),
        _saveIndicator(tokens),
        Builder(
            builder: (anchor) => AppIconButton(
                key: const ValueKey('task-format-toggle'),
                icon: WorkFollowIcons.format,
                tooltip: '显示格式工具',
                active: documentKey.currentState?.toolbarVisible ?? false,
                activeBackgroundColor: tokens.canvas,
                iconColor: tokens.textSecondary,
                onPressed: () {
                  unawaited(documentKey.currentState?.toggleToolbar(anchor));
                },
                size: WorkFollowMetrics.iconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon)),
        Builder(
            builder: (anchor) => AppIconButton(
                key: const ValueKey('task-more-actions'),
                icon: WorkFollowIcons.more,
                tooltip: '更多操作',
                active: moreOpen,
                activeBackgroundColor: tokens.canvas,
                iconColor: tokens.textSecondary,
                onPressed: () => _more(anchor),
                size: WorkFollowMetrics.iconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon)),
      ]),
    );
  }

  Widget _editorBody(TaskItem task, WorkFollowTheme tokens,
      {double minHeight = 0}) {
    final horizontalPadding = widget.inline
        ? WorkFollowSpacing.inspectorInlineHorizontalPadding
        : WorkFollowSpacing.inspectorContentHorizontalPadding;
    final topPadding = widget.inline
        ? WorkFollowSpacing.inspectorInlineTopPadding
        : WorkFollowSpacing.inspectorContentTopPadding;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          WorkFollowSpacing.inspectorContentBottomPadding),
      child: TaskEditorViewport(
        minHeight: (minHeight -
                topPadding -
                WorkFollowSpacing.inspectorContentBottomPadding)
            .clamp(0, double.infinity),
        title: TextField(
            key: const ValueKey('task-title-editor'),
            controller: title,
            focusNode: titleFocus,
            minLines: 1,
            maxLines: 2,
            style: TextStyle(
                fontSize: WorkFollowMacTypography.detailTitle,
                fontWeight: WorkFollowMacWeight.semibold,
                height: WorkFollowMacTypography.lineControl,
                letterSpacing: WorkFollowMacTracking.none,
                color:
                    task.completed ? tokens.textTertiary : tokens.textPrimary,
                decoration: task.completed ? TextDecoration.lineThrough : null),
            decoration: const InputDecoration(
                hintText: '任务标题',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero),
            onChanged: (value) =>
                widget.controller.taskActions.setTitle(task.id, value)),
        document: TaskDocumentEditor(
          key: documentKey,
          task: task,
          controller: widget.controller,
          onOpenTags: _tags,
          onOpenRelation: _relation,
          onOpenDeadline: (anchor) => _date(anchor, 'deadline'),
          onOpenFocus: _openFocus,
          onEscape: _escape,
          onToolbarChanged: (_) {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final tokens = WorkFollowTheme.of(context);
    final content = Column(
        mainAxisSize: widget.inline ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _header(context, task, tokens),
          if (widget.inline)
            FocusScope(node: editingScope, child: _editorBody(task, tokens))
          else
            Expanded(
              child: FocusScope(
                node: editingScope,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const ValueKey('task-editor-scroll'),
                    child: _editorBody(task, tokens,
                        minHeight: constraints.maxHeight),
                  ),
                ),
              ),
            ),
          _footer(context, task, tokens),
        ]);
    return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
        child: Focus(
          focusNode: inspectorFocus,
          child: Container(
              color: widget.inline ? Colors.transparent : tokens.content,
              child: content),
        ));
  }
}

/// Compact control strip for the inspector's top property row.
class _TopPropertyButton extends StatelessWidget {
  const _TopPropertyButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.color,
    this.iconOnly = false,
    this.popupOpen = false,
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext anchor) onPressed;
  final bool active;
  final Color? color;
  final bool iconOnly;
  final bool popupOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final foreground = color ?? (active ? tokens.accent : tokens.textSecondary);
    return Builder(
      builder: (anchor) => Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: TextButton(
            onPressed: () => onPressed(anchor),
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              backgroundColor: popupOpen ? tokens.canvas : Colors.transparent,
              textStyle: TextStyle(
                  fontSize: WorkFollowMacTypography.control,
                  height: WorkFollowMacTypography.lineControl,
                  fontWeight: WorkFollowMacWeight.medium,
                  letterSpacing: WorkFollowMacTracking.none),
              minimumSize: Size(iconOnly ? WorkFollowMetrics.iconHitTarget : 0,
                  WorkFollowMetrics.iconHitTarget),
              padding: EdgeInsets.symmetric(horizontal: iconOnly ? WorkFollowSpacing.inlineGap : WorkFollowSpacing.compactInset),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon,
                    size: WorkFollowMetrics.toolbarIcon, color: foreground),
                if (!iconOnly) ...[
                  const SizedBox(width: WorkFollowSpacing.inlineGap),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RelationPicker extends StatefulWidget {
  const _RelationPicker({required this.controller, this.selected});

  final WorkspaceController controller;
  final String? selected;

  @override
  State<_RelationPicker> createState() => _RelationPickerState();
}

class _RelationPickerState extends State<_RelationPicker> {
  late final TextEditingController search;

  @override
  void initState() {
    super.initState();
    search = TextEditingController()..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    search.removeListener(_changed);
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final query = search.text.trim().toLowerCase();
    final notes = widget.controller.activeNotes
        .where((note) =>
            query.isEmpty ||
            note.title.toLowerCase().contains(query) ||
            note.folder.toLowerCase().contains(query))
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.cardInset, WorkFollowSpacing.cardInset, WorkFollowSpacing.cardInset, WorkFollowSpacing.compactGap),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const ValueKey('task-relation-search'),
          controller: search,
          autofocus: true,
          decoration: InputDecoration(
              prefixIcon: const AppIcon(WorkFollowIcons.search,
                  size: WorkFollowMetrics.toolbarIcon),
              hintText: '搜索笔记',
              isDense: true,
              filled: true,
              fillColor: tokens.canvas,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control),
                  borderSide: BorderSide.none)),
        ),
        const SizedBox(height: WorkFollowSpacing.compactGap),
        for (final note in notes)
          ListTile(
            key: ValueKey('relation-note-${note.id}'),
            dense: true,
            minTileHeight: 42,
            leading: const AppIcon(WorkFollowIcons.article,
                size: WorkFollowMetrics.navigationIcon),
            title: Text(note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: WorkFollowMacTypography.listTitle,
                    height: WorkFollowMacTypography.lineList,
                    fontWeight: WorkFollowMacWeight.medium)),
            subtitle: Text(note.folder,
                style: TextStyle(
                    fontSize: WorkFollowMacTypography.listMeta,
                    height: WorkFollowMacTypography.lineControl,
                    fontWeight: WorkFollowMacWeight.regular,
                    color: tokens.textTertiary)),
            trailing: widget.selected == note.id
                ? AppIcon(WorkFollowIcons.check,
                    size: WorkFollowMetrics.toolbarIcon, color: tokens.accent)
                : null,
            onTap: () => Navigator.of(context).pop(note.id),
          ),
        if (notes.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: WorkFollowSpacing.space4),
              child: Text('没有匹配的笔记',
                  style: TextStyle(
                      fontSize: WorkFollowMacTypography.supporting,
                      height: WorkFollowMacTypography.lineControl,
                      fontWeight: WorkFollowMacWeight.regular,
                      color: tokens.textTertiary))),
      ]),
    );
  }
}
