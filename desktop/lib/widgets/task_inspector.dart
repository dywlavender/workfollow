import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'save_status_footer.dart';

class TaskInspector extends StatefulWidget {
  const TaskInspector({
    super.key,
    required this.task,
    required this.controller,
    this.showBack = false,
    this.onBack,
  });

  final TaskItem task;
  final WorkspaceController controller;

  /// Narrow-window layout: the inspector fills the pane alone and offers a
  /// back path to the list.
  final bool showBack;
  final VoidCallback? onBack;

  @override
  State<TaskInspector> createState() => _TaskInspectorState();
}

class _TaskInspectorState extends State<TaskInspector> {
  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  late final FocusNode titleFocusNode;
  late final FocusNode descriptionFocusNode;
  late int _seenTitleFocusVersion;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.task.title);
    descriptionController =
        TextEditingController(text: _descriptionFor(widget.task));
    titleFocusNode = FocusNode();
    descriptionFocusNode = FocusNode();
    _seenTitleFocusVersion = widget.controller.inspectorTitleFocusVersion;
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant TaskInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(titleController, widget.task.title, titleFocusNode);
    _syncController(descriptionController, _descriptionFor(widget.task),
        descriptionFocusNode);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    titleFocusNode.dispose();
    descriptionFocusNode.dispose();
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    final version = widget.controller.inspectorTitleFocusVersion;
    if (!mounted || version == _seenTitleFocusVersion) return;
    _seenTitleFocusVersion = version;
    titleFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final task = widget.task;
    final updatedLabel = noteUpdatedLabelFor(task.updatedAt);
    return Container(
      color: tokens.inspector,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 16, 13),
            child: Row(
              children: [
                if (widget.showBack) ...[
                  AppIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: '返回列表',
                      size: 28,
                      iconSize: 15,
                      onPressed: widget.onBack),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.circle,
                          size: 7, color: _listColor(task.listName, tokens)),
                      const SizedBox(width: 7),
                      Text(task.listName,
                          style: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Icon(Icons.chevron_right_rounded,
                              size: 14, color: tokens.textTertiary)),
                      Text(_bucketLabel(task.bucket),
                          style: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                AppIconButton(
                    icon: Icons.copy_all_outlined,
                    tooltip: '复制任务',
                    size: 28,
                    iconSize: 16,
                    onPressed: () => _copyTask(context, task)),
                AppIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: '更多操作',
                    size: 28,
                    iconSize: 17,
                    onPressed: () => _showMoreMenu(context, task)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 7, 22, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('task-title-editor'),
                    controller: titleController,
                    focusNode: titleFocusNode,
                    onChanged: (value) =>
                        widget.controller.updateTaskTitle(task.id, value),
                    onSubmitted: widget.controller.updateSelectedTitle,
                    cursorColor: tokens.accent,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: -.45),
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero),
                  ),
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      Expanded(
                        child: _InspectorPrimaryAction(
                          label: task.completed ? '标记未完成' : '标记完成',
                          icon: task.completed
                              ? Icons.undo_rounded
                              : Icons.check_rounded,
                          completed: task.completed,
                          onPressed: () =>
                              widget.controller.toggleTask(task.id),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppIconButton(
                          icon: Icons.calendar_today_outlined,
                          tooltip: '安排日期',
                          size: 36,
                          iconSize: 17,
                          onPressed: () => _pickDueDate(context, task)),
                    ],
                  ),
                  const SizedBox(height: 25),
                  _InspectorSection(
                    label: '安排',
                    child: Column(
                      children: [
                        _InspectorProperty(
                            icon: Icons.calendar_today_outlined,
                            label: '日期',
                            value: task.timeLabel ?? '未安排',
                            onTap: () => _pickDueDate(context, task)),
                        _InspectorProperty(
                            icon: Icons.notifications_none_rounded,
                            label: '提醒',
                            value: _reminderLabel(task),
                            onTap: () => _pickReminder(context, task)),
                        _InspectorProperty(
                            icon: Icons.repeat_rounded,
                            label: '重复',
                            value: _recurrenceLabel(task),
                            onTap: () => _chooseRecurrence(context, task)),
                        _InspectorProperty(
                            icon: Icons.flag_outlined,
                            label: '优先级',
                            value: task.priority.label,
                            onTap: () => _choosePriority(context, task)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 23),
                  _InspectorSection(
                    label: '描述',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(13, 5, 13, 5),
                      decoration: BoxDecoration(
                          color: tokens.content,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: tokens.border)),
                      child: TextField(
                        key: const ValueKey('task-description-editor'),
                        controller: descriptionController,
                        focusNode: descriptionFocusNode,
                        onChanged: (value) => widget.controller
                            .updateTaskDescription(task.id, value),
                        cursorColor: tokens.accent,
                        minLines: 3,
                        maxLines: 8,
                        style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 13,
                            height: 1.55),
                        decoration: InputDecoration(
                          hintText: '添加一段描述，让未来的自己更容易接着做。',
                          hintStyle: TextStyle(
                              color: tokens.textTertiary,
                              fontSize: 13,
                              height: 1.55),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 7),
                        ),
                      ),
                    ),
                  ),
                  if (task.subtaskTotal > 0) ...[
                    const SizedBox(height: 23),
                    _InspectorSection(
                      label:
                          '子任务  ${task.subtaskCompleted}/${task.subtaskTotal}',
                      child: Column(
                        children: [
                          for (final subtask in task.subtasks)
                            _SubtaskRow(
                              key: ValueKey(subtask.id),
                              label: subtask.title,
                              completed: subtask.completed,
                              tokens: tokens,
                              onToggle: () => widget.controller
                                  .toggleSubtask(task.id, subtask.id),
                              onRemove: () => widget.controller
                                  .removeSubtask(task.id, subtask.id),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 23),
                  _InspectorSection(
                    label: '添加子任务',
                    child: _AddSubtaskField(
                        controller: widget.controller, taskId: task.id),
                  ),
                  ...[
                    const SizedBox(height: 23),
                    _InspectorSection(
                      label: '附件',
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final fileName in task.attachments)
                            InputChip(
                              label: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 190),
                                child: Text(fileName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: tokens.textSecondary,
                                        fontSize: 11)),
                              ),
                              avatar: Icon(Icons.insert_drive_file_outlined,
                                  size: 14, color: tokens.textTertiary),
                              onDeleted: () => widget.controller
                                  .removeAttachment(task.id, fileName),
                              deleteIconColor: tokens.textTertiary,
                              backgroundColor: tokens.content,
                              side: BorderSide(color: tokens.border),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => widget.controller
                                  .revealAttachment(task.id, fileName),
                            ),
                          ActionChip(
                            label: const Text('添加附件'),
                            avatar:
                                const Icon(Icons.attach_file_rounded, size: 14),
                            onPressed: () =>
                                widget.controller.attachFileToTask(task.id),
                            labelStyle: TextStyle(
                                color: tokens.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                            backgroundColor: tokens.accentFaint,
                            side: BorderSide(
                                color: tokens.accent.withOpacity(.18)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ],
                  ...[
                    const SizedBox(height: 23),
                    _InspectorSection(
                      label: '相关笔记',
                      child: _SourceNoteRow(
                          controller: widget.controller, taskId: task.id),
                    ),
                  ],
                  const SizedBox(height: 23),
                  _InspectorSection(
                    label: '标签',
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        ...task.tags.map((tag) => InputChip(
                              label: Text(tag),
                              onDeleted: () => widget.controller.updateTaskTags(
                                  task.id,
                                  task.tags
                                      .where((item) => item != tag)
                                      .toList()),
                              deleteIconColor: tokens.textTertiary,
                              labelStyle: TextStyle(
                                  color: tokens.textSecondary, fontSize: 11),
                              backgroundColor: tokens.content,
                              side: BorderSide(color: tokens.border),
                              visualDensity: VisualDensity.compact,
                            )),
                        ActionChip(
                          label: const Text('添加标签'),
                          avatar: const Icon(Icons.add, size: 14),
                          onPressed: () => _addTag(context, task),
                          labelStyle: TextStyle(
                              color: tokens.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                          backgroundColor: tokens.accentFaint,
                          side:
                              BorderSide(color: tokens.accent.withOpacity(.18)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SaveStatusFooter(
            controller: widget.controller,
            trailing: updatedLabel,
          ),
        ],
      ),
    );
  }

  String _descriptionFor(TaskItem task) => task.description ?? task.note ?? '';

  void _syncController(
      TextEditingController controller, String value, FocusNode focusNode) {
    if (focusNode.hasFocus || controller.text == value) return;
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  String _bucketLabel(TaskBucket bucket) => switch (bucket) {
        TaskBucket.overdue => '逾期',
        TaskBucket.today => '今天',
        TaskBucket.later => '稍后',
        TaskBucket.unscheduled => '未安排',
      };

  String _reminderLabel(TaskItem task) {
    final reminder =
        task.reminderAt == null ? null : DateTime.tryParse(task.reminderAt!);
    if (reminder == null) return '不提醒';
    return '${reminder.month} 月 ${reminder.day} 日 ${reminder.hour.toString().padLeft(2, '0')}:${reminder.minute.toString().padLeft(2, '0')}';
  }

  String _recurrenceLabel(TaskItem task) {
    final type = task.recurrenceType.toUpperCase();
    switch (type) {
      case 'DAILY':
        return '每天';
      case 'WEEKLY':
        final weekday = (task.recurrenceConfig?['weekday'] as num?)?.toInt();
        const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
        return weekday != null && weekday >= 1 && weekday <= 7
            ? '每周 · 周${weekdays[weekday - 1]}'
            : '每周';
      case 'MONTHLY':
        final day = (task.recurrenceConfig?['dayOfMonth'] as num?)?.toInt();
        return day != null ? '每月 · $day 号' : '每月';
      default:
        return '不重复';
    }
  }

  Future<void> _copyTask(BuildContext context, TaskItem task) async {
    final description = _descriptionFor(task);
    await Clipboard.setData(ClipboardData(
        text: '${task.title}${description.isEmpty ? '' : '\n$description'}'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('任务内容已复制')));
  }

  Future<void> _showMoreMenu(BuildContext context, TaskItem task) async {
    final tokens = WorkFollowTheme.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final offset = box == null
        ? const Offset(400, 150)
        : box.localToGlobal(Offset(box.size.width - 12, 35));
    final choice = await showMenu<String>(
      context: context,
      color: tokens.overlay,
      position: RelativeRect.fromLTRB(
          offset.dx, offset.dy, offset.dx + 1, offset.dy + 1),
      items: [
        const PopupMenuItem(value: 'move', child: Text('移动到清单')),
        const PopupMenuItem(value: 'copy', child: Text('复制任务内容')),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'delete',
            child: Text('移到废纸篓', style: TextStyle(color: tokens.danger))),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'move':
        await _chooseList(context, task);
      case 'copy':
        await _copyTask(context, task);
      case 'delete':
        widget.controller.removeTask(task.id);
    }
  }

  Future<void> _chooseList(BuildContext context, TaskItem task) async {
    final tokens = WorkFollowTheme.of(context);
    final listName = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: tokens.overlay,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('移动到清单',
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700))),
            ...widget.controller.lists.map((list) => ListTile(
                  leading: Icon(
                      list.name == task.listName
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: list.name == task.listName
                          ? tokens.accent
                          : tokens.textTertiary),
                  title: Text(list.name),
                  onTap: () => Navigator.of(sheetContext).pop(list.name),
                )),
          ],
        ),
      ),
    );
    if (listName != null) widget.controller.moveTaskToList(task.id, listName);
  }

  Future<void> _pickDueDate(BuildContext context, TaskItem task) async {
    final action = await _dateAction(context, task.dueAt != null);
    if (!context.mounted) return;
    if (action == 'clear') {
      widget.controller.updateTaskDue(task.id, null);
      return;
    }
    if (action != 'pick') return;
    final current = task.dueAt == null
        ? DateTime.now()
        : DateTime.tryParse(task.dueAt!) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择任务日期',
    );
    if (picked != null) widget.controller.updateTaskDue(task.id, picked);
  }

  Future<void> _pickReminder(BuildContext context, TaskItem task) async {
    final action =
        await _dateAction(context, task.reminderAt != null, label: '提醒');
    if (!context.mounted) return;
    if (action == 'clear') {
      widget.controller.updateTaskReminder(task.id, null);
      return;
    }
    if (action != 'pick') return;
    final current = task.reminderAt == null
        ? DateTime.now()
        : DateTime.tryParse(task.reminderAt!) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择提醒日期',
    );
    if (picked != null) widget.controller.updateTaskReminder(task.id, picked);
  }

  Future<String?> _dateAction(BuildContext context, bool canClear,
      {String label = '日期'}) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text('选择$label'),
                onTap: () => Navigator.of(sheetContext).pop('pick')),
            if (canClear)
              ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: Text('清除$label'),
                  onTap: () => Navigator.of(sheetContext).pop('clear')),
            ListTile(
                title: const Center(child: Text('取消')),
                onTap: () => Navigator.of(sheetContext).pop()),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseRecurrence(BuildContext context, TaskItem task) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const {
              'NONE': '不重复',
              'DAILY': '每天',
              'WEEKLY': '每周…',
              'MONTHLY': '每月…'
            }.entries)
              ListTile(
                  title: Text(option.value),
                  trailing: task.recurrenceType == option.key
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option.key)),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (selected != 'WEEKLY' && selected != 'MONTHLY') {
      widget.controller.updateTaskRecurrence(task.id, selected);
      return;
    }
    // 每周指定星期、每月指定日期；月末没有的日期自动落到当月最后一天。
    final config = await _pickRecurrenceConfig(context, selected, task);
    if (config == null) return;
    widget.controller.updateTaskRecurrence(task.id, selected, config: config);
  }

  Future<Map<String, dynamic>?> _pickRecurrenceConfig(
      BuildContext context, String type, TaskItem task) async {
    final tokens = WorkFollowTheme.of(context);
    final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    if (type == 'WEEKLY') {
      final weekdays = const ['一', '二', '三', '四', '五', '六', '日'];
      var weekday = (task.recurrenceConfig?['weekday'] as num?)?.toInt() ??
          (due?.weekday ?? DateTime.now().weekday);
      return showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: StatefulBuilder(builder: (sheetContext, setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                    padding: EdgeInsets.all(14), child: Text('每周的哪一天？')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (var value = 1; value <= 7; value++)
                        ChoiceChip(
                          label: Text('周${weekdays[value - 1]}'),
                          selected: weekday == value,
                          selectedColor: tokens.accentSoft,
                          labelStyle: TextStyle(
                              color: weekday == value
                                  ? tokens.accent
                                  : tokens.textSecondary,
                              fontSize: 11.5),
                          onSelected: (_) =>
                              setSheetState(() => weekday = value),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(sheetContext).pop({'weekday': weekday}),
                    child: const Text('保存'),
                  ),
                ),
              ],
            );
          }),
        ),
      );
    }
    var dayOfMonth = (task.recurrenceConfig?['dayOfMonth'] as num?)?.toInt() ??
        (due?.day ?? DateTime.now().day);
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(builder: (sheetContext, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.all(14), child: Text('每月的几号？')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text('当月没有这一天时，会安排到当月最后一天。',
                    style: TextStyle(color: tokens.textTertiary, fontSize: 11)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var value = 1; value <= 31; value++)
                        ChoiceChip(
                          label: Text('$value'),
                          selected: dayOfMonth == value,
                          selectedColor: tokens.accentSoft,
                          labelStyle: TextStyle(
                              color: dayOfMonth == value
                                  ? tokens.accent
                                  : tokens.textSecondary,
                              fontSize: 11.5),
                          onSelected: (_) =>
                              setSheetState(() => dayOfMonth = value),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext)
                      .pop({'dayOfMonth': dayOfMonth}),
                  child: const Text('保存'),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _choosePriority(BuildContext context, TaskItem task) async {
    final selected = await showModalBottomSheet<TaskPriority>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final priority in TaskPriority.values)
              ListTile(
                  title: Text(priority.label),
                  trailing: task.priority == priority
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(priority)),
          ],
        ),
      ),
    );
    if (selected != null)
      widget.controller.updateTaskPriority(task.id, selected);
  }

  Future<void> _addTag(BuildContext context, TaskItem task) async {
    final tagController = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
            controller: tagController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '例如：项目、阅读')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(tagController.text),
              child: const Text('添加')),
        ],
      ),
    );
    tagController.dispose();
    if (tag == null || tag.trim().isEmpty) return;
    widget.controller.updateTaskTags(task.id, [...task.tags, tag]);
  }

  Color _listColor(String listName, WorkFollowTheme tokens) {
    return switch (listName) {
      '工作' => tokens.accent,
      '学习' => tokens.warning,
      '个人' => tokens.success,
      _ => tokens.textTertiary,
    };
  }
}

