import 'package:flutter/material.dart';

import 'desktop_popover.dart';
import '../theme/workfollow_icons.dart';

/// Actions available from the task inspector's trailing ellipsis. This is a
/// task menu, not a second property form: every entry either starts a focused
/// operation or delegates to the existing TaskActions boundary.
class TaskMoreMenu {
  const TaskMoreMenu._();

  static Future<String?> show(BuildContext anchor,
      {required bool hasSourceNote}) {
    final entries = <DesktopMenuEntry<String>>[
      const DesktopMenuEntry('add-subtask', '添加子任务',
          icon: WorkFollowIcons.subtask),
      const DesktopMenuEntry('tags', '编辑标签', icon: WorkFollowIcons.tag),
      const DesktopMenuEntry('attachment', '添加附件',
          icon: WorkFollowIcons.attachment),
      const DesktopMenuEntry('focus', '专注记录', icon: WorkFollowIcons.focus),
      const DesktopMenuEntry('relation', '关联笔记', icon: WorkFollowIcons.link),
      if (hasSourceNote)
        const DesktopMenuEntry('open-source-note', '打开来源笔记',
            icon: WorkFollowIcons.article),
      const DesktopMenuEntry('copy', '复制任务正文', icon: WorkFollowIcons.copy),
      const DesktopMenuEntry('duplicate', '创建副本',
          icon: WorkFollowIcons.duplicate),
      const DesktopMenuEntry('delete', '移到废纸篓',
          icon: WorkFollowIcons.trash, destructive: true),
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
