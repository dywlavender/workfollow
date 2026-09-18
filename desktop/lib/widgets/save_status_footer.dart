import 'dart:async';

import 'package:flutter/material.dart';

import '../state/workspace_controller.dart';
import '../theme/workfollow_icons.dart';
import '../theme/workfollow_theme.dart';
import 'app_icon_button.dart';

/// The editor footer that reports the real persistence state: saving, saved,
/// failed, or paused because the local snapshot could not be parsed.
///
/// It is deliberately quiet. The old footer was a full-width bar under a
/// hairline with an icon, a medium-weight sentence and a clock time on it —
/// permanently the loudest thing on a page whose point is the writing. This one
/// is right-aligned metadata: saving, failure and error keep the full sentence
/// and stay until they resolve, while a successful save states itself once and
/// fades after [savedLinger]. Only the ink fades; the row keeps its height, so
/// nothing below it moves.
class SaveStatusFooter extends StatelessWidget {
  const SaveStatusFooter(
      {super.key, required this.controller, this.trailing, this.actions});

  final WorkspaceController controller;

  /// Quiet secondary readout on the leading side of the same line — the note
  /// page puts its word count here instead of keeping a pill in the header.
  final String? trailing;

  /// Page-level controls that ride the same line, after the save state.
  ///
  /// The note page puts its formatting trigger here: the trigger belongs to the
  /// page, and pinning it to the bottom row keeps it off the prose. Ordering
  /// mirrors the task inspector's header, where the save indicator is likewise
  /// followed by the formatting toggle.
  final Widget? actions;

  /// How long a successful save stays on screen before it fades.
  static const Duration savedLinger = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final status = _statusFor(controller, tokens);
    return Container(
      padding: const EdgeInsets.fromLTRB(WorkFollowSpacing.space5,
          WorkFollowSpacing.space1, WorkFollowSpacing.space5, WorkFollowSpacing.space3),
      child: Row(
        children: [
          if (trailing != null)
            Text(trailing!,
                style: TextStyle(
                    color: tokens.textTertiary,
                    fontSize: WorkFollowMacTypography.caption)),
          const Spacer(),
          _LingeringStatus(
            // A new save is a new widget, which restarts the fade instead of
            // leaving a stale timestamp on screen.
            key: ValueKey('save-status-${status.$1.codePoint}-'
                '${controller.lastSavedAt?.toIso8601String()}'),
            icon: status.$1,
            label: status.$2,
            color: status.$3,
            linger: status.$4,
          ),
          if (actions != null) ...[
            const SizedBox(width: WorkFollowSpacing.space2),
            actions!,
          ],
        ],
      ),
    );
  }

  (IconData, String, Color, Duration?) _statusFor(
      WorkspaceController controller, WorkFollowTheme tokens) {
    if (controller.loadError != null) {
      return (WorkFollowIcons.report, controller.loadError!, tokens.danger, null);
    }
    switch (controller.saveStatus) {
      case SaveStatus.saving:
        return (WorkFollowIcons.more, '保存中…', tokens.textTertiary, null);
      case SaveStatus.failed:
        final label = controller.saveError == null
            ? '保存失败'
            : '保存失败：${controller.saveError}';
        return (WorkFollowIcons.error, label, tokens.danger, null);
      case SaveStatus.saved:
        if (controller.lastSavedAt == null) {
          return (
            WorkFollowIcons.check,
            '更改会自动保存到本机',
            tokens.textTertiary,
            null
          );
        }
        return (WorkFollowIcons.check, '已保存', tokens.textTertiary, savedLinger);
    }
  }
}

/// One status line. [linger] is null for states that must stay visible; a
/// duration fades the line out after it has been read.
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
