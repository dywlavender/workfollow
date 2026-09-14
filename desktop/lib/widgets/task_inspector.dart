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

/// Task detail surface, used both as the in-list inline editor and as the
/// standalone narrow-window detail page. The redesign organises it into
/// a clean title/body surface by default; secondary properties remain
/// available through progressive disclosure.
class TaskInspector extends StatefulWidget {
  const TaskInspector(
      {super.key,
      required this.task,
      required this.controller,
      this.showBack = false,
      this.onBack,
      this.inline = false});
  final TaskItem task;
  final WorkspaceController controller;
  final bool showBack;
  final VoidCallback? onBack;
  final bool inline;

  @override
  State<TaskInspector> createState() => _TaskInspectorState();
}

class _TaskInspectorState extends State<TaskInspector> {
  late final TextEditingController title;
  late final TextEditingController description;
  final subtask = TextEditingController();
  final titleFocus = FocusNode();
  final descriptionFocus = FocusNode();
  late int focusVersion;
  bool showAdvanced = false;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task.title);
    description = TextEditingController(
        text: widget.task.description ?? widget.task.note ?? '');
    focusVersion = widget.controller.inspectorTitleFocusVersion;
    widget.controller.addListener(_focusRequested);
    // TickTick lets a selected row continue straight into title editing. A
    // post-frame request keeps the inspector mounted before taking focus and
    // still leaves the full detail surface visible for click-to-inspect.
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
    if (!titleFocus.hasFocus && title.text != widget.task.title)
      title.text = widget.task.title;
    final body = widget.task.description ?? widget.task.note ?? '';
    if (!descriptionFocus.hasFocus && description.text != body)
      description.text = body;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_focusRequested);
    title.dispose();
    description.dispose();
    subtask.dispose();
    titleFocus.dispose();
    descriptionFocus.dispose();
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
      'reminder' => await TaskReminderPicker.show(anchor, value: task.reminderAt),
      'deadline' => await TaskDeadlinePicker.show(anchor, value: task.deadlineAt),
      _ => await TaskSchedulePicker.show(anchor,
          value: task.dueAt, hasTime: task.scheduledWithTime),
    };
    if (value == null || !mounted) return;
    if (kind == 'reminder') {
      _showActionFeedback(value.date == null
          ? widget.controller.taskActions.clearReminder(task.id)
          : widget.controller.taskActions.setReminder(task.id, value.date));
    } else if (kind == 'deadline') {
      _showActionFeedback(
          widget.controller.taskActions.setDeadline(task.id, value.date));
    } else {
      _showActionFeedback(widget.controller.taskActions.setSchedule(
          task.id,
          TaskScheduleDraft(dueAt: value.date, hasTime: value.hasTime)));
    }
  }

  Future<void> _list(BuildContext anchor) async {
    final selected = await TaskListPicker.show(anchor,
        controller: widget.controller, selected: widget.task.listName);
    if (selected != null) {
      _showActionFeedback(
          widget.controller.taskActions.moveToList(widget.task.id, selected));
    }
  }

  Future<void> _priority(BuildContext anchor) async {
    final value = await TaskPriorityPicker.show(anchor,
        selected: widget.task.priority);
    if (value != null) {
      _showActionFeedback(
          widget.controller.taskActions.setPriority(widget.task.id, value));
    }
  }

  Future<void> _tags(BuildContext anchor) async {
    final value = await TaskTagPicker.show(anchor,
        initial: widget.task.tags.join('，'));
    if (value != null) {
      _showActionFeedback(widget.controller.taskActions
          .setTags(widget.task.id, value.split(RegExp('[,，]'))));
    }
  }

  Future<void> _repeat(BuildContext anchor) async {
    final result = await TaskRepeatPicker.show(anchor, task: widget.task);
    if (result != null) {
      _showActionFeedback(widget.controller.taskActions.setRecurrence(
          widget.task.id, result));
    }
  }

  Future<void> _more(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(anchor, entries: [
      DesktopMenuEntry('toggle-details', showAdvanced ? '收起更多属性' : '显示更多属性',
          icon: showAdvanced ? Icons.expand_less : Icons.tune_outlined),
      const DesktopMenuEntry('copy', '复制任务正文', icon: Icons.copy_outlined),
      const DesktopMenuEntry('duplicate', '创建副本',
          icon: Icons.control_point_duplicate_outlined),
      const DesktopMenuEntry('delete', '移到废纸篓',
          icon: Icons.delete_outline, destructive: true),
    ]);
    if (!mounted) return;
    if (action == 'toggle-details') {
      setState(() => showAdvanced = !showAdvanced);
      return;
    }
    if (action == 'copy')
      await Clipboard.setData(
          ClipboardData(text: '${title.text}\n${description.text}'.trim()));
    if (action == 'duplicate') {
      _showActionFeedback(
          widget.controller.taskActions.duplicate(widget.task.id));
    }
    if (action == 'delete') {
      _showActionFeedback(widget.controller.taskActions.delete(widget.task.id));
    }
  }

  void _showActionFeedback(TaskActionResult result) {
    if (!mounted || !result.success || result.message == null) return;
    if (result.destination == TaskDestination.current) return;
    final id = result.taskId;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message!),
      action: id == null
          ? null
          : SnackBarAction(
              label: '查看任务', onPressed: () => widget.controller.openTask(id)),
    ));
  }

  void _addSubtask() {
    if (widget.controller.addSubtask(widget.task.id, subtask.text))
      subtask.clear();
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
          Builder(
              builder: (anchor) => IconButton(
                  tooltip: '收起任务',
                  visualDensity: VisualDensity.compact,
                  onPressed: close,
                  icon:
                      Icon(Icons.close, color: tokens.textTertiary, size: 18))),
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
        const SizedBox(width: 8),
        AppIconButton(
            key: const ValueKey('task-advanced-toggle'),
            icon:
                showAdvanced ? Icons.expand_less_rounded : Icons.tune_outlined,
            tooltip: showAdvanced ? '收起更多属性' : '显示更多属性',
            active: showAdvanced,
            onPressed: () => setState(() => showAdvanced = !showAdvanced),
            size: 30,
            iconSize: 16),
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
    final source = widget.controller.sourceNoteFor(task.id);
    final subtaskProgress = task.subtaskTotal == 0
        ? null
        : task.subtaskCompleted / task.subtaskTotal;
    final editorBody = Padding(
      padding: EdgeInsets.fromLTRB(
          widget.inline ? 20 : 26, 14, widget.inline ? 20 : 26, 22),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                key: const ValueKey('task-title-editor'),
                controller: title,
                focusNode: titleFocus,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    letterSpacing: -.3,
                    color: task.completed
                        ? tokens.textTertiary
                        : tokens.textPrimary,
                    decoration:
                        task.completed ? TextDecoration.lineThrough : null),
                decoration: const InputDecoration(
                    hintText: '任务标题',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
                onChanged: (value) =>
                    widget.controller.taskActions.setTitle(task.id, value)),
            const SizedBox(height: 12),
            TextField(
                key: const ValueKey('task-description-editor'),
                controller: description,
                focusNode: descriptionFocus,
                minLines: 1,
                maxLines: 8,
                style: TextStyle(
                    fontSize: 13.5, height: 1.65, color: tokens.textSecondary),
                decoration: InputDecoration(
                    hintText: '添加备注…',
                    hintStyle: TextStyle(color: tokens.textTertiary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
                onChanged: (value) =>
                    widget.controller.taskActions
                        .setDescription(task.id, value)),
            if (showAdvanced) ...[
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: [
                PropertyButton(
                    key: const ValueKey('task-deadline'),
                    icon: Icons.flag_outlined,
                    label: calendarDateLabel(
                        localDateTimeFromStorage(task.deadlineAt),
                        empty: '截止日期'),
                    active: task.deadlineAt != null,
                    tooltip: '截止日期：最晚什么时候完成',
                    onPressed: (anchor) => _date(anchor, 'deadline')),
                PropertyButton(
                    key: const ValueKey('task-tags'),
                    icon: Icons.tag_rounded,
                    label: task.tags.isEmpty ? '标签' : task.tags.join(' · '),
                    active: task.tags.isNotEmpty,
                    onPressed: _tags),
              ]),
              if (task.focusCount > 0) ...[
                const SizedBox(height: 12),
                Row(key: const ValueKey('task-focus'), children: [
                  Icon(Icons.timer_outlined,
                      size: 16, color: tokens.textTertiary),
                  const SizedBox(width: 7),
                  Text('已专注 ${task.focusCount} 个番茄',
                      style:
                          TextStyle(color: tokens.textTertiary, fontSize: 11)),
                ]),
              ],
              const SizedBox(height: 22),
              Row(children: [
                Text('子任务',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: tokens.textSecondary)),
                if (task.subtaskTotal > 0) ...[
                  const SizedBox(width: 10),
                  Expanded(
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                              value: subtaskProgress,
                              minHeight: 3.5,
                              backgroundColor: tokens.border,
                              color: subtaskProgress == 1
                                  ? tokens.success
                                  : tokens.accent))),
                  const SizedBox(width: 10),
                  Text('${task.subtaskCompleted}/${task.subtaskTotal}',
                      style:
                          TextStyle(fontSize: 11, color: tokens.textTertiary)),
                ] else
                  const Spacer(),
              ]),
              const SizedBox(height: 4),
              for (final item in task.subtasks)
                Row(key: ValueKey(item.id), children: [
                  SizedBox(
                      width: 30,
                      height: 36,
                      child: Checkbox(
                          value: item.completed,
                          shape: const CircleBorder(),
                          side: BorderSide(
                              color: tokens.borderStrong, width: 1.4),
                          onChanged: (_) => widget.controller
                              .toggleSubtask(task.id, item.id))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextFormField(
                          initialValue: item.title,
                          style: TextStyle(
                              fontSize: 13,
                              color: item.completed
                                  ? tokens.textTertiary
                                  : tokens.textPrimary,
                              decoration: item.completed
                                  ? TextDecoration.lineThrough
                                  : null),
                          decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 8)),
                          onChanged: (value) => widget.controller
                              .renameSubtask(task.id, item.id, value))),
                  IconButton(
                      tooltip: '删除子任务',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close,
                          size: 14, color: tokens.textTertiary),
                      onPressed: () =>
                          widget.controller.removeSubtask(task.id, item.id)),
                ]),
              Row(children: [
                const SizedBox(width: 7),
                Icon(Icons.add, size: 17, color: tokens.textTertiary),
                const SizedBox(width: 14),
                Expanded(
                    child: TextField(
                        controller: subtask,
                        key: const ValueKey('new-subtask'),
                        style: const TextStyle(fontSize: 13),
                        onSubmitted: (_) => _addSubtask(),
                        decoration: const InputDecoration(
                            hintText: '添加子任务，按 Return 确认',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 10)))),
              ]),
              const SizedBox(height: 16),
              Text('附件与关联',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary)),
              const SizedBox(height: 8),
              if (task.attachments.isEmpty && source == null)
                Text('还没有附件。从笔记生成的任务会在这里关联原文。',
                    style:
                        TextStyle(fontSize: 11.5, color: tokens.textTertiary)),
              Wrap(
                  key: const ValueKey('task-attachments'),
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final file in task.attachments)
                      InputChip(
                          label:
                              Text(file, style: const TextStyle(fontSize: 12)),
                          avatar: const Icon(Icons.insert_drive_file_outlined,
                              size: 15),
                          onPressed: () =>
                              widget.controller.revealAttachment(task.id, file),
                          onDeleted: () => widget.controller
                              .removeAttachment(task.id, file)),
                    TextButton.icon(
                        onPressed: () =>
                            widget.controller.attachFileToTask(task.id),
                        icon: const Icon(Icons.attach_file, size: 16),
                        label:
                            const Text('添加附件', style: TextStyle(fontSize: 12))),
                  ]),
              if (source != null) ...[
                const SizedBox(height: 8),
                _SourceNoteCard(
                    title: source.title,
                    folder: source.folder,
                    onTap: () => widget.controller.openNote(source.id)),
              ],
            ],
          ]),
    );
    final header = _header(context, task, tokens);
    final content = Column(
        mainAxisSize: widget.inline ? MainAxisSize.min : MainAxisSize.max,
        children: [
          header,
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

/// Compact property control used by the inspector's top strip. Most
/// properties are icon-only to keep the strip usable in a 340px pane; the
/// tooltip and semantic label still expose the full value to keyboard and
/// assistive-technology users.
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

/// Card that links a generated task back to its source note.
class _SourceNoteCard extends StatelessWidget {
  const _SourceNoteCard(
      {required this.title, required this.folder, required this.onTap});

  final String title;
  final String folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Material(
        color: tokens.accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  Icon(Icons.article_outlined, size: 17, color: tokens.accent),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary)),
                        Text('来自笔记 · $folder',
                            style: TextStyle(
                                fontSize: 10.5, color: tokens.textTertiary)),
                      ])),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: tokens.textTertiary),
                ]))));
  }
}
