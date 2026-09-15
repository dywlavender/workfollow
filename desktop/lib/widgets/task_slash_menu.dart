import 'package:flutter/material.dart';

import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

enum TaskSlashAction {
  heading1,
  heading2,
  heading3,
  bullet,
  ordered,
  checklist,
  quote,
  divider,
  subtask,
  tag,
  relation,
  attachment,
}

extension TaskSlashActionLabel on TaskSlashAction {
  String get label => switch (this) {
        TaskSlashAction.heading1 => '一级标题',
        TaskSlashAction.heading2 => '二级标题',
        TaskSlashAction.heading3 => '三级标题',
        TaskSlashAction.bullet => '无序列表',
        TaskSlashAction.ordered => '有序列表',
        TaskSlashAction.checklist => '检查项',
        TaskSlashAction.quote => '引用',
        TaskSlashAction.divider => '水平分割线',
        TaskSlashAction.subtask => '子任务',
        TaskSlashAction.tag => '标签',
        TaskSlashAction.relation => '关联任务/笔记',
        TaskSlashAction.attachment => '附件',
      };

  String get keyName => switch (this) {
        TaskSlashAction.heading1 => 'heading-1',
        TaskSlashAction.heading2 => 'heading-2',
        TaskSlashAction.heading3 => 'heading-3',
        TaskSlashAction.bullet => 'bullet',
        TaskSlashAction.ordered => 'ordered',
        TaskSlashAction.checklist => 'checklist',
        TaskSlashAction.quote => 'quote',
        TaskSlashAction.divider => 'divider',
        TaskSlashAction.subtask => 'subtask',
        TaskSlashAction.tag => 'tag',
        TaskSlashAction.relation => 'relation',
        TaskSlashAction.attachment => 'attachment',
      };

  IconData get icon => switch (this) {
        TaskSlashAction.heading1 => WorkFollowIcons.heading1,
        TaskSlashAction.heading2 => WorkFollowIcons.heading2,
        TaskSlashAction.heading3 => WorkFollowIcons.heading3,
        TaskSlashAction.bullet => WorkFollowIcons.bullet,
        TaskSlashAction.ordered => WorkFollowIcons.ordered,
        TaskSlashAction.checklist => WorkFollowIcons.checklist,
        TaskSlashAction.quote => WorkFollowIcons.quote,
        TaskSlashAction.divider => WorkFollowIcons.divider,
        TaskSlashAction.subtask => WorkFollowIcons.subtask,
        TaskSlashAction.tag => WorkFollowIcons.tag,
        TaskSlashAction.relation => WorkFollowIcons.link,
        TaskSlashAction.attachment => WorkFollowIcons.attachment,
      };
}

/// Small command palette shown when a task document line contains `/`.
///
/// This is intentionally closer to TickTick's command palette than to a
/// generic Material popup: the menu is a quiet document surface, grouped by a
/// hairline divider and with enough room for the icon/title pair to breathe.
class TaskSlashMenu extends StatelessWidget {
  const TaskSlashMenu({super.key, required this.onSelected, this.actions});

  final ValueChanged<TaskSlashAction> onSelected;

  /// Optional subset used by other document surfaces such as Notes. The task
  /// editor keeps the full menu when this is omitted.
  final List<TaskSlashAction>? actions;

  static const _text = <TaskSlashAction>[
    TaskSlashAction.heading1,
    TaskSlashAction.heading2,
    TaskSlashAction.heading3,
    TaskSlashAction.bullet,
    TaskSlashAction.ordered,
    TaskSlashAction.checklist,
    TaskSlashAction.quote,
    TaskSlashAction.divider,
  ];

  static const _task = <TaskSlashAction>[
    TaskSlashAction.subtask,
    TaskSlashAction.tag,
    TaskSlashAction.relation,
    TaskSlashAction.attachment,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final visible = actions;
    final textActions = visible == null
        ? _text
        : visible.where(_text.contains).toList(growable: false);
    final taskActions = visible == null
        ? _task
        : visible.where(_task.contains).toList(growable: false);
    return Material(
      key: const ValueKey('task-slash-menu'),
      elevation: 8,
      shadowColor: tokens.shadow,
      color: tokens.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkFollowRadii.popover),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 276, maxHeight: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (textActions.isNotEmpty) ...[
                for (final action in textActions) _item(action, tokens),
              ],
              if (taskActions.isNotEmpty) ...[
                if (textActions.isNotEmpty) _sectionDivider(tokens),
                for (final action in taskActions) _item(action, tokens),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionDivider(WorkFollowTheme tokens) => Semantics(
        label: '任务内容操作',
        container: true,
        child: Divider(
          height: 10,
          thickness: 1,
          indent: 12,
          endIndent: 12,
          color: tokens.border,
        ),
      );

  Widget _item(TaskSlashAction action, WorkFollowTheme tokens) => ListTile(
        key: ValueKey('task-slash-option-${action.keyName}'),
        dense: true,
        minTileHeight: WorkFollowMetrics.menuRowHeight,
        horizontalTitleGap: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13),
        hoverColor: tokens.accentFaint,
        splashColor: Colors.transparent,
        leading: AppIcon(action.icon,
            size: WorkFollowMetrics.navigationIcon,
            color: tokens.textSecondary),
        title: Text(action.label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: tokens.textPrimary)),
        onTap: () => onSelected(action),
      );
}
