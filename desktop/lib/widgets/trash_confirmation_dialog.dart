import 'package:flutter/material.dart';

import '../theme/workfollow_icons.dart';
import '../theme/workfollow_interaction_states.dart';
import '../theme/workfollow_surface_tokens.dart';
import '../theme/workfollow_theme.dart';
import 'desktop_popover.dart';

Future<bool?> showTrashConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String barrierLabel,
}) {
  final tokens = WorkFollowTheme.of(context);
  return showDesktopDialog<bool>(
    context: context,
    barrierLabel: barrierLabel,
    barrierColor: WorkFollowOverlayTokens.dialogBarrier(tokens),
    builder: (dialogContext) => TrashConfirmationDialog(
      title: title,
      message: message,
      onCancel: () => Navigator.of(dialogContext).pop(false),
      onConfirm: () => Navigator.of(dialogContext).pop(true),
    ),
  );
}

class TrashConfirmationDialog extends StatelessWidget {
  const TrashConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onCancel,
    required this.onConfirm,
    this.confirmLabel = '确认',
  });

  final String title;
  final String message;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = WorkFollowTheme.of(context);
    // Keep a confirmation dialog proportionate to its short message. The
    // previous 560pt surface read like a second page on a desktop window.
    final dialogWidth = (MediaQuery.sizeOf(context).width -
            TrashConfirmationDialogMetrics.viewportInset * 2)
        .clamp(0.0, TrashConfirmationDialogMetrics.maxWidth)
        .toDouble();
    final actionWidth = ((dialogWidth -
                TrashConfirmationDialogMetrics.horizontalPadding * 2 -
                TrashConfirmationDialogMetrics.actionGap) /
            2)
        .clamp(0.0, TrashConfirmationDialogMetrics.actionMaxWidth)
        .toDouble();

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: Container(
            key: const ValueKey('clear-trash-dialog'),
            width: dialogWidth,
            padding: const EdgeInsets.fromLTRB(
              TrashConfirmationDialogMetrics.horizontalPadding,
              TrashConfirmationDialogMetrics.topPadding,
              TrashConfirmationDialogMetrics.horizontalPadding,
              TrashConfirmationDialogMetrics.bottomPadding,
            ),
            decoration: WorkFollowSurfaceTokens.decoration(
              WorkFollowSurfaceRole.dialog,
              tokens,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: TrashConfirmationDialogMetrics.dismissRowHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: '取消',
                      // The disc carries the fill, not the InkWell's child.
                      // An InkWell paints its ink on the nearest Material and
                      // passes it to the child on top, so a fill painted inside
                      // the child hides the pointer feedback completely —
                      // this key used to show nothing at all on hover.
                      child: Material(
                        color: Theme.of(context).colorScheme.error,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: onCancel,
                          customBorder: const CircleBorder(),
                          // A destructive key is a solid fill, so it darkens
                          // within its own hue rather than taking the shared
                          // neutral hover (and not a tint of itself, which
                          // would be invisible on an opaque red).
                          overlayColor:
                              WorkFollowInteractionStyles.solidTintOverlay(
                                  Theme.of(context).colorScheme.error),
                          child: SizedBox(
                            width: TrashConfirmationDialogMetrics
                                .dismissTargetSize,
                            height: TrashConfirmationDialogMetrics
                                .dismissTargetSize,
                            child: Icon(
                              WorkFollowIcons.close,
                              size: TrashConfirmationDialogMetrics
                                  .dismissGlyphSize,
                              color: Theme.of(context).colorScheme.onError,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(
                    height: TrashConfirmationDialogMetrics.dismissTitleGap),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: WorkFollowMacTypography.pageTitle,
                    height: WorkFollowMacTypography.lineTight,
                    fontWeight: WorkFollowMacWeight.semibold,
                  ),
                ),
                const SizedBox(
                    height: TrashConfirmationDialogMetrics.titleMessageGap),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: WorkFollowMacTypography.body,
                    height: WorkFollowMacTypography.lineList,
                  ),
                ),
                const SizedBox(
                    height: TrashConfirmationDialogMetrics.messageActionsGap),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: actionWidth,
                      height: TrashConfirmationDialogMetrics.actionHeight,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.textPrimary,
                          textStyle: const TextStyle(
                            fontSize: WorkFollowMacTypography.menu,
                            fontWeight: WorkFollowMacWeight.medium,
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(
                        width: TrashConfirmationDialogMetrics.actionGap),
                    SizedBox(
                      width: actionWidth,
                      height: TrashConfirmationDialogMetrics.actionHeight,
                      child: FilledButton(
                        onPressed: onConfirm,
                        style: FilledButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          textStyle: const TextStyle(
                            fontSize: WorkFollowMacTypography.menu,
                            fontWeight: WorkFollowMacWeight.medium,
                          ),
                        ),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