class _InspectorPrimaryAction extends StatelessWidget {
  const _InspectorPrimaryAction(
      {required this.label,
      required this.icon,
      required this.completed,
      required this.onPressed});

  final String label;
  final IconData icon;
  final bool completed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Material(
      color: completed ? tokens.success : tokens.accent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 36,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700))
          ]),
        ),
      ),
    );
  }
}

class _InspectorSection extends StatelessWidget {
  const _InspectorSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .55))),
      child,
    ]);
  }
}

class _InspectorProperty extends StatelessWidget {
  const _InspectorProperty(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: tokens.border.withOpacity(.7)))),
          child: Row(children: [
            Icon(icon, size: 16, color: tokens.textTertiary),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Flexible(
                child: Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                size: 15, color: tokens.textTertiary),
          ]),
        ),
      ),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({
    super.key,
    required this.label,
    required this.completed,
    required this.tokens,
    required this.onToggle,
    required this.onRemove,
  });

  final String label;
  final bool completed;
  final WorkFollowTheme tokens;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: completed ? tokens.success : Colors.transparent,
                    border: Border.all(
                        color: completed ? tokens.success : tokens.borderStrong,
                        width: 1.4)),
                child: completed
                    ? const Icon(Icons.check_rounded,
                        size: 11, color: Colors.white)
                    : null),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color:
                        completed ? tokens.textTertiary : tokens.textSecondary,
                    fontSize: 12,
                    decoration:
                        completed ? TextDecoration.lineThrough : null))),
        AppIconButton(
            icon: Icons.close_rounded,
            tooltip: '删除子任务',
            size: 22,
            iconSize: 13,
            onPressed: onRemove),
      ]),
    );
  }
}

