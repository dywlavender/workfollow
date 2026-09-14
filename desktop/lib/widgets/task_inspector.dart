import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import '../features/tasks/application/task_actions.dart';
import '../features/tasks/domain/task_schedule.dart';
import 'app_icon_button.dart';
import 'desktop_popover.dart';
import 'task_date_picker.dart';
import 'task_schedule_picker.dart';
import 'task_reminder_picker.dart';
import 'task_deadline_picker.dart';
import 'task_priority_picker.dart';
import 'task_list_picker.dart';
import 'task_tag_picker.dart';
import 'task_repeat_picker.dart';
import 'task_document_editor.dart';
import 'task_more_menu.dart';

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
  final documentKey = GlobalKey<TaskDocumentEditorState>();
  late int focusVersion;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task.title);
    focusVersion = widget.controller.inspectorTitleFocusVersion;
    widget.controller.addListener(_focusRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.selectedTaskId == widget.task.id) {
        titleFocus.requestFocus();
      }
    });
  }

  void _focusRequested() {
    if (focusVersion == widget.controller.inspectorTitleFocusVersion) return;
    focusVersion = widget.controller.inspectorTitleFocusVersion;
    titleFocus.requestFocus();
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
    final result = task.completed
        ? widget.controller.taskActions.restore(task.id)
        : widget.controller.taskActions.complete(task.id);
    _showActionFeedback(result);
  }

  Future<void> _date(BuildContext anchor, String kind) async {
    final task = widget.task;
    final value = switch (kind) {
      'reminder' =>
        await TaskReminderPicker.show(anchor, value: task.reminderAt),
      'deadline' =>
        await TaskDeadlinePicker.show(anchor, value: task.deadlineAt),
      _ => await TaskSchedulePicker.show(anchor,
          value: task.dueAt, hasTime: task.scheduledWithTime),
    };
    if (value == null || !mounted) return;
    if (kind == 'reminder') {
      _showActionFeedback(value.date == null
          ? widget.controller.taskActions.clearReminder(task.id)
          : widget.controller.taskActions.setReminder(task.id, value.date));
    } else if (kind == 'deadline') {
      _showActionFeedback(value.date == null
          ? widget.controller.taskActions.clearDeadline(task.id)
          : widget.controller.taskActions.setDeadline(task.id, value.date));
    } else {
      _showActionFeedback(value.date == null
          ? widget.controller.taskActions.clearSchedule(task.id)
          : widget.controller.taskActions.setSchedule(task.id,
              TaskScheduleDraft(dueAt: value.date, hasTime: value.hasTime)));
    }
  }

  Future<void> _list(BuildContext anchor) async {
    final selected = await TaskListPicker.show(anchor,
        controller: widget.controller, selected: widget.task.listName);
    if (selected == null || !mounted) return;
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
    final value =
        await TaskTagPicker.show(anchor, initial: widget.task.tags.join('，'));
    if (value == null || !mounted) return;
    _showActionFeedback(widget.controller.taskActions
        .setTags(widget.task.id, value.split(RegExp('[,，]'))));
  }

  Future<void> _repeat(BuildContext anchor) async {
    final result = await TaskRepeatPicker.show(anchor, task: widget.task);
    if (result == null || !mounted) return;
    _showActionFeedback(result.enabled
        ? widget.controller.taskActions.setRecurrence(widget.task.id, result)
        : widget.controller.taskActions.clearRecurrence(widget.task.id));
  }

  Future<void> _relation(BuildContext anchor) async {
    final noteId = await showDesktopPopover<String>(anchor,
        width: 330,
        maxHeight: 420,
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

  Future<void> _more(BuildContext anchor) async {
    final action = await TaskMoreMenu.show(anchor,
        hasSourceNote: widget.controller.sourceNoteFor(widget.task.id) != null);
    if (!mounted || action == null) return;
    switch (action) {
      case 'add-subtask':
        documentKey.currentState?.insertSubtasksBlock();
      case 'tags':
        await _tags(anchor);
      case 'attachment':
        await documentKey.currentState?.attachFile();
      case 'focus':
        if (widget.onOpenFocusTimer != null) {
          widget.onOpenFocusTimer!();
        } else {
          final count = widget.task.focusCount;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(count == 0 ? '还没有专注记录' : '已专注 $count 个番茄')));
        }
      case 'relation':
        await _relation(anchor);
      case 'open-source-note':
        final source = widget.controller.sourceNoteFor(widget.task.id);
        if (source != null) widget.controller.openNote(source.id);
      case 'copy':
        await Clipboard.setData(ClipboardData(
            text: '${title.text}\n${documentKey.currentState?.plainText ?? ''}'
                .trim()));
      case 'duplicate':
        _showActionFeedback(
            widget.controller.taskActions.duplicate(widget.task.id));
      case 'delete':
        _showActionFeedback(
            widget.controller.taskActions.delete(widget.task.id));
    }
  }

  void _showActionFeedback(TaskActionResult result) {
    if (!mounted || !result.success || result.message == null) return;
    final undo = result.undo;
    final canUndo = undo != null && undo.label != '撤销完成';
    final id = result.taskId;
    final moved = id != null &&
        result.destination != null &&
        result.destination != TaskDestination.current &&
        result.destination != TaskDestination.hidden;
    if (!moved && !canUndo && !result.showFeedback) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 64),
      content: Row(children: [
        Expanded(child: Text(result.message!)),
        if (canUndo)
          TextButton(
              onPressed: () => _runUndo(undo),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('撤销')),
      ]),
      action: moved
          ? SnackBarAction(
              label: '查看任务', onPressed: () => widget.controller.openTask(id))
          : null,
    ));
  }

  void _runUndo(UndoCommand undo) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final outcome = undo.execute();
    if (outcome is Future<bool>) unawaited(outcome);
  }

  Widget _header(BuildContext context, TaskItem task, WorkFollowTheme tokens) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          widget.inline ? 20 : 26, 10, widget.inline ? 20 : 26, 8),
      decoration: widget.inline
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border))),
      child: Row(children: [
        if (widget.showBack)
          IconButton(
              tooltip: '返回列表',
              onPressed: close,
              icon: const Icon(Icons.arrow_back, size: 18)),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _TopPropertyButton(
                  key: const ValueKey('task-complete'),
                  icon: task.completed
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  label: task.completed ? '标记未完成' : '完成任务',
                  active: task.completed,
                  color: task.completed ? tokens.success : null,
                  onPressed: (_) => _complete(task),
                  iconOnly: true),
              const SizedBox(width: 4),
              _TopPropertyButton(
                  key: const ValueKey('task-schedule'),
                  icon: Icons.calendar_today_outlined,
                  label: calendarDateLabel(localDateTimeFromStorage(task.dueAt),
                      hasTime: task.scheduledWithTime, empty: '安排日期'),
                  active: task.dueAt != null,
                  onPressed: (anchor) => _date(anchor, 'schedule')),
              _TopPropertyButton(
                  key: const ValueKey('task-reminder'),
                  icon: Icons.notifications_none_rounded,
                  label: calendarDateLabel(
                      localDateTimeFromStorage(task.reminderAt),
                      hasTime: true,
                      empty: '提醒'),
                  active: task.reminderAt != null,
                  onPressed: (anchor) => _date(anchor, 'reminder'),
                  iconOnly: true),
              _TopPropertyButton(
                  key: const ValueKey('task-repeat'),
                  icon: Icons.repeat_rounded,
                  label: switch (task.recurrenceType) {
                    'DAILY' => '每天',
                    'WEEKLY' => '每周',
                    'MONTHLY' => '每月',
                    _ => '重复',
                  },
                  active: task.recurrenceType != 'NONE',
                  onPressed: _repeat,
                  iconOnly: true),
              _TopPropertyButton(
                  key: const ValueKey('task-deadline'),
                  icon: Icons.event_available_outlined,
                  label: calendarDateLabel(
                      localDateTimeFromStorage(task.deadlineAt),
                      empty: '截止日期'),
                  active: task.deadlineAt != null,
                  color: task.deadlineAt == null ? null : tokens.danger,
                  onPressed: (anchor) => _date(anchor, 'deadline'),
                  iconOnly: true),
              _TopPropertyButton(
                  key: const ValueKey('task-priority'),
                  icon: Icons.flag_outlined,
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
            ]),
          ),
        ),
        if (widget.inline)
          IconButton(
              tooltip: '收起任务',
              visualDensity: VisualDensity.compact,
              onPressed: close,
              icon: Icon(Icons.close, color: tokens.textTertiary, size: 18)),
        if (!widget.inline && !widget.showBack)
          IconButton(
              tooltip: '关闭详情',
              visualDensity: VisualDensity.compact,
              onPressed: close,
              icon: Icon(Icons.close, color: tokens.textTertiary, size: 18)),
      ]),
    );
  }

  Widget _saveIndicator(WorkFollowTheme tokens) {
    final IconData icon;
    final String label;
    final Color color;
    if (widget.controller.loadError != null) {
      icon = Icons.report_outlined;
      label = widget.controller.loadError!;
      color = tokens.danger;
    } else {
      switch (widget.controller.saveStatus) {
        case SaveStatus.saving:
          icon = Icons.sync_rounded;
          label = '保存中…';
          color = tokens.textTertiary;
        case SaveStatus.failed:
          icon = Icons.error_outline;
          label = widget.controller.saveError == null
              ? '保存失败'
              : '保存失败：${widget.controller.saveError}';
          color = tokens.danger;
        case SaveStatus.saved:
          icon = Icons.check_rounded;
          final savedAt = widget.controller.lastSavedAt;
          label = savedAt == null
              ? '已保存'
              : '已保存 · ${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}';
          color = tokens.success;
      }
    }
    return Tooltip(
        message: label,
        child: Semantics(
            label: label,
            child: Icon(icon,
                key: const ValueKey('save-status-indicator'),
                size: 15,
                color: color)));
  }

  Widget _footer(BuildContext context, TaskItem task, WorkFollowTheme tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 9),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: tokens.border))),
      child: Row(children: [
        Builder(
            builder: (anchor) => TextButton.icon(
                key: const ValueKey('task-list-footer'),
                onPressed: () => _list(anchor),
                icon: Icon(Icons.inbox_outlined,
                    size: 15, color: tokens.textSecondary),
                label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(task.listName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact))),
        const Spacer(),
        _saveIndicator(tokens),
        const SizedBox(width: 7),
        AppIconButton(
            key: const ValueKey('task-format-toggle'),
            icon: Icons.text_format_rounded,
            tooltip: '显示格式工具',
            active: documentKey.currentState?.toolbarVisible ?? false,
            onPressed: () => documentKey.currentState?.toggleToolbar(),
            size: 30,
            iconSize: 17),
        Builder(
            builder: (anchor) => AppIconButton(
                key: const ValueKey('task-more-actions'),
                icon: Icons.more_horiz,
                tooltip: '更多操作',
                onPressed: () => _more(anchor),
                size: 30,
                iconSize: 18)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final tokens = WorkFollowTheme.of(context);
    final editorBody = Padding(
      padding: EdgeInsets.fromLTRB(
          widget.inline ? 20 : 26, 14, widget.inline ? 20 : 26, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            key: const ValueKey('task-title-editor'),
            controller: title,
            focusNode: titleFocus,
            minLines: 1,
            maxLines: 4,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.35,
                letterSpacing: -.3,
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
        const SizedBox(height: 9),
        TaskDocumentEditor(
          key: documentKey,
          task: task,
          controller: widget.controller,
          onOpenTags: _tags,
          onOpenRelation: _relation,
          onToolbarChanged: (_) {
            if (mounted) setState(() {});
          },
        ),
      ]),
    );
    final content = Column(
        mainAxisSize: widget.inline ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _header(context, task, tokens),
          if (widget.inline)
            editorBody
          else
            Expanded(child: SingleChildScrollView(child: editorBody)),
          _footer(context, task, tokens),
        ]);
    return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
        child: Container(
            color: widget.inline ? Colors.transparent : tokens.content,
            child: content));
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
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext anchor) onPressed;
  final bool active;
  final Color? color;
  final bool iconOnly;

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
              backgroundColor: active ? tokens.accentFaint : Colors.transparent,
              minimumSize: Size(iconOnly ? 32 : 0, 32),
              padding: EdgeInsets.symmetric(horizontal: iconOnly ? 6 : 9),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                if (!iconOnly) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
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
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const ValueKey('task-relation-search'),
          controller: search,
          autofocus: true,
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 17),
              hintText: '搜索笔记',
              isDense: true,
              filled: true,
              fillColor: tokens.canvas,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 7),
        for (final note in notes)
          ListTile(
            key: ValueKey('relation-note-${note.id}'),
            dense: true,
            minTileHeight: 42,
            leading: const Icon(Icons.article_outlined, size: 17),
            title: Text(note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
            subtitle: Text(note.folder,
                style: TextStyle(fontSize: 10.5, color: tokens.textTertiary)),
            trailing: widget.selected == note.id
                ? Icon(Icons.check_rounded, size: 16, color: tokens.accent)
                : null,
            onTap: () => Navigator.of(context).pop(note.id),
          ),
        if (notes.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('没有匹配的笔记',
                  style: TextStyle(fontSize: 12, color: tokens.textTertiary))),
      ]),
    );
  }
}
