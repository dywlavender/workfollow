import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import '../widgets/app_icon_button.dart';

/// The persistent trash: soft-deleted tasks and notes can be restored or
/// permanently removed here. Everything survives an app restart.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final tasks = controller.deletedTasks;
    final notes = controller.deletedNotes;
    return Container(
      color: tokens.canvas,
      padding: const EdgeInsets.fromLTRB(26, 23, 26, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('废纸篓',
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.pageTitle,
                  fontWeight: WorkFollowMacWeight.semibold,
                  height: WorkFollowMacTypography.lineTight,
                  letterSpacing: WorkFollowMacTracking.none)),
          const SizedBox(height: 5),
          Text('已删除的任务和笔记会保留在这里，直到你永久删除。',
              style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: WorkFollowMacTypography.supporting,
                  height: WorkFollowMacTypography.lineList)),
          const SizedBox(height: 18),
          Expanded(
            child: tasks.isEmpty && notes.isEmpty
                ? _EmptyTrash(tokens: tokens)
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tasks.isNotEmpty) ...[
                          _TrashSectionLabel(label: '任务', count: tasks.length),
                          for (final task in tasks)
                            _TrashTaskRow(task: task, controller: controller),
                        ],
                        if (notes.isNotEmpty) ...[
                          _TrashSectionLabel(label: '笔记', count: notes.length),
                          for (final note in notes)
                            _TrashNoteRow(note: note, controller: controller),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash({required this.tokens});

  final WorkFollowTheme tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: tokens.accentFaint, shape: BoxShape.circle),
              child: AppIcon(WorkFollowIcons.trash,
                  color: tokens.accent,
                  size: WorkFollowMetrics.navigationIcon + 6)),
          const SizedBox(height: 15),
          Text('废纸篓是空的',
              style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: WorkFollowMacTypography.body,
                  fontWeight: WorkFollowMacWeight.semibold)),
          const SizedBox(height: 5),
          Text('删除的任务和笔记会先到这里。',
              style: TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.supporting)),
        ],
      ),
    );
  }
}

class _TrashSectionLabel extends StatelessWidget {
  const _TrashSectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7, top: 4),
      child: Text('$label · $count',
          style: TextStyle(
              color: tokens.textTertiary,
              fontSize: WorkFollowMacTypography.sectionTitle,
              fontWeight: WorkFollowMacWeight.semibold,
              letterSpacing: WorkFollowMacTracking.none)),
    );
  }
}

class _TrashRowBase extends StatelessWidget {
  const _TrashRowBase({
    required this.title,
    required this.subtitle,
    required this.deletedLabel,
    required this.onRestore,
    required this.onPurge,
  });

  final String title;
  final String subtitle;
  final String deletedLabel;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration: BoxDecoration(
            color: tokens.content,
            borderRadius: BorderRadius.circular(WorkFollowRadii.surface),
            border: Border.all(color: tokens.border)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: WorkFollowMacTypography.listTitle,
                          fontWeight: WorkFollowMacWeight.semibold,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: tokens.textDisabled)),
                  const SizedBox(height: 3),
                  Text('$subtitle · 删除于 $deletedLabel',
                      style:
                          TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.listMeta)),
                ],
              ),
            ),
            AppIconButton(
                icon: WorkFollowIcons.restore,
                tooltip: '恢复',
                size: WorkFollowMetrics.iconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon,
                onPressed: onRestore),
            AppIconButton(
                icon: WorkFollowIcons.deleteForever,
                tooltip: '永久删除',
                size: WorkFollowMetrics.iconHitTarget,
                iconSize: WorkFollowMetrics.toolbarIcon,
                onPressed: onPurge),
          ],
        ),
      ),
    );
  }
}

class _TrashTaskRow extends StatelessWidget {
  const _TrashTaskRow({required this.task, required this.controller});

  final TaskItem task;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return _TrashRowBase(
      title: task.title,
      subtitle: task.listName,
      deletedLabel: noteUpdatedLabelFor(task.deletedAt),
      onRestore: () => controller.restoreTask(task.id),
      onPurge: () => _confirmPurge(context, '永久删除这个任务？',
          '「${task.title}」将无法恢复。', () => controller.purgeTask(task.id)),
    );
  }
}

class _TrashNoteRow extends StatelessWidget {
  const _TrashNoteRow({required this.note, required this.controller});

  final NoteItem note;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return _TrashRowBase(
      title: note.title,
      subtitle: note.folder,
      deletedLabel: noteUpdatedLabelFor(note.deletedAt),
      onRestore: () => controller.restoreNote(note.id),
      onPurge: () => _confirmPurge(context, '永久删除这条笔记？',
          '「${note.title}」将无法恢复。', () => controller.purgeNote(note.id)),
    );
  }
}

Future<void> _confirmPurge(BuildContext context, String title, String message,
    VoidCallback onConfirm) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消')),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('永久删除')),
      ],
    ),
  );
  if (confirmed == true) onConfirm();
}