class _AddSubtaskField extends StatefulWidget {
  const _AddSubtaskField({required this.controller, required this.taskId});

  final WorkspaceController controller;
  final String taskId;

  @override
  State<_AddSubtaskField> createState() => _AddSubtaskFieldState();
}

class _AddSubtaskFieldState extends State<_AddSubtaskField> {
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  @override
  void dispose() {
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.controller.addSubtask(widget.taskId, textController.text)) {
      textController.clear();
      focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 5, 13, 5),
      decoration: BoxDecoration(
          color: tokens.content,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: tokens.border)),
      child: Row(
        children: [
          const SizedBox(width: 2),
          Icon(Icons.add_rounded, size: 15, color: tokens.textTertiary),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              cursorColor: tokens.accent,
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              decoration: InputDecoration(
                hintText: '输入子任务，按 Return 添加…',
                hintStyle: TextStyle(color: tokens.textTertiary, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "回到记录" entry: the note this task was generated from.
class _SourceNoteRow extends StatelessWidget {
  const _SourceNoteRow({required this.controller, required this.taskId});

  final WorkspaceController controller;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final note = controller.sourceNoteFor(taskId);
    if (note == null) {
      return Text('尚未关联笔记。在笔记里选中文字即可生成带来源的任务。',
          style: TextStyle(color: tokens.textTertiary, fontSize: 11));
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => controller.openNote(note.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
              color: tokens.content,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border)),
          child: Row(
            children: [
              Icon(Icons.note_alt_outlined, size: 15, color: tokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              Text(note.folder,
                  style: TextStyle(color: tokens.textTertiary, fontSize: 10)),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded,
                  size: 13, color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
