import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';
import 'save_status_footer.dart';
import 'task_date_picker.dart';

/// Task detail surface, used both as the in-list inline editor and as the
/// standalone narrow-window detail page. The redesign organises it into
/// labelled sections: 标题与备注 → 属性 → 子任务 → 附件与关联.
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

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.task.title);
    description = TextEditingController(
        text: widget.task.description ?? widget.task.note ?? '');
    focusVersion = widget.controller.inspectorTitleFocusVersion;
    widget.controller.addListener(_focusRequested);
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

  Future<void> _date(BuildContext anchor, String kind) async {
    final task = widget.task;
    final value = await showTaskDatePicker(anchor,
        value: kind == 'reminder'
            ? task.reminderAt
            : kind == 'deadline'
                ? task.deadlineAt
                : task.dueAt,
        title: kind == 'reminder'
            ? '提醒我'
            : kind == 'deadline'
                ? '截止日期'
                : '安排日期',
        hasTime: kind == 'schedule' ? task.scheduledWithTime : null,
        reminder: kind == 'reminder',
        allowTime: kind != 'deadline');
    if (value == null || !mounted) return;
    if (kind == 'reminder') {
      widget.controller.updateTaskReminder(task.id, value.date);
    } else if (kind == 'deadline') {
      widget.controller.updateTaskDeadline(task.id, value.date);
    } else {
      widget.controller
          .updateTaskDue(task.id, value.date, hasTime: value.hasTime);
      if (!widget.controller.visibleTasks.any((item) => item.id == task.id)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(value.date == null
              ? '已清除安排日期'
              : '已安排到${calendarDateLabel(value.date, hasTime: value.hasTime)}'),
          action: SnackBarAction(
              label: '查看任务',
              onPressed: () => widget.controller.openTask(task.id)),
        ));
      }
    }
  }

  Future<void> _list(BuildContext anchor) async {
    final selected = await showDesktopMenu<String>(anchor,
        selected: widget.task.listName,
        entries: [
          for (final list in widget.controller.lists)
            DesktopMenuEntry(list.name, list.name, icon: Icons.list_rounded)
        ]);
    if (selected != null)
      widget.controller.moveTaskToList(widget.task.id, selected);
  }

  Future<void> _priority(BuildContext anchor) async {
    final value = await showDesktopMenu<TaskPriority>(anchor,
        selected: widget.task.priority,
        entries: [
          for (final priority in TaskPriority.values)
            DesktopMenuEntry(priority,
                priority == TaskPriority.none ? '无优先级' : priority.label,
                icon: Icons.flag_outlined)
        ]);
    if (value != null)
      widget.controller.updateTaskPriority(widget.task.id, value);
  }

  Future<void> _tags(BuildContext anchor) async {
    final value = await showDesktopPopover<String>(anchor,
        width: 300,
        maxHeight: 220,
        builder: (context) => _TagsEditor(initial: widget.task.tags.join('，')));
    if (value != null)
      widget.controller
          .updateTaskTags(widget.task.id, value.split(RegExp('[,，]')));
  }

  Future<void> _repeat(BuildContext anchor) async {
    final result = await showDesktopPopover<(String, Map<String, dynamic>?)>(
        anchor,
        width: 300,
        maxHeight: 290,
        builder: (_) => _RepeatEditor(task: widget.task));
    if (result != null)
      widget.controller
          .updateTaskRecurrence(widget.task.id, result.$1, config: result.$2);
  }

  Future<void> _more(BuildContext anchor) async {
    final action = await showDesktopMenu<String>(anchor, entries: const [
      DesktopMenuEntry('copy', '复制任务正文', icon: Icons.copy_outlined),
      DesktopMenuEntry('duplicate', '创建副本',
          icon: Icons.control_point_duplicate_outlined),
      DesktopMenuEntry('delete', '移到废纸篓',
          icon: Icons.delete_outline, destructive: true),
    ]);
    if (!mounted) return;
    if (action == 'copy')
      await Clipboard.setData(
          ClipboardData(text: '${title.text}\n${description.text}'.trim()));
    if (action == 'duplicate') widget.controller.duplicateTask(widget.task.id);
    if (action == 'delete') widget.controller.removeTask(widget.task.id);
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
                  onPressed: (_) => widget.controller.toggleTask(task.id),
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
        Builder(
            builder: (anchor) => IconButton(
                tooltip: '更多操作',
                visualDensity: VisualDensity.compact,
                onPressed: () => _more(anchor),
                icon: Icon(Icons.more_horiz,
                    color: tokens.textTertiary, size: 20))),
        if (!widget.showBack)
          IconButton(
              tooltip: '收起任务',
              visualDensity: VisualDensity.compact,
              onPressed: close,
              icon: Icon(Icons.close, color: tokens.textTertiary, size: 18)),
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
                    widget.controller.updateTaskTitle(task.id, value)),
            const SizedBox(height: 12),
            TextField(
                key: const ValueKey('task-description-editor'),
                controller: description,
                focusNode: descriptionFocus,
                minLines: 2,
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
                    widget.controller.updateTaskDescription(task.id, value)),
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, children: [
              PropertyButton(
                  icon: Icons.list_rounded,
                  label: task.listName,
                  active: true,
                  onPressed: _list),
              PropertyButton(
                  icon: Icons.flag_outlined,
                  label: calendarDateLabel(
                      localDateTimeFromStorage(task.deadlineAt),
                      empty: '截止日期'),
                  active: task.deadlineAt != null,
                  tooltip: '截止日期：最晚什么时候完成',
                  onPressed: (anchor) => _date(anchor, 'deadline')),
              PropertyButton(
                  icon: Icons.tag_rounded,
                  label: task.tags.isEmpty ? '标签' : task.tags.join(' · '),
                  active: task.tags.isNotEmpty,
                  onPressed: _tags),
            ]),
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
                    style: TextStyle(fontSize: 11, color: tokens.textTertiary)),
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
                        side:
                            BorderSide(color: tokens.borderStrong, width: 1.4),
                        onChanged: (_) =>
                            widget.controller.toggleSubtask(task.id, item.id))),
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
                            contentPadding: EdgeInsets.symmetric(vertical: 8)),
                        onChanged: (value) => widget.controller
                            .renameSubtask(task.id, item.id, value))),
                IconButton(
                    tooltip: '删除子任务',
                    visualDensity: VisualDensity.compact,
                    icon:
                        Icon(Icons.close, size: 14, color: tokens.textTertiary),
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
                          contentPadding: EdgeInsets.symmetric(vertical: 10)))),
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
                  style: TextStyle(fontSize: 11.5, color: tokens.textTertiary)),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final file in task.attachments)
                    InputChip(
                        label: Text(file, style: const TextStyle(fontSize: 12)),
                        avatar: const Icon(Icons.insert_drive_file_outlined,
                            size: 15),
                        onPressed: () =>
                            widget.controller.revealAttachment(task.id, file),
                        onDeleted: () =>
                            widget.controller.removeAttachment(task.id, file)),
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
          SaveStatusFooter(controller: widget.controller),
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

