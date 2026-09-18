import 'package:flutter/material.dart';

import '../../theme/workfollow_icons.dart';
import '../../theme/workfollow_surface_tokens.dart';
import '../../theme/workfollow_theme.dart';
import '../../widgets/app_icon_button.dart';
import 'feedback_event.dart';

/// Geometry of the result HUD.
///
/// Width is a range rather than a fixed number: a two-character message
/// ("已复制") and a sentence must both look deliberate, and a fixed width would
/// either squeeze the short one into a slab or clip the long one.
class FeedbackMetrics {
  const FeedbackMetrics._();

  static const double minWidth = 220;
  static const double maxWidth = 360;
  static const double height = 60;
  static const double horizontalPadding = WorkFollowSpacing.sectionGap;
  static const double radius = WorkFollowRadii.card;
  static const double messageActionGap = WorkFollowSpacing.space3;
  static const double actionIconSize = 17;
  static const double actionHitTarget = 28;

  /// Distance from the window bottom. The host takes the larger of this and
  /// the safe-area inset so the HUD never sits under system chrome.
  static const double bottomMargin = WorkFollowSpacing.pageHorizontalPadding;
}

/// The dark HUD: `任务已完成    ↶`.
///
/// One dark surface in both themes. It carries the message and at most one
/// action; it owns no timer and no state — the host decides when it appears and
/// how it moves.
class FeedbackToast extends StatelessWidget {
  const FeedbackToast(
      {super.key, required this.feedback, required this.onAction});

  final WorkFollowFeedback feedback;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    final hasAction = feedback.onAction != null &&
        (feedback.actionIcon != null || feedback.actionLabel != null);
    return Container(
        key: const ValueKey('feedback-toast'),
        constraints: const BoxConstraints(
            minWidth: FeedbackMetrics.minWidth,
            maxWidth: FeedbackMetrics.maxWidth,
            minHeight: FeedbackMetrics.height,
            maxHeight: FeedbackMetrics.height),
        padding: const EdgeInsets.symmetric(
            horizontal: FeedbackMetrics.horizontalPadding),
        decoration: WorkFollowSurfaceTokens.toast(tokens),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // A failure must not be mistakable for a success at a glance, and the
          // HUD is otherwise one uniform surface.
          if (feedback.kind.isFailure) ...[
            AppIcon(WorkFollowIcons.error,
                size: FeedbackMetrics.actionIconSize, color: tokens.danger),
            const SizedBox(width: WorkFollowSpacing.controlGap),
          ],
          Flexible(
              child: Text(feedback.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: WorkFollowMacTypography.feedback,
                      height: WorkFollowMacTypography.lineControl,
                      fontWeight: WorkFollowMacWeight.medium,
                      color: tokens.feedbackText))),
          if (hasAction) ...[
            const SizedBox(width: FeedbackMetrics.messageActionGap),
            AppIconButton(
                key: const ValueKey('feedback-toast-action'),
                icon: feedback.actionIcon ?? WorkFollowIcons.undo,
                // No tooltip, deliberately. The host is mounted above the
                // Navigator so the HUD also covers dialogs, and that position
                // has no Overlay for a Tooltip to float in — asking for one
                // throws at build time. The glyph carries the meaning and the
                // label below still reaches VoiceOver.
                tooltip: null,
                // A word would cost width the message needs. The two actions
                // that reach this slot are fixed and unambiguous at this size:
                // ↶ takes the last change back, → follows a task that left the
                // current list.
                semanticLabel: feedback.actionLabel ?? '撤销',
                size: FeedbackMetrics.actionHitTarget,
                iconSize: FeedbackMetrics.actionIconSize,
                iconColor: tokens.feedbackAction,
                onPressed: feedback.onAction == null ? null : onAction),
          ],
        ]));
  }
}
