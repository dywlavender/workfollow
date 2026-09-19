import 'dart:async';

import 'package:flutter/material.dart';

import '../../../state/workspace_controller.dart';
import '../../../theme/workfollow_icons.dart';
import '../../../theme/workfollow_theme.dart';
import '../../../widgets/app_icon_button.dart';

/// Persistence feedback for task and note document editors.
///
/// It speaks only when a write has gone wrong. The resting states are gone:
/// "保存中…" while a write is in flight and "已保存" once it lands were both
/// saying what the document already implies — a document that saves itself has
/// nothing to report, and the corner they sat in belongs to the document's own
/// actions. What is left is the one state a reader cannot infer and may have to
/// act on, because a failed save with nothing on screen is a silent one.
class DocumentSaveStatus extends StatelessWidget {
  const DocumentSaveStatus({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tokens = WorkFollowTheme.of(context);
        final status = _statusFor(controller);
        if (status == null) return const SizedBox.shrink();
        return Tooltip(
          message: status.tooltip,
          child: TextButton.icon(
            key: const ValueKey('save-status-indicator'),
            onPressed: status.canRetry
                ? () => unawaited(controller.retrySave())
                : null,
            icon: AppIcon(status.icon,
                size: WorkFollowMetrics.metadataIcon, color: tokens.danger),
            label: Text(status.label),
            style: TextButton.styleFrom(
              foregroundColor: tokens.danger,
              textStyle: const TextStyle(
                  fontSize: WorkFollowMacTypography.control,
                  fontWeight: WorkFollowMacWeight.medium),
              padding: const EdgeInsets.symmetric(
                  horizontal: WorkFollowSpacing.inlineGap),
            ),
          ),
        );
      },
    );
  }

  _SaveStatusView? _statusFor(WorkspaceController controller) {
    if (controller.loadError != null) {
      return _SaveStatusView(
        icon: WorkFollowIcons.report,
        label: '读取失败',
        tooltip: controller.loadError!,
      );
    }
    switch (controller.saveStatus) {
      case SaveStatus.failed:
        return _SaveStatusView(
          icon: WorkFollowIcons.error,
          label: '保存失败 · 重试',
          tooltip: controller.saveError ?? '保存失败',
          canRetry: true,
        );
      case SaveStatus.saving:
      case SaveStatus.saved:
        return null;
    }
  }
}

class _SaveStatusView {
  const _SaveStatusView({
    required this.icon,
    required this.label,
    this.tooltip = '',
    this.canRetry = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool canRetry;
}
