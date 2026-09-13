import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_theme.dart';

/// The editor footer that reports the real persistence state: saving, saved
/// (with the time of the last completed write), failed, or paused because the
/// local snapshot could not be parsed.
class SaveStatusFooter extends StatelessWidget {
  const SaveStatusFooter({super.key, required this.controller, this.trailing});

  final WorkspaceController controller;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final (icon, label, color) = _statusFor(controller, tokens);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: tokens.border))),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(trailing!,
                style: TextStyle(color: tokens.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }

  (IconData, String, Color) _statusFor(
      WorkspaceController controller, WorkFollowTheme tokens) {
    if (controller.loadError != null) {
      return (Icons.report_outlined, controller.loadError!, tokens.danger);
    }
    switch (controller.saveStatus) {
      case SaveStatus.saving:
        return (Icons.more_horiz, '保存中…', tokens.textTertiary);
      case SaveStatus.failed:
        final label = controller.saveError == null
            ? '保存失败'
            : '保存失败：${controller.saveError}';
        return (Icons.error_outline, label, tokens.danger);
      case SaveStatus.saved:
        final savedAt = controller.lastSavedAt;
        if (savedAt == null) {
          return (Icons.check_rounded, '更改会自动保存到本机', tokens.success);
        }
        final time =
            '${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}';
        return (Icons.check_rounded, '已保存 · $time', tokens.success);
    }
  }
}
