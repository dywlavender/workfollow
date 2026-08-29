import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.controller,
    required this.selected,
  });

  final TaskItem task;
  final WorkspaceController controller;
  final bool selected;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  bool hovering = false;
  bool focusVisible = false;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final task = widget.task;
    final rowColor = widget.selected
        ? tokens.accentSoft
        : (hovering ? tokens.overlay.withOpacity(.62) : Colors.transparent);
    final titleColor = task.completed ? tokens.textTertiary : tokens.textPrimary;
    final titleStyle = TextStyle(
      color: titleColor,
      fontSize: 13,
      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
      height: 1.35,
      decoration: task.completed ? TextDecoration.lineThrough : TextDecoration.none,
      decorationColor: tokens.textTertiary.withOpacity(.55),
      decorationThickness: 1.2,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => focusVisible = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(onInvoke: (_) {
            widget.controller.toggleTask(task.id);
            return null;
          }),
        },
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: '${task.title}${task.completed ? '，已完成' : ''}',
          child: GestureDetector(
            onTap: () => widget.controller.selectTask(task.id),
            onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: rowColor,
                borderRadius: BorderRadius.circular(9),
                border: focusVisible ? Border.all(color: tokens.accent.withOpacity(.42)) : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _TaskCompletionButton(
                    completed: task.completed,
                    accent: tokens.accent,
                    success: tokens.success,
                    onPressed: () => widget.controller.toggleTask(task.id),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (task.timeLabel != null)
                              _TaskMeta(
                                icon: task.bucket == TaskBucket.overdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                                label: task.timeLabel!,
                                color: task.bucket == TaskBucket.overdue ? tokens.warning : tokens.textTertiary,
                              ),
                            _TaskMeta(icon: Icons.circle, label: task.listName, color: _listColor(task.listName, tokens)),
                            if (task.priority != TaskPriority.none)
                              _TaskMeta(icon: Icons.flag_rounded, label: task.priority.label, color: _priorityColor(task.priority, tokens)),
                            if (task.subtaskTotal > 0)
                              _TaskMeta(icon: Icons.checklist_rounded, label: '${task.subtaskCompleted}/${task.subtaskTotal}', color: tokens.textTertiary),
                            if (task.hasAttachment) Icon(Icons.attach_file_rounded, size: 13, color: tokens.textTertiary),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: hovering || widget.selected ? 1 : 0,
                    child: AppIconButton(icon: Icons.more_horiz_rounded, tooltip: '更多操作', size: 28, iconSize: 17, onPressed: () => _showContextMenu(context, null)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset? position) async {
    final tokens = WorkFollowTheme.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final fallback = box == null ? const Offset(300, 260) : box.localToGlobal(Offset(24, box.size.height - 4));
    final anchor = position ?? fallback;
    final selected = await showMenu<String>(
      context: context,
      color: tokens.overlay,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      position: RelativeRect.fromLTRB(anchor.dx, anchor.dy, anchor.dx + 1, anchor.dy + 1),
      items: [
        PopupMenuItem<String>(value: 'toggle', child: Text(widget.task.completed ? '标记未完成' : '标记完成')),
        const PopupMenuItem<String>(value: 'today', child: Text('安排到今天')),
        const PopupMenuDivider(),
        PopupMenuItem<String>(value: 'delete', child: Text('移到废纸篓', style: TextStyle(color: tokens.danger))),
      ],
    );
    if (!context.mounted) return;
    if (selected == 'toggle') widget.controller.toggleTask(widget.task.id);
    if (selected == 'today') widget.controller.moveTaskToToday(widget.task.id);
    if (selected == 'delete') widget.controller.removeTask(widget.task.id);
  }

  Color _listColor(String listName, WorkFollowTheme tokens) {
    return switch (listName) {
      '工作' => tokens.accent,
      '学习' => tokens.warning,
      '个人' => tokens.success,
      _ => tokens.textTertiary,
    };
  }

  Color _priorityColor(TaskPriority priority, WorkFollowTheme tokens) {
    return switch (priority) {
      TaskPriority.high => tokens.danger,
      TaskPriority.medium => tokens.warning,
      TaskPriority.low => tokens.accent,
      TaskPriority.none => tokens.textTertiary,
    };
  }
}

class _TaskCompletionButton extends StatelessWidget {
  const _TaskCompletionButton({
    required this.completed,
    required this.accent,
    required this.success,
    required this.onPressed,
  });

  final bool completed;
  final Color accent;
  final Color success;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: completed,
      label: completed ? '标记未完成' : '标记完成',
      child: GestureDetector(
        onTap: onPressed,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: completed ? success : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: completed ? success : accent.withOpacity(.42), width: 1.7),
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 150),
                scale: completed ? 1 : .4,
                curve: Curves.easeOutBack,
                child: Icon(Icons.check_rounded, color: Colors.white, size: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 6 : 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1)),
      ],
    );
  }
}
