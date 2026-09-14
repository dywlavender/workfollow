import 'package:flutter/material.dart';

import '../theme/workfollow_theme.dart';

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
        TaskSlashAction.heading1 => Icons.title_rounded,
        TaskSlashAction.heading2 => Icons.text_fields_rounded,
        TaskSlashAction.heading3 => Icons.short_text_rounded,
        TaskSlashAction.bullet => Icons.format_list_bulleted_rounded,
        TaskSlashAction.ordered => Icons.format_list_numbered_rounded,
        TaskSlashAction.checklist => Icons.check_box_outlined,
        TaskSlashAction.quote => Icons.format_quote_rounded,
        TaskSlashAction.divider => Icons.horizontal_rule_rounded,
        TaskSlashAction.subtask => Icons.playlist_add_rounded,
        TaskSlashAction.tag => Icons.tag_rounded,
        TaskSlashAction.relation => Icons.link_rounded,
        TaskSlashAction.attachment => Icons.attach_file_rounded,
      };
}

/// Small command palette shown when a task document line contains `/`.
class TaskSlashMenu extends StatelessWidget {
  const TaskSlashMenu({super.key, required this.onSelected});

  final ValueChanged<TaskSlashAction> onSelected;

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
    return Material(
      key: const ValueKey('task-slash-menu'),
      elevation: 10,
      color: tokens.content,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 270, maxHeight: 390),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('文本结构', tokens),
              for (final action in _text) _item(action, tokens),
              _sectionLabel('任务能力', tokens),
              for (final action in _task) _item(action, tokens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, WorkFollowTheme tokens) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 4),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: tokens.textTertiary)),
      );

  Widget _item(TaskSlashAction action, WorkFollowTheme tokens) => ListTile(
        key: ValueKey('task-slash-option-${action.keyName}'),
        dense: true,
        minTileHeight: 34,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(action.icon, size: 16, color: tokens.textSecondary),
        title: Text(action.label,
            style: TextStyle(fontSize: 12.5, color: tokens.textPrimary)),
        onTap: () => onSelected(action),
      );
}
