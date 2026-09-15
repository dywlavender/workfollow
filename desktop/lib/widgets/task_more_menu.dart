import 'package:flutter/material.dart';

import 'desktop_popover.dart';

/// Actions available from the task inspector's trailing ellipsis. This is a
/// task menu, not a second property form: every entry either starts a focused
/// operation or delegates to the existing TaskActions boundary.
class TaskMoreMenu {
  const TaskMoreMenu._();

  static Future<String?> show(BuildContext anchor,
      {required bool hasSourceNote}) {
    final entries = <DesktopMenuEntry<String>>[
      const DesktopMenuEntry('add-subtask', '添加子任务',
          icon: Icons.playlist_add_rounded),
      const DesktopMenuEntry('tags', '编辑标签', icon: Icons.tag_rounded),
      const DesktopMenuEntry('attachment', '添加附件',
          icon: Icons.attach_file_rounded),
      const DesktopMenuEntry('focus', '专注记录', icon: Icons.timer_outlined),
      const DesktopMenuEntry('relation', '关联笔记', icon: Icons.link_rounded),
      if (hasSourceNote)
        const DesktopMenuEntry('open-source-note', '打开来源笔记',
            icon: Icons.article_outlined),
      const DesktopMenuEntry('copy', '复制任务正文', icon: Icons.copy_outlined),
      const DesktopMenuEntry('duplicate', '创建副本',
          icon: Icons.control_point_duplicate_outlined),
      const DesktopMenuEntry('delete', '移到废纸篓',
          icon: Icons.delete_outline, destructive: true),
    ];
    return showDesktopMenu<String>(
      anchor,
      width: 270,
      maxHeight: 480,
      placement: PopoverPlacement.topEnd,
      entries: entries,
    );
  }
}
