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
import 'task_children_panel.dart';
import 'task_completion_box.dart';
import 'task_date_picker.dart';
import 'task_schedule_panel.dart';
import 'task_deadline_picker.dart';
import 'task_priority_picker.dart';
import 'task_list_picker.dart';
import 'task_tag_picker.dart';
import 'task_document_editor.dart';
import '../features/editor/document_editor_viewport.dart';
import '../features/editor/presentation/document_title_editor.dart';
import '../features/editor/presentation/document_editor_shell.dart';
import '../features/editor/presentation/document_editor_footer.dart';
import '../features/editor/presentation/document_save_status.dart';
import '../features/editor/presentation/document_formatting_toggle.dart';
import 'task_more_menu.dart';
import 'task_menu_actions.dart';

/// Controls the layout container used by [TaskInspector]. The editing
/// capabilities are shared; only the surrounding presentation changes.
enum TaskInspectorPresentation {
  /// The persistent detail pane used by the wide Today view.
  pane,

  /// The compact editor embedded in a task list row.
  inline,

  /// The floating editor opened from a Matrix task row.
  popup,
}

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
    this.presentation = TaskInspectorPresentation.pane,
  });

  final TaskItem task;
  final WorkspaceController controller;
  final bool showBack;
  final VoidCallback? onBack;
  final TaskInspectorPresentation presentation;

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

  bool get _isInline => widget.presentation == TaskInspectorPresentation.inline;

  bool get _isPopup => widget.presentation == TaskInspectorPresentation.popup;

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
      if (mounted) _addChildTask();
    });
  }

  void _addChildTask() {
    // One nesting level for now: a child never spawns grandchildren, no
    // matter which entry (More menu, slash palette, context menu) fires.
    if (widget.task.isChildTask) return;
    widget.controller.createChildTask(widget.task.id);
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
    if (_isPopup) {
      close();
      return;
    }
    if (editingScope.hasFocus) {
      inspectorFocus.requestFocus();
      return;
    }
    if (_isInline || widget.showBack) close();
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
        width: TaskInspectorMetrics.overlayWidth,
        maxHeight: TaskInspectorMetrics.overlayMaxHeight,
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
        _addChildTask();
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
      case 'relation':
        await _relation(anchor);
      default:
        final result = await runTaskMenuAction(
            context, widget.controller, widget.task, action);
        if (result != null) _showActionFeedback(result);
        // A deleted child's clearest landing spot is its parent: the tree
        // row is gone, so falling back to a blank list would lose context.
        if (action == 'delete' &&
            widget.task.isChildTask &&
            widget.task.parentTaskId != null) {
          widget.controller.openTask(widget.task.parentTaskId!);
        }
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
      constraints:
          const BoxConstraints(minHeight: TaskInspectorMetrics.headerMinHeight),
      padding: const EdgeInsets.symmetric(
          horizontal: WorkFollowSpacing.space5,
          vertical: WorkFollowSpacing.cardInset),
      decoration: _isInline
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
            // The completion mark is drawn rather than taken from the icon set,
            // so this control is the same box a task row draws and the same one
            // a calendar bar carries — one silhouette wherever a task appears.
            // An abandoned task is not merely an unfinished one and keeps its
            // own glyph instead of borrowing the box.
            icon: task.isAbandoned ? WorkFollowIcons.abandon : null,
            leading: task.isAbandoned
                ? null
                : TaskCompletionBox(
                    // The product's box side, not the toolbar's icon size:
                    // the two happened to be the same number, which is how a
                    // change to one would have moved the other.
                    size: WorkFollowMetrics.completionBoxSize,
                    completed: task.completed,
                    // The same edge the task carries in the list. Priority
                    // lives on the box there, so it lives on the box here:
                    // one task cannot be a red box in the list and a grey one
                    // in its own editor. The done fill is the shared completion
                    // role for the same reason: the editor used to fill it with
                    // its own green, which made the same task two different
                    // boxes on the two sides of the window.
                    openColor: taskPriorityColor(task.priority, tokens)),
            label: task.isAbandoned
                ? '恢复任务'
                : task.completed
                    ? '标记未完成'
                    : '完成任务',
            active: task.completed,
            color: task.completed ? tokens.success : null,
            onPressed: (_) => _complete(task),
            iconOnly: true,
            // The slot carries a box the product draws, whether it shows the
            // box or the abandoned task's own glyph, so the slot is what drops
            // the pointer halo rather than the branch.
            carriesDrawnMark: true),
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
        if (_isInline)
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
        width: TaskInspectorMetrics.headerDividerWidth,
        height: TaskInspectorMetrics.headerDividerHeight,
        margin: const EdgeInsets.symmetric(
            horizontal: WorkFollowSpacing.compactGap),
        color: tokens.border,
      );

  Widget _footer(BuildContext context, TaskItem task, WorkFollowTheme tokens) {
    return DocumentEditorFooter(
      key: const ValueKey('task-inspector-footer'),
      showTopBorder: true,
      minHeight: TaskInspectorMetrics.footerMinHeight,
      padding: const EdgeInsets.fromLTRB(
          WorkFollowSpacing.space5,
          WorkFollowSpacing.space2,
          WorkFollowSpacing.space5,
          WorkFollowSpacing.compactInset),
      leading: task.isChildTask
          // A child moves with its parent (S7): the list entry is hidden
          // rather than disabled so the footer keeps its rhythm.
          ? null
          : Builder(
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
                      constraints: const BoxConstraints(
                          maxWidth: TaskInspectorMetrics.listLabelMaxWidth),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: WorkFollowSpacing.inlineGap),
                      minimumSize:
                          const Size(0, WorkFollowMetrics.compactButtonHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact))),
      status: DocumentSaveStatus(controller: widget.controller),
      actions: [
        DocumentFormattingToggle(
          active: documentKey.currentState?.toolbarVisible ?? false,
          onPressed: (anchor) =>
              unawaited(documentKey.currentState?.toggleToolbar(anchor)),
        ),
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
      ],
    );
  }

  Widget _editorBody(TaskItem task, {double minHeight = 0}) {
    final horizontalPadding = _isInline
        ? WorkFollowSpacing.inspectorInlineHorizontalPadding
        : WorkFollowSpacing.inspectorContentHorizontalPadding;
    final topPadding = _isInline
        ? WorkFollowSpacing.inspectorInlineTopPadding
        : WorkFollowSpacing.inspectorContentTopPadding;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, topPadding,
          horizontalPadding, WorkFollowSpacing.inspectorContentBottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.controller.parentOf(task.id) case final parent?)
            Padding(
                padding:
                    const EdgeInsets.only(bottom: WorkFollowSpacing.space3),
                child: TaskParentBreadcrumb(
                    parent: parent,
                    onOpen: () => widget.controller.openTask(parent.id))),
          DocumentEditorViewport(
            minHeight: (minHeight -
                    topPadding -
                    WorkFollowSpacing.inspectorContentBottomPadding)
                .clamp(0, double.infinity),
            title: DocumentTitleEditor(
              fieldKey: const ValueKey('task-title-editor'),
              controller: title,
              focusNode: titleFocus,
              placeholder: task.isChildTask ? '准备做什么？' : '任务标题',
              fontSize: WorkFollowMacTypography.detailTitle,
              muted: task.completed,
              strikethrough: task.completed,
              onChanged: (value) =>
                  widget.controller.taskActions.setTitle(task.id, value),
            ),
            document: TaskDocumentEditor(
              key: documentKey,
              task: task,
              controller: widget.controller,
              onAddChildTask: _addChildTask,
              onOpenTags: _tags,
              onOpenRelation: _relation,
              onOpenDeadline: (anchor) => _date(anchor, 'deadline'),
              onEscape: _escape,
              onToolbarChanged: (_) {
                if (mounted) setState(() {});
              },
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final tokens = WorkFollowTheme.of(context);
    final shell = DocumentEditorShell(
      backgroundColor: _isInline ? Colors.transparent : tokens.content,
      mainAxisSize: _isInline ? MainAxisSize.min : MainAxisSize.max,
      header: _header(context, task, tokens),
      body: _isInline
          ? FocusScope(node: editingScope, child: _editorBody(task))
          : Expanded(
              child: FocusScope(
                node: editingScope,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const ValueKey('task-editor-scroll'),
                    child: _editorBody(task, minHeight: constraints.maxHeight),
                  ),
                ),
              ),
            ),
      footer: _footer(context, task, tokens),
    );
    return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
        child: Focus(
          focusNode: inspectorFocus,
          child: shell,
        ));
  }
}