class _TagsEditor extends StatefulWidget {
  const _TagsEditor({required this.initial});
  final String initial;
  @override
  State<_TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends State<_TagsEditor> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
                controller: text,
                autofocus: true,
                onSubmitted: (value) => Navigator.of(context).pop(value),
                decoration: const InputDecoration(
                    hintText: '用逗号分隔，例如 工作，重要',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 12),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(text.text),
                    child: const Text('完成'))),
          ]));
}

class _RepeatEditor extends StatefulWidget {
  const _RepeatEditor({required this.task});
  final TaskItem task;
  @override
  State<_RepeatEditor> createState() => _RepeatEditorState();
}

class _RepeatEditorState extends State<_RepeatEditor> {
  late String type = widget.task.recurrenceType;
  late int weekday = (widget.task.recurrenceConfig?['weekday'] as num?)
          ?.toInt() ??
      (localDateTimeFromStorage(widget.task.dueAt) ?? DateTime.now()).weekday;
  late int day =
      (widget.task.recurrenceConfig?['dayOfMonth'] as num?)?.toInt() ??
          (localDateTimeFromStorage(widget.task.dueAt) ?? DateTime.now()).day;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('重复任务', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                    labelText: '频率',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  for (final entry in {
                    'NONE': '不重复',
                    'DAILY': '每天',
                    'WEEKLY': '每周',
                    'MONTHLY': '每月'
                  }.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value))
                ],
                onChanged: (value) => setState(() => type = value!)),
            if (type == 'WEEKLY' || type == 'MONTHLY') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                  key: ValueKey(type),
                  initialValue: type == 'WEEKLY' ? weekday : day,
                  decoration: InputDecoration(
                      labelText: type == 'WEEKLY' ? '星期' : '每月日期',
                      border: const OutlineInputBorder(),
                      isDense: true),
                  items: [
                    for (var i = 1; i <= (type == 'WEEKLY' ? 7 : 31); i++)
                      DropdownMenuItem(
                          value: i,
                          child: Text(type == 'WEEKLY'
                              ? '星期${'一二三四五六日'[i - 1]}'
                              : '$i 日'))
                  ],
                  onChanged: (value) => setState(() {
                        if (type == 'WEEKLY') {
                          weekday = value!;
                        } else {
                          day = value!;
                        }
                      })),
            ],
            const SizedBox(height: 12),
            const Text('完成本次任务后，会自动生成下一次。', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.of(context).pop((
                          type,
                          type == 'WEEKLY'
                              ? <String, dynamic>{'weekday': weekday}
                              : type == 'MONTHLY'
                                  ? <String, dynamic>{'dayOfMonth': day}
                                  : null
                        )),
                    child: const Text('确定'))),
          ]));
}
