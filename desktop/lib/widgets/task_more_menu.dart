import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';
import 'task_editor_glyph.dart';
import 'desktop_popover.dart';
import 'task_editor_popover.dart';
import 'task_menu_glyph.dart';
import 'task_menu_selection.dart';
import 'task_menu_style.dart';

class TaskMoreMenu {
  const TaskMoreMenu._();

  /// Presents only the entry list and returns the user's selection. The
  /// controller parameter remains part of the public call shape for existing
  /// inspectors, but this widget deliberately performs no task or document
  /// mutation; the inspector routes the result to TaskActions or
  /// TaskDocumentCommands.
  static Future<TaskMenuSelection?> show(BuildContext anchor,
          {required TaskItem task, required WorkspaceController controller}) =>
      showTaskEditorPopover<TaskMenuSelection>(
        anchor,
        width: TaskEditorPopoverStyle.moreWidth,
        placement: PopoverPlacement.topEnd,
        scrollable: true,
        builder: (_) => _MoreMenu(task: task),
      );
}

class _MoreMenu extends StatefulWidget {
  const _MoreMenu({required this.task});
  final TaskItem task;
  @override
  State<_MoreMenu> createState() => _MoreMenuState();
}

class _MoreMenuState extends State<_MoreMenu> {
  int? focused;
  List<(String, String)> get entries => [
        ('add-subtask', '添加子任务'),
        ('pin', widget.task.isPinned ? '取消置顶' : '置顶'),
        ('abandon', widget.task.isAbandoned ? '恢复任务' : '放弃'),
        ('tags', '标签'),
        ('attachment', '上传附件'),
        ('convert-note', '转换为笔记'),
        ('delete', '删除'),
      ];

  bool enabled(int index) =>
      entries[index].$1 != 'abandon' || !widget.task.completed;
  void select(int index) {
    if (enabled(index))
      Navigator.of(context).pop(TaskMenuSelection(entries[index].$1));
  }

  @override
  Widget build(BuildContext context) {
    final colors = TaskMenuStyle.colors(context);
    return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent)
            return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowUp) {
            final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
            var next = ((focused ?? (step == 1 ? -1 : entries.length)) + step)
                .clamp(0, entries.length - 1);
            if (!enabled(next))
              next = (next + step).clamp(0, entries.length - 1);
            setState(() => focused = next);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            select(focused ?? 0);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Padding(
          key: const ValueKey('task-more-menu'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i == 5)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Divider(height: 1, color: colors.border)),
              Builder(builder: (context) {
                final entry = entries[i];
                final color =
                    enabled(i) ? colors.textPrimary : colors.textTertiary;
                return InkWell(
                  key: ValueKey('menu-option-${entry.$1}'),
                  onTap: enabled(i) ? () => select(i) : null,
                  child: Container(
                    height: TaskEditorPopoverStyle.rowHeight,
                    color: focused == i ? colors.accentFaint : null,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      if (entry.$1 == 'attachment')
                        TaskEditorGlyph('attachment', size: 18, color: color)
                      else if (entry.$1 == 'abandon' && widget.task.isAbandoned)
                        AppIcon(WorkFollowIcons.restore, size: 18, color: color)
                      else
                        TaskMenuGlyph(entry.$1, size: 18, color: color),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(entry.$2,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium!
                                  .copyWith(
                                      fontSize: WorkFollowMacTypography.menu,
                                      color: color))),
                    ]),
                  ),
                );
              }),
            ],
          ]),
        ));
  }
}
