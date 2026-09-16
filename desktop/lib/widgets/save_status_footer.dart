import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

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
          AppIcon(icon, size: WorkFollowMetrics.metadataIcon, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: WorkFollowMacTypography.control, fontWeight: WorkFollowMacWeight.medium),
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(trailing!,
                style: TextStyle(color: tokens.textTertiary, fontSize: WorkFollowMacTypography.caption)),
        ],
      ),
    );
  }

  (IconData, String, Color) _statusFor(
      WorkspaceController controller, WorkFollowTheme tokens) {
    if (controller.loadError != null) {
      return (WorkFollowIcons.report, controller.loadError!, tokens.danger);
    }
    switch (controller.saveStatus) {
      case SaveStatus.saving:
        return (WorkFollowIcons.more, '保存中…', tokens.textTertiary);
      case SaveStatus.failed:
        final label = controller.saveError == null
            ? '保存失败'
            : '保存失败：${controller.saveError}';
        return (WorkFollowIcons.error, label, tokens.danger);
      case SaveStatus.saved:
        final savedAt = controller.lastSavedAt;
        if (savedAt == null) {
          return (WorkFollowIcons.check, '更改会自动保存到本机', tokens.success);
        }
        final time =
            '${savedAt.hour.toString().padLeft(2, '0')}:${savedAt.minute.toString().padLeft(2, '0')}';
        return (WorkFollowIcons.check, '已保存 · $time', tokens.success);
    }
  }
}