/// Compact control strip for the inspector's top property row.
class _TopPropertyButton extends StatelessWidget {
  const _TopPropertyButton({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.color,
    this.iconOnly = false,
    this.popupOpen = false,
    this.carriesDrawnMark = false,
  });

  /// The glyph at the button's head. Left unset when [leading] draws it.
  final IconData? icon;

  /// A drawn head instead of a glyph, for the one control whose mark is a shape
  /// the rest of the product shares rather than an icon of its own.
  final Widget? leading;

  final String label;
  final void Function(BuildContext anchor) onPressed;
  final bool active;
  final Color? color;
  final bool iconOnly;
  final bool popupOpen;

  /// True for the one control whose mark is a box the product draws itself.
  ///
  /// Material answers a pointer with a faded halo the size of the whole button.
  /// Behind a glyph that reads as a button lighting up; behind a drawn box it
  /// reads as a second, wrong silhouette — the box appears to sit on a plate,
  /// and the plate eases in and out while every other fill in the product
  /// switches on the frame. The box already states its own state through its
  /// fill, so this control answers the pointer with nothing.
  final bool carriesDrawnMark;

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
              overlayColor: carriesDrawnMark ? Colors.transparent : null,
              textStyle: TextStyle(
                  fontSize: WorkFollowMacTypography.control,
                  height: WorkFollowMacTypography.lineControl,
                  fontWeight: WorkFollowMacWeight.medium,
                  letterSpacing: WorkFollowMacTracking.none),
              minimumSize: Size(iconOnly ? WorkFollowMetrics.iconHitTarget : 0,
                  WorkFollowMetrics.iconHitTarget),
              padding: EdgeInsets.symmetric(
                  horizontal: iconOnly
                      ? WorkFollowSpacing.inlineGap
                      : WorkFollowSpacing.compactInset),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WorkFollowRadii.control)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading ??
                    AppIcon(icon!,
                        size: WorkFollowMetrics.toolbarIcon, color: foreground),
                if (!iconOnly) ...[
                  const SizedBox(width: WorkFollowSpacing.inlineGap),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: TaskInspectorMetrics.propertyLabelMaxWidth),
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
      padding: const EdgeInsets.fromLTRB(
          WorkFollowSpacing.cardInset,
          WorkFollowSpacing.cardInset,
          WorkFollowSpacing.cardInset,
          WorkFollowSpacing.compactGap),
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
              padding: const EdgeInsets.symmetric(
                  vertical: WorkFollowSpacing.space4),
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
