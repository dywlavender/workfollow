import 'dart:async';

import 'package:flutter/material.dart';

import '../../../state/workspace_controller.dart';
import '../../../theme/workfollow_icons.dart';
import '../../../theme/workfollow_theme.dart';
import '../../../widgets/app_icon_button.dart';

/// Shared persistence feedback for task and note document editors.
class DocumentSaveStatus extends StatelessWidget {
  const DocumentSaveStatus({super.key, required this.controller});

  final WorkspaceController controller;

  static const Duration savedLinger = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tokens = WorkFollowTheme.of(context);
        final status = _statusFor(controller, tokens);
        if (status.isFailure) {
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
        }
        return _LingeringStatus(
          key: ValueKey('save-status-${status.icon.codePoint}-'
              '${controller.lastSavedAt?.toIso8601String()}'),
          icon: status.icon,
          label: status.label,
          color: status.color,
          linger: status.linger,
        );
      },
    );
  }

  _SaveStatusView _statusFor(
      WorkspaceController controller, WorkFollowTheme tokens) {
    if (controller.loadError != null) {
      return _SaveStatusView(
        icon: WorkFollowIcons.report,
        label: '读取失败',
        tooltip: controller.loadError!,
        color: tokens.danger,
        isFailure: true,
        canRetry: false,
      );
    }
    switch (controller.saveStatus) {
      case SaveStatus.saving:
        return _SaveStatusView(
          icon: WorkFollowIcons.more,
          label: '保存中…',
          color: tokens.textTertiary,
        );
      case SaveStatus.failed:
        return _SaveStatusView(
          icon: WorkFollowIcons.error,
          label: '保存失败 · 重试',
          tooltip: controller.saveError ?? '保存失败',
          color: tokens.danger,
          isFailure: true,
          canRetry: true,
        );
      case SaveStatus.saved:
        if (controller.lastSavedAt == null) {
          return _SaveStatusView(
            icon: WorkFollowIcons.check,
            label: '更改会自动保存到本机',
            color: tokens.textTertiary,
          );
        }
        return _SaveStatusView(
          icon: WorkFollowIcons.check,
          label: '已保存',
          color: tokens.textTertiary,
          linger: savedLinger,
        );
    }
  }
}

class _SaveStatusView {
  const _SaveStatusView({
    required this.icon,
    required this.label,
    required this.color,
    this.tooltip = '',
    this.linger,
    this.isFailure = false,
    this.canRetry = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String tooltip;
  final Duration? linger;
  final bool isFailure;
  final bool canRetry;
}

class _LingeringStatus extends StatefulWidget {
  const _LingeringStatus({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.linger,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Duration? linger;

  @override
  State<_LingeringStatus> createState() => _LingeringStatusState();
}

class _LingeringStatusState extends State<_LingeringStatus> {
  Timer? _timer;
  bool _faded = false;

  @override
  void initState() {
    super.initState();
    final linger = widget.linger;
    if (linger == null) return;
    _timer = Timer(linger, () {
      if (mounted) setState(() => _faded = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _faded ? 0 : 1,
      duration: WorkFollowMotion.normal,
      curve: WorkFollowMotion.standard,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(widget.icon,
              size: WorkFollowMetrics.metadataIcon, color: widget.color),
          const SizedBox(width: WorkFollowSpacing.denseGap),
          Text(widget.label,
              style: TextStyle(
                  color: widget.color,
                  fontSize: WorkFollowMacTypography.supporting)),
        ],
      ),
    );
  }
}
